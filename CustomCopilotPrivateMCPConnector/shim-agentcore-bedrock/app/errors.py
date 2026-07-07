"""Shim error model.

Mirrors the error table in the parent spec
(docs/power-platform-mcp-private-proxy-connector-spec.md#error-model) and
Variant A2 spec (docs/variant-a2-thin-mcp-adapter-spec.md#error-handling-inherited)
so the connector always gets the same documented error envelope regardless
of which backend variant is behind it.
"""
from __future__ import annotations

from typing import Any, Optional


class ShimError(Exception):
    """Base class for all errors the shim returns to the connector as JSON."""

    http_status: int = 500
    code: str = "InternalError"
    #: Class-level default for whether this error is safe to retry once for
    #: an idempotent call. Individual raise sites can override per-instance
    #: (e.g. AWS ThrottlingException is retryable, ServiceQuotaExceeded is
    #: not) -- see app/agentcore_client.py.
    retryable: bool = False

    def __init__(self, message: str, details: Optional[list[Any]] = None, retryable: Optional[bool] = None):
        super().__init__(message)
        self.message = message
        self.details = details or []
        if retryable is not None:
            self.retryable = retryable


class InvalidArguments(ShimError):
    http_status = 400
    code = "InvalidArguments"


class Unauthenticated(ShimError):
    http_status = 401
    code = "Unauthenticated"


class UnauthorizedTool(ShimError):
    http_status = 403
    code = "UnauthorizedTool"


class UnknownTarget(ShimError):
    http_status = 404
    code = "UnknownTarget"


class BackendTimeout(ShimError):
    http_status = 408
    code = "BackendTimeout"


class ToolConflict(ShimError):
    http_status = 409
    code = "ToolConflict"


class QuotaExceeded(ShimError):
    http_status = 429
    code = "QuotaExceeded"


class BackendProtocolError(ShimError):
    http_status = 502
    code = "BackendProtocolError"


class BackendUnavailable(ShimError):
    http_status = 503
    code = "BackendUnavailable"


#: Maps the string codes produced by mcp_protocol.classify_rpc_error_code()
#: to the corresponding ShimError subclass.
_CODE_TO_EXCEPTION: dict[str, type[ShimError]] = {
    "InvalidArguments": InvalidArguments,
    "UnknownTarget": UnknownTarget,
    "BackendProtocolError": BackendProtocolError,
}


def error_for_code(code: str, message: str) -> ShimError:
    exc_type = _CODE_TO_EXCEPTION.get(code, BackendProtocolError)
    return exc_type(message)


def to_error_envelope(error: ShimError, correlation_id: str) -> dict:
    """Build the standard error response body documented in the parent spec."""
    return {
        "error": {
            "code": error.code,
            "message": error.message,
            "correlationId": correlation_id,
            "details": error.details,
        }
    }
