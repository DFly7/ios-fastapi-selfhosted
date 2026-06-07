# Backend (FastAPI)

FastAPI service with Supabase JWT verification, Postgres access via RLS-aware clients when you add repositories, and a production-style layout (structured logging, rate limits, Docker).

This folder is the **Python backend only** (not the Swift client). It is set up like a small production-style service: typed configuration, structured logging, rate limits, optional metrics and error tracking, and Docker.

---

## Layout

```
backend/
├── main.py                 # Local dev: uvicorn with --reload
├── Dockerfile
├── docker-compose.yml
├── .dockerignore
├── .gitignore
├── .env.example            # Copy to .env and fill in
├── pyproject.toml          # Dependencies (managed with uv)
├── uv.lock                 # Locked dependency tree
├── README.md
├── app/
│   ├── __init__.py
│   ├── main.py             # App factory: lifespan, middleware, routers, OpenAPI
│   ├── logging_config.py   # structlog (JSON or console)
│   ├── exception_handlers.py
│   ├── exceptions.py       # Domain error base (extend as needed)
│   ├── api/
│   │   └── v1/
│   │       └── router.py   # v1 routes (/ping, /secure-test, …)
│   ├── core/
│   │   ├── config.py       # pydantic-settings (.env, validation)
│   │   ├── auth.py         # Supabase JWT (JWKS via httpx), user-scoped clients
│   │   └── rate_limit.py   # SlowAPI limiter (per-user when JWT context exists)
│   ├── middleware/
│   │   ├── request_id.py
│   │   ├── auth_context.py # Decode JWT for logging (no verification here)
│   │   └── access_log.py
│   ├── utils/
│   │   └── log_context.py  # PII-safe dicts, background task logging helpers
│   ├── services/           # Use cases (placeholders to extend)
│   ├── repositories/     # Supabase/data access (placeholders)
│   └── schemas/          # Pydantic API models (placeholders)
└── tests/
    ├── README.md
    ├── conftest.py
    ├── test_smoke.py
    ├── unit/                 # README + conftest; test_services/README
    ├── api/                  # README
    └── integration/        # README + conftest
```

---

## What is already in place

| Area | Details |
|------|--------|
| **Framework** | FastAPI, Uvicorn |
| **Configuration** | `pydantic-settings`: loads `.env`, validates URLs and common types, production-friendly defaults for log level / JSON logs / Sentry env when vars are omitted |
| **Auth** | Supabase JWT verification against JWKS (`RS256` / `ES256`, audience `authenticated`). Lazy JWKS fetch over **`httpx` async** so verification does not block the event loop. Dependencies: `verify_jwt`, `get_supabase_client_as_user`, `get_authenticated_client` |
| **Middleware (order)** | Request ID → auth context (claims for logs only) → SlowAPI (if enabled) → access log → CORS |
| **Rate limiting** | SlowAPI; key is user id when `AuthContextMiddleware` has set it, otherwise client IP (rightmost `X-Forwarded-For`). Toggle with `RATE_LIMIT_ENABLED` |
| **Logging** | structlog: JSON in production-style defaults, colored console in development; sensitive keys masked; request ID bound in context |
| **Errors** | Central handlers for HTTP, validation, unhandled exceptions, rate limits, PostgREST / RLS-style errors |
| **Observability (optional)** | **Sentry** if `SENTRY_DSN` is set. **Prometheus** metrics at `/metrics` if `ENABLE_METRICS=true` |
| **API** | `GET /healthz` (rate-limit exempt). `GET /api/v1/ping`, `GET /api/v1/secure-test` (JWT). OpenAPI security scheme for `/api/v1` |
| **Container** | `Dockerfile` + `docker-compose.yml` (`build: .`, `env_file: .env`, port `8000`) |

---

## Quick start (local)

Requires [uv](https://docs.astral.sh/uv/) (pinned version in `.mise.toml`; run `mise install` to get it).

```bash
cd backend
uv sync                       # creates .venv and installs all deps from uv.lock
cp .env.example .env          # set at least SUPABASE_URL and SUPABASE_PUBLIC_ANON_KEY for JWT flows
uv run python main.py         # or: uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

- Docs: http://127.0.0.1:8000/docs  
- Health: http://127.0.0.1:8000/healthz  

## Docker

```bash
cd backend
cp .env.example .env   # fill in real values
docker compose up --build
```

---

## Environment variables

See **`.env.example`** for the full list and comments. Minimum for auth-protected routes: **`SUPABASE_URL`**, **`SUPABASE_PUBLIC_ANON_KEY`**.

---

## Tests

```bash
uv run pytest
```

See **`tests/README.md`** for conventions. **`tests/unit/`**, **`tests/api/`**, and **`tests/integration/`** each have a **README** describing which tests to add there as the codebase grows.

CI may set secrets like `SUPABASE_URL` for imports that touch auth configuration; keep fixtures and env aligned with `.github/workflows/` if present.

---

## Known trade-offs / scaling notes

| Area | Current behaviour | At-scale upgrade |
|------|------------------|-----------------|
| **Supabase client per request** | `acreate_client(url, key)` (async) is called on every authenticated request and `.postgrest.auth(token)` immediately mutates it with the caller's JWT. Per-request creation is intentional: the auth header is user-specific so a shared, mutable client would race. | For high-throughput workloads, pass a shared `httpx.AsyncClient` (with a connection pool) as the transport, or call PostgREST directly via the pooled client you already have in `AsyncJWKSManager`. |
| **JWKS fetch** | Lazy, cached after first fetch, re-fetched on unknown `kid`. Single `httpx.AsyncClient` shared across all requests. | Already async and non-blocking; suitable for production traffic as-is. |

---

## Extending the project

1. Add Pydantic models under `app/schemas/`.
2. Add Supabase access under `app/repositories/`.
3. Add orchestration under `app/services/`.
4. Create a dedicated sub-router file under `app/api/v1/` (e.g. `invoices.py`) and mount it in `router.py` with `include_router`.

Keep route handlers thin; enforce auth with `Depends(verify_jwt)` or router-level dependencies when entire groups should be private.

### `async def` in route handlers

All route handlers use `async def` and `await` every Supabase `.execute()` call.
The project uses `acreate_client` (the async Supabase client), so the event loop
is never blocked by database I/O.

Pure utility handlers that do no I/O (e.g. `/ping`) keep plain `def` — there is
nothing to await and FastAPI handles both without any thread-pool overhead.

If you ever call a **sync** blocking library from inside an `async def` handler,
wrap it with `asyncio.to_thread(...)` to avoid stalling the event loop.

### Inline routes vs feature sub-routers

`router.py` contains a few short utility endpoints inline (`/ping`,
`/secure-test`, `/me/profile`) to show common patterns at a glance.  For
anything beyond a single endpoint — its own service layer, multiple CRUD
operations, dedicated tests — create a sub-router file (see `notes.py` as the
reference implementation) and mount it with `include_router`.
