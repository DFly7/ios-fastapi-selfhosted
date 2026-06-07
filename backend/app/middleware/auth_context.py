"""
Decode JWT without verification for logging context only (user_id, email, role).
Route-level Depends(verify_jwt) performs real verification.
"""

from collections.abc import Awaitable, Callable
from typing import cast

import jwt
import structlog
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

logger = structlog.get_logger(__name__)


class AuthContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        auth_header = request.headers.get("Authorization")
        if auth_header and auth_header.startswith("Bearer "):
            try:
                token = auth_header.replace("Bearer ", "")
                decoded = jwt.decode(token, options={"verify_signature": False})
                if sub := decoded.get("sub"):
                    request.state.user_id = sub
                if email := decoded.get("email"):
                    request.state.user_email = email
                if role := decoded.get("role"):
                    request.state.user_role = role
            except Exception as exc:
                logger.debug(
                    "failed_to_extract_user_context",
                    error=type(exc).__name__,
                )
        return cast(Response, await call_next(request))
