"""MCP JSON-RPC 2.0 envelope construction and response parsing.

Amazon Bedrock AgentCore Runtime passes the InvokeAgentRuntime payload
through directly to the hosted MCP server and returns its raw response
(either `application/json` or `text/event-stream`), so this module speaks
plain MCP Streamable HTTP framing -- nothing AgentCore-specific leaks in
here. See docs/a2-howto-agentcore-bedrock.md for how this fits into the
overall request lifecycle.
"""
from __future__ import annotations

import itertools
import json
from dataclasses import dataclass, field
from typing import Any, Optional

_id_counter = itertools.count(1)


class McpProtocolError(Exception):
    """Raised when a backend response cannot be interpreted as MCP JSON-RPC."""


def next_request_id() -> int:
    return next(_id_counter)


def build_request(method: str, params: Optional[dict] = None, request_id: Optional[int] = None) -> dict:
    envelope: dict[str, Any] = {
        "jsonrpc": "2.0",
        "method": method,
        "id": request_id if request_id is not None else next_request_id(),
    }
    if params is not None:
        envelope["params"] = params
    return envelope


def build_notification(method: str, params: Optional[dict] = None) -> dict:
    """Notifications (e.g. notifications/initialized) carry no id and expect no response."""
    envelope: dict[str, Any] = {"jsonrpc": "2.0", "method": method}
    if params is not None:
        envelope["params"] = params
    return envelope


def build_initialize_request(protocol_version: str, request_id: Optional[int] = None) -> dict:
    return build_request(
        "initialize",
        {
            "protocolVersion": protocol_version,
            "capabilities": {},
            "clientInfo": {"name": "power-platform-mcp-shim", "version": "1.0.0"},
        },
        request_id=request_id,
    )


def build_tools_list_request(request_id: Optional[int] = None) -> dict:
    return build_request("tools/list", {}, request_id=request_id)


def build_tools_call_request(tool_name: str, arguments: dict, request_id: Optional[int] = None) -> dict:
    return build_request("tools/call", {"name": tool_name, "arguments": arguments}, request_id=request_id)


def build_resources_list_request(request_id: Optional[int] = None) -> dict:
    return build_request("resources/list", {}, request_id=request_id)


def build_resources_read_request(uri: str, request_id: Optional[int] = None) -> dict:
    return build_request("resources/read", {"uri": uri}, request_id=request_id)


def build_prompts_list_request(request_id: Optional[int] = None) -> dict:
    return build_request("prompts/list", {}, request_id=request_id)


def build_prompts_get_request(prompt_name: str, arguments: dict, request_id: Optional[int] = None) -> dict:
    return build_request("prompts/get", {"name": prompt_name, "arguments": arguments}, request_id=request_id)


@dataclass
class RpcResponse:
    """A parsed JSON-RPC response, plus any interim SSE events buffered alongside it."""

    id: Any
    result: Optional[dict] = None
    error: Optional[dict] = None
    events: list[dict] = field(default_factory=list)

    @property
    def is_protocol_error(self) -> bool:
        """True if the MCP server rejected the request at the JSON-RPC level."""
        return self.error is not None

    @property
    def is_tool_error(self) -> bool:
        """True if a tools/call succeeded at the protocol level but the tool itself failed.

        Per the MCP spec, tool execution failures are reported as a normal
        JSON-RPC result with `isError: true`, not as a JSON-RPC protocol error.
        """
        return bool(self.result and self.result.get("isError"))


def classify_rpc_error_code(error: dict) -> str:
    """Map a JSON-RPC error object to one of the shim's documented error codes."""
    code = error.get("code")
    if code == -32602:
        return "InvalidArguments"
    if code == -32601:
        return "UnknownTarget"
    return "BackendProtocolError"


def _rpc_response_from_dict(data: dict, expected_id: Any) -> RpcResponse:
    if data.get("jsonrpc") != "2.0":
        raise McpProtocolError("Response is missing the jsonrpc=2.0 marker")
    if expected_id is not None and "id" in data and data.get("id") != expected_id:
        raise McpProtocolError(
            f"Response id {data.get('id')!r} does not match request id {expected_id!r}"
        )
    return RpcResponse(id=data.get("id"), result=data.get("result"), error=data.get("error"))


def parse_json_response(body: bytes, expected_id: Any) -> RpcResponse:
    """Parse a plain application/json MCP response body."""
    try:
        data = json.loads(body)
    except json.JSONDecodeError as exc:
        raise McpProtocolError(f"Malformed JSON-RPC response: {exc}") from exc
    if not isinstance(data, dict):
        raise McpProtocolError("JSON-RPC response body must be a JSON object")
    return _rpc_response_from_dict(data, expected_id)


def parse_sse_events(text: str) -> list[dict]:
    """Split a text/event-stream body into its individual JSON payloads.

    Each SSE event is one or more `data:` lines followed by a blank line.
    Non-JSON payloads (e.g. keep-alive comments) are silently skipped.
    """
    events: list[dict] = []
    data_lines: list[str] = []

    def _flush() -> None:
        if not data_lines:
            return
        payload = "\n".join(data_lines)
        try:
            events.append(json.loads(payload))
        except json.JSONDecodeError:
            pass  # not a JSON-RPC payload (e.g. a keep-alive) -- ignore

    for raw_line in text.splitlines():
        line = raw_line.rstrip("\r")
        if line == "":
            _flush()
            data_lines = []
            continue
        if line.startswith("data:"):
            data_lines.append(line[len("data:"):].lstrip(" "))
        # event:, id:, retry:, and ":" comment lines are intentionally ignored;
        # the JSON-RPC `id` inside each `data:` payload is what we match on.
    _flush()
    return events


def flatten_sse_response(text: str, expected_id: Any) -> RpcResponse:
    """Flatten a buffered SSE body into one RpcResponse plus interim events.

    Power Automate and Power Apps do not parse text/event-stream, so the
    shim always buffers the stream server-side and returns plain JSON to the
    connector. Interim progress/log notifications are preserved in
    `RpcResponse.events` instead of being discarded.
    """
    all_events = parse_sse_events(text)
    final: Optional[dict] = None
    interim: list[dict] = []
    for event in all_events:
        if event.get("id") == expected_id and ("result" in event or "error" in event):
            final = event
        else:
            interim.append(event)
    if final is None:
        raise McpProtocolError(
            f"No JSON-RPC response with id={expected_id!r} found in SSE stream "
            f"({len(all_events)} event(s) buffered)"
        )
    response = _rpc_response_from_dict(final, expected_id)
    response.events = interim
    return response
