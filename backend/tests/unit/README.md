# Unit tests

Fast, isolated tests: **no HTTP server**, **no real Supabase**. Mock repositories and I/O.

## What will live here

| Planned module / area | What you will test |
|----------------------|---------------------|
| `test_config.py` | `Settings` / env parsing: defaults per `environment`, bool coercion, `allowed_origins_csv`, optional `HttpUrl` for `supabase_url`, bounds on `log_request_body_max_size` and `sentry_traces_sample_rate`. |
| `test_calculations.py` *(or domain-specific names)* | Pure functions: categorisation rules, tax helpers, deduplication logic, PDF text normalisation—anything that is deterministic and DB-free. |
| `test_services/` | Service-layer orchestration with **faked** repositories (see subdirectory README). |

Run (from `backend/`):

```bash
pytest tests/unit/ -v
```
