# Run from the repo root: make <target>
# Pass extra flags directly:  make dev ARGS="--regen --sim-logs"

.PHONY: dev dev-logs stop check-config sync-models check-models ios-gen ios-workspace ios-run ios-device ios-build ios-build-for-testing ios-test ios-test-real ios-test-fast ios-test-ui e2e-test lint backend-lint backend-test backend-integration-test db-migrate db-revision validate cloud-validate validate-full smoke-test bootstrap worktree-init worktree-clean check-deps help

# Which simulator to build/test against: this worktree's own session sim, created on first use.
# Falling back to the "last available iPhone" instead lands on whichever device some *other*
# worktree is using — and since every agent shares one bundle id, installing onto it kills their
# app. Override explicitly with: make ios-test-real SIM_ID=<udid>
SIM_ID ?= $(shell bash scripts/session-sim.sh)

# No xcodebuild stage may run unbounded: a wedged simulator or a stuck SPM resolve makes it wait
# forever rather than fail, and ten minutes of silence is worse for an agent than an error.
# Absolute path: the iOS recipes cd into ios/StarterApp before invoking it.
BUILD_TIMEOUT ?= 900
TIMEOUT = bash $(CURDIR)/scripts/with-timeout.sh $(BUILD_TIMEOUT)

# One build cache per worktree, shared by every xcodebuild entry point (make + scripts/ios-sim.sh).
# Without this, `make ios-build` writes to Xcode's default DerivedData while ios-sim.sh writes to
# ./DerivedDataRun — two disjoint caches, so the same app is compiled twice per worktree.
# Path is relative to ios/StarterApp, which is where every recipe below cds to.
DERIVED_DATA ?= DerivedDataRun

# ── Local dev ────────────────────────────────────────────────────────────────

dev: ## Start Postgres + backend + iOS Simulator
	./scripts/dev.sh $(ARGS)

dev-logs: ## Same as dev + 3-pane log view (FastAPI / Postgres / iOS)
	./scripts/dev-logs.sh $(ARGS)

stop: ## Stop all running services (Docker, tmux log session)
	-cd backend && docker compose down
	-tmux kill-session -t dev-stack 2>/dev/null

check-config: ## Show and validate iOS xcconfig + backend .env (no services needed)
	@bash -c 'REPO_ROOT="$(CURDIR)" && source scripts/_lib.sh && check_config_files'

# ── iOS ──────────────────────────────────────────────────────────────────────

ios-gen: ## Resolve SPM deps and re-generate the Xcode project
	cd ios/StarterApp && tuist install && tuist generate --no-open

# The .xcworkspace is gitignored and Tuist-generated, so it does not exist in a fresh worktree.
# Every xcodebuild target below depends on this so it self-heals instead of failing with a
# "workspace not found" error that reads like a broken checkout.
ios-workspace:
	@[ -d ios/StarterApp/StarterApp.xcworkspace ] || $(MAKE) ios-gen

ios-run: ios-workspace ## Run ios-gen, then build and launch StarterApp on Simulator (override: SIM_ID=<udid>)
	@[ -n "$(SIM_ID)" ] || (echo "No iPhone simulator found — install one via Xcode ▸ Settings ▸ Platforms"; exit 1)
	$(MAKE) ios-gen
	./scripts/ios-sim.sh --udid $(SIM_ID)

ios-device: ## Build, install & launch StarterApp on a paired physical iPhone (override: TEAM=<id> DEVICE_ID=<udid>)
	./scripts/ios-device.sh $(if $(TEAM),--team $(TEAM)) $(if $(DEVICE_ID),--device-id $(DEVICE_ID)) $(ARGS)

ios-build: ios-workspace ## Build the iOS app for Simulator without running tests (faster CI gate)
	@[ -n "$(SIM_ID)" ] || (echo "No iPhone simulator found — install one via Xcode ▸ Settings ▸ Platforms"; exit 1)
	set -o pipefail && cd ios/StarterApp && $(TIMEOUT) xcodebuild build \
		-workspace StarterApp.xcworkspace \
		-scheme StarterApp \
		-derivedDataPath $(DERIVED_DATA) \
		-destination 'platform=iOS Simulator,id=$(SIM_ID)' \
		2>&1 | bundle exec xcpretty --color

# CI uses build-for-testing + test-without-building; plain `xcodebuild test` can hang locally.
IOS_XCODEBUILD_DEST = -destination 'platform=iOS Simulator,id=$(SIM_ID)'

