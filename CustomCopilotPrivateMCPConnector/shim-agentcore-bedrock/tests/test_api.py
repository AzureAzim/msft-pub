"""API-level tests for the shim's FastAPI routes.

These tests patch AgentCoreMcpClient.invoke/initialize_session so the
routes, auth, allow-list, and schema-validation logic can be exercised
end-to-end through FastAPI's TestClient without any AWS calls. See
tests/test_agentcore_client.py for tests that instead exercise the real
boto3 client wrapper via botocore Stubber.
"""
from __future__ import annotations

from typing import Any, Optional

import pytest
from fastapi.testclient import TestClient

from app import mcp_protocol as m
from app.agentcore_client import AgentCoreMcpClient, InvokeResult

TOOLS_LIST_RESULT = {
    "tools": [
        {
            "name": "echoTool",
            "inputSchema": {
                "type": "object",
                "properties": {"message": {"type": "string"}},
                "required": ["message"],
                "additionalProperties": False,
            },
        },
        {"name": "adminOnlyTool", "inputSchema": {"type": "object", "properties": {}}},
        {"name": "failingTool", "inputSchema": {"type": "object", "properties": {}}},
        {"name": "protocolErrorTool", "inputSchema": {"type": "object", "properties": {}}},
    ]
}


def _fake_invoke(
    self: AgentCoreMcpClient,
    rpc_request: dict,
    runtime_session_id: str,
    mcp_session_id: Optional[str],
    idempotent: bool,
) -> InvokeResult:
    method = rpc_request["method"]
    req_id = rpc_request.get("id")

    if method == "tools/list":
        rpc = m.RpcResponse(id=req_id, result=TOOLS_LIST_RESULT)
    elif method == "tools/call":
        name = rpc_request["params"]["name"]
        args = rpc_request["params"]["arguments"]
        if name == "echoTool":
            rpc = m.RpcResponse(
                id=req_id, result={"content": [{"type": "text", "text": f"echo:{args.get('message')}"}]}
            )
        elif name == "adminOnlyTool":
            rpc = m.RpcResponse(id=req_id, result={"content": [{"type": "text", "text": "admin-ok"}]})
        elif name == "failingTool":
            rpc = m.RpcResponse(
                id=req_id, result={"isError": True, "content": [{"type": "text", "text": "tool failed"}]}
            )
        elif name == "protocolErrorTool":
            rpc = m.RpcResponse(id=req_id, error={"code": -32000, "message": "server error"})
        else:
            rpc = m.RpcResponse(id=req_id, error={"code": -32601, "message": "unknown tool"})
    elif method == "resources/read":
        rpc = m.RpcResponse(
            id=req_id, result={"contents": [{"uri": rpc_request["params"]["uri"], "text": "resource-data"}]}
        )
    elif method == "prompts/get":
        rpc = m.RpcResponse(id=req_id, result={"messages": [{"role": "user", "content": "rendered"}]})
    else:
        rpc = m.RpcResponse(id=req_id, error={"code": -32601, "message": "unknown method"})

    return InvokeResult(
        rpc=rpc,
        runtime_session_id=runtime_session_id,
        mcp_session_id=mcp_session_id or "fake-mcp-session",
        elapsed_ms=1,
    )


def _fake_initialize_session(self: AgentCoreMcpClient, runtime_session_id: str) -> InvokeResult:
    return InvokeResult(
        rpc=m.RpcResponse(id=1, result={"protocolVersion": "2025-06-18"}),
        runtime_session_id=runtime_session_id,
        mcp_session_id="fake-mcp-session",
        elapsed_ms=1,
    )


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(AgentCoreMcpClient, "invoke", _fake_invoke)
    monkeypatch.setattr(AgentCoreMcpClient, "initialize_session", _fake_initialize_session)

    from app.main import app as fastapi_app

    with TestClient(fastapi_app) as test_client:
        yield test_client


def test_health_does_not_require_auth(client: TestClient):
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["serverId"] == "test-server"


def test_list_servers_requires_auth(client: TestClient):
    resp = client.get("/v1/servers")
    assert resp.status_code == 401
    body = resp.json()
    assert body["error"]["code"] == "Unauthenticated"
    assert "correlationId" in body["error"]


def test_list_servers_success(client: TestClient, basic_auth_header: dict[str, str]):
    resp = client.get("/v1/servers", headers=basic_auth_header)
    assert resp.status_code == 200
    servers = resp.json()
    assert servers == [{"serverId": "test-server", "displayName": "Test MCP server"}]


def test_list_tools_hides_tools_caller_cannot_see(client: TestClient, basic_auth_header: dict[str, str]):
    resp = client.get("/v1/servers/test-server/tools", headers=basic_auth_header)
    assert resp.status_code == 200
    names = {tool["name"] for tool in resp.json()}
    # test-user is allowed on every wildcard-allow-listed tool but not
    # adminOnlyTool (allowedCallers: ["only-admin-user"]).
    assert names == {"echoTool", "failingTool", "protocolErrorTool"}


