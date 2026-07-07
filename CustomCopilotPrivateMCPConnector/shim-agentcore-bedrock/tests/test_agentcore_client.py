"""Unit tests for the Amazon Bedrock AgentCore Runtime client wrapper.

Uses botocore's Stubber against a real (but credential-less/offline)
bedrock-agentcore client so these tests exercise the exact exception types
and response shape the live AWS SDK uses, without any network access.
"""
from __future__ import annotations

import io
import json

import pytest
from botocore.stub import Stubber

from app import mcp_protocol as m
from app.agentcore_client import AgentCoreMcpClient, new_runtime_session_id
from app.config import AwsConfig, McpConfig
from app.errors import (
    BackendProtocolError,
    BackendUnavailable,
    InvalidArguments,
    QuotaExceeded,
    ToolConflict,
    UnknownTarget,
)

AGENT_RUNTIME_ARN = "arn:aws:bedrock-agentcore:us-east-1:123456789012:runtime/test-abc123"


def _make_client() -> AgentCoreMcpClient:
    aws_config = AwsConfig(region="us-east-1", agentRuntimeArn=AGENT_RUNTIME_ARN, qualifier="DEFAULT")
    mcp_config = McpConfig(requestTimeoutSeconds=5, maxResponseBytes=1_000_000)
    return AgentCoreMcpClient(aws_config, mcp_config)


def _stub_success(client: AgentCoreMcpClient, rpc_result: dict, runtime_session_id: str, mcp_session_id="mcp-sess-1"):
    body = json.dumps(rpc_result).encode()
    stubber = Stubber(client._client)
    stubber.add_response(
        "invoke_agent_runtime",
        {
            "runtimeSessionId": runtime_session_id,
            "mcpSessionId": mcp_session_id,
            "contentType": "application/json",
            "statusCode": 200,
            "response": io.BytesIO(body),
        },
    )
    stubber.activate()
    return stubber


def test_new_runtime_session_id_meets_agentcore_length_bounds():
    session_id = new_runtime_session_id()
    assert 33 <= len(session_id) <= 256


def test_initialize_session_success():
    client = _make_client()
    runtime_session_id = new_runtime_session_id()
    stubber = _stub_success(
        client,
        {"jsonrpc": "2.0", "id": 1, "result": {"protocolVersion": "2025-06-18"}},
        runtime_session_id,
    )
    result = client.initialize_session(runtime_session_id)
    assert result.mcp_session_id == "mcp-sess-1"
    assert result.runtime_session_id == runtime_session_id
    stubber.deactivate()


def test_invoke_tools_call_success():
    client = _make_client()
    runtime_session_id = new_runtime_session_id()
    stubber = _stub_success(
        client,
        {"jsonrpc": "2.0", "id": 5, "result": {"content": [{"type": "text", "text": "42"}]}},
        runtime_session_id,
    )
    request = m.build_tools_call_request("echoTool", {"message": "hi"}, request_id=5)
    result = client.invoke(request, runtime_session_id, "mcp-sess-1", idempotent=True)
    assert not result.rpc.is_protocol_error
    assert result.rpc.result["content"][0]["text"] == "42"
    stubber.deactivate()


def test_invoke_maps_validation_exception_to_invalid_arguments():
    client = _make_client()
    stubber = Stubber(client._client)
    stubber.add_client_error(
        "invoke_agent_runtime", service_error_code="ValidationException", service_message="bad params"
    )
    stubber.activate()
    request = m.build_tools_call_request("echoTool", {}, request_id=1)
    with pytest.raises(InvalidArguments):
        client.invoke(request, new_runtime_session_id(), None, idempotent=False)
    stubber.deactivate()


def test_invoke_maps_resource_not_found_to_unknown_target():
    client = _make_client()
    stubber = Stubber(client._client)
    stubber.add_client_error(
        "invoke_agent_runtime", service_error_code="ResourceNotFoundException", service_message="no such runtime"
    )
    stubber.activate()
    request = m.build_tools_list_request(request_id=1)
    with pytest.raises(UnknownTarget):
        client.invoke(request, new_runtime_session_id(), None, idempotent=True)
    stubber.deactivate()


def test_invoke_maps_throttling_to_quota_exceeded_and_retries_idempotent():
    client = _make_client()
    stubber = Stubber(client._client)
    # First call throttled, second call (the idempotent retry) succeeds.
    stubber.add_client_error(
        "invoke_agent_runtime", service_error_code="ThrottlingException", service_message="slow down"
    )
    runtime_session_id = new_runtime_session_id()
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "result": {"tools": []}}).encode()
    stubber.add_response(
        "invoke_agent_runtime",
        {
            "runtimeSessionId": runtime_session_id,
            "contentType": "application/json",
            "statusCode": 200,
            "response": io.BytesIO(body),
        },
    )
    stubber.activate()
    request = m.build_tools_list_request(request_id=1)
    result = client.invoke(request, runtime_session_id, None, idempotent=True)
    assert result.rpc.result == {"tools": []}
    stubber.deactivate()


