# Run from the repo root: make <target>
# Pass extra flags directly:  make dev ARGS="--regen --sim-logs"

.PHONY: dev dev-logs stop check-config sync-models check-models ios-gen ios-run ios-build ios-test ios-test-ui lint backend-test backend-integration-test validate check-deps help

# Auto-detect latest available iPhone simulator; override with UDID: make ios-test SIM_ID=<udid>
SIM_ID ?= $(shell xcrun simctl list devices available | grep -i iphone | tail -1 | grep -oEi '[0-9A-F-]{36}')

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

ios-run: ## Run ios-gen, then build and launch StarterApp on Simulator (override: SIM_ID=<udid>)
	@[ -n "$(SIM_ID)" ] || (echo "No iPhone simulator found — install one via Xcode ▸ Settings ▸ Platforms"; exit 1)
	$(MAKE) ios-gen
	./scripts/ios-sim.sh --udid $(SIM_ID)

ios-build: ## Build the iOS app for Simulator without running tests (faster CI gate)
	@[ -n "$(SIM_ID)" ] || (echo "No iPhone simulator found — install one via Xcode ▸ Settings ▸ Platforms"; exit 1)
	set -o pipefail && cd ios/StarterApp && xcodebuild build \
		-workspace StarterApp.xcworkspace \
		-scheme StarterApp \
		-destination 'platform=iOS Simulator,id=$(SIM_ID)' \
		2>&1 | bundle exec xcpretty --color

ios-test: ## Run unit tests on Simulator  (override: SIM_ID=<udid>)
	@[ -n "$(SIM_ID)" ] || (echo "No iPhone simulator found — install one via Xcode ▸ Settings ▸ Platforms"; exit 1)
	set -o pipefail && cd ios/StarterApp && xcodebuild test \
		-workspace StarterApp.xcworkspace \
		-scheme StarterApp \
		-only-testing:StarterAppTests \
		-destination 'platform=iOS Simulator,id=$(SIM_ID)' \
		2>&1 | bundle exec xcpretty --color

ios-test-ui: ## Run UI tests on Simulator  (override: SIM_ID=<udid>)
	@[ -n "$(SIM_ID)" ] || (echo "No iPhone simulator found — install one via Xcode ▸ Settings ▸ Platforms"; exit 1)
	set -o pipefail && cd ios/StarterApp && xcodebuild test \
		-workspace StarterApp.xcworkspace \
		-scheme StarterApp \
		-only-testing:StarterAppUITests \
		-destination 'platform=iOS Simulator,id=$(SIM_ID)' \
		2>&1 | bundle exec xcpretty --color

# ── Distribution ─────────────────────────────────────────────────────────────

setup-dist: ## One-time wizard: configure signing, create App Store record, seed certs repo
	./scripts/setup-dist.sh

create-app: ## Create App Store Connect record + register App ID (idempotent)
	cd ios/StarterApp && bundle exec fastlane create_app

beta: ## Build and upload to TestFlight via Fastlane
	cd ios/StarterApp && bundle exec fastlane beta

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
		uv run pytest tests/ -v --tb=short -m "not integration" \
			--cov=app \
			--cov-report=term-missing:skip-covered && \
		uv run coverage report --skip-covered --show-missing

backend-integration-test: ## Run backend integration tests against PostgreSQL (requires docker compose)
	@echo "── Backend integration tests ────────────────────────────────────"
	@cd backend && docker compose up -d db
	@echo "Waiting for PostgreSQL..."
	@sleep 5
	cd backend && uv sync --frozen && \
		ENVIRONMENT=ci LOG_JSON=false RATE_LIMIT_ENABLED=false \
		DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/postgres_test \
		uv run alembic upgrade head && \
		uv run pytest tests/integration/ -v -m integration --tb=short

lint: ## Same linters as CI: backend (ruff + mypy via uv) + iOS SwiftLint
	cd backend && uv sync --frozen && uv run ruff check . && uv run ruff format --check . && uv run mypy app
	cd ios/StarterApp && \
	  if command -v mise >/dev/null 2>&1; then \
	    mise exec -- swiftlint lint --strict --config .swiftlint.yml; \
	  else \
	    swiftlint lint --strict --config .swiftlint.yml; \
	  fi

# ── Validate (local CI-gate simulation) ──────────────────────────────────────

validate: ## Run all checks in sequence: lint → type-check → model-sync → unit tests → iOS build
	@echo "\n── 1/5  lint & type-check ──────────────────────────────────────"
	@$(MAKE) lint
	@echo "\n── 2/5  model-sync check ───────────────────────────────────────"
	@$(MAKE) check-models
	@echo "\n── 3/5  backend unit tests ─────────────────────────────────────"
	@$(MAKE) backend-test
	@echo "\n── 4/5  iOS unit tests ─────────────────────────────────────────"
	@$(MAKE) ios-test
	@echo "\n── 5/5  iOS build check ────────────────────────────────────────"
	@$(MAKE) ios-build
	@echo "\n✓  All checks passed — safe to push."

# ── Dependency check ─────────────────────────────────────────────────────────

check-deps: ## Check all prerequisite tools are installed and running
	@bash scripts/check-deps.sh

# ── Help ─────────────────────────────────────────────────────────────────────

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
