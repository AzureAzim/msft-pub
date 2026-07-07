"""Amazon Bedrock AgentCore Runtime client for the MCP shim.

Wraps `boto3`'s `bedrock-agentcore` client so the rest of the shim only
deals with MCP JSON-RPC requests/responses, never AWS SDK details.

Networking note: this client does not need to know whether it is talking to
AgentCore over the public endpoint or over a PrivateLink interface VPC
endpoint. When a `com.amazonaws.<region>.bedrock-agentcore` interface
endpoint with private DNS enabled exists in the shim's VPC, the region's
default endpoint (`bedrock-agentcore.<region>.amazonaws.com`) transparently
resolves to the private ENI and every `invoke_agent_runtime` call stays on
AWS's private network. See docs/a2-howto-agentcore-bedrock.md, step 3.
"""
from __future__ import annotations

import json
import logging
import time
import uuid
from dataclasses import dataclass
from typing import Any, Optional

import boto3
from botocore.config import Config as BotoConfig
from botocore.exceptions import (
    ClientError,
    ConnectTimeoutError,
    EndpointConnectionError,
    ReadTimeoutError,
)

from . import mcp_protocol
from .config import AwsConfig, McpConfig
from .errors import (
    BackendProtocolError,
    BackendTimeout,
    BackendUnavailable,
    InvalidArguments,
    QuotaExceeded,
    ShimError,
    ToolConflict,
    UnknownTarget,
    error_for_code,
)

logger = logging.getLogger("shim.agentcore_client")


@dataclass
class InvokeResult:
    rpc: mcp_protocol.RpcResponse
    runtime_session_id: str
    mcp_session_id: Optional[str]
    elapsed_ms: int


def new_runtime_session_id() -> str:
    """Generate a runtimeSessionId meeting AgentCore's 33-256 character requirement.

    A UUID4 hex string prefixed with a stable label comfortably satisfies the
    minimum length and stays well under the maximum.
    """
    return f"ppmcp-{uuid.uuid4().hex}-{uuid.uuid4().hex[:8]}"


def _read_capped(streaming_body, max_bytes: int) -> tuple[bytes, bool]:
    """Read a botocore StreamingBody up to max_bytes + 1 to detect truncation
    without holding an unbounded amount of an oversized response in memory.

    Accepts anything with a `.read(size)` method (the real StreamingBody
    boto3 returns in production, or an io.BytesIO used in tests) as well as
    plain bytes, defensively.
    """
    if isinstance(streaming_body, (bytes, bytearray)):
        data = bytes(streaming_body)
        return data[: max_bytes + 1], len(data) > max_bytes

    chunks: list[bytes] = []
    total = 0
    chunk_size = 65536
    while True:
        chunk = streaming_body.read(chunk_size)
        if not chunk:
            break
        chunks.append(chunk)
        total += len(chunk)
        if total > max_bytes:
            return b"".join(chunks), True
    return b"".join(chunks), False


