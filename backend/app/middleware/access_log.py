"""
Structured access logging (method, path, status, duration, user, IP, optional body).
"""

import json
import time
from collections.abc import Awaitable, Callable
from typing import cast

import structlog
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.core.config import get_settings
from app.utils.log_context import safe_log_dict

logger = structlog.get_logger(__name__)
settings = get_settings()


def get_client_ip(request: Request) -> str | None:
    forwarded_for = request.headers.get("X-Forwarded-For")
    if forwarded_for:
        return forwarded_for.split(",")[-1].strip()
    real_ip = request.headers.get("X-Real-IP")
    if real_ip:
        return real_ip.strip()
    if request.client:
        return request.client.host
    return None


def get_user_details(request: Request) -> tuple[str | None, str | None]:
    user_id = getattr(request.state, "user_id", None)
    user_email = getattr(request.state, "user_email", None)
    user = getattr(request.state, "user", None)
    if user:
        if not user_id and hasattr(user, "id"):
            user_id = user.id
        if not user_email and hasattr(user, "email"):
            user_email = user.email
    return user_id, user_email


async def get_request_body(request: Request, max_size: int = 1000) -> dict | None:
    try:
        content_type = request.headers.get("content-type", "")
        if "application/json" not in content_type:
            return {"content_type": content_type, "logged": False}
        body_bytes = await request.body()
        body_size = len(body_bytes)
        if body_size > max_size:
            return {
                "size_bytes": body_size,
                "logged": False,
                "reason": f"body_too_large (max: {max_size} bytes)",
            }
        if body_bytes:
            body_json = json.loads(body_bytes)
            return safe_log_dict(body_json)
        return None
    except json.JSONDecodeError:
        return {"error": "invalid_json"}
    except Exception as exc:
        return {"error": type(exc).__name__}


class AccessLogMiddleware(BaseHTTPMiddleware):
    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        start_time = time.perf_counter()
        method = request.method
        path = request.url.path
        query_params = dict(request.query_params) if request.query_params else None
        user_id, user_email = get_user_details(request)
        client_ip = get_client_ip(request)

        if user_id:
            structlog.contextvars.bind_contextvars(
                user_id=user_id,
                user_email=user_email,
                client_ip=client_ip,
            )

        request_body = None
        if settings.log_request_body and method in ("POST", "PUT", "PATCH"):
            request_body = await get_request_body(request, settings.log_request_body_max_size)

        try:
            response = cast(Response, await call_next(request))
            status = response.status_code
            duration_ms = (time.perf_counter() - start_time) * 1000
            log_level = "info"
            if status >= 500:
                log_level = "error"
            elif status >= 400:
                log_level = "warning"

            log_data = {
                "event": "request_completed",
                "method": method,
                "path": path,
                "status": status,
                "duration_ms": round(duration_ms, 2),
                "client_ip": client_ip,
            }
            if query_params:
                log_data["query_params"] = query_params
            if user_id:
                log_data["user_id"] = user_id
                if user_email:
                    log_data["user_email"] = user_email
            if request_body is not None:
                log_data["request_body"] = request_body

            getattr(logger, log_level)(**log_data)
            return response

        except Exception as exc:
            duration_ms = (time.perf_counter() - start_time) * 1000
            error_log_data = {
                "event": "request_failed",
                "method": method,
                "path": path,
                "duration_ms": round(duration_ms, 2),
                "error_type": type(exc).__name__,
                "error_message": str(exc),
                "client_ip": client_ip,
                "exc_info": True,
            }
            if query_params:
                error_log_data["query_params"] = query_params
            if user_id:
                error_log_data["user_id"] = user_id
                if user_email:
                    error_log_data["user_email"] = user_email
            if request_body is not None:
                error_log_data["request_body"] = request_body
            logger.error(**error_log_data)
            raise
