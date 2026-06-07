# Backend tests

Keep **fast, deterministic checks** as the default in CI, and **isolate anything that talks to Supabase or the network** so PRs stay reliable.

---

## Principles

1. **Unit tests** — Pure Python: settings parsing, helpers in `app/utils/`, domain logic in `app/services/` with repositories faked or stubbed. No HTTP server, no real DB.
2. **API / HTTP tests** — FastAPI `TestClient` (or `httpx.AsyncClient` with `ASGITransport` for async routes). Exercise status codes, JSON shape, and auth behaviour using **mocked** JWKS or dependency overrides.
3. **Integration tests** — Real Supabase project (or local stack), real JWTs, migrations applied. Run locally and optionally in a protected CI job (secrets on `main`, not on fork PRs).

Use **pytest markers** so you can run `pytest -m "not integration"` in CI and `pytest -m integration` when you intend to hit real services.

---

## Suggested layout (evolve as you add code)

```
tests/
├── README.md                 # This file
├── conftest.py               # Shared fixtures: app, client, mock auth, env
├── test_smoke.py             # Tiny always-on checks (e.g. /healthz)
├── unit/
│   ├── README.md             # What belongs in unit tests
│   ├── conftest.py           # Mocks and unit-only fixtures
│   └── test_services/
│       └── README.md         # Service-layer unit test plans
├── api/
│   └── README.md             # HTTP/API test plans
└── integration/
    ├── README.md             # Real Supabase / RLS test plans
    └── conftest.py           # Session fixtures, secrets from env
```

Add `test_*.py` files under `unit/`, `api/`, and `integration/` as you implement features. Each folder’s **README** lists the tests you intend to add there.

---

## Fixtures (`conftest.py`)

**Shared (`tests/conftest.py`)**

- **`app`** — Import `app` from `app.main` (already wires lifespan and middleware).
- **`client`** — Prefer a context-managed client so lifespan shutdown runs (closes JWKS `httpx` client, etc.):

  ```python
  @pytest.fixture
  def client():
      from fastapi.testclient import TestClient
      from app.main import app
      with TestClient(app) as c:
          yield c
  ```

- **Auth** — For routes that need a user without calling Supabase:
  - **`dependency_overrides`**: override `verify_jwt` to return a fixed payload; or
  - **Signed test JWT** + **mocked JWKS HTTP** (e.g. `respx` / `httpx.MockTransport`) so `get_public_key` never calls Supabase.

**Integration-only (`tests/integration/conftest.py`)**

- Read `SUPABASE_URL` / keys from environment (or skip entire module if missing).
- Reuse one client or session for expensive setup; avoid resetting the DB unless tests use disposable data.

---

## Naming and style

- Files: `test_*.py` or `*_test.py` (pytest default).
- Tests: `test_<behaviour>_<condition>()` for clarity.
- One obvious behaviour per test; share setup via fixtures, not copy-paste.

---

## Markers (recommended)

Add a `pytest.ini` or `[tool.pytest.ini_options]` later, for example:

```ini
[pytest]
markers =
    integration: hits real Supabase or external APIs
    slow: intentionally slower tests
```

Then default CI: `pytest -m "not integration"`.

---

## Environment and CI

GitHub Actions (`.github/workflows/backend-ci.yml`) currently sets **`RATE_LIMIT_ENABLED=false`** and placeholder Supabase vars so imports and smoke tests stay stable. As you add tests:

- **No network in default job** — Mock JWKS and Supabase clients in `api/` and `unit/` tests.
- **Real Supabase** — Optional job or workflow on `main` only, with secrets in `env:`, and tests marked `@pytest.mark.integration`.

---

## Async routes and dependencies

If you add more `async def` endpoints or dependencies, you can keep using `TestClient` for many cases; for strict async behaviour or streaming, use **`httpx.AsyncClient(app=app, base_url="http://test")`** with **`ASGITransport`**. See FastAPI testing docs for the pattern.

---

## Checklist when adding a feature

| Step | Action |
|------|--------|
| 1 | Put **business rules** under `unit/` with mocks. |
| 2 | Add **`api/`** tests for the new router: status codes, validation errors, 401 without token. |
| 3 | If RLS matters, add **one** targeted `integration/` test with a real project (marker + secrets). |
| 4 | Update fixtures in `conftest.py` instead of duplicating client/auth setup. |

This keeps the suite fast on every push while still allowing deeper confidence when you opt in to integration runs.
