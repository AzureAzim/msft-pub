"""Per-caller MCP session cache.

Implements the Variant A2 spec's recommended default session strategy: one
AgentCore `runtimeSessionId` (and, once learned, one MCP `mcpSessionId`) per
authenticated caller identity, cached with an idle TTL and re-initialized
transparently on expiry or backend rejection. See
docs/variant-a2-thin-mcp-adapter-spec.md#mcp-session-management for the
tradeoffs against shared-pool and per-request session strategies.
"""
from __future__ import annotations

import threading
import time
from dataclasses import dataclass
from typing import Optional

from .agentcore_client import AgentCoreMcpClient, new_runtime_session_id


@dataclass
class CachedSession:
    runtime_session_id: str
    mcp_session_id: Optional[str]
    last_used_monotonic: float


class SessionManager:
    """Thread-safe per-caller session cache with idle-TTL eviction.

    A background sweep thread is intentionally not used; expiry is checked
    lazily on access, which is sufficient at the request volumes this shim
    is designed for (see the parent spec's reliability targets). Idle
    entries are simply overwritten in place the next time that caller makes
    a request after expiry.
    """

    def __init__(self, idle_ttl_minutes: int, agentcore_client: AgentCoreMcpClient):
        self._idle_ttl_seconds = idle_ttl_minutes * 60
        self._client = agentcore_client
        self._sessions: dict[str, CachedSession] = {}
        self._lock = threading.Lock()

    def _is_expired(self, session: CachedSession) -> bool:
        return (time.monotonic() - session.last_used_monotonic) > self._idle_ttl_seconds

    def get_or_create(self, caller_id: str) -> CachedSession:
        """Return a warm session for this caller, initializing a new one if needed or expired."""
        with self._lock:
            existing = self._sessions.get(caller_id)
            if existing and not self._is_expired(existing):
                return existing

        # Perform the (network-bound) initialize handshake outside the lock
        # so a slow backend does not block other callers' cache lookups.
        runtime_session_id = new_runtime_session_id()
        result = self._client.initialize_session(runtime_session_id)
        session = CachedSession(
            runtime_session_id=result.runtime_session_id,
            mcp_session_id=result.mcp_session_id,
            last_used_monotonic=time.monotonic(),
        )
        with self._lock:
            self._sessions[caller_id] = session
        return session

    def update(self, caller_id: str, runtime_session_id: str, mcp_session_id: Optional[str]) -> None:
        """Refresh the cached session's freshness and ids after a successful call."""
        with self._lock:
            self._sessions[caller_id] = CachedSession(
                runtime_session_id=runtime_session_id,
                mcp_session_id=mcp_session_id,
                last_used_monotonic=time.monotonic(),
            )

    def invalidate(self, caller_id: str) -> None:
        """Drop a caller's cached session, forcing a fresh initialize on the next call.

        Called after a session-related backend failure so the shim
        self-heals instead of repeatedly reusing a session AgentCore has
        already discarded.
        """
        with self._lock:
            self._sessions.pop(caller_id, None)

    def size(self) -> int:
        with self._lock:
            return len(self._sessions)
