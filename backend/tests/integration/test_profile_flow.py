"""Integration tests: real local Supabase stack + FastAPI TestClient.

What each test proves
---------------------
1. test_secure_test_returns_correct_user_id
   A real Supabase access_token flows through the FastAPI route and the correct
   user_id (JWT sub claim) is echoed back.

2. test_profile_auto_created_by_trigger
   Signing up fires the handle_new_user() trigger, which inserts a row into
   public.profiles.  The FastAPI GET /me/profile route then returns that row —
   proving migrations ran, the trigger executed, PostgREST is reachable, and
   RLS allows the owner to read their own row.

3. test_patch_profile_updates_display_name
   PATCH /me/profile updates the display_name and returns the updated row,
   proving the PATCH route, Pydantic validation, and the Supabase .update()
   call all work end-to-end.

4. test_profile_returns_404_after_row_deleted
   Deleting the profile row via the service-role REST API (bypasses RLS) and
   then calling GET /me/profile returns 404 — exercising the
   "empty PostgREST result → HTTPException(404)" branch in the route handler.
   This also confirms RLS is not silently hiding the row (the trigger test above
   confirmed creation; this confirms deletion is visible to the route).

Run locally (requires `supabase start` and the three env vars exported):

    export SUPABASE_URL=http://127.0.0.1:54321
    export SUPABASE_PUBLIC_ANON_KEY=<anon key from supabase status>
    export SUPABASE_SERVICE_ROLE_KEY=<service role key from supabase status>
    cd backend
    uv run pytest tests/integration/ -v -m integration
"""

import httpx
import pytest

pytestmark = pytest.mark.integration


def test_secure_test_returns_correct_user_id(integration_client, test_credentials: dict) -> None:
    """Real token → /api/v1/secure-test echoes the correct user_id."""
    resp = integration_client.get(
        "/api/v1/secure-test",
        headers={"Authorization": f"Bearer {test_credentials['access_token']}"},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["user_id"] == test_credentials["user_id"]
    assert resp.json()["message"] == "Token valid"


def test_profile_auto_created_by_trigger(integration_client, test_credentials: dict) -> None:
    """Signup trigger fires → profile row exists and is readable via the API.

    This is the core end-to-end assertion: it would fail if:
    - the migration was never applied (table missing)
    - the handle_new_user trigger did not fire on auth.users insert
    - PostgREST is misconfigured or unreachable from the FastAPI process
    - RLS blocks the owner from reading their own row
    """
    resp = integration_client.get(
        "/api/v1/me/profile",
        headers={"Authorization": f"Bearer {test_credentials['access_token']}"},
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["id"] == test_credentials["user_id"]
    assert "created_at" in data
    # display_name and avatar_url are nullable — just verify the keys are present.
    assert "display_name" in data
    assert "avatar_url" in data


def test_patch_profile_updates_display_name(integration_client, test_credentials: dict) -> None:
    """PATCH /me/profile with display_name → 200 and updated row returned.

    Proves the PATCH route handler, Pydantic ProfileUpdate validation, and the
    Supabase .update() → .eq() chain all work against a real database row.
    RLS enforces that only the owner can update their own row.
    """
    resp = integration_client.patch(
        "/api/v1/me/profile",
        json={"display_name": "Integration Tester"},
        headers={"Authorization": f"Bearer {test_credentials['access_token']}"},
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["id"] == test_credentials["user_id"]
    assert data["display_name"] == "Integration Tester"


def test_profile_returns_404_after_row_deleted(
    integration_client, integration_env: dict, test_credentials: dict
) -> None:
    """Row deleted via service-role API → GET /me/profile returns 404.

    Uses the PostgREST service-role endpoint to bypass RLS and remove the
    profile row directly, then asserts the FastAPI route correctly surfaces 404.
    This test must run *after* test_profile_auto_created_by_trigger in the same
    session because both share the session-scoped test user.
    """
    url = integration_env["url"]
    service_key = integration_env["service_key"]
    user_id = test_credentials["user_id"]
    access_token = test_credentials["access_token"]

    # Delete the row directly, bypassing RLS via the service_role key.
    del_resp = httpx.delete(
        f"{url}/rest/v1/profiles?id=eq.{user_id}",
        headers={
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Prefer": "return=minimal",
        },
        timeout=15,
    )
    assert del_resp.status_code in (200, 204), del_resp.text

    resp = integration_client.get(
        "/api/v1/me/profile",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert resp.status_code == 404, resp.text
