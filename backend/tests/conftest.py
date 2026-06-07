# Shared pytest fixtures.
#
# JWT-protected routes are tested via FastAPI dependency_overrides — no live Supabase
# instance is required. See tests/api/test_auth_routes.py and
# tests/api/test_notes_routes.py for the pattern.
#
# If you add integration tests that need a real Supabase, set SUPABASE_URL in the
# environment (or a .env.test file) and align with the secrets in .github/workflows/.

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture
def client() -> TestClient:
    with TestClient(app) as c:
        yield c
