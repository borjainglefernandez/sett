"""Sign in with Apple identity-token verification.

The JWKS fetcher is injectable: production uses httpx against Apple's JWKS
endpoint (cached in-process for 24h, refetched on unknown kid); tests inject a
fake verifier via the `get_apple_verifier` dependency override.
"""

from __future__ import annotations

import time
from typing import Any, Awaitable, Callable, Protocol

import httpx
import jwt

from ..config import Settings


class AppleVerificationError(Exception):
    pass


class AppleVerifier(Protocol):
    async def verify(self, identity_token: str, nonce: str | None) -> dict[str, Any]:
        """Return the verified claims dict or raise AppleVerificationError."""
        ...


JWKSFetcher = Callable[[], Awaitable[dict[str, Any]]]


async def _default_jwks_fetcher_factory(url: str) -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=10) as client:
        response = await client.get(url)
        response.raise_for_status()
        return response.json()


class RemoteAppleVerifier:
    """RS256 verification against Apple's JWKS with a 24h in-process cache."""

    def __init__(self, settings: Settings, jwks_fetcher: JWKSFetcher | None = None) -> None:
        self._settings = settings
        self._jwks_fetcher = jwks_fetcher or (lambda: _default_jwks_fetcher_factory(settings.apple_jwks_url))
        self._keys: dict[str, Any] = {}
        self._fetched_at: float = 0.0

    async def _key_for(self, kid: str) -> Any:
        stale = (time.monotonic() - self._fetched_at) > 24 * 3600
        if kid not in self._keys or stale:
            jwks = await self._jwks_fetcher()
            self._keys = {k["kid"]: k for k in jwks.get("keys", [])}
            self._fetched_at = time.monotonic()
        if kid not in self._keys:
            raise AppleVerificationError(f"unknown key id {kid!r}")
        return self._keys[kid]

    async def verify(self, identity_token: str, nonce: str | None) -> dict[str, Any]:
        try:
            header = jwt.get_unverified_header(identity_token)
            key = await self._key_for(header["kid"])
            claims = jwt.decode(
                identity_token,
                key=jwt.PyJWK(key).key,
                algorithms=["RS256"],
                audience=self._settings.apple_bundle_id,
                issuer=self._settings.apple_issuer,
            )
        except AppleVerificationError:
            raise
        except Exception as exc:  # signature, expiry, audience, malformed token
            raise AppleVerificationError(str(exc)) from exc
        if nonce is not None and claims.get("nonce") not in (None, nonce):
            raise AppleVerificationError("nonce mismatch")
        return claims
