"""Unit tests for MCP JSON-RPC envelope construction and response parsing."""
from __future__ import annotations

import json

import pytest

from app import mcp_protocol as m


def test_build_tools_call_request_shape():
    req = m.build_tools_call_request("echoTool", {"message": "hi"})
    assert req["jsonrpc"] == "2.0"
    assert req["method"] == "tools/call"
    assert req["params"] == {"name": "echoTool", "arguments": {"message": "hi"}}
    assert isinstance(req["id"], int)


def test_build_initialize_request_includes_protocol_version():
    req = m.build_initialize_request("2025-06-18")
    assert req["method"] == "initialize"
    assert req["params"]["protocolVersion"] == "2025-06-18"


def test_build_notification_has_no_id():
    note = m.build_notification("notifications/initialized")
    assert "id" not in note
    assert note["method"] == "notifications/initialized"


def test_parse_json_response_success():
    body = json.dumps({"jsonrpc": "2.0", "id": 42, "result": {"tools": []}}).encode()
    resp = m.parse_json_response(body, 42)
    assert resp.result == {"tools": []}
    assert not resp.is_protocol_error
    assert not resp.is_tool_error


def test_parse_json_response_protocol_error():
    body = json.dumps({"jsonrpc": "2.0", "id": 42, "error": {"code": -32602, "message": "bad"}}).encode()
    resp = m.parse_json_response(body, 42)
    assert resp.is_protocol_error
    assert m.classify_rpc_error_code(resp.error) == "InvalidArguments"


def test_classify_rpc_error_code_unknown_method():
    assert m.classify_rpc_error_code({"code": -32601, "message": "no such method"}) == "UnknownTarget"


def test_classify_rpc_error_code_falls_back_to_backend_protocol_error():
    assert m.classify_rpc_error_code({"code": -32000, "message": "server error"}) == "BackendProtocolError"


def test_parse_json_response_id_mismatch_raises():
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "result": {}}).encode()
    with pytest.raises(m.McpProtocolError):
        m.parse_json_response(body, 2)


def test_parse_json_response_missing_jsonrpc_marker_raises():
    body = json.dumps({"id": 1, "result": {}}).encode()
    with pytest.raises(m.McpProtocolError):
        m.parse_json_response(body, 1)


def test_parse_json_response_malformed_body_raises():
    with pytest.raises(m.McpProtocolError):
        m.parse_json_response(b"not json", 1)


def test_tool_error_detected_without_being_a_protocol_error():
    body = json.dumps(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "result": {"isError": True, "content": [{"type": "text", "text": "boom"}]},
        }
    ).encode()
    resp = m.parse_json_response(body, 1)
    assert resp.is_tool_error
    assert not resp.is_protocol_error


def test_flatten_sse_response_collects_interim_events_and_final_result():
    sse_text = (
        'data: {"jsonrpc": "2.0", "method": "notifications/progress", "params": {"pct": 50}}\n'
        "\n"
        'data: {"jsonrpc": "2.0", "id": 7, "result": {"ok": true}}\n'
        "\n"
    )
    resp = m.flatten_sse_response(sse_text, 7)
    assert resp.result == {"ok": True}
    assert len(resp.events) == 1
    assert resp.events[0]["method"] == "notifications/progress"


def test_flatten_sse_response_missing_final_raises():
    sse_text = 'data: {"jsonrpc": "2.0", "method": "notifications/progress"}\n\n'
    with pytest.raises(m.McpProtocolError):
        m.flatten_sse_response(sse_text, 99)


def test_flatten_sse_response_ignores_non_json_keepalive_lines():
    sse_text = ": keep-alive\n\ndata: {\"jsonrpc\": \"2.0\", \"id\": 3, \"result\": {}}\n\n"
    resp = m.flatten_sse_response(sse_text, 3)
    assert resp.result == {}
    assert resp.events == []


def test_parse_sse_events_handles_multiline_data_payload():
    # A single JSON payload split across two `data:` lines must be
    # concatenated before parsing, per the SSE spec.
    sse_text = 'data: {"jsonrpc": "2.0",\ndata: "id": 1, "result": {}}\n\n'
    events = m.parse_sse_events(sse_text)
    assert events == [{"jsonrpc": "2.0", "id": 1, "result": {}}]
