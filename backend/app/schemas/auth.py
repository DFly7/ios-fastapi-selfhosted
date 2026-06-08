from pydantic import BaseModel


class RegisterRequest(BaseModel):
    """POST /auth/register request body."""

    email: str
    password: str
    display_name: str | None = None


class LoginRequest(BaseModel):
    """POST /auth/token request body."""

    email: str
    password: str


class RefreshRequest(BaseModel):
    """POST /auth/refresh request body."""

    refresh_token: str


class TokenResponse(BaseModel):
    """Auth token pair returned by register, login, and refresh endpoints."""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"
