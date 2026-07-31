# Superpowers artifacts (agent planning)

Design docs and implementation plans live here — **not under `docs/`**. `docs/` is for the
**published site** (e.g. GitHub Pages) and optional product reference docs — not agent planning.

## Layout

| Path | Use |
|------|-----|
| **`plans/`** | Current design docs + implementation plans. New work goes here. |
| **`specs/`** | Legacy location for design specs; kept only for live ones. **Write new designs in `plans/` as `*-design.md`.** |
| [`../archive/plans/`](../archive/plans/), [`../archive/specs/`](../archive/specs/) | Completed or superseded plans/specs — historical, not current. |

## Conventions

- **A feature is a pair:** `YYYY-MM-DD-<feature>-design.md` (the brainstorm / decision log,
  carries a `Status:` header) + `YYYY-MM-DD-<feature>.md` (the executable implementation plan).
- **`Status:` headers drift.** Prefer git history and product docs over a plan's own header as
  proof of what shipped.
- **When a plan's feature merges, move the pair to `../archive/plans/`** (and update the table
  below if you keep one). Link forward from new docs; don't edit archived ones.

## In-flight

| Initiative | Docs | State |
|---|---|---|
| _(none)_ | — | Add a row when you start a plan; remove it and archive the files when the work merges. |

This directory is tracked in git so paths in `AGENTS.md` and workflow skills resolve to a real folder.
