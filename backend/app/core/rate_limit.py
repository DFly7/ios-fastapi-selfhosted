"""
Rate limiting via SlowAPI.

- key_func prefers authenticated user_id (set by AuthContextMiddleware) over IP.
- Client IP uses the rightmost X-Forwarded-For value (common behind Railway/reverse proxies).
- For multiple instances, configure Limiter(storage_uri="redis://...").
"""

from slowapi import Limiter
from starlette.requests import Request

from app.core.config import get_settings


def get_client_ip(request: Request) -> str:
    forwarded_for = request.headers.get("X-Forwarded-For")
    if forwarded_for:
        return forwarded_for.split(",")[-1].strip()
    real_ip = request.headers.get("X-Real-IP")
    if real_ip:
        return real_ip.strip()
    return request.client.host if request.client else "unknown"


def get_rate_limit_key(request: Request) -> str:
    user_id = getattr(request.state, "user_id", None)
    if user_id:
        return f"user:{user_id}"
    return f"ip:{get_client_ip(request)}"


_settings = get_settings()
limiter = Limiter(
    key_func=get_rate_limit_key,
    default_limits=[_settings.rate_limit_default],
)
