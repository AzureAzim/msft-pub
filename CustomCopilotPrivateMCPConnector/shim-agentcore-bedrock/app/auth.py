"""Caller authentication for the AgentCore MCP shim.

Validates the credential the on-premises data gateway forwards from the
Power Platform custom connector. Per the parent spec's authentication
model, the shim re-validates the caller credential itself rather than
trusting the gateway hop implicitly -- this module is that validation.
"""
from __future__ import annotations

import base64
import hmac
import logging
import os
import time
from dataclasses import dataclass
from typing import Optional

import httpx
from fastapi import Request
from jose import jwt
from jose.exceptions import JOSEError

from .config import AuthConfig
from .errors import Unauthenticated

logger = logging.getLogger("shim.auth")

_JWKS_CACHE_TTL_SECONDS = 3600


@dataclass
class CallerIdentity:
    caller_id: str
    auth_type: str


class _JwksCache:
    """In-memory cache of one Entra ID tenant's OIDC discovery document and JWKS."""

    def __init__(self, tenant_id: str):
        self._tenant_id = tenant_id
        self._keys: dict[str, dict] = {}
        self._issuer: Optional[str] = None
        self._fetched_at: float = 0.0

    def _refresh(self) -> None:
        discovery_url = (
            f"https://login.microsoftonline.com/{self._tenant_id}"
            "/v2.0/.well-known/openid-configuration"
        )
        with httpx.Client(timeout=10) as client:
            discovery = client.get(discovery_url).json()
            self._issuer = discovery["issuer"]
            jwks = client.get(discovery["jwks_uri"]).json()
        self._keys = {key["kid"]: key for key in jwks.get("keys", [])}
        self._fetched_at = time.monotonic()

    def get_key(self, kid: str) -> Optional[dict]:
        if not self._keys or (time.monotonic() - self._fetched_at) > _JWKS_CACHE_TTL_SECONDS:
            self._refresh()
        key = self._keys.get(kid)
        if key is None:
            # Possible key rotation: refresh once before giving up.
            self._refresh()
            key = self._keys.get(kid)
        return key

    @property
    def issuer(self) -> str:
        if self._issuer is None:
            self._refresh()
        return self._issuer  # type: ignore[return-value]


_jwks_caches: dict[str, _JwksCache] = {}


def _get_jwks_cache(tenant_id: str) -> _JwksCache:
    if tenant_id not in _jwks_caches:
        _jwks_caches[tenant_id] = _JwksCache(tenant_id)
    return _jwks_caches[tenant_id]


def _authenticate_oauth_entra_id(request: Request, config: AuthConfig) -> CallerIdentity:
    if config.oauth_entra_id is None:
        raise Unauthenticated("oauthEntraId auth is enabled but not configured")
    authz_header = request.headers.get("authorization", "")
    if not authz_header.lower().startswith("bearer "):
        raise Unauthenticated("Missing Bearer token in Authorization header")
    token = authz_header.split(" ", 1)[1].strip()

    try:
        unverified_header = jwt.get_unverified_header(token)
    except JOSEError as exc:
        raise Unauthenticated(f"Malformed bearer token: {exc}") from exc

    kid = unverified_header.get("kid")
    cache = _get_jwks_cache(config.oauth_entra_id.tenant_id)
    key = cache.get_key(kid) if kid else None
    if key is None:
        raise Unauthenticated("Bearer token key id not found in tenant JWKS")

    try:
        claims = jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            audience=config.oauth_entra_id.audience,
            issuer=cache.issuer,
        )
    except JOSEError as exc:
        raise Unauthenticated(f"Bearer token failed validation: {exc}") from exc

    caller_id = claims.get("oid") or claims.get("sub") or claims.get("appid")
    if not caller_id:
        raise Unauthenticated("Bearer token has no oid/sub/appid claim to identify the caller")
    return CallerIdentity(caller_id=str(caller_id), auth_type="oauthEntraId")


def _authenticate_basic(request: Request, config: AuthConfig) -> CallerIdentity:
    if config.basic is None:
        raise Unauthenticated("basic auth is enabled but not configured")
    authz_header = request.headers.get("authorization", "")
    if not authz_header.lower().startswith("basic "):
        raise Unauthenticated("Missing Basic credentials in Authorization header")

    expected_username = os.environ.get(config.basic.username_env)
    expected_password = os.environ.get(config.basic.password_env)
    if not expected_username or not expected_password:
        raise Unauthenticated(
            f"Basic auth is enabled but {config.basic.username_env}/"
            f"{config.basic.password_env} are not set in the shim's environment"
        )

    try:
        decoded = base64.b64decode(authz_header.split(" ", 1)[1].strip()).decode("utf-8")
        username, _, password = decoded.partition(":")
    except Exception as exc:  # noqa: BLE001 - any decode failure means unauthenticated
        raise Unauthenticated(f"Malformed Basic credentials: {exc}") from exc

    username_ok = hmac.compare_digest(username, expected_username)
    password_ok = hmac.compare_digest(password, expected_password)
    if not (username_ok and password_ok):
        raise Unauthenticated("Invalid Basic credentials")
    return CallerIdentity(caller_id=username, auth_type="basic")


def authenticate(request: Request, config: AuthConfig) -> CallerIdentity:
    """Authenticate an incoming connector request against the configured caller schemes.

    "windows" (Windows Integrated Auth / Kerberos-NTLM) is deliberately not
    implemented here: it requires a domain-trust boundary that does not
    exist between an on-premises-managed gateway and a shim hosted in AWS.
    Configure oauthEntraId for this deployment topology; see
    docs/a2-howto-agentcore-bedrock.md for the rationale.
    """
    attempts: list[str] = []
    for auth_type in config.caller_accepted_types:
        try:
            if auth_type == "oauthEntraId":
                return _authenticate_oauth_entra_id(request, config)
            if auth_type == "basic":
                return _authenticate_basic(request, config)
            if auth_type == "windows":
                raise Unauthenticated(
                    "windows auth is not supported by this shim; configure "
                    "oauthEntraId instead (see docs/a2-howto-agentcore-bedrock.md)"
                )
        except Unauthenticated as exc:
            attempts.append(f"{auth_type}: {exc.message}")
            continue
    raise Unauthenticated(
        "No configured authentication scheme accepted this request: " + "; ".join(attempts)
    )
