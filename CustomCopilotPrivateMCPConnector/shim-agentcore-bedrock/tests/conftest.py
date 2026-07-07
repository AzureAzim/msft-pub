"""Shared pytest fixtures for the AgentCore MCP shim test suite."""
from __future__ import annotations

from pathlib import Path

import pytest

TESTS_DIR = Path(__file__).parent
TEST_CONFIG_PATH = TESTS_DIR / "fixtures" / "test_server.yaml"


@pytest.fixture(autouse=True)
def shim_config_env(monkeypatch):
    """Point every test at the fixture config and reset the config cache.

    Autouse so individual test modules don't need to remember to apply it.
    Also pins dummy AWS credentials/region so boto3 client construction and
    SigV4 signing never depend on (or accidentally use) real ambient AWS
    credentials from the host running the tests, and never attempts a
    network credential lookup (e.g. instance metadata).
    """
    monkeypatch.setenv("SHIM_CONFIG_PATH", str(TEST_CONFIG_PATH))
    monkeypatch.setenv("SHIM_BASIC_USERNAME", "test-user")
    monkeypatch.setenv("SHIM_BASIC_PASSWORD", "test-pass")
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("AWS_EC2_METADATA_DISABLED", "true")

    from app.config import reset_config_cache

    reset_config_cache()
    yield
    reset_config_cache()


@pytest.fixture
def basic_auth_header() -> dict[str, str]:
    import base64

    token = base64.b64encode(b"test-user:test-pass").decode()
    return {"Authorization": f"Basic {token}"}


@pytest.fixture(autouse=True)
def reset_mcp_request_id_counter():
    """Reset mcp_protocol's module-level JSON-RPC id counter before each test.

    Without this, the id assigned to a given call depends on how many other
    requests earlier tests in the same process happened to build, making
    any test that hardcodes an expected id in a stubbed response order-
    dependent and flaky.
    """
    import itertools

    from app import mcp_protocol

    mcp_protocol._id_counter = itertools.count(1)
    yield
