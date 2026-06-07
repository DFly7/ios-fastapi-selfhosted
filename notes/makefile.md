# Makefile

The `Makefile` lives at the repo root and provides convenience targets for common tasks.
Run all targets from the repo root: `make <target>`

---

## Targets

### `sync-models`

```bash
make sync-models
```

**When to use:** After adding, removing, or changing any field in `backend/app/schemas/`.

Runs `scripts/sync_models.py` inside the backend's `uv` environment. The script:
1. Scans every `BaseModel` subclass in `backend/app/schemas/`
2. Generates matching Swift `Decodable & Equatable` structs with correct `CodingKeys` for snake_case fields
3. Writes the output to `ios/StarterApp/StarterApp/Models/GeneratedModels.swift`

`GeneratedModels.swift` is auto-included by Tuist's `sources: ["StarterApp/**/*.swift"]` glob — no project file changes needed.

> **Rule:** Never manually edit `GeneratedModels.swift`. Always edit the Pydantic schema and re-run this target.

---

### `check-models`

```bash
make check-models
```

**When to use:** In CI, or to verify models are in sync before committing.

Same as `sync-models` but dry-run only — exits with code `1` if `GeneratedModels.swift` would change, without writing anything. Wired into the `check-models` job in `.github/workflows/backend-ci.yml`.

---

### `backend-dev`

```bash
make backend-dev
```

Starts the full local stack by delegating to `run.sh`: Supabase local instance + FastAPI via Docker Compose + any tunnel setup.

---

### `ios-gen`

```bash
make ios-gen
```

Re-generates the Xcode workspace from the Tuist manifest (`ios/StarterApp/Project.swift`).

**When to use:**
- After `sync-models` creates the `Models/` folder for the first time
- After adding/removing any Swift source files or SPM dependencies
- After changing `Project.swift` or `Tuist/Package.swift`

Runs `tuist generate` inside `ios/StarterApp/`.

---

### `help`

```bash
make help
```

Prints a summary of all documented targets (lines prefixed with `##` in the Makefile).

---

## Model sync pipeline (summary)

```
backend/app/schemas/*.py   ← edit here (Pydantic, source of truth)
        │
        │  make sync-models
        ▼
ios/.../Models/GeneratedModels.swift   ← never edit manually
        │
        │  make ios-gen  (first time only, or after folder structure changes)
        ▼
Xcode workspace picks up the file automatically via Tuist glob
```

The `check-models` CI job enforces that `GeneratedModels.swift` is always committed in sync with the schemas — if a developer changes a schema without running `sync-models`, the CI job fails with instructions to re-run it.