class AgentCoreMcpClient:
    """MCP client whose transport is Amazon Bedrock AgentCore's InvokeAgentRuntime API.

    Rather than opening a raw Streamable HTTP connection to the MCP server,
    the shim constructs MCP JSON-RPC envelopes itself and hands them to
    boto3's `invoke_agent_runtime`, which SigV4-signs the call using the
    compute's IAM role and tunnels the payload through to the MCP server
    container running inside AgentCore Runtime. This avoids having to
    reimplement a SigV4-aware Streamable HTTP client, and matches the
    pattern AWS's own documentation uses for calling MCP servers hosted on
    AgentCore Runtime with IAM (SigV4) authentication.
    """

    def __init__(self, aws_config: AwsConfig, mcp_config: McpConfig):
        self._aws_config = aws_config
        self._mcp_config = mcp_config
        client_kwargs: dict[str, Any] = {
            "region_name": aws_config.region,
            "config": BotoConfig(
                retries={"max_attempts": 0},  # the shim owns its own retry policy
                connect_timeout=10,
                read_timeout=mcp_config.request_timeout_seconds,
            ),
        }
        if aws_config.endpoint_url:
            # Local/dev testing only -- see AwsConfig.endpoint_url.
            client_kwargs["endpoint_url"] = aws_config.endpoint_url
        self._client = boto3.client("bedrock-agentcore", **client_kwargs)

    def _invoke_once(
        self,
        rpc_request: dict,
        runtime_session_id: str,
        mcp_session_id: Optional[str],
    ) -> InvokeResult:
        payload = json.dumps(rpc_request).encode("utf-8")
        kwargs: dict[str, Any] = {
            "agentRuntimeArn": self._aws_config.agent_runtime_arn,
            "qualifier": self._aws_config.qualifier,
            "runtimeSessionId": runtime_session_id,
            "contentType": "application/json",
            "accept": "application/json, text/event-stream",
            "mcpProtocolVersion": self._mcp_config.protocol_version,
            "payload": payload,
        }
        if mcp_session_id:
            kwargs["mcpSessionId"] = mcp_session_id

        started = time.monotonic()
        try:
            response = self._client.invoke_agent_runtime(**kwargs)
        except self._client.exceptions.ValidationException as exc:
            raise InvalidArguments(f"AgentCore rejected the request: {exc}") from exc
        except self._client.exceptions.ResourceNotFoundException as exc:
            raise UnknownTarget(f"AgentCore Runtime ARN or qualifier not found: {exc}") from exc
        except self._client.exceptions.ThrottlingException as exc:
            # Transient rate limiting -- safe to retry once for idempotent calls.
            raise QuotaExceeded(f"AgentCore Runtime is throttling requests: {exc}", retryable=True) from exc
        except self._client.exceptions.ServiceQuotaExceededException as exc:
            # A hard quota/limit, not a transient rate limit -- retrying
            # immediately will not help, so this is NOT marked retryable.
            raise QuotaExceeded(f"AgentCore Runtime service quota exceeded: {exc}", retryable=False) from exc
        except self._client.exceptions.RetryableConflictException as exc:
            raise ToolConflict(
                f"AgentCore Runtime reported a retryable conflict: {exc}", retryable=True
            ) from exc
        except self._client.exceptions.AccessDeniedException as exc:
            # The caller already passed shim-level authn/authz; a denial here
            # means the shim's own IAM role/endpoint policy is misconfigured.
            # Retrying immediately will not fix a permissions problem.
            raise BackendUnavailable(
                f"Shim IAM identity is not authorized to invoke AgentCore Runtime: {exc}", retryable=False
            ) from exc
        except self._client.exceptions.RuntimeClientError as exc:
            raise BackendProtocolError(f"MCP server container returned an error: {exc}") from exc
        except self._client.exceptions.InternalServerException as exc:
            raise BackendUnavailable(f"AgentCore Runtime internal error: {exc}", retryable=True) from exc
        except (ReadTimeoutError, ConnectTimeoutError) as exc:
            raise BackendTimeout(f"Timed out calling AgentCore Runtime: {exc}", retryable=True) from exc
        except EndpointConnectionError as exc:
            raise BackendUnavailable(f"Could not reach AgentCore Runtime endpoint: {exc}", retryable=True) from exc
        except ClientError as exc:
            raise BackendUnavailable(f"AgentCore Runtime call failed: {exc}") from exc

        body, was_truncated = _read_capped(response["response"], self._mcp_config.max_response_bytes)
        if was_truncated:
            raise BackendProtocolError(
                f"AgentCore response exceeded the {self._mcp_config.max_response_bytes}-byte limit"
            )

        content_type = response.get("contentType") or "application/json"
        expected_id = rpc_request.get("id")
        try:
            if "text/event-stream" in content_type:
                rpc = mcp_protocol.flatten_sse_response(body.decode("utf-8"), expected_id)
            else:
                rpc = mcp_protocol.parse_json_response(body, expected_id)
        except mcp_protocol.McpProtocolError as exc:
            raise BackendProtocolError(str(exc)) from exc

        elapsed_ms = int((time.monotonic() - started) * 1000)
        return InvokeResult(
            rpc=rpc,
            runtime_session_id=response.get("runtimeSessionId") or runtime_session_id,
            mcp_session_id=response.get("mcpSessionId") or mcp_session_id,
            elapsed_ms=elapsed_ms,
        )

    def invoke(
        self,
        rpc_request: dict,
        runtime_session_id: str,
        mcp_session_id: Optional[str],
        idempotent: bool,
    ) -> InvokeResult:
        """Invoke the MCP server through AgentCore, retrying once for idempotent calls.

        Per the parent spec's reliability requirements, only idempotent
        operations (tools/list, resources/read, prompts/get, and any
        tools/call explicitly marked idempotent in the allow-list) are
        retried, and only when the specific failure is itself marked
        `retryable` (see ShimError.retryable and the exception mapping
        above -- e.g. SigV4 throttling is retryable, a hard service quota
        or an IAM permissions error is not). Mutating tool calls are never
        retried automatically, to avoid double execution.
        """
        try:
            return self._invoke_once(rpc_request, runtime_session_id, mcp_session_id)
        except ShimError as exc:
            if not (idempotent and exc.retryable):
                raise
            logger.warning(
                "Transient AgentCore failure (%s) on an idempotent call; retrying once", exc.code
            )
            return self._invoke_once(rpc_request, runtime_session_id, mcp_session_id)

    def initialize_session(self, runtime_session_id: str) -> InvokeResult:
        """Perform the MCP `initialize` handshake for a fresh logical session.

        AgentCore's recommended default is stateless MCP mode, where the
        platform accepts and echoes back a caller-supplied session id rather
        than requiring a stateful handshake. This call still exercises
        `initialize` so genuinely stateful MCP servers (see the parent spec's
        session strategy discussion) work without special-casing.
        """
        request = mcp_protocol.build_initialize_request(self._mcp_config.protocol_version)
        result = self.invoke(request, runtime_session_id, mcp_session_id=None, idempotent=True)
        if result.rpc.is_protocol_error:
            error = result.rpc.error or {}
            raise error_for_code(
                mcp_protocol.classify_rpc_error_code(error),
                error.get("message", "MCP initialize failed"),
            )
        return result
