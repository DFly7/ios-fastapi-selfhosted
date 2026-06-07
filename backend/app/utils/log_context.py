"""
PII-safe logging helpers and background task log correlation.
"""

import asyncio
import re
import uuid
from collections.abc import Coroutine
from contextlib import contextmanager
from typing import Any, cast

import structlog
from structlog.stdlib import BoundLogger

logger = structlog.get_logger(__name__)

EMAIL_PATTERN = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b")
PHONE_PATTERN = re.compile(r"\b\d{3}[-.]?\d{3}[-.]?\d{4}\b")
SSN_PATTERN = re.compile(r"\b\d{3}-\d{2}-\d{4}\b")
CREDIT_CARD_PATTERN = re.compile(r"\b\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b")


def mask_sensitive_value(value: Any, mask_char: str = "*", visible_chars: int = 4) -> Any:
    if isinstance(value, str):
        if len(value) <= visible_chars:
            return mask_char * len(value)
        masked_length = len(value) - visible_chars
        return (mask_char * masked_length) + value[-visible_chars:]
    if isinstance(value, dict):
        return {k: mask_sensitive_value(v, mask_char, visible_chars) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return type(value)(mask_sensitive_value(item, mask_char, visible_chars) for item in value)
    return value


def mask_pii_in_text(text: str) -> str:
    text = EMAIL_PATTERN.sub(lambda m: f"***@{m.group().split('@')[1]}", text)
    text = PHONE_PATTERN.sub(lambda m: f"***-***-{m.group()[-4:]}", text)
    text = SSN_PATTERN.sub("***-**-****", text)
    text = CREDIT_CARD_PATTERN.sub(lambda m: f"****-****-****-{m.group()[-4:]}", text)
    return text


@contextmanager
def log_context(**kwargs: Any):
    structlog.contextvars.bind_contextvars(**kwargs)
    try:
        yield
    finally:
        structlog.contextvars.unbind_contextvars(*kwargs.keys())


class BackgroundTaskLogger:
    def __init__(
        self,
        task_name: str,
        request_id: str | None = None,
        user_id: str | None = None,
        **extra_context: Any,
    ):
        self.task_name = task_name
        self.request_id = request_id or str(uuid.uuid4())
        self.user_id = user_id
        self.extra_context = extra_context
        self.logger = structlog.get_logger(task_name)

    async def __aenter__(self) -> BoundLogger:
        context: dict[str, Any] = {
            "task_name": self.task_name,
            "request_id": self.request_id,
            **self.extra_context,
        }
        if self.user_id:
            context["user_id"] = self.user_id
        structlog.contextvars.bind_contextvars(**context)
        self.logger.info("background_task_started")
        return cast(BoundLogger, self.logger)

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if exc_type is not None:
            self.logger.error(
                "background_task_failed",
                error_type=exc_type.__name__,
                error_message=str(exc_val),
                exc_info=True,
            )
        else:
            self.logger.info("background_task_completed")
        structlog.contextvars.clear_contextvars()
        return False


async def run_in_background[T](
    coro: Coroutine[Any, Any, T],
    task_name: str,
    request_id: str | None = None,
    user_id: str | None = None,
    **extra_context: Any,
) -> asyncio.Task[T]:
    async def _wrapped_coro():
        async with BackgroundTaskLogger(
            task_name=task_name,
            request_id=request_id,
            user_id=user_id,
            **extra_context,
        ):
            return await coro

    return asyncio.create_task(_wrapped_coro())


def safe_log_dict(data: dict[str, Any], sensitive_keys: set | None = None) -> dict[str, Any]:
    from app.logging_config import SENSITIVE_FIELDS

    sensitive = SENSITIVE_FIELDS.copy()
    if sensitive_keys:
        sensitive.update(sensitive_keys)
    safe_dict: dict[str, Any] = {}
    for key, value in data.items():
        if any(sensitive_field in key.lower() for sensitive_field in sensitive):
            safe_dict[key] = "***MASKED***"
        elif isinstance(value, dict):
            safe_dict[key] = safe_log_dict(value, sensitive_keys)
        else:
            safe_dict[key] = value
    return safe_dict
