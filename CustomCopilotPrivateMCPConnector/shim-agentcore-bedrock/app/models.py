"""Request/response models for the shim's REST surface.

These mirror the connector action model in the parent spec
(docs/power-platform-mcp-private-proxy-connector-spec.md#connector-action-model)
exactly, so the same custom connector OpenAPI definition works unmodified
against either a Variant A1 central proxy or this Variant A2 adapter.
"""
from __future__ import annotations

from typing import Any, Literal, Optional

from pydantic import BaseModel, Field


class InvokeToolRequest(BaseModel):
    arguments: dict[str, Any] = Field(default_factory=dict)
    execution_options: Optional["ExecutionOptions"] = Field(default=None, alias="executionOptions")

    model_config = {"populate_by_name": True}


class ExecutionOptions(BaseModel):
    timeout_seconds: Optional[int] = Field(default=None, alias="timeoutSeconds")

    model_config = {"populate_by_name": True}


class ReadResourceRequest(BaseModel):
    uri: str


class RenderPromptRequest(BaseModel):
    arguments: dict[str, Any] = Field(default_factory=dict)


class ContentItem(BaseModel):
    type: Literal["json", "text"]
    value: Any


class InvokeToolResponse(BaseModel):
    server_id: str = Field(alias="serverId")
    tool_name: str = Field(alias="toolName")
    status: Literal["succeeded", "failed"]
    content: list[ContentItem]
    correlation_id: str = Field(alias="correlationId")
    elapsed_ms: int = Field(alias="elapsedMs")

    model_config = {"populate_by_name": True}


class ServerSummary(BaseModel):
    server_id: str = Field(alias="serverId")
    display_name: str = Field(alias="displayName")

    model_config = {"populate_by_name": True}


class ToolSummary(BaseModel):
    name: str
    idempotent: bool
    input_schema: dict[str, Any] = Field(default_factory=dict, alias="inputSchema")

    model_config = {"populate_by_name": True}


class HealthResponse(BaseModel):
    status: Literal["ok", "degraded"]
    server_id: str = Field(alias="serverId")
    active_sessions: int = Field(alias="activeSessions")

    model_config = {"populate_by_name": True}


class ErrorDetail(BaseModel):
    code: str
    message: str
    correlation_id: str = Field(alias="correlationId")
    details: list[Any] = Field(default_factory=list)

    model_config = {"populate_by_name": True}


class ErrorEnvelope(BaseModel):
    error: ErrorDetail
