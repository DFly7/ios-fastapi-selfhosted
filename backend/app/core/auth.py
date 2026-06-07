import asyncio
import functools
from typing import Any, TypedDict

import httpx
import jwt
import structlog
from fastapi import Depends, HTTPException, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel
from supabase import AsyncClient, acreate_client

from app.core.config import get_settings

logger = structlog.get_logger(__name__)

_settings = get_settings()


class AuthenticatedClient(BaseModel):
    model_config = {"arbitrary_types_allowed": True}

    client: AsyncClient
    payload: dict


class AuthData(TypedDict):
    token: str
    payload: dict[str, Any]


def _supabase_base_url() -> str:
    base = _settings.supabase_url
    if not base:
        raise HTTPException(
            status_code=503,
            detail="Server missing SUPABASE_URL; cannot verify tokens",
        )
    return str(base).rstrip("/")


class AsyncJWKSManager:
    """
    Fetches and caches Supabase JWKS via httpx (non-blocking for the event loop).
    """

    def __init__(self, jwk_url: str) -> None:
        self.jwk_url = jwk_url
        self.jwks: dict[str, Any] = {"keys": []}
        self._lock = asyncio.Lock()
        self._client: httpx.AsyncClient | None = None

    async def _client_ac(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(timeout=10.0)
        return self._client

    async def aclose(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None

    async def fetch_jwks(self) -> None:
        async with self._lock:
            client = await self._client_ac()
            try:
                response = await client.get(self.jwk_url)
                response.raise_for_status()
                self.jwks = response.json()
            except httpx.HTTPError as e:
                if not self.jwks.get("keys"):
                    raise RuntimeError(f"Could not fetch JWKs: {e}") from e

    async def get_public_key(self, kid: str):
        if not self.jwks.get("keys"):
            await self.fetch_jwks()

        key = next((k for k in self.jwks["keys"] if k.get("kid") == kid), None)

        if not key:
            await self.fetch_jwks()
            key = next((k for k in self.jwks["keys"] if k.get("kid") == kid), None)

            if not key:
                raise HTTPException(status_code=401, detail="Invalid Key ID (kid)")

        try:
            if key["kty"] == "RSA":
                return jwt.algorithms.RSAAlgorithm.from_jwk(key)
            if key["kty"] == "EC":
                return jwt.algorithms.ECAlgorithm.from_jwk(key)
            raise HTTPException(status_code=401, detail=f"Unsupported key type: {key['kty']}")
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=401, detail=f"Failed to parse key: {e}") from e


@functools.cache
def _get_jwk_manager() -> AsyncJWKSManager:
    base = _settings.supabase_url
    if not base:
        raise HTTPException(
            status_code=503,
            detail="Server missing SUPABASE_URL; cannot verify tokens",
        )
    return AsyncJWKSManager(f"{str(base).rstrip('/')}/auth/v1/.well-known/jwks.json")


async def close_jwk_http_client() -> None:
    if _get_jwk_manager.cache_info().currsize > 0:
        await _get_jwk_manager().aclose()


http_bearer = HTTPBearer(auto_error=False, scheme_name="BearerAuth", bearerFormat="JWT")


async def verify_jwt(
    credentials: HTTPAuthorizationCredentials | None = Security(http_bearer),
) -> dict[str, Any]:
    if not credentials:
        raise HTTPException(status_code=401, detail="Missing Authorization header")

    try:
        token = credentials.credentials
        header = jwt.get_unverified_header(token)
        kid = header["kid"]
        public_key = await _get_jwk_manager().get_public_key(kid)
        decoded = jwt.decode(
            token,
            public_key,
            algorithms=["RS256", "ES256"],
            audience="authenticated",
        )
        return {"token": token, "payload": decoded}

    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired") from None
    except jwt.InvalidTokenError as e:
        raise HTTPException(status_code=401, detail=f"Invalid token: {e}") from e
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Token verification failed: {e}") from e


async def get_supabase_client_as_user(auth_data: AuthData = Depends(verify_jwt)) -> AsyncClient:
    url = _supabase_base_url()
    key = _settings.supabase_public_anon_key
    if not key:
        raise HTTPException(status_code=503, detail="Server missing SUPABASE_PUBLIC_ANON_KEY")
    # Per-request allocation is intentional: .postgrest.auth() mutates the client with
    # this user's JWT, so a shared instance would race across concurrent requests.
    supabase = await acreate_client(url, key)
    supabase.postgrest.auth(auth_data["token"])
    return supabase


async def get_authenticated_client(
    auth_data: AuthData = Depends(verify_jwt),
) -> AuthenticatedClient:
    user_id = auth_data["payload"]["sub"]
    user_email = auth_data["payload"].get("email")
    logger.debug(
        "creating_authenticated_client",
        user_id=user_id,
        user_email=user_email,
    )
    url = _supabase_base_url()
    key = _settings.supabase_public_anon_key
    if not key:
        raise HTTPException(status_code=503, detail="Server missing SUPABASE_PUBLIC_ANON_KEY")
    supabase = await acreate_client(url, key)
    supabase.postgrest.auth(auth_data["token"])
    return AuthenticatedClient(client=supabase, payload=auth_data["payload"])
