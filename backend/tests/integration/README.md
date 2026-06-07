# Integration tests

Tests that run against a **real local Supabase stack** to verify migrations, the
`handle_new_user` trigger, PostgREST RLS, and end-to-end FastAPI route behaviour.

## Running locally

**1. Start the local Supabase stack** (from the repo root):

```bash
supabase start
```

This boots Postgres, GoTrue (auth), and PostgREST as Docker containers using the
config in `supabase/config.toml`. Takes ~60–90 s on first run (image pull); fast
on subsequent runs.

**2. Export the local credentials** (one-liner):

```bash
eval "$(supabase status -o env)"
export SUPABASE_URL="$API_URL"
export SUPABASE_PUBLIC_ANON_KEY="$ANON_KEY"
export SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY"
```

Or copy the values from `supabase status` output manually if you prefer.

**3. Run the integration tests** (from the `backend/` directory):

```bash
cd backend
uv run pytest tests/integration/ -v -m integration
```

**4. Stop the stack when done:**

```bash
supabase stop
```

## What the tests cover

| Test | What it proves |
|------|----------------|
| `test_secure_test_returns_correct_user_id` | Real access token flows through FastAPI and the correct `user_id` is returned |
| `test_profile_auto_created_by_trigger` | Migration applied + `handle_new_user` trigger fires on signup + PostgREST reachable + RLS allows owner read |
| `test_profile_returns_404_after_row_deleted` | Empty PostgREST result correctly maps to HTTP 404 in the route handler |

## CI

The `backend-integration.yml` workflow runs these tests automatically on every
push to `main` that touches `backend/**` or `supabase/**`. No repository secrets
are needed — `supabase status -o env` emits all required keys.
