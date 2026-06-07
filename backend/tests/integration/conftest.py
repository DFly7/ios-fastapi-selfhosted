"""Integration-only fixtures: real local Supabase stack, throw-away test user,
and a FastAPI TestClient wired to that stack.

These fixtures call pytest.skip() when the required env vars are absent, so
the normal unit-test CI job never accidentally picks them up — only the
backend-integration workflow (which sets SUPABASE_URL, SUPABASE_PUBLIC_ANON_KEY,
and SUPABASE_SERVICE_ROLE_KEY from `supabase status -o env`) runs them.

JWT verification note
---------------------
The local Supabase stack signs tokens with HS256 using a shared secret, but
the production verify_jwt() path uses JWKS (RS256/ES256 only).  Rather than
reconfigure the local stack just for CI, the integration_client fixture overrides
verify_jwt to skip JWKS validation while still injecting the *real* access_token
into every request.  That token is forwarded to PostgREST via
supabase.postgrest.auth(token), so Row Level Security is enforced against the
live database exactly as it would be in production.  The RS256/JWKS path is
covered by the unit tests.
"""

import os
import uuid

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.auth import _get_jwk_manager, verify_jwt
from app.core.config import get_settings
from app.main import app


def _require_env(key: str) -> str:
    """Return the value of *key* or skip the test if it is absent."""
    val = os.environ.get(key)
    if not val:
        pytest.skip(
            f"Integration env var {key!r} not set — "
            "run the backend-integration workflow or export it locally."
        )
    return val


@pytest.fixture(scope="session")
def integration_env() -> dict:
    """Collect the three env vars exported by `supabase status -o env`."""
    return {
        "url": _require_env("SUPABASE_URL"),
        "anon_key": _require_env("SUPABASE_PUBLIC_ANON_KEY"),
        "service_key": _require_env("SUPABASE_SERVICE_ROLE_KEY"),
    }


@pytest.fixture(scope="session")
def test_credentials(integration_env: dict) -> dict:
    """Create a throw-away Supabase user, sign in, yield credentials, then delete.

    Uses the Supabase Auth Admin REST API directly (no supabase-py client needed)
    so there are no async complications in a synchronous pytest session.

    Yields a dict with keys: user_id, email, access_token.
    """
    url = integration_env["url"]
    service_key = integration_env["service_key"]
    anon_key = integration_env["anon_key"]

    admin_headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
    }

    email = f"integration+{uuid.uuid4().hex[:8]}@test.example"
    password = "Integration-Test-Password-123!"

    # Create the user with email_confirm=True so sign-in works immediately —
    # the local Inbucket mail server would otherwise hold the confirmation link.
    create_resp = httpx.post(
        f"{url}/auth/v1/admin/users",
        headers=admin_headers,
        json={"email": email, "password": password, "email_confirm": True},
        timeout=30,
    )
    create_resp.raise_for_status()
    user_id = create_resp.json()["id"]

    # Sign in with the password grant to obtain a real, RLS-capable access token.
    signin_resp = httpx.post(
        f"{url}/auth/v1/token?grant_type=password",
        headers={"apikey": anon_key, "Content-Type": "application/json"},
        json={"email": email, "password": password},
        timeout=30,
    )
    signin_resp.raise_for_status()
    access_token = signin_resp.json()["access_token"]

    yield {"user_id": user_id, "email": email, "access_token": access_token}

    # Teardown — delete the user so each CI run starts with a clean slate.
    httpx.delete(
        f"{url}/auth/v1/admin/users/{user_id}",
        headers=admin_headers,
        timeout=30,
    )


@pytest.fixture(scope="session")
def integration_client(integration_env: dict, test_credentials: dict):
    """FastAPI TestClient pointed at the real local Supabase stack.

    Sets SUPABASE_URL / SUPABASE_PUBLIC_ANON_KEY in os.environ and clears the
    lru_cache on get_settings() and _get_jwk_manager() so the app re-reads them.
    Both caches are restored on teardown.
    """
    saved_url = os.environ.get("SUPABASE_URL")
    saved_key = os.environ.get("SUPABASE_PUBLIC_ANON_KEY")

    os.environ["SUPABASE_URL"] = integration_env["url"]
    os.environ["SUPABASE_PUBLIC_ANON_KEY"] = integration_env["anon_key"]

    # Bust module-level caches so the app picks up the updated env vars.
    get_settings.cache_clear()
    _get_jwk_manager.cache_clear()

    access_token = test_credentials["access_token"]
    user_id = test_credentials["user_id"]
    email = test_credentials["email"]

    # Override verify_jwt: skip JWKS verification but inject the real token so
    # get_authenticated_client forwards it to PostgREST and RLS is enforced.
    def _real_token_override() -> dict:
        return {
            "token": access_token,
            "payload": {
                "sub": user_id,
                "email": email,
                "aud": "authenticated",
                "role": "authenticated",
            },
        }

    app.dependency_overrides[verify_jwt] = _real_token_override

    with TestClient(app) as client:
        yield client

    app.dependency_overrides.pop(verify_jwt, None)

    # Restore env and caches to avoid leaking state into any non-integration tests
    # that happen to share the same process.
    get_settings.cache_clear()
    _get_jwk_manager.cache_clear()

    if saved_url is not None:
        os.environ["SUPABASE_URL"] = saved_url
    else:
        os.environ.pop("SUPABASE_URL", None)

    if saved_key is not None:
        os.environ["SUPABASE_PUBLIC_ANON_KEY"] = saved_key
    else:
        os.environ.pop("SUPABASE_PUBLIC_ANON_KEY", None)
