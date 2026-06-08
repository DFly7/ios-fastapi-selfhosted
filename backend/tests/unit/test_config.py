"""Unit tests for app.core.config.Settings.

No HTTP server, no database. Tests are fully isolated from .env files and
process-level env vars (see conftest.py autouse fixture + _env_file=None below).

Coverage matches the test_config.py section in tests/unit/README.md:
- Defaults per environment (development / production)
- bool coercion from string env vars ("1", "true", "yes" → True, etc.)
- allowed_origins_csv → allowed_origins computed field
- OptionalHttpUrl / OptionalStr: empty / whitespace strings → None
- Bounds on log_request_body_max_size and sentry_traces_sample_rate
- debug computed field
- sentry_environment default from environment
"""

import pytest
from pydantic import ValidationError

from app.core.config import Settings, _empty_to_none


def make(**kwargs) -> Settings:
    """Construct a Settings instance with no .env file and explicit overrides.

    Provides defaults for required fields (database_url, jwt_secret) unless overridden.
    """
    defaults = {
        "database_url": "postgresql+asyncpg://localhost/test",
        "jwt_secret": "test_secret_min_32_chars_long_12345",
    }
    defaults.update(kwargs)
    return Settings(_env_file=None, **defaults)


# ---------------------------------------------------------------------------
# _empty_to_none — pure helper function
# ---------------------------------------------------------------------------


class TestEmptyToNone:
    def test_none_returns_none(self) -> None:
        assert _empty_to_none(None) is None

    def test_empty_string_returns_none(self) -> None:
        assert _empty_to_none("") is None

    def test_whitespace_only_returns_none(self) -> None:
        assert _empty_to_none("   ") is None

    def test_non_empty_string_passthrough(self) -> None:
        assert _empty_to_none("hello") == "hello"

    def test_non_string_non_none_passthrough(self) -> None:
        assert _empty_to_none(42) == 42


# ---------------------------------------------------------------------------
# Development defaults
# ---------------------------------------------------------------------------


class TestDevelopmentDefaults:
    def test_default_environment_is_development(self) -> None:
        assert make().environment == "development"

    def test_development_log_level_is_debug(self) -> None:
        assert make().log_level == "DEBUG"

    def test_development_log_json_is_false(self) -> None:
        assert make().log_json is False

    def test_development_debug_computed_field_is_true(self) -> None:
        assert make().debug is True

    def test_staging_debug_is_true(self) -> None:
        assert make(environment="staging").debug is True


# ---------------------------------------------------------------------------
# Production defaults
# ---------------------------------------------------------------------------


class TestProductionDefaults:
    def test_production_log_level_is_info(self) -> None:
        assert make(environment="production").log_level == "INFO"

    def test_production_log_json_is_true(self) -> None:
        assert make(environment="production").log_json is True

    def test_production_debug_is_false(self) -> None:
        assert make(environment="production").debug is False


# ---------------------------------------------------------------------------
# Explicit log_level / log_json override the env-dependent defaults
# ---------------------------------------------------------------------------


class TestExplicitOverridesWinOverEnvDefaults:
    def test_explicit_log_level_overrides_production_default(self) -> None:
        s = make(environment="production", log_level="DEBUG")
        assert s.log_level == "DEBUG"

    def test_explicit_log_json_false_overrides_production_default(self) -> None:
        s = make(environment="production", log_json=False)
        assert s.log_json is False


# ---------------------------------------------------------------------------
# sentry_environment default
# ---------------------------------------------------------------------------


class TestSentryEnvironment:
    def test_defaults_to_app_environment(self) -> None:
        assert make(environment="staging").sentry_environment == "staging"

    def test_explicit_value_overrides_default(self) -> None:
        s = make(environment="production", sentry_environment="prod-eu-west")
        assert s.sentry_environment == "prod-eu-west"

    def test_development_sentry_environment(self) -> None:
        assert make().sentry_environment == "development"


# ---------------------------------------------------------------------------
# allowed_origins_csv → allowed_origins
# ---------------------------------------------------------------------------


