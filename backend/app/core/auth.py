from typing import Any

import jwt
import structlog
from fastapi import HTTPException, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.services.auth_service import decode_access_token

logger = structlog.get_logger(__name__)

http_bearer = HTTPBearer(auto_error=False, scheme_name="BearerAuth", bearerFormat="JWT")


async def verify_jwt(
    credentials: HTTPAuthorizationCredentials | None = Security(http_bearer),
) -> dict[str, Any]:
    if not credentials:
        raise HTTPException(status_code=401, detail="Missing Authorization header")
    try:
        payload = decode_access_token(credentials.credentials)
        if payload.get("type") != "access":
            raise HTTPException(status_code=401, detail="Not an access token")
        return {"token": credentials.credentials, "payload": payload}
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired") from None
    except jwt.InvalidTokenError as e:
        raise HTTPException(status_code=401, detail=f"Invalid token: {e}") from e
