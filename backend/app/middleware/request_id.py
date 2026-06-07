"""
Request ID middleware: correlation ID in state, structlog context, and X-Request-ID header.
"""

import uuid
from collections.abc import Awaitable, Callable
from typing import cast

import structlog
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response


class RequestIDMiddleware(BaseHTTPMiddleware):
    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        request_id = request.headers.get("X-Request-ID") or str(uuid.uuid4())
        request.state.request_id = request_id
        structlog.contextvars.clear_contextvars()
        structlog.contextvars.bind_contextvars(request_id=request_id)
        response = cast(Response, await call_next(request))
        response.headers["X-Request-ID"] = request_id
        return response
