# API / HTTP tests

Exercises **FastAPI routes** via `TestClient` (or async `httpx` + `ASGITransport` later). External services stay **mocked** or replaced with `dependency_overrides` unless you intentionally run integration tests.

## What will be added

| Planned file / focus | What you will test |
|---------------------|-------------------|
| `test_health.py` | `GET /healthz`: 200, body shape, rate-limit exempt behaviour when SlowAPI is enabled in test config. |
| `test_v1_ping.py` | `GET /api/v1/ping`: 200, JSON `{ "ok": true }`. |
| `test_v1_secure.py` *(or split by resource)* | **JWT:** 401 without `Authorization`, 401 with bad token, 200 with valid token using **mocked JWKS** or **`verify_jwt` override** returning a fixture payload. |
| `test_v1_*_router.py` | Per feature area: CRUD/list routes, 422 on invalid bodies, 403 handling when PostgREST errors are mapped (if simulated). |
| `test_exception_handlers.py` | Optional: request validation and custom error JSON shape via client calls. |

**Convention:** prefer a shared `client` fixture from `tests/conftest.py`; use `with TestClient(app) as client` so lifespan teardown runs.

Run:

```bash
pytest tests/api/ -v
```
