from functools import lru_cache
from typing import Annotated, Any

from pydantic import AnyUrl, Field, HttpUrl, computed_field, field_validator, model_validator
from pydantic.functional_validators import BeforeValidator
from pydantic_settings import BaseSettings, SettingsConfigDict


def _empty_to_none(v: Any) -> Any:
    if v is None:
        return None
    if isinstance(v, str) and not v.strip():
        return None
    return v


OptionalHttpUrl = Annotated[HttpUrl | None, BeforeValidator(_empty_to_none)]
OptionalStr = Annotated[str | None, BeforeValidator(_empty_to_none)]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "Starter API"
    environment: str = "development"

    log_level: str = "DEBUG"
    log_json: bool = False

    log_request_body: bool = True
    log_request_body_max_size: int = Field(default=1000, ge=1, le=1_000_000)

    sentry_dsn: str | None = None
    sentry_environment: str | None = None
    sentry_traces_sample_rate: float = Field(default=0.1, ge=0.0, le=1.0)

    enable_metrics: bool = False

    rate_limit_enabled: bool = True
    rate_limit_default: str = Field(default="100/minute", min_length=1)

    database_url: AnyUrl = Field(..., description="asyncpg DSN")
    jwt_secret: str = Field(..., description="HS256 signing secret — min 32 chars")
    jwt_access_token_expire_seconds: int = 3600
    jwt_refresh_token_expire_seconds: int = 2_592_000  # 30 days

    revenuecat_webhook_secret: OptionalStr = None

    resend_api_key: OptionalStr = None
    resend_from_email: OptionalStr = Field(
        default=None,
        description="Sender address verified in Resend (e.g. onboarding@yourdomain.com).",
    )

    allowed_origins_csv: str = Field(
        default="*",
        validation_alias="ALLOWED_ORIGINS",
    )

    @computed_field
    def debug(self) -> bool:
        return self.environment != "production"

    @computed_field
    def allowed_origins(self) -> list[str]:
        return [o.strip() for o in self.allowed_origins_csv.split(",") if o.strip()]

    @model_validator(mode="before")
    @classmethod
    def env_dependent_defaults(cls, data: Any) -> Any:
        if not isinstance(data, dict):
            return data

        env = data.get("environment") or data.get("ENVIRONMENT")
        if env is None or (isinstance(env, str) and not str(env).strip()):
            env = "development"
        else:
            env = str(env).strip()

        # Keys match pydantic-settings merged input (field names are usually lowercase here)
        if not data.get("log_level"):
            data["log_level"] = "INFO" if env == "production" else "DEBUG"
        if "log_json" not in data:
            data["log_json"] = env == "production"

        if not data.get("sentry_environment"):
            data["sentry_environment"] = env

        return data

    @field_validator(
        "log_json",
        "enable_metrics",
        "rate_limit_enabled",
        "log_request_body",
        mode="before",
    )
    @classmethod
    def coerce_bool_env(cls, v: Any) -> Any:
        if isinstance(v, str):
            return v.lower() in ("1", "true", "yes")
        return v


@lru_cache
def get_settings() -> Settings:
    return Settings()
