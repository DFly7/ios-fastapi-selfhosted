# Unit-only fixtures: mocked repositories, sample payloads, frozen clocks, etc.

import pytest

# Every env var that pydantic-settings reads for Settings.
# Cleared before each unit test so local .env / shell exports don't bleed in.
_SETTINGS_ENV_VARS = [
    "APP_NAME",
    "ENVIRONMENT",
    "LOG_LEVEL",
    "LOG_JSON",
    "LOG_REQUEST_BODY",
    "LOG_REQUEST_BODY_MAX_SIZE",
    "SENTRY_DSN",
    "SENTRY_ENVIRONMENT",
    "SENTRY_TRACES_SAMPLE_RATE",
    "ENABLE_METRICS",
    "RATE_LIMIT_ENABLED",
    "RATE_LIMIT_DEFAULT",
    "SUPABASE_URL",
    "SUPABASE_PUBLIC_ANON_KEY",
    "RESEND_API_KEY",
    "RESEND_FROM_EMAIL",
    "ALLOWED_ORIGINS",
]


@pytest.fixture(autouse=True)
def isolate_settings_env(monkeypatch: pytest.MonkeyPatch) -> None:
    """Clear all Settings-related env vars before each unit test.

    Combined with Settings(_env_file=None, ...) in the test helpers, this
    guarantees the test environment is independent of any local .env file
    or shell exports, so assertions on Settings defaults are deterministic.
    """
    for key in _SETTINGS_ENV_VARS:
        monkeypatch.delenv(key, raising=False)
