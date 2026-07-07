"""FastAPI application for the AgentCore MCP shim.

Implements the connector action model from the parent spec
(docs/power-platform-mcp-private-proxy-connector-spec.md#connector-action-model),
scoped to the single MCP server configured for this shim instance (Variant
A2). See docs/a2-howto-agentcore-bedrock.md for the end-to-end deployment
guide this code accompanies.

Known scope limitations of this reference implementation (documented, not
silently omitted -- see the how-to's "Known limitations" section):
  * Per-tool `timeoutSeconds` from the allow-list is enforced as a ceiling
    on the caller-requested timeout, not as a literal per-call socket
    timeout override; the shim uses one process-wide AgentCore request
    timeout (mcp.requestTimeoutSeconds).
  * No built-in per-caller rate limiting/backpressure; front the shim with
    an ALB/NLB + WAF rate-based rule, or extend SessionManager with a token
    bucket, if you need QuotaExceeded (429) enforcement at this layer.
"""
from __future__ import annotations

import logging
import time
import uuid
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from . import authz, mcp_protocol, models
from .agentcore_client import AgentCoreMcpClient
from .audit import AuditRecord, configure as configure_audit, emit as emit_audit
from .auth import authenticate
from .config import get_config
from .errors import InvalidArguments, ShimError, UnknownTarget, error_for_code, to_error_envelope
from .session_manager import SessionManager

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
logger = logging.getLogger("shim.main")


class ShimState:
    """Process-wide dependencies constructed once at startup."""

    def __init__(self) -> None:
        self.config = get_config()
        self.agentcore_client = AgentCoreMcpClient(self.config.aws, self.config.mcp)
        self.session_manager = SessionManager(
            self.config.mcp.session_idle_ttl_minutes, self.agentcore_client
        )
        self.schema_registry = authz.ToolSchemaRegistry(self.agentcore_client, self.session_manager)
        configure_audit(self.config.audit)


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.shim = ShimState()
    logger.info("Shim ready for server_id=%s", app.state.shim.config.server_id)
    yield


app = FastAPI(title="AgentCore MCP Shim", version="1.0.0", lifespan=lifespan)


def _correlation_id(request: Request) -> str:
    return request.headers.get("x-correlation-id") or str(uuid.uuid4())


def _ensure_server_id(server_id: str, state: ShimState) -> None:
    if server_id != state.config.server_id:
        raise UnknownTarget(f"Unknown server_id '{server_id}'; this shim only serves '{state.config.server_id}'")


def _map_tool_content(result: dict) -> list[models.ContentItem]:
    """Map an MCP tools/call result into the connector's simplified content shape."""
    structured = result.get("structuredContent")
    if structured is not None:
        return [models.ContentItem(type="json", value=structured)]
    items: list[models.ContentItem] = []
    for item in result.get("content", []) or []:
        if item.get("type") == "text":
            items.append(models.ContentItem(type="text", value=item.get("text", "")))
        else:
            items.append(models.ContentItem(type="json", value=item))
    return items


@app.exception_handler(ShimError)
async def shim_error_handler(request: Request, exc: ShimError) -> JSONResponse:
    correlation_id = _correlation_id(request)
    logger.warning("Request failed: code=%s message=%s correlation_id=%s", exc.code, exc.message, correlation_id)
    return JSONResponse(status_code=exc.http_status, content=to_error_envelope(exc, correlation_id))


@app.get("/health")
async def health(request: Request) -> models.HealthResponse:
    state: ShimState = request.app.state.shim
    return models.HealthResponse(
        status="ok",
        server_id=state.config.server_id,
        active_sessions=state.session_manager.size(),
    )


@app.get("/v1/servers")
async def list_servers(request: Request) -> list[models.ServerSummary]:
    state: ShimState = request.app.state.shim
    authenticate(request, state.config.auth)
    return [models.ServerSummary(server_id=state.config.server_id, display_name=state.config.display_name)]


@app.get("/v1/servers/{server_id}/tools")
async def list_tools(server_id: str, request: Request) -> list[models.ToolSummary]:
    state: ShimState = request.app.state.shim
    _ensure_server_id(server_id, state)
    identity = authenticate(request, state.config.auth)

    summaries: list[models.ToolSummary] = []
    for policy in state.config.allowed_capabilities.tools:
        try:
            authz.check_caller_allowed(policy, identity.caller_id)
        except ShimError:
            continue  # silently omit tools this caller cannot see, per allow-list semantics
        schema = state.schema_registry.get_schema(policy.name) or {}
        summaries.append(models.ToolSummary(name=policy.name, idempotent=policy.idempotent, input_schema=schema))
    return summaries