ios-build-for-testing: ios-workspace ## Build app + test bundle for Simulator (run after code changes)
	@[ -n "$(SIM_ID)" ] || (echo "No iPhone simulator found — install one via Xcode ▸ Settings ▸ Platforms"; exit 1)
	set -o pipefail && cd ios/StarterApp && $(TIMEOUT) xcodebuild build-for-testing \
		-workspace StarterApp.xcworkspace \
		-scheme StarterApp \
		-derivedDataPath $(DERIVED_DATA) \
		$(IOS_XCODEBUILD_DEST) \
		2>&1 | bundle exec xcpretty --color

# test-without-building must read the SAME derivedDataPath that build-for-testing wrote to.
# Wrapped in a script that reboots the sim and retries once if the device is too stale to host the
# test runner, and that prints xcodebuild's verdict (xcpretty swallows it, leaving a bare Error 65).
ios-test-fast: ## Run unit tests only (requires ios-build-for-testing first)  (override: SIM_ID=<udid>)
	@[ -n "$(SIM_ID)" ] || (echo "No iPhone simulator found — install one via Xcode ▸ Settings ▸ Platforms"; exit 1)
	@bash scripts/ios-unit-test.sh $(SIM_ID) $(DERIVED_DATA)

ios-test: ios-test-real ## Build + run the iOS unit tests (alias for ios-test-real)

ios-test-real: ios-build-for-testing ios-test-fast ## Build + run iOS unit tests for real (override: SIM_ID=<udid>)

ios-test-ui: ios-workspace ## Run UI tests on Simulator  (override: SIM_ID=<udid>)
	@[ -n "$(SIM_ID)" ] || (echo "No iPhone simulator found — install one via Xcode ▸ Settings ▸ Platforms"; exit 1)
	set -o pipefail && cd ios/StarterApp && xcodebuild test \
		-workspace StarterApp.xcworkspace \
		-scheme StarterApp \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:StarterAppUITests \
		-destination 'platform=iOS Simulator,id=$(SIM_ID)' \
		2>&1 | bundle exec xcpretty --color

e2e-test: ## Local E2E: UI test against running dev stack (requires make dev)
	@bash scripts/e2e-test.sh

# ── Distribution ─────────────────────────────────────────────────────────────

setup-dist: ## One-time wizard: configure signing + seed certs repo (ASC app is manual/2FA)
	./scripts/setup-dist.sh

beta: ios-gen ## Build and upload to TestFlight via Fastlane
	# ios-gen prerequisite: the Release archive needs a fresh Tuist project or it fails
	# "cannot find X in scope" when a merge added Swift files (CI's distribute.yml regenerates too).
	# LANG/LC_ALL: xcpretty crashes ("invalid byte sequence in US-ASCII") when the shell has no
	# UTF-8 locale — the case in non-interactive agent shells. Harmless when a locale is already set.
	cd ios/StarterApp && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 bundle exec fastlane beta

release: ## Submit to App Store via Fastlane (review not triggered automatically)
	cd ios/StarterApp && bundle exec fastlane release

# ── Models ───────────────────────────────────────────────────────────────────

sync-models: ## Generate Swift Codable structs from Pydantic schemas
	cd backend && uv run python ../scripts/sync_models.py

check-models: ## Dry-run: exit 1 if GeneratedModels.swift is out of sync (use in CI)
	cd backend && uv run python ../scripts/sync_models.py --check

# ── Lint / backend tests (parity with GitHub Actions) ───────────────────────

backend-test: ## Backend pytest + coverage (same env/flags as Backend CI test job)
	cd backend && uv sync --frozen && \
		ENVIRONMENT=ci LOG_JSON=false RATE_LIMIT_ENABLED=false \
		uv run python -m pytest tests/ -v --tb=short -m "not integration" \
			--cov=app \
			--cov-report=term-missing:skip-covered && \
		uv run python -m coverage report --skip-covered --show-missing

db-migrate: ## Run Alembic migrations inside the running Docker backend container (run make dev first)
	@docker compose ps backend --format '{{.State}}' 2>/dev/null | grep -q running \
		|| (echo "Error: backend container is not running — start it with 'make dev' first"; exit 1)
	docker compose exec backend uv run alembic upgrade head

db-revision: ## Generate an Alembic revision locally against localhost:5432 (MSG=... required)
	@[ -n "$(MSG)" ] \
		|| (echo "Error: MSG is required — run: make db-revision MSG=\"your message here\""; exit 1)
	cd backend && uv sync --frozen && \
		DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/postgres \
		uv run python -m alembic revision --autogenerate -m "$(MSG)"

backend-integration-test: ## Run backend integration tests against PostgreSQL (requires docker compose)
	@echo "── Backend integration tests ────────────────────────────────────"
	@cd backend && docker compose up -d db
	@echo "Waiting for PostgreSQL..."
	@sleep 5
	cd backend && uv sync --frozen && \
		ENVIRONMENT=ci LOG_JSON=false RATE_LIMIT_ENABLED=false \
		DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/postgres_test \
		JWT_SECRET=testsecretatleast32charslong1234 \
		uv run python -m alembic upgrade head && \
		uv run python -m pytest tests/integration/ -v -m integration --tb=short