def test_unknown_server_id_returns_404(client: TestClient, basic_auth_header: dict[str, str]):
    resp = client.get("/v1/servers/does-not-exist/tools", headers=basic_auth_header)
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "UnknownTarget"


def test_invoke_tool_success(client: TestClient, basic_auth_header: dict[str, str]):
    resp = client.post(
        "/v1/servers/test-server/tools/echoTool:invoke",
        headers=basic_auth_header,
        json={"arguments": {"message": "hi"}},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "succeeded"
    assert body["content"] == [{"type": "text", "value": "echo:hi"}]
    assert body["serverId"] == "test-server"
    assert body["toolName"] == "echoTool"
    assert "correlationId" in body


def test_invoke_tool_not_on_allow_list_is_forbidden(client: TestClient, basic_auth_header: dict[str, str]):
    resp = client.post(
        "/v1/servers/test-server/tools/notConfiguredTool:invoke",
        headers=basic_auth_header,
        json={"arguments": {}},
    )
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "UnauthorizedTool"


def test_invoke_tool_caller_not_in_allow_list_is_forbidden(client: TestClient, basic_auth_header: dict[str, str]):
    # adminOnlyTool only allows caller "only-admin-user"; the test client
    # authenticates as "test-user".
    resp = client.post(
        "/v1/servers/test-server/tools/adminOnlyTool:invoke",
        headers=basic_auth_header,
        json={"arguments": {}},
    )
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "UnauthorizedTool"


def test_invoke_tool_missing_required_argument_is_invalid(client: TestClient, basic_auth_header: dict[str, str]):
    resp = client.post(
        "/v1/servers/test-server/tools/echoTool:invoke",
        headers=basic_auth_header,
        json={"arguments": {}},  # missing required "message"
    )
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "InvalidArguments"


def test_invoke_tool_requested_timeout_above_ceiling_is_invalid(client: TestClient, basic_auth_header: dict[str, str]):
    resp = client.post(
        "/v1/servers/test-server/tools/echoTool:invoke",
        headers=basic_auth_header,
        json={"arguments": {"message": "hi"}, "executionOptions": {"timeoutSeconds": 9999}},
    )
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "InvalidArguments"


def test_invoke_tool_that_reports_a_tool_level_error_returns_200_failed(
    client: TestClient, basic_auth_header: dict[str, str]
):
    resp = client.post(
        "/v1/servers/test-server/tools/failingTool:invoke",
        headers=basic_auth_header,
        json={"arguments": {}},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "failed"
    assert body["content"] == [{"type": "text", "value": "tool failed"}]


def test_invoke_tool_protocol_error_maps_to_backend_protocol_error(
    client: TestClient, basic_auth_header: dict[str, str]
):
    resp = client.post(
        "/v1/servers/test-server/tools/protocolErrorTool:invoke",
        headers=basic_auth_header,
        json={"arguments": {}},
    )
    assert resp.status_code == 502
    assert resp.json()["error"]["code"] == "BackendProtocolError"


def test_read_resource_success(client: TestClient, basic_auth_header: dict[str, str]):
    resp = client.post(
        "/v1/servers/test-server/resources:read",
        headers=basic_auth_header,
        json={"uri": "res://example"},
    )
    assert resp.status_code == 200
    assert resp.json()["contents"][0]["text"] == "resource-data"


def test_read_resource_not_on_allow_list(client: TestClient, basic_auth_header: dict[str, str]):
    resp = client.post(
        "/v1/servers/test-server/resources:read",
        headers=basic_auth_header,
        json={"uri": "res://not-configured"},
    )
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "UnknownTarget"


def test_render_prompt_success(client: TestClient, basic_auth_header: dict[str, str]):
    resp = client.post(
        "/v1/servers/test-server/prompts/examplePrompt:render",
        headers=basic_auth_header,
        json={"arguments": {}},
    )
    assert resp.status_code == 200
    assert resp.json()["messages"] == [{"role": "user", "content": "rendered"}]


def test_render_unknown_prompt_is_404(client: TestClient, basic_auth_header: dict[str, str]):
    resp = client.post(
        "/v1/servers/test-server/prompts/notConfiguredPrompt:render",
        headers=basic_auth_header,
        json={"arguments": {}},
    )
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "UnknownTarget"


def test_wrong_basic_credentials_are_unauthenticated(client: TestClient):
    import base64

    bad_header = {"Authorization": f"Basic {base64.b64encode(b'test-user:wrong-pass').decode()}"}
    resp = client.get("/v1/servers", headers=bad_header)
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "Unauthenticated"