@app.post("/v1/servers/{server_id}/tools/{tool_name}:invoke")
async def invoke_tool(
    server_id: str, tool_name: str, body: models.InvokeToolRequest, request: Request
) -> models.InvokeToolResponse:
    state: ShimState = request.app.state.shim
    correlation_id = _correlation_id(request)
    started = time.monotonic()
    identity = None
    try:
        _ensure_server_id(server_id, state)
        identity = authenticate(request, state.config.auth)
        policy = authz.find_tool_policy(state.config, tool_name)
        authz.check_caller_allowed(policy, identity.caller_id)

        requested_timeout = body.execution_options.timeout_seconds if body.execution_options else None
        if requested_timeout is not None and requested_timeout > policy.timeout_seconds:
            raise InvalidArguments(
                f"Requested timeoutSeconds={requested_timeout} exceeds the "
                f"{policy.timeout_seconds}s ceiling configured for '{tool_name}'"
            )

        schema = state.schema_registry.get_schema(tool_name)
        authz.validate_arguments(schema, body.arguments)

        session = state.session_manager.get_or_create(identity.caller_id)
        rpc_request = mcp_protocol.build_tools_call_request(tool_name, body.arguments)
        result = state.agentcore_client.invoke(
            rpc_request, session.runtime_session_id, session.mcp_session_id, idempotent=policy.idempotent
        )
        state.session_manager.update(identity.caller_id, result.runtime_session_id, result.mcp_session_id)

        if result.rpc.is_protocol_error:
            error = result.rpc.error or {}
            raise error_for_code(
                mcp_protocol.classify_rpc_error_code(error), error.get("message", "tools/call failed")
            )

        status = "failed" if result.rpc.is_tool_error else "succeeded"
        content = _map_tool_content(result.rpc.result or {})
        elapsed_ms = int((time.monotonic() - started) * 1000)

        emit_audit(
            AuditRecord(
                correlation_id=correlation_id,
                caller_id=identity.caller_id,
                auth_type=identity.auth_type,
                server_id=state.config.server_id,
                action="InvokeMcpTool",
                tool_or_resource=tool_name,
                decision="allowed",
                http_status=200,
                elapsed_ms=elapsed_ms,
                redacted_arguments=authz.redact(body.arguments, policy.redact_arguments),
            )
        )
        return models.InvokeToolResponse(
            server_id=state.config.server_id,
            tool_name=tool_name,
            status=status,
            content=content,
            correlation_id=correlation_id,
            elapsed_ms=elapsed_ms,
        )
    except ShimError as exc:
        elapsed_ms = int((time.monotonic() - started) * 1000)
        emit_audit(
            AuditRecord(
                correlation_id=correlation_id,
                caller_id=identity.caller_id if identity else "unknown",
                auth_type=identity.auth_type if identity else "none",
                server_id=server_id,
                action="InvokeMcpTool",
                tool_or_resource=tool_name,
                decision="denied" if exc.http_status in (401, 403, 404, 400) else "error",
                http_status=exc.http_status,
                elapsed_ms=elapsed_ms,
                error_code=exc.code,
            )
        )
        raise


@app.get("/v1/servers/{server_id}/resources")
async def list_resources(server_id: str, request: Request) -> list[dict[str, Any]]:
    state: ShimState = request.app.state.shim
    _ensure_server_id(server_id, state)
    identity = authenticate(request, state.config.auth)
    allowed_names = set()
    for policy in state.config.allowed_capabilities.resources:
        try:
            authz.check_caller_allowed(policy, identity.caller_id)
            allowed_names.add(policy.name)
        except ShimError:
            continue
    return [{"name": name} for name in sorted(allowed_names)]


@app.post("/v1/servers/{server_id}/resources:read")
async def read_resource(server_id: str, body: models.ReadResourceRequest, request: Request) -> dict[str, Any]:
    state: ShimState = request.app.state.shim
    _ensure_server_id(server_id, state)
    identity = authenticate(request, state.config.auth)

    # Resources reuse the ToolPolicy config shape, matching by URI instead of tool name.
    matching = next((p for p in state.config.allowed_capabilities.resources if p.name == body.uri), None)
    if matching is None:
        raise UnknownTarget(f"Resource '{body.uri}' is not on the allow-list for this server")
    authz.check_caller_allowed(matching, identity.caller_id)

    session = state.session_manager.get_or_create(identity.caller_id)
    rpc_request = mcp_protocol.build_resources_read_request(body.uri)
    result = state.agentcore_client.invoke(
        rpc_request, session.runtime_session_id, session.mcp_session_id, idempotent=True
    )
    state.session_manager.update(identity.caller_id, result.runtime_session_id, result.mcp_session_id)
    if result.rpc.is_protocol_error:
        error = result.rpc.error or {}
        raise error_for_code(mcp_protocol.classify_rpc_error_code(error), error.get("message", "resources/read failed"))
    return result.rpc.result or {}


@app.get("/v1/servers/{server_id}/prompts")
async def list_prompts(server_id: str, request: Request) -> list[dict[str, Any]]:
    state: ShimState = request.app.state.shim
    _ensure_server_id(server_id, state)
    identity = authenticate(request, state.config.auth)
    allowed_names = set()
    for policy in state.config.allowed_capabilities.prompts:
        try:
            authz.check_caller_allowed(policy, identity.caller_id)
            allowed_names.add(policy.name)
        except ShimError:
            continue
    return [{"name": name} for name in sorted(allowed_names)]


@app.post("/v1/servers/{server_id}/prompts/{prompt_name}:render")
async def render_prompt(
    server_id: str, prompt_name: str, body: models.RenderPromptRequest, request: Request
) -> dict[str, Any]:
    state: ShimState = request.app.state.shim
    _ensure_server_id(server_id, state)
    identity = authenticate(request, state.config.auth)
    matching = next((p for p in state.config.allowed_capabilities.prompts if p.name == prompt_name), None)
    if matching is None:
        raise UnknownTarget(f"Prompt '{prompt_name}' is not on the allow-list for this server")
    authz.check_caller_allowed(matching, identity.caller_id)

    session = state.session_manager.get_or_create(identity.caller_id)
    rpc_request = mcp_protocol.build_prompts_get_request(prompt_name, body.arguments)
    result = state.agentcore_client.invoke(
        rpc_request, session.runtime_session_id, session.mcp_session_id, idempotent=True
    )
    state.session_manager.update(identity.caller_id, result.runtime_session_id, result.mcp_session_id)
    if result.rpc.is_protocol_error:
        error = result.rpc.error or {}
        raise error_for_code(mcp_protocol.classify_rpc_error_code(error), error.get("message", "prompts/get failed"))
    return result.rpc.result or {}
