# Local Dev Script (dev.sh)

`dev.sh` is the single-command local development launcher. It wires up the full stack on your Mac with no tunnels required.

## Why no tunnels?

The iOS Simulator runs as a process on your Mac — it's not a real device on a separate network. It can reach `127.0.0.1` directly, just like any other app on your machine.

| Component | Address used by simulator | Address used by Docker container |
|---|---|---|
| Supabase local | `http://127.0.0.1:54321` | `http://host.docker.internal:54321` |
| FastAPI backend | `http://127.0.0.1:8000` | — (same network) |

## Usage

```bash
# First time after cloning — runs tuist install + generate
make dev-regen

# Normal day-to-day
make dev

# Services only, no iOS build (e.g. when working on backend only)
make dev-no-ios

# With simulator console logs streaming
./dev.sh --sim-logs
```

## What the script does, step by step

1. **`supabase start`** — boots local Postgres, Auth, Storage, Studio (port 54323)
2. **`supabase status`** — reads the anon key
3. **`backend/.env`** — upserts `SUPABASE_URL` (Docker host URL) and `SUPABASE_PUBLIC_ANON_KEY`; creates from `.env.example` if missing
4. **`docker compose up --build -d`** — starts FastAPI on port 8000
5. **Polls `GET /healthz`** — waits up to 60 s for the backend to be ready
6. **`ios/StarterApp/Config-Debug.xcconfig`** — upserts `BACKEND_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`; creates from `Config.example.xcconfig` if missing
7. **`run-sim.sh`** — builds and launches the app on the newest available iPhone simulator

## Config files updated automatically

| File | Keys written |
|---|---|
| `backend/.env` | `SUPABASE_URL`, `SUPABASE_PUBLIC_ANON_KEY` |
| `ios/StarterApp/Config-Debug.xcconfig` | `BACKEND_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` |

Both files are git-ignored. Other keys (bundle ID, team ID, PostHog, Resend, etc.) are left untouched — set them once and the script won't overwrite them.

## Stopping

`Ctrl-C` — the script traps this and runs cleanup:
- `docker compose down` (backend)
- `supabase stop` (local Supabase)

## Troubleshooting

**Backend never becomes ready**
```bash
cd backend && docker compose logs -f
```

**Simulator can't reach the backend**
- Confirm `BACKEND_URL` in `Config-Debug.xcconfig` is `http:/$()/127.0.0.1:8000`
- Make sure `docker compose ps` shows the backend container as `Up`
- Check that port 8000 is not taken by another process: `lsof -i :8000`

**`supabase start` is slow**
- Normal on first run — it pulls Docker images. Subsequent runs are fast.

**Xcode workspace missing**
- Use `make dev-regen` instead of `make dev` — it runs `tuist install + generate` first.
