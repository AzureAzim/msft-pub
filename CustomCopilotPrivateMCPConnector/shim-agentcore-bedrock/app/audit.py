"""Structured audit logging for the AgentCore MCP shim.

Emits one JSON line per connector call with exactly the fields the parent
spec's audit sink requires: caller, environment, action, server, tool,
decision, latency, and correlation id. Full prompts, tool arguments, and
tool responses are never logged by default; callers pass already-redacted
argument summaries in (see authz.redact).
"""
from __future__ import annotations

import json
import logging
import logging.handlers
import os
import time
from dataclasses import asdict, dataclass, field
from typing import Any, Optional

from .config import AuditConfig

_audit_logger = logging.getLogger("shim.audit")
_configured = False


@dataclass
class AuditRecord:
    correlation_id: str
    caller_id: str
    auth_type: str
    server_id: str
    action: str
    tool_or_resource: Optional[str]
    decision: str  # "allowed" | "denied" | "error"
    http_status: int
    elapsed_ms: int
    error_code: Optional[str] = None
    redacted_arguments: Optional[dict[str, Any]] = None
    timestamp: float = field(default_factory=time.time)

    def to_json(self) -> str:
        return json.dumps(asdict(self), default=str, separators=(",", ":"))


def configure(audit_config: AuditConfig) -> None:
    """Attach a file handler for the audit logger. Safe to call more than once."""
    global _configured
    if _configured:
        return
    _audit_logger.setLevel(logging.INFO)
    _audit_logger.propagate = False

    log_dir = os.path.dirname(audit_config.local_path)
    if log_dir:
        os.makedirs(log_dir, exist_ok=True)

    handler = logging.handlers.RotatingFileHandler(
        audit_config.local_path, maxBytes=50 * 1024 * 1024, backupCount=5
    )
    handler.setFormatter(logging.Formatter("%(message)s"))
    _audit_logger.addHandler(handler)

    # Always also emit to stdout so container log drivers (e.g. the ECS
    # awslogs driver forwarding to CloudWatch Logs) capture audit events
    # even if the local file path is ephemeral container storage.
    stream_handler = logging.StreamHandler()
    stream_handler.setFormatter(logging.Formatter("%(message)s"))
    _audit_logger.addHandler(stream_handler)

    _configured = True


def emit(record: AuditRecord) -> None:
    _audit_logger.info(record.to_json())
