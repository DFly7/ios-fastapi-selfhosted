"""Unit tests for centralized exception handlers."""

import json
from unittest.mock import MagicMock

import pytest
from slowapi.errors import RateLimitExceeded
from starlette.requests import Request

from app.exception_handlers import rate_limit_exceeded_handler


@pytest.mark.asyncio
async def test_rate_limit_exceeded_includes_detail_and_error():
    request = MagicMock(spec=Request)
    request.state = MagicMock(request_id="req-429")
    request.method = "POST"
    request.url.path = "/api/v1/auth/token"

    response = await rate_limit_exceeded_handler(request, MagicMock(spec=RateLimitExceeded))

    assert response.status_code == 429
    body = json.loads(response.body.decode())
    assert body["error"] == "Too Many Requests"
    assert body["detail"] == "Too many attempts. Please try again later."
    assert body["status_code"] == 429
    assert body["request_id"] == "req-429"
