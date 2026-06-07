"""RevenueCat webhook handler.

RevenueCat posts subscription lifecycle events to POST /api/v1/webhooks/revenuecat.
This endpoint updates ``profiles.is_pro`` in Supabase using the service role key
(bypasses RLS) so the change is applied regardless of the user's auth state.

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
from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from supabase import acreate_client

from app.core.config import get_settings

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
async def revenuecat_webhook(request: Request) -> dict[str, str]:
    """Receive a RevenueCat event and update ``profiles.is_pro`` accordingly."""
    settings = get_settings()

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

    if not settings.supabase_url or not settings.supabase_service_role_key:
        logger.error(
            "revenuecat_webhook_no_supabase_credentials",
            extra={"missing": "SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY"},
        )
        raise HTTPException(
            status_code=503,
            detail="Server configuration error: Supabase service role credentials missing.",
        )

    is_pro = event_type in _ACTIVE_EVENTS

    # Use the service role key to bypass RLS and update any user's row.
    client = await acreate_client(
        str(settings.supabase_url),
        settings.supabase_service_role_key,
    )

    try:
        result = await (
            client.table("profiles").update({"is_pro": is_pro}).eq("id", app_user_id).execute()
        )
    except Exception as exc:
        logger.error(
            "revenuecat_webhook_db_error",
            extra={"error": str(exc), "app_user_id": app_user_id},
        )
        raise HTTPException(status_code=500, detail="Database update failed.") from exc

    rows_updated = len(result.data or [])
    logger.info(
        "revenuecat_webhook_processed",
        extra={
            "event_type": event_type,
            "app_user_id": app_user_id,
            "is_pro": is_pro,
            "rows_updated": rows_updated,
        },
    )

    return {"status": "ok", "is_pro": str(is_pro)}
