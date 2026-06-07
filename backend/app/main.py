from contextlib import asynccontextmanager
from typing import cast

import sentry_sdk
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.starlette import StarletteIntegration
from slowapi.middleware import SlowAPIMiddleware

from app.api.v1.router import api_router
from app.core.auth import close_jwk_http_client
from app.core.config import get_settings
from app.core.rate_limit import limiter
from app.exception_handlers import register_exception_handlers
from app.logging_config import get_logger, setup_logging
from app.middleware import AccessLogMiddleware, AuthContextMiddleware, RequestIDMiddleware

settings = get_settings()

setup_logging()
logger = get_logger(__name__)

if settings.sentry_dsn:
    sentry_sdk.init(
        dsn=settings.sentry_dsn,
        environment=settings.sentry_environment,
        traces_sample_rate=settings.sentry_traces_sample_rate,
        integrations=[
            StarletteIntegration(),
            FastApiIntegration(),
        ],
    )
    logger.info("sentry_initialized", environment=settings.sentry_environment)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info(
        "application_started",
        app_name=settings.app_name,
        environment=settings.environment,
        debug=settings.debug,
        log_level=settings.log_level,
        log_json=settings.log_json,
        rate_limit_enabled=settings.rate_limit_enabled,
    )
    print("FastAPI app started. Docs: /docs | Redoc: /redoc | Health: /healthz")
    yield
    await close_jwk_http_client()
    logger.info("application_shutdown", app_name=settings.app_name)


app = FastAPI(
    title=settings.app_name,
    swagger_ui_parameters={"persistAuthorization": True},
    lifespan=lifespan,
)

app.state.limiter = limiter

register_exception_handlers(app)

# Order: last registered runs first. Desired flow:
# RequestID → AuthContext → SlowAPI → AccessLog → route
app.add_middleware(AccessLogMiddleware)
if settings.rate_limit_enabled:
    app.add_middleware(SlowAPIMiddleware)
app.add_middleware(AuthContextMiddleware)
app.add_middleware(RequestIDMiddleware)

# Browsers reject allow_credentials=True with a wildcard origin (CORS spec).
# When origins are explicit, credentials (cookies / Authorization headers) are allowed.
# For a mobile-only API this is moot, but keeping it correct avoids confusion if a
# web frontend is added later.
_allowed = cast(list[str], settings.allowed_origins)
cors_origins = ["*"] if _allowed == ["*"] else _allowed
cors_credentials = cors_origins != ["*"]
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=cors_credentials,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/healthz")
@limiter.exempt
def healthz() -> dict:
    return {"status": "ok"}


if settings.enable_metrics:
    from prometheus_client import make_asgi_app

    metrics_app = make_asgi_app()
    app.mount("/metrics", metrics_app)
    logger.warning(
        "prometheus_metrics_enabled",
        endpoint="/metrics",
        warning=(
            "/metrics is unauthenticated. "
            "Restrict access via a reverse proxy rule or network policy before exposing publicly."
        ),
    )


app.include_router(api_router, prefix="/api/v1")
