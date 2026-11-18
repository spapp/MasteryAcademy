import os
from dataclasses import dataclass
from functools import lru_cache


@dataclass(frozen=True)
class Settings:
    database_url: str
    jwt_secret: str
    access_ttl_seconds: int
    refresh_ttl_days: int
    content_dir: str
    environment: str
    # Phase 2 (AI). The Claude key and the app key live only in the server's environment.
    anthropic_api_key: str = ""
    app_key: str = ""
    ai_model_fast: str = "claude-haiku-5-5"
    ai_model_strong: str = "claude-sonnet-5-5"
    ai_daily_limit: int = 100
    ai_monthly_cap_cents: int = 500
    # US dollars per million tokens as (input, output). Set AI_PRICE_FAST / AI_PRICE_STRONG from Anthropic's
    # pricing page; the defaults are deliberately high so the cost cap errs on the safe side.
    ai_price_fast: tuple = (1.0, 5.0)
    ai_price_strong: tuple = (3.0, 15.0)


def normalise_database_url(url: str) -> str:
    """Hosts such as Render hand out postgres:// or postgresql:// URLs; SQLAlchemy needs the psycopg 3 driver named."""
    for prefix in ("postgres://", "postgresql://"):
        if url.startswith(prefix):
            return "postgresql+psycopg://" + url[len(prefix):]
    return url


@lru_cache
def get_settings() -> Settings:
    env = os.environ.get("ENVIRONMENT", "development")
    secret = os.environ.get("JWT_SECRET", "")
    if env == "production" and len(secret) < 32:
        raise RuntimeError("JWT_SECRET must be at least 32 characters in production")
    return Settings(
        database_url=normalise_database_url(os.environ.get("DATABASE_URL", "sqlite:///./academy-dev.db")),
        jwt_secret=secret or "dev-only-secret-not-for-production-use",
        access_ttl_seconds=int(os.environ.get("ACCESS_TTL_SECONDS", "900")),
        refresh_ttl_days=int(os.environ.get("REFRESH_TTL_DAYS", "60")),
        content_dir=os.environ.get("CONTENT_DIR", os.path.join(os.path.dirname(__file__), "../../content/build")),
        environment=env,
        anthropic_api_key=os.environ.get("ANTHROPIC_API_KEY", ""),
        app_key=os.environ.get("APP_KEY", ""),
        ai_model_fast=os.environ.get("AI_MODEL_FAST", "claude-haiku-5-5"),
        ai_model_strong=os.environ.get("AI_MODEL_STRONG", "claude-sonnet-5-5"),
        ai_daily_limit=int(os.environ.get("AI_DAILY_LIMIT", "100")),
        ai_monthly_cap_cents=int(round(float(os.environ.get("AI_MONTHLY_CAP_USD", "5")) * 100)),
        ai_price_fast=_price(os.environ.get("AI_PRICE_FAST", "1,5")),
        ai_price_strong=_price(os.environ.get("AI_PRICE_STRONG", "3,15")),
    )


def _price(text: str) -> tuple:
    """ "1,5" -> (1.0, 5.0): dollars per million input and output tokens."""
    parts = [float(p) for p in text.split(",")]
    if len(parts) != 2 or min(parts) < 0:
        raise RuntimeError("AI price must be 'input,output' in dollars per million tokens")
    return (parts[0], parts[1])
