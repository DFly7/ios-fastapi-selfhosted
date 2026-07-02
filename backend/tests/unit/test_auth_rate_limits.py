"""Verify auth endpoints carry stricter SlowAPI rate limits."""

import app.api.v1.auth  # noqa: F401 — registers route limits on import
from app.core.rate_limit import limiter

AUTH_STRICT_ENDPOINTS = (
    "app.api.v1.auth.register",
    "app.api.v1.auth.login",
    "app.api.v1.auth.refresh",
)


def test_auth_register_login_refresh_have_5_per_minute_limits():
    for endpoint_key in AUTH_STRICT_ENDPOINTS:
        limits = limiter._route_limits.get(endpoint_key, [])
        assert limits, f"{endpoint_key} has no route-specific rate limits"
        assert any(str(limit.limit) == "5 per 1 minute" for limit in limits), (
            f"{endpoint_key} limits {[str(limit.limit) for limit in limits]!r} "
            "do not include 5/minute"
        )
