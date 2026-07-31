# CLAUDE.md

Claude Code reads this file at session start.

**Full workspace conventions live in [`AGENTS.md`](AGENTS.md)** (stack, TDD, simulator,
Cursor Cloud, skills). Read it before non-trivial work. The rules below are the
**non-negotiables inlined here** so a narrow task still respects them even if `AGENTS.md`
is never opened — `AGENTS.md` remains the source of truth when they need more detail.

- **Verification gate:** run **`make validate`** (lint, model-sync check, backend tests, iOS unit
  tests, iOS build) before claiming work is ready or merging. Don't assert tests pass without
  running it. During an iOS edit loop use **`make ios-build`** as the fast inner gate.
  On Cursor Cloud / Linux use **`make cloud-validate`** instead (no iOS).
- **iOS is Tuist-generated — never hand-edit `*.pbxproj` or `*.xcworkspace`.** Wire packages and
  settings in `ios/StarterApp/Project.swift` / `Tuist/Package.swift`, then run **`make ios-gen`**.
  Adding Swift files (or merging files in) requires `make ios-gen` before the project builds.
- **API contracts flow one way:** edit Pydantic schemas in `backend/`, then `make sync-models`
  (check with `make check-models`). Don't hand-edit `GeneratedModels.swift`.
- **Fresh git worktree:** run **`make worktree-init`** first (gitignored config + mise trust),
  and **`make worktree-clean`** when done, or build caches fill the disk.
- **Agent planning** lives under **`.agents/superpowers/`** (not `docs/`). See `AGENTS.md`
  § Docs layout.
- **TDD by default:** failing test first, then minimal code (unless the user opts out).

Don't invent new top-level conventions that contradict existing patterns.