class TestAllowedOrigins:
    # allowed_origins_csv uses validation_alias="ALLOWED_ORIGINS", so pydantic
    # requires the alias key in __init__ (not the Python field name).

    def test_default_is_wildcard(self) -> None:
        assert make().allowed_origins == ["*"]

    def test_single_origin(self) -> None:
        s = make(ALLOWED_ORIGINS="https://example.com")
        assert s.allowed_origins == ["https://example.com"]

    def test_multiple_origins_parsed_from_csv(self) -> None:
        s = make(ALLOWED_ORIGINS="https://a.com,https://b.com")
        assert s.allowed_origins == ["https://a.com", "https://b.com"]

    def test_whitespace_around_each_origin_is_stripped(self) -> None:
        s = make(ALLOWED_ORIGINS=" https://a.com , https://b.com ")
        assert s.allowed_origins == ["https://a.com", "https://b.com"]

    def test_empty_segments_are_dropped(self) -> None:
        s = make(ALLOWED_ORIGINS="https://a.com,,https://b.com")
        assert s.allowed_origins == ["https://a.com", "https://b.com"]


# ---------------------------------------------------------------------------
# Bool coercion from string env vars
# ---------------------------------------------------------------------------


class TestBoolCoercion:
    @pytest.mark.parametrize("truthy", ["1", "true", "True", "TRUE", "yes", "Yes", "YES"])
    def test_truthy_string_coerces_to_true(self, truthy: str) -> None:
        assert make(log_json=truthy).log_json is True

    @pytest.mark.parametrize("falsy", ["0", "false", "False", "FALSE", "no", "No", "NO", "random"])
    def test_falsy_string_coerces_to_false(self, falsy: str) -> None:
        assert make(log_json=falsy).log_json is False

    def test_bool_true_passes_through(self) -> None:
        assert make(log_json=True).log_json is True

    def test_bool_false_passes_through(self) -> None:
        assert make(log_json=False).log_json is False

    def test_coercion_applies_to_all_bool_fields(self) -> None:
        s = make(
            log_json="true",
            enable_metrics="1",
            rate_limit_enabled="yes",
            log_request_body="false",
        )
        assert s.log_json is True
        assert s.enable_metrics is True
        assert s.rate_limit_enabled is True
        assert s.log_request_body is False


# ---------------------------------------------------------------------------
# OptionalHttpUrl / OptionalStr: empty → None
# ---------------------------------------------------------------------------


class TestOptionalFields:
    def test_empty_resend_api_key_becomes_none(self) -> None:
        assert make(resend_api_key="").resend_api_key is None


# ---------------------------------------------------------------------------
# Bounded numeric fields
# ---------------------------------------------------------------------------


class TestBoundedFields:
    # log_request_body_max_size: ge=1, le=1_000_000

    def test_log_request_body_max_size_default_is_1000(self) -> None:
        assert make().log_request_body_max_size == 1000

    def test_log_request_body_max_size_min_boundary_accepted(self) -> None:
        assert make(log_request_body_max_size=1).log_request_body_max_size == 1

    def test_log_request_body_max_size_max_boundary_accepted(self) -> None:
        assert make(log_request_body_max_size=1_000_000).log_request_body_max_size == 1_000_000

    def test_log_request_body_max_size_zero_raises(self) -> None:
        with pytest.raises(ValidationError):
            make(log_request_body_max_size=0)

    def test_log_request_body_max_size_above_max_raises(self) -> None:
        with pytest.raises(ValidationError):
            make(log_request_body_max_size=1_000_001)

    # sentry_traces_sample_rate: ge=0.0, le=1.0

    def test_sentry_traces_sample_rate_default_is_0_1(self) -> None:
        assert make().sentry_traces_sample_rate == 0.1

    def test_sentry_traces_sample_rate_zero_accepted(self) -> None:
        assert make(sentry_traces_sample_rate=0.0).sentry_traces_sample_rate == 0.0

    def test_sentry_traces_sample_rate_one_accepted(self) -> None:
        assert make(sentry_traces_sample_rate=1.0).sentry_traces_sample_rate == 1.0

    def test_sentry_traces_sample_rate_above_one_raises(self) -> None:
        with pytest.raises(ValidationError):
            make(sentry_traces_sample_rate=1.1)

    def test_sentry_traces_sample_rate_below_zero_raises(self) -> None:
        with pytest.raises(ValidationError):
            make(sentry_traces_sample_rate=-0.01)