def test_invoke_maps_throttling_without_retry_for_non_idempotent():
    client = _make_client()
    stubber = Stubber(client._client)
    stubber.add_client_error(
        "invoke_agent_runtime", service_error_code="ThrottlingException", service_message="slow down"
    )
    stubber.activate()
    request = m.build_tools_call_request("createSupportTicket", {}, request_id=1)
    with pytest.raises(QuotaExceeded):
        client.invoke(request, new_runtime_session_id(), None, idempotent=False)
    stubber.deactivate()


def test_invoke_maps_retryable_conflict_to_tool_conflict():
    client = _make_client()
    stubber = Stubber(client._client)
    stubber.add_client_error(
        "invoke_agent_runtime", service_error_code="RetryableConflictException", service_message="try again"
    )
    stubber.activate()
    request = m.build_tools_call_request("echoTool", {}, request_id=1)
    with pytest.raises(ToolConflict):
        client.invoke(request, new_runtime_session_id(), None, idempotent=False)
    stubber.deactivate()


def test_invoke_maps_internal_server_error_to_backend_unavailable():
    client = _make_client()
    stubber = Stubber(client._client)
    stubber.add_client_error(
        "invoke_agent_runtime", service_error_code="InternalServerException", service_message="oops"
    )
    stubber.activate()
    request = m.build_tools_call_request("echoTool", {}, request_id=1)
    with pytest.raises(BackendUnavailable):
        client.invoke(request, new_runtime_session_id(), None, idempotent=False)
    stubber.deactivate()


def test_invoke_raises_backend_protocol_error_on_malformed_body():
    client = _make_client()
    runtime_session_id = new_runtime_session_id()
    stubber = Stubber(client._client)
    stubber.add_response(
        "invoke_agent_runtime",
        {
            "runtimeSessionId": runtime_session_id,
            "contentType": "application/json",
            "statusCode": 200,
            "response": io.BytesIO(b"not json"),
        },
    )
    stubber.activate()
    request = m.build_tools_list_request(request_id=1)
    with pytest.raises(BackendProtocolError):
        client.invoke(request, runtime_session_id, None, idempotent=True)
    stubber.deactivate()


def test_invoke_raises_backend_protocol_error_when_response_exceeds_max_bytes():
    aws_config = AwsConfig(region="us-east-1", agentRuntimeArn=AGENT_RUNTIME_ARN, qualifier="DEFAULT")
    mcp_config = McpConfig(requestTimeoutSeconds=5, maxResponseBytes=10)
    client = AgentCoreMcpClient(aws_config, mcp_config)
    runtime_session_id = new_runtime_session_id()
    oversized_body = json.dumps({"jsonrpc": "2.0", "id": 1, "result": {"padding": "x" * 500}}).encode()
    stubber = Stubber(client._client)
    stubber.add_response(
        "invoke_agent_runtime",
        {
            "runtimeSessionId": runtime_session_id,
            "contentType": "application/json",
            "statusCode": 200,
            "response": io.BytesIO(oversized_body),
        },
    )
    stubber.activate()
    request = m.build_tools_list_request(request_id=1)
    with pytest.raises(BackendProtocolError):
        client.invoke(request, runtime_session_id, None, idempotent=True)
    stubber.deactivate()


def test_invoke_flattens_sse_response():
    client = _make_client()
    runtime_session_id = new_runtime_session_id()
    sse_body = (
        'data: {"jsonrpc": "2.0", "method": "notifications/progress", "params": {}}\n'
        "\n"
        'data: {"jsonrpc": "2.0", "id": 9, "result": {"content": []}}\n'
        "\n"
    ).encode()
    stubber = Stubber(client._client)
    stubber.add_response(
        "invoke_agent_runtime",
        {
            "runtimeSessionId": runtime_session_id,
            "mcpSessionId": "mcp-sess-2",
            "contentType": "text/event-stream",
            "statusCode": 200,
            "response": io.BytesIO(sse_body),
        },
    )
    stubber.activate()
    request = m.build_tools_call_request("echoTool", {}, request_id=9)
    result = client.invoke(request, runtime_session_id, None, idempotent=True)
    assert result.rpc.result == {"content": []}
    assert len(result.rpc.events) == 1
    stubber.deactivate()