lint: ## Same linters as CI: backend (ruff + mypy via uv) + iOS SwiftLint
	@$(MAKE) backend-lint
	cd ios/StarterApp && \
	  if command -v mise >/dev/null 2>&1; then \
	    mise exec -- swiftlint lint --strict --config .swiftlint.yml; \
	  else \
	    swiftlint lint --strict --config .swiftlint.yml; \
	  fi

backend-lint: ## Backend ruff + mypy only (Linux / Cursor Cloud safe)
	cd backend && uv sync --frozen && uv run python -m ruff check . && uv run python -m ruff format --check . && uv run python -m mypy app

# ── Validate (local CI-gate simulation) ──────────────────────────────────────

validate: ## Run all checks in sequence: model-sync → lint → backend tests → iOS tests → iOS build
	@echo "\n── 1/5  model-sync check ───────────────────────────────────────"
	@$(MAKE) check-models
	@echo "\n── 2/5  lint & type-check ──────────────────────────────────────"
	@$(MAKE) lint
	@echo "\n── 3/5  backend unit tests ─────────────────────────────────────"
	@$(MAKE) backend-test
	@echo "\n── 4/5  iOS unit tests ─────────────────────────────────────────"
	@$(MAKE) ios-test-real
	@echo "\n── 5/5  iOS build check ────────────────────────────────────────"
	@$(MAKE) ios-build
	@echo "\n✓  Checks passed — iOS tests included."

cloud-validate: ## Cursor Cloud / Linux gate: models + backend lint/tests (no iOS)
	@echo "\n── 1/3  model-sync check ───────────────────────────────────────"
	@$(MAKE) check-models
	@echo "\n── 2/3  backend lint & type-check ──────────────────────────────"
	@$(MAKE) backend-lint
	@echo "\n── 3/3  backend unit tests ─────────────────────────────────────"
	@$(MAKE) backend-test
	@echo "\n✓  Cloud checks passed — iOS compile/tests are macOS CI / local."

validate-full: validate ## Full validation: validate + integration tests + smoke test
	@echo "\n── 6/7  backend integration tests ──────────────────────────────"
	@$(MAKE) backend-integration-test
	@echo "\n── 7/7  smoke test ─────────────────────────────────────────────"
	@bash scripts/smoke-test.sh
	@echo "\n✓  Full validation passed."

smoke-test: ## Run curl-based happy-path smoke test against running backend
	@bash scripts/smoke-test.sh

# ── Worktrees ────────────────────────────────────────────────────────────────

worktree-init: ## Make a fresh git worktree buildable: seed gitignored config, trust mise, generate project
	@bash scripts/worktree-init.sh

worktree-clean: ## Delete this worktree's build cache + its session simulator (both are regenerable)
	@bash scripts/worktree-clean.sh $(ARGS)

# ── Dependency check ─────────────────────────────────────────────────────────

check-deps: ## Check all prerequisite tools are installed and running
	@bash scripts/check-deps.sh

# ── Bootstrap ────────────────────────────────────────────────────────────────

bootstrap: ## First-time setup: copy .env files, generate JWT_SECRET, install tools + deps
	@echo "\n── Bootstrapping project ──────────────────────────────────────"
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		JWT=$$(openssl rand -hex 32); \
		sed -i '' "s/change-me-generate-with-openssl-rand-hex-32/$$JWT/" .env; \
		echo "  ✓ Created .env with generated JWT_SECRET"; \
	else \
		echo "  · .env already exists — skipping"; \
	fi
	@if [ ! -f backend/.env ]; then \
		cp backend/.env.example backend/.env; \
		JWT=$$(grep '^JWT_SECRET=' .env | cut -d= -f2); \
		sed -i '' "s/change-me-generate-with-openssl-rand-hex-32/$$JWT/" backend/.env; \
		echo "  ✓ Created backend/.env (JWT_SECRET synced from root)"; \
	else \
		echo "  · backend/.env already exists — skipping"; \
	fi
	@echo "\n── Installing tools (mise) ────────────────────────────────────"
	@if command -v mise >/dev/null 2>&1; then \
		mise install; \
	else \
		echo "  ⚠  mise not found — install from https://mise.jdx.dev then re-run"; \
	fi
	@echo "\n── Installing Python dependencies ─────────────────────────────"
	cd backend && uv sync
	@echo "\n── Checking all dependencies ──────────────────────────────────"
	@bash scripts/check-deps.sh
	@echo "\n✓  Bootstrap complete. Run 'make dev' to start the stack."

# ── Help ─────────────────────────────────────────────────────────────────────

help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' Makefile \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
