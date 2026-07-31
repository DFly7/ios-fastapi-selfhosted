"""Unit tests for the log masker in app.logging_config.

The masker keys off field *names*. "token" is overloaded — an auth credential
and a unit of LLM text — so these tests pin both directions: credentials stay
masked, usage counters stay readable.
"""

import pytest

from app.logging_config import is_sensitive_key, mask_sensitive_data


@pytest.mark.parametrize(
    "key",
    [
        "password",
        "token",
        "access_token",
        "refresh_token",
        "id_token",
        "oauth_token",
        "api_key",
        "authorization",
        "jwt_secret",
        "credentials",
        "credit_card",
        "ssn",
        "Authorization",
    ],
)
def test_credential_keys_are_masked(key):
    assert is_sensitive_key(key) is True


@pytest.mark.parametrize(
    "key",
    [
        "tokens_in",
        "tokens_out",
        "prompt_tokens",
        "completion_tokens",
        "total_tokens",
        "token_count",
        "latency_ms",
        "model",
        "iterations",
    ],
)
def test_metric_keys_are_not_masked(key):
    assert is_sensitive_key(key) is False


def test_llm_call_telemetry_survives_masking():
    event = {
        "event": "llm_call",
        "model": "gpt-4o-mini",
        "tokens_in": 4213,
        "tokens_out": 118,
        "latency_ms": 3866,
        "authorization": "Bearer sk-deadbeef",
    }
    masked = mask_sensitive_data(None, "info", event)

    assert masked["tokens_in"] == 4213
    assert masked["tokens_out"] == 118
    assert masked["latency_ms"] == 3866
    assert masked["authorization"] == "***MASKED***"


def test_masking_recurses_into_nested_dicts():
    event = {"usage": {"tokens_out": 9, "api_key": "sk-live-123"}}
    masked = mask_sensitive_data(None, "info", event)

    assert masked["usage"]["tokens_out"] == 9
    assert masked["usage"]["api_key"] == "***MASKED***"
