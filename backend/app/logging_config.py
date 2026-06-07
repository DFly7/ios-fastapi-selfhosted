"""
Structured logging with structlog: JSON in production, console in development.
"""

import logging
import sys
from collections.abc import MutableMapping
from typing import Any, cast

import structlog
from structlog.types import EventDict, Processor

from app.core.config import get_settings

settings = get_settings()

SENSITIVE_FIELDS = {
    "password",
    "token",
    "secret",
    "api_key",
    "apikey",
    "authorization",
    "auth",
    "credentials",
    "credit_card",
    "ssn",
}


def mask_sensitive_data(logger: Any, method_name: str, event_dict: EventDict) -> EventDict:
    def _mask_dict(d: MutableMapping[str, Any]) -> dict[str, Any]:
        masked: dict[str, Any] = {}
        for key, value in d.items():
            if isinstance(key, str) and any(
                sensitive in key.lower() for sensitive in SENSITIVE_FIELDS
            ):
                masked[key] = "***MASKED***"
            elif isinstance(value, dict):
                masked[key] = _mask_dict(value)
            elif isinstance(value, (list, tuple)):
                masked[key] = [
                    _mask_dict(item) if isinstance(item, dict) else item for item in value
                ]
            else:
                masked[key] = value
        return masked

    return _mask_dict(event_dict)


def add_service_context(logger: Any, method_name: str, event_dict: EventDict) -> EventDict:
    event_dict.setdefault("service", settings.app_name)
    event_dict.setdefault("env", settings.environment)
    return event_dict


def rename_event_key(logger: Any, method_name: str, event_dict: EventDict) -> EventDict:
    if "event" in event_dict:
        event_dict["message"] = event_dict["event"]
    return event_dict


def setup_logging() -> None:
    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=getattr(logging, settings.log_level.upper()),
    )
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.error").setLevel(logging.WARNING)
    logging.getLogger("slowapi").propagate = False
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.getLogger("h2").setLevel(logging.WARNING)
    logging.getLogger("hpack").setLevel(logging.WARNING)
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    logging.getLogger("requests").setLevel(logging.WARNING)

    shared_processors: list[Processor] = [
        structlog.contextvars.merge_contextvars,
        structlog.stdlib.add_log_level,
        structlog.stdlib.add_logger_name,
        structlog.processors.TimeStamper(fmt="iso", utc=True, key="ts"),
        add_service_context,
        mask_sensitive_data,
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        rename_event_key,
    ]

    if settings.log_json:
        processors = shared_processors + [structlog.processors.JSONRenderer()]
    else:
        processors = shared_processors + [structlog.dev.ConsoleRenderer(colors=True)]

    structlog.configure(
        processors=processors,
        wrapper_class=structlog.stdlib.BoundLogger,
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )


def get_logger(name: str | None = None) -> structlog.stdlib.BoundLogger:
    return cast(structlog.stdlib.BoundLogger, structlog.get_logger(name))


logger = get_logger(__name__)
