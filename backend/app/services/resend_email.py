"""Transactional email via Resend (https://resend.com).

This is a library-ready module — it is not wired to any route by default.
Call ``send_email`` from a route handler or a BackgroundTask when you need
to trigger transactional mail (e.g. welcome, password reset, notifications).

Required env vars: ``RESEND_API_KEY``, ``RESEND_FROM_EMAIL``.
When either is absent the module loads fine; ``send_email`` raises
``ResendNotConfiguredError`` at call time so the app starts without email config.

Usage example (inside a router):

    from fastapi import BackgroundTasks
    from app.services.resend_email import send_email, resend_is_configured

    @router.post("/signup")
    async def signup(background_tasks: BackgroundTasks, ...):
        ...
        if resend_is_configured():
            background_tasks.add_task(
                send_email,
                to=[user.email],
                subject="Welcome!",
                html="<p>Thanks for signing up.</p>",
            )
"""

from __future__ import annotations

from typing import Any, cast

import resend
from pydantic import EmailStr

from app.core.config import Settings, get_settings
from app.logging_config import get_logger

logger = get_logger(__name__)


class ResendNotConfiguredError(RuntimeError):
    pass


def resend_is_configured(settings: Settings | None = None) -> bool:
    s = settings or get_settings()
    return bool(s.resend_api_key and s.resend_from_email)


async def send_email(
    *,
    to: list[EmailStr],
    subject: str,
    html: str,
    text: str | None = None,
    reply_to: EmailStr | None = None,
    tags: list[dict[str, str]] | None = None,
    settings: Settings | None = None,
) -> dict[str, Any]:
    """Send one email via Resend. Raises ``ResendNotConfiguredError`` if env is not set."""
    s = settings or get_settings()
    if not s.resend_api_key or not s.resend_from_email:
        raise ResendNotConfiguredError(
            "Set RESEND_API_KEY and RESEND_FROM_EMAIL to send mail with Resend."
        )

    resend.api_key = s.resend_api_key

    params: resend.Emails.SendParams = {
        "from": s.resend_from_email,
        "to": [str(addr) for addr in to],
        "subject": subject,
        "html": html,
    }
    if text:
        params["text"] = text
    if reply_to:
        params["reply_to"] = str(reply_to)
    if tags:
        params["tags"] = cast(Any, tags)

    try:
        result = await resend.Emails.send_async(params)
    except Exception:
        logger.exception("resend_send_failed", to_count=len(to))
        raise

    logger.info("resend_send_ok", email_id=getattr(result, "id", None))
    if isinstance(result, dict):
        return cast(dict[str, Any], result)
    return {"id": getattr(result, "id", None)}
