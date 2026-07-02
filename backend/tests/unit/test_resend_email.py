"""Unit tests for app.services.resend_email."""

from unittest.mock import AsyncMock, patch

import pytest

from app.core.config import Settings
from app.services.resend_email import (
    ResendNotConfiguredError,
    resend_is_configured,
    send_email,
)


def make(**kwargs) -> Settings:
    """Construct Settings with no .env file (same pattern as test_config.py)."""
    defaults = {
        "database_url": "postgresql+asyncpg://localhost/test",
        "jwt_secret": "test_secret_min_32_chars_long_12345",
    }
    defaults.update(kwargs)
    return Settings(_env_file=None, **defaults)


class TestResendIsConfigured:
    def test_returns_false_when_both_missing(self) -> None:
        assert resend_is_configured(settings=make()) is False

    def test_returns_false_when_api_key_missing(self) -> None:
        assert resend_is_configured(settings=make(resend_from_email="noreply@example.com")) is False

    def test_returns_false_when_from_email_missing(self) -> None:
        assert resend_is_configured(settings=make(resend_api_key="re_123")) is False

    def test_returns_true_when_both_set(self) -> None:
        assert (
            resend_is_configured(
                settings=make(
                    resend_api_key="re_123",
                    resend_from_email="noreply@example.com",
                )
            )
            is True
        )


class TestSendEmail:
    async def test_raises_when_not_configured(self) -> None:
        with pytest.raises(ResendNotConfiguredError, match="RESEND_API_KEY"):
            await send_email(
                to=["user@example.com"],
                subject="Hi",
                html="<p>Hi</p>",
                settings=make(),
            )

    @patch("app.services.resend_email.resend.Emails.send_async", new_callable=AsyncMock)
    async def test_calls_resend_and_returns_dict_on_success(
        self, mock_send_async: AsyncMock
    ) -> None:
        mock_send_async.return_value = {"id": "email-123"}
        settings = make(
            resend_api_key="re_secret",
            resend_from_email="noreply@example.com",
        )

        result = await send_email(
            to=["user@example.com"],
            subject="Welcome",
            html="<p>Welcome</p>",
            settings=settings,
        )

        assert result == {"id": "email-123"}
        mock_send_async.assert_awaited_once()
        params = mock_send_async.await_args[0][0]
        assert params["from"] == "noreply@example.com"
        assert params["to"] == ["user@example.com"]
        assert params["subject"] == "Welcome"
        assert params["html"] == "<p>Welcome</p>"

    @patch("app.services.resend_email.logger.exception")
    @patch("app.services.resend_email.resend.Emails.send_async", new_callable=AsyncMock)
    async def test_reraises_and_logs_on_send_failure(
        self,
        mock_send_async: AsyncMock,
        mock_log_exception,
    ) -> None:
        mock_send_async.side_effect = RuntimeError("Resend API down")
        settings = make(
            resend_api_key="re_secret",
            resend_from_email="noreply@example.com",
        )

        with pytest.raises(RuntimeError, match="Resend API down"):
            await send_email(
                to=["user@example.com"],
                subject="Hi",
                html="<p>Hi</p>",
                settings=settings,
            )

        mock_log_exception.assert_called_once_with("resend_send_failed", to_count=1)
