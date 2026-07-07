"""Configuration loading for the AgentCore MCP shim.

The shim fronts exactly one Amazon Bedrock AgentCore Runtime that hosts an
MCP server (Variant A2: thin adapter, single backend). Configuration is kept
outside the deployable container image so the same image runs at every site;
only this file (or the environment variables that override it) differs per
deployment.
"""
from __future__ import annotations

import os
from functools import lru_cache
from typing import Literal, Optional

import yaml
from pydantic import BaseModel, Field, field_validator


class ToolPolicy(BaseModel):
    """Allow-list entry for a single MCP tool."""

    name: str
    idempotent: bool = False
    timeout_seconds: int = Field(default=30, alias="timeoutSeconds")
    max_response_bytes: int = Field(default=262_144, alias="maxResponseBytes")
    allowed_callers: list[str] = Field(default_factory=lambda: ["*"], alias="allowedCallers")
    redact_arguments: list[str] = Field(default_factory=list, alias="redactArguments")

    model_config = {"populate_by_name": True}


class AllowedCapabilities(BaseModel):
    tools: list[ToolPolicy] = Field(default_factory=list)
    resources: list[ToolPolicy] = Field(default_factory=list)
    prompts: list[ToolPolicy] = Field(default_factory=list)


class AwsConfig(BaseModel):
    region: str
    agent_runtime_arn: str = Field(alias="agentRuntimeArn")
    qualifier: str = "DEFAULT"
    # Leave endpoint_url unset in every real deployment. When unset, boto3
    # resolves the region's default bedrock-agentcore endpoint, which -- when
    # a PrivateLink interface VPC endpoint with private DNS is present in the
    # shim's VPC -- transparently resolves to the private ENI instead of the
    # public endpoint. Only set this for local testing against a stub/mock.
    endpoint_url: Optional[str] = Field(default=None, alias="endpointUrl")

    model_config = {"populate_by_name": True}


class McpConfig(BaseModel):
    protocol_version: str = Field(default="2025-06-18", alias="protocolVersion")
    stateless: bool = True
    session_idle_ttl_minutes: int = Field(default=10, alias="sessionIdleTtlMinutes")
    request_timeout_seconds: int = Field(default=30, alias="requestTimeoutSeconds")
    # Aligned by default to the on-premises data gateway's 8 MB compressed
    # read-response limit so the shim fails fast instead of the gateway.
    max_response_bytes: int = Field(default=8_388_608, alias="maxResponseBytes")

    model_config = {"populate_by_name": True}


class BasicAuthConfig(BaseModel):
    username_env: str = Field(default="SHIM_BASIC_USERNAME", alias="usernameEnv")
    password_env: str = Field(default="SHIM_BASIC_PASSWORD", alias="passwordEnv")

    model_config = {"populate_by_name": True}


class OAuthEntraIdConfig(BaseModel):
    tenant_id: str = Field(alias="tenantId")
    audience: str

    model_config = {"populate_by_name": True}


CallerAuthType = Literal["basic", "windows", "oauthEntraId"]


class AuthConfig(BaseModel):
    caller_accepted_types: list[CallerAuthType] = Field(
        default_factory=lambda: ["oauthEntraId"], alias="callerAcceptedTypes"
    )
    basic: Optional[BasicAuthConfig] = None
    oauth_entra_id: Optional[OAuthEntraIdConfig] = Field(default=None, alias="oauthEntraId")

    model_config = {"populate_by_name": True}


class AuditConfig(BaseModel):
    local_path: str = Field(default="/var/log/mcp-shim/audit.log", alias="localPath")
    forward_to_siem: bool = Field(default=False, alias="forwardToSiem")

    model_config = {"populate_by_name": True}


class ShimConfig(BaseModel):
    server_id: str = Field(alias="serverId")
    display_name: str = Field(alias="displayName")
    aws: AwsConfig
    mcp: McpConfig = Field(default_factory=McpConfig)
    auth: AuthConfig = Field(default_factory=AuthConfig)
    allowed_capabilities: AllowedCapabilities = Field(
        default_factory=AllowedCapabilities, alias="allowedCapabilities"
    )
    audit: AuditConfig = Field(default_factory=AuditConfig)

    model_config = {"populate_by_name": True}

    @field_validator("server_id")
    @classmethod
    def _server_id_not_empty(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("serverId must not be empty")
        return v


def _load_yaml(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


@lru_cache(maxsize=1)
def get_config() -> ShimConfig:
    """Load and cache the shim configuration for the process lifetime.

    Resolution order:
    1. SHIM_CONFIG_YAML environment variable, if set -- the raw YAML text
       of the config, inline. This is the recommended path for ECS/Fargate:
       inject the per-site config as an ECS task definition `secrets` entry
       (backed by Secrets Manager or SSM Parameter Store) so the container
       image itself stays identical across every site, per the Variant A2
       spec's "configuration lives outside the deployable artifact"
       principle -- see docs/a2-howto-agentcore-bedrock.md, step 5.
    2. SHIM_CONFIG_PATH environment variable, if set -- a file path.
    3. ./config/server.yaml relative to the working directory.
    4. ./config/server.example.yaml as a last-resort local dev fallback.
    """
    inline_yaml = os.environ.get("SHIM_CONFIG_YAML")
    if inline_yaml:
        raw = yaml.safe_load(inline_yaml) or {}
        return ShimConfig.model_validate(raw)

    path = os.environ.get("SHIM_CONFIG_PATH")
    if not path:
        for candidate in ("config/server.yaml", "config/server.example.yaml"):
            if os.path.exists(candidate):
                path = candidate
                break
    if not path or not os.path.exists(path):
        raise FileNotFoundError(
            "No shim configuration found. Set SHIM_CONFIG_YAML (inline), "
            "SHIM_CONFIG_PATH (file path), or provide config/server.yaml."
        )
    raw = _load_yaml(path)
    return ShimConfig.model_validate(raw)


def reset_config_cache() -> None:
    """Clear the cached config. Intended for tests only."""
    get_config.cache_clear()
