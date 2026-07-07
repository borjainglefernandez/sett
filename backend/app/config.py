"""Environment-driven configuration. No third-party settings library needed."""

from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache

from cryptography.fernet import Fernet


@dataclass(frozen=True)
class Settings:
    database_url: str
    jwt_secret: str
    apple_bundle_id: str
    apple_issuer: str
    apple_jwks_url: str
    access_ttl_sec: int
    refresh_ttl_days: int
    oura_client_id: str
    oura_client_secret: str
    oura_redirect_uri: str
    oura_token_key: str
    oura_authorize_url: str
    oura_token_url: str
    oura_api_base: str
    oura_deeplink: str
    anthropic_api_key: str
    digest_model: str
    digest_input_usd_per_mtok: float
    digest_output_usd_per_mtok: float
    analyze_daily_limit: int
    monthly_budget_usd: float
    api_version: str
    min_client_build: int
    auto_create_schema: bool
    backup_s3_bucket: str
    backup_s3_prefix: str
    postgres_host: str
    sentry_dsn: str


@lru_cache
def get_settings() -> Settings:
    def env(key: str, default: str = "") -> str:
        return os.environ.get(key, default)

    return Settings(
        database_url=env("DATABASE_URL", "sqlite+aiosqlite:///./sett_dev.db"),
        jwt_secret=env("JWT_SECRET", "dev-secret-do-not-use-in-prod-padding"),
        apple_bundle_id=env("APPLE_BUNDLE_ID", "com.borja.sett"),
        apple_issuer="https://appleid.apple.com",
        apple_jwks_url="https://appleid.apple.com/auth/keys",
        access_ttl_sec=int(env("ACCESS_TTL_SEC", "3600")),
        refresh_ttl_days=int(env("REFRESH_TTL_DAYS", "90")),
        oura_client_id=env("OURA_CLIENT_ID"),
        oura_client_secret=env("OURA_CLIENT_SECRET"),
        oura_redirect_uri=env("OURA_REDIRECT_URI", "https://sett.example.com/v1/oura/callback"),
        # Dev fallback: ephemeral per-process key so local runs work without env.
        oura_token_key=env("OURA_TOKEN_KEY") or Fernet.generate_key().decode(),
        oura_authorize_url="https://cloud.ouraring.com/oauth/authorize",
        oura_token_url="https://api.ouraring.com/oauth/token",
        oura_api_base="https://api.ouraring.com",
        oura_deeplink=env("OURA_DEEPLINK", "sett://oura/connected"),
        anthropic_api_key=env("ANTHROPIC_API_KEY"),
        digest_model=env("DIGEST_MODEL", "claude-haiku-4-5"),
        digest_input_usd_per_mtok=1.00,
        digest_output_usd_per_mtok=5.00,
        analyze_daily_limit=int(env("ANALYZE_DAILY_LIMIT", "3")),
        monthly_budget_usd=float(env("MONTHLY_BUDGET_USD", "1.00")),
        api_version=env("API_VERSION", "2.0.0"),
        min_client_build=int(env("MIN_CLIENT_BUILD", "1")),
        auto_create_schema=env("AUTO_CREATE_SCHEMA", "1") not in ("0", "false", "no"),
        backup_s3_bucket=env("BACKUP_S3_BUCKET"),
        backup_s3_prefix=env("BACKUP_S3_PREFIX", "sett/pg"),
        postgres_host=env("POSTGRES_HOST", "sett-db"),
        sentry_dsn=env("SENTRY_DSN"),
    )
