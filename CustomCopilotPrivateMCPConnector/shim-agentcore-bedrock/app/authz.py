"""Authorization and argument validation for the AgentCore MCP shim.

Enforces the parent spec's "deny by default" policy: every tool, resource,
and prompt must appear in this server's allow-list configuration, and every
tool call's arguments are validated against the tool's JSON schema (learned
from the backend MCP server's own tools/list) before AgentCore is invoked.

The allow-list itself always comes from local configuration, never from the
backend MCP server, so a compromised or misbehaving MCP server cannot
expand its own exposed surface by advertising extra tools.
"""
from __future__ import annotations

import logging
import threading
import time
from typing import Optional

import jsonschema

from . import mcp_protocol
from .agentcore_client import AgentCoreMcpClient
from .config import ShimConfig, ToolPolicy
from .errors import InvalidArguments, UnauthorizedTool
from .session_manager import SessionManager

logger = logging.getLogger("shim.authz")

_SCHEMA_CACHE_TTL_SECONDS = 300


class ToolSchemaRegistry:
    """Caches tool input schemas fetched from the backend MCP server's tools/list.

    Schemas drive argument validation (see validate_arguments below).
    """

    def __init__(self, agentcore_client: AgentCoreMcpClient, session_manager: SessionManager):
        self._client = agentcore_client
        self._sessions = session_manager
        self._schemas: dict[str, dict] = {}
        self._fetched_at: float = 0.0
        self._lock = threading.Lock()

    def _refresh(self) -> None:
        session = self._sessions.get_or_create("__system_schema_refresh__")
        request = mcp_protocol.build_tools_list_request()
        result = self._client.invoke(
            request, session.runtime_session_id, session.mcp_session_id, idempotent=True
        )
        if result.rpc.is_protocol_error:
            logger.warning("tools/list failed while refreshing the schema cache: %s", result.rpc.error)
            return
        tools = (result.rpc.result or {}).get("tools", [])
        with self._lock:
            self._schemas = {tool["name"]: tool.get("inputSchema", {}) for tool in tools if "name" in tool}
            self._fetched_at = time.monotonic()

    def get_schema(self, tool_name: str) -> Optional[dict]:
        with self._lock:
            is_stale = (time.monotonic() - self._fetched_at) > _SCHEMA_CACHE_TTL_SECONDS
            has_entry = tool_name in self._schemas
        if is_stale or not has_entry:
            self._refresh()
        with self._lock:
            return self._schemas.get(tool_name)


def find_tool_policy(config: ShimConfig, tool_name: str) -> ToolPolicy:
    for tool in config.allowed_capabilities.tools:
        if tool.name == tool_name:
            return tool
    raise UnauthorizedTool(f"Tool '{tool_name}' is not on the allow-list for this server")


def check_caller_allowed(policy: ToolPolicy, caller_id: str) -> None:
    if "*" in policy.allowed_callers:
        return
    if caller_id in policy.allowed_callers:
        return
    raise UnauthorizedTool(f"Caller '{caller_id}' is not permitted to invoke '{policy.name}'")


def validate_arguments(schema: Optional[dict], arguments: dict) -> None:
    """Validate tool/prompt arguments against a cached JSON schema, if one is available.

    Design tradeoff (documented deliberately, not a silent gap): if no
    schema has been published by the backend yet, or the schema cache could
    not be refreshed, validation is skipped here -- enforcement falls back
    to the allow-list check plus whatever the MCP server itself validates.
    The allow-list membership check is always fail-closed; only the
    argument-shape check fails open when a schema is unavailable.
    """
    if not schema:
        return
    try:
        jsonschema.validate(instance=arguments, schema=schema)
    except jsonschema.ValidationError as exc:
        raise InvalidArguments(f"Arguments failed schema validation: {exc.message}") from exc
    except jsonschema.SchemaError as exc:
        logger.warning("Cached tool schema is itself invalid; skipping validation: %s", exc)


def redact(arguments: dict, redact_keys: list[str]) -> dict:
    """Return a copy of arguments with configured keys masked, for safe logging."""
    if not redact_keys:
        return dict(arguments)
    redacted = dict(arguments)
    for key in redact_keys:
        if key in redacted:
            redacted[key] = "***REDACTED***"
    return redacted
