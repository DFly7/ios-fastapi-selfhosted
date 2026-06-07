# Scripts & Makefile

All automation lives in `scripts/`. Run everything from the repo root.

---

## scripts/dev.sh

Full local stack for simulator development. No tunnels needed — the simulator shares `127.0.0.1` with the host.

1. Starts Supabase, reads the anon key
2. Writes `backend/.env` (Supabase Docker URL + anon key)
3. Starts FastAPI via Docker Compose, waits for `/healthz`
4. Writes `ios/StarterApp/Config-Debug.xcconfig` (backend URL, Supabase URL, anon key)
5. Runs `tuist generate`, then builds and launches the simulator

```bash
./scripts/dev.sh               # full stack
./scripts/dev.sh --regen       # tuist install + generate first (after cloning)
./scripts/dev.sh --no-ios      # services only, skip iOS build
./scripts/dev.sh --sim-logs    # stream simulator console after launch
```

Ctrl-C shuts everything down cleanly.

---

## scripts/dev-logs.sh

Same as `dev.sh` but after launch splits the terminal into a 3-pane log view:

```
┌─────────────────────────────┐
│         FastAPI Logs        │
├──────────────┬──────────────┤
│  Supabase    │     iOS      │
│    Logs      │    Logs      │
└──────────────┴──────────────┘
```

Uses AppleScript pane-splitting in iTerm2; falls back to tmux elsewhere.

```bash
./scripts/dev-logs.sh
./scripts/dev-logs.sh --regen
./scripts/dev-logs.sh --no-ios
```

---

## scripts/tunnel.sh

For testing on a physical device or sharing the backend externally. Starts the same local stack, then exposes both services via [instatunnel](https://instatunnel.dev).

After tunnels are up you are prompted to override `Config-Debug.xcconfig` with the tunnel URLs:

```
BACKEND_URL  set to: http://127.0.0.1:8000
Override with https://my-backend-api.instatunnel.dev? [y/N]
```

If you confirm, the xcconfig is updated, `tuist generate` is run, and the simulator is built. A summary banner is printed telling you to run the app on your device.

Edit the two subdomain constants at the top of the file before first use:

```bash
SUPA_SUBDOMAIN="my-supa-api"
BACKEND_SUBDOMAIN="my-backend-api"
```

```bash
./scripts/tunnel.sh            # start services + tunnels + prompt + build
./scripts/tunnel.sh --build    # rebuild Docker image first
./scripts/tunnel.sh --regen    # tuist install + generate before build
./scripts/tunnel.sh --no-ios   # skip iOS config prompts and build entirely
```

---

## scripts/ios-sim.sh

Standalone iOS build and simulator launcher. Called by `dev.sh` and `tunnel.sh` internally, but also useful on its own when you only need to rebuild and relaunch the app.

```bash
./scripts/ios-sim.sh                  # auto-picks newest iPhone sim
./scripts/ios-sim.sh --regen          # tuist install + generate first
./scripts/ios-sim.sh --udid <UDID>    # target a specific simulator
./scripts/ios-sim.sh --logs           # stream console after launch
```

---

## scripts/_lib.sh

Internal shared library — not meant to be called directly. Sourced by `dev.sh`, `dev-logs.sh`, and `tunnel.sh`. Contains:

- `start_supabase` — starts Supabase, exports `SUPA_ANON_KEY`
- `configure_backend_env` — writes `backend/.env`
- `configure_ios_xcconfig` — writes `Config-Debug.xcconfig`
- `run_tuist` — runs `tuist install` (if needed) + `tuist generate`
- `wait_for_backend` — polls `/healthz` with a 60 s timeout
- `upsert_env` / `upsert_xcconfig` / `xcconfig_url` — config file helpers

---

## Makefile

```bash
make dev            # → scripts/dev.sh
make dev-logs       # → scripts/dev-logs.sh
make stop           # docker compose down + supabase stop + kill tmux session
make ios-gen        # tuist generate (refresh Xcode project after file changes)
make sync-models    # generate GeneratedModels.swift from Pydantic schemas
make check-models   # dry-run sync — exits 1 if out of sync (use in CI)
make help           # print all targets
```

Extra flags can be passed via `ARGS`:

```bash
make dev ARGS="--regen --sim-logs"
```
