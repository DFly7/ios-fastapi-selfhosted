# Unit tests — services

Tests for `app/services/*`: use cases that **call repositories or clients through mocks/stubs**, not real HTTP or Postgres.

## What will be added

| Service area (examples) | Tests to add |
|------------------------|--------------|
| Statement / PDF pipeline | Parse orchestration, validation of extracted rows, error mapping when a parser raises. |
| Transaction / categorisation | Rule application, batch operations, idempotency assumptions—mock repo returns. |
| Receipt / OCR | Response shaping, merge/dedup logic against fixed fixture payloads (no real Vision API in unit tier). |
| Jobs / background work | Scheduling helpers or chunking logic if kept pure; long-running flows covered lightly with fakes. |

**Convention:** one file per service module, e.g. `test_statement_service.py`, importing `pytest` fixtures from `tests/conftest.py` or `tests/unit/conftest.py` for shared mocks.
