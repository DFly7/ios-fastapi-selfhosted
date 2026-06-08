# Run from the repo root: make <target>
# Pass extra flags directly:  make dev ARGS="--regen --sim-logs"

.PHONY: dev dev-logs stop check-config sync-models check-models ios-gen ios-run ios-build ios-test ios-test-ui lint backend-test backend-integration-test validate validate-full smoke-test bootstrap check-deps help

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
		uv run python -m pytest tests/ -v --tb=short -m "not integration" \
			--cov=app \
			--cov-report=term-missing:skip-covered && \
		uv run python -m coverage report --skip-covered --show-missing

backend-integration-test: ## Run backend integration tests against PostgreSQL (requires docker compose)
	@echo "── Backend integration tests ────────────────────────────────────"
	@cd backend && docker compose up -d db
	@echo "Waiting for PostgreSQL..."
	@sleep 5
	cd backend && uv sync --frozen && \
		ENVIRONMENT=ci LOG_JSON=false RATE_LIMIT_ENABLED=false \
		DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/postgres_test \
		uv run python -m alembic upgrade head && \
		uv run python -m pytest tests/integration/ -v -m integration --tb=short

lint: ## Same linters as CI: backend (ruff + mypy via uv) + iOS SwiftLint
	cd backend && uv sync --frozen && uv run python -m ruff check . && uv run python -m ruff format --check . && uv run python -m mypy app
	cd ios/StarterApp && \
	  if command -v mise >/dev/null 2>&1; then \
	    mise exec -- swiftlint lint --strict --config .swiftlint.yml; \
	  else \
	    swiftlint lint --strict --config .swiftlint.yml; \
	  fi

# ── Validate (local CI-gate simulation) ──────────────────────────────────────

validate: ## Run all checks in sequence: model-sync → lint → backend tests → iOS tests → iOS build
	@echo "\n── 1/5  model-sync check ───────────────────────────────────────"
	@$(MAKE) check-models
	@echo "\n── 2/5  lint & type-check ──────────────────────────────────────"
	@$(MAKE) lint
	@echo "\n── 3/5  backend unit tests ─────────────────────────────────────"
	@$(MAKE) backend-test
	@echo "\n── 4/5  iOS unit tests ─────────────────────────────────────────"
	@$(MAKE) ios-test
	@echo "\n── 5/5  iOS build check ────────────────────────────────────────"
	@$(MAKE) ios-build
	@echo "\n✓  All checks passed — safe to push."

validate-full: validate ## Full validation: validate + integration tests + smoke test
	@echo "\n── 6/7  backend integration tests ──────────────────────────────"
	@$(MAKE) backend-integration-test
	@echo "\n── 7/7  smoke test ─────────────────────────────────────────────"
	@bash scripts/smoke-test.sh
	@echo "\n✓  Full validation passed."

smoke-test: ## Run curl-based happy-path smoke test against running backend
	@bash scripts/smoke-test.sh

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
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
