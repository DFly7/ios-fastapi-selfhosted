"""RevenueCat webhook handler.

RevenueCat posts subscription lifecycle events to POST /api/v1/webhooks/revenuecat.
This endpoint updates ``profiles.is_pro`` in the database using the service account.

Security: every request must include the ``Authorization`` header set to the value
of ``REVENUECAT_WEBHOOK_SECRET`` in the backend environment. Configure the same
secret in the RevenueCat dashboard under Project → Integrations → Webhooks.

Event mapping
-------------
is_pro = True:
    INITIAL_PURCHASE, RENEWAL, UNCANCELLATION, BILLING_ISSUE (grace period active)

is_pro = False:
    CANCELLATION, EXPIRATION, SUBSCRIBER_ALIAS

All other event types (TRIAL_STARTED, PRODUCT_CHANGE, etc.) are acknowledged
with 200 and ignored — RevenueCat retries on non-2xx.
"""

import hmac
import logging
import uuid
from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.db.session import get_db
from app.repositories import profile_repo

logger = logging.getLogger(__name__)

router = APIRouter()

# Events that indicate an active, paying subscription.
_ACTIVE_EVENTS = {
    "INITIAL_PURCHASE",
    "RENEWAL",
    "UNCANCELLATION",
    "BILLING_ISSUE",  # Grace period — treat as still active.
}

# Events that indicate the subscription has lapsed.
_INACTIVE_EVENTS = {
    "CANCELLATION",
    "EXPIRATION",
    "SUBSCRIBER_ALIAS",
}


def _verify_secret(authorization: str = Header(default="")) -> None:
    """Dependency that validates the shared webhook secret.

    Uses ``hmac.compare_digest`` to prevent timing-based attacks.
    Returns immediately (allows all) when no secret is configured — useful for
    local development, but log a warning so it is not forgotten.
    """
    settings = get_settings()
    expected = settings.revenuecat_webhook_secret

    if not expected:
        logger.warning(
            "revenuecat_webhook_secret is not set — webhook auth is disabled. "
            "Set REVENUECAT_WEBHOOK_SECRET in production."
        )
        return

    if not authorization or not hmac.compare_digest(authorization, expected):
        raise HTTPException(status_code=401, detail="Invalid webhook secret.")


@router.post("/revenuecat", dependencies=[Depends(_verify_secret)])
async def revenuecat_webhook(
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    """Receive a RevenueCat event and update ``profiles.is_pro`` accordingly."""
    body: dict[str, Any] = await request.json()
    event: dict[str, Any] = body.get("event", {})

    event_type: str = event.get("type", "")
    app_user_id: str | None = event.get("app_user_id")

    logger.info(
        "revenuecat_webhook_received",
        extra={"event_type": event_type, "app_user_id": app_user_id},
    )

    if event_type not in _ACTIVE_EVENTS and event_type not in _INACTIVE_EVENTS:
        # Unknown or unhandled event — acknowledge and ignore.
        logger.debug("revenuecat_event_ignored", extra={"event_type": event_type})
        return {"status": "ignored"}

    if not app_user_id:
        logger.warning("revenuecat_webhook_missing_user_id", extra={"event_type": event_type})
        raise HTTPException(status_code=422, detail="Missing app_user_id in event payload.")

    is_pro = event_type in _ACTIVE_EVENTS

    try:
        await profile_repo.set_pro_status(db, uuid.UUID(app_user_id), is_pro=is_pro)
    except Exception as exc:
        logger.error(
            "revenuecat_webhook_db_error",
            extra={"error": str(exc), "app_user_id": app_user_id},
        )
        raise HTTPException(status_code=500, detail="Database update failed.") from exc

    logger.info(
        "revenuecat_webhook_processed",
        extra={
            "event_type": event_type,
            "app_user_id": app_user_id,
            "is_pro": is_pro,
        },
    )

    return {"status": "ok", "is_pro": str(is_pro)}
