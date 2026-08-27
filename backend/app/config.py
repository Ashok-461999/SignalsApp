from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # SmartAPI
    smartapi_api_key: str = ""
    smartapi_client_code: str = ""
    smartapi_password: str = ""
    smartapi_totp_secret: str = ""

    # SQLite (single-file DB on VM / Docker volume)
    sqlite_path: str = "./data/signalapp.db"

    app_env: str = "production"
    cors_origins: str = "*"

    # Live feed & scheduler
    enable_live_feed: bool = True
    enable_scheduler: bool = True
    backfill_days: int = 5
    session_refresh_hours: int = 6
    gap_backfill_hours: int = 12

    # Trading safety — paper mode default-on; live gated behind explicit flag + kill switch
    paper_trading: bool = True
    live_execution_enabled: bool = False
    kill_switch: bool = False
    risk_percent: float = 1.0
    trading_capital_inr: float = 20000.0
    trading_style: str = "hybrid"  # scalp | swing | hybrid

    # Crypto — keys stored encrypted in DB; Claude key stays on phone only
    crypto_storage_secret: str = ""
    crypto_paper_trading: bool = True
    crypto_live_enabled: bool = False

    # Signals — set false to fire on setup detection without backtest validation
    require_backtest_for_signals: bool = False

    # Options — minimum days to expiry for suggested contracts
    min_option_dte: int = 20
    min_option_dte_scalp: int = 0  # nearest weekly for scalping

    # Scalping — quick in/out on 5m bars (~30 min hold)
    scalp_holding_bars: int = 6  # 6 x 5m = 30 min scalp window
    scalp_min_confidence: int = 65  # quality TAKE without blocking whole choppy days
    max_take_signals_per_day: int = 15  # scalp cap — not 70+ spam
    signal_cooldown_minutes: int = 30  # same setup+instrument gap
    persist_take_signals_only: bool = True  # stop logging every NO_TRADE bar

    @property
    def database_url(self) -> str:
        path = Path(self.sqlite_path).as_posix()
        return f"sqlite+aiosqlite:///{path}"

    @property
    def database_url_sync(self) -> str:
        path = Path(self.sqlite_path).as_posix()
        return f"sqlite:///{path}"

    @property
    def cors_origin_list(self) -> list[str]:
        if self.cors_origins.strip() == "*":
            return ["*"]
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def smartapi_configured(self) -> bool:
        return all(
            [
                self.smartapi_api_key,
                self.smartapi_client_code,
                self.smartapi_password,
                self.smartapi_totp_secret,
            ]
        )

    @property
    def execution_allowed(self) -> bool:
        """Live order placement requires all safety gates to pass."""
        return (
            not self.paper_trading
            and self.live_execution_enabled
            and not self.kill_switch
        )


@lru_cache
def get_settings() -> Settings:
    return Settings()
