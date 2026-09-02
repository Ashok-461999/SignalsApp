"""India Alpha Engine v2 — constants, specs, caps."""

from __future__ import annotations

ALPHA_INSTRUMENTS: tuple[str, ...] = ("NIFTY", "BANKNIFTY", "SENSEX")

INSTRUMENT_SPECS: dict[str, dict] = {
    "NIFTY": {"lot_size": 25, "strike_step": 50, "weekly_expiry_weekday": 3, "exchange": "NFO", "sector": "Index"},
    "BANKNIFTY": {"lot_size": 15, "strike_step": 100, "weekly_expiry_weekday": 2, "exchange": "NFO", "sector": "Bank"},
    "SENSEX": {"lot_size": 10, "strike_step": 100, "weekly_expiry_weekday": 4, "exchange": "BFO", "sector": "Index"},
}

SECTOR_INDICES: dict[str, str] = {
    "Bank": "BANKNIFTY",
    "IT": "NIFTY",
    "Index": "NIFTY",
}

STOCK_LOT_SIZES: dict[str, int] = {
    "RELIANCE": 250, "TCS": 175, "INFY": 250, "HDFCBANK": 550, "ICICIBANK": 700,
    "SBIN": 750, "LT": 175, "ITC": 1600, "AXISBANK": 625, "KOTAKBANK": 400,
    "HUL": 350, "MARUTI": 100, "TATAMOTORS": 1425, "SUNPHARMA": 700, "BHARTIARTL": 475,
}

MCX_SPECS: dict[str, dict] = {
    "GOLD": {"lot_size": 100, "tick": 1.0},
    "SILVER": {"lot_size": 30, "tick": 1.0},
    "CRUDEOIL": {"lot_size": 100, "tick": 1.0},
    "NATURALGAS": {"lot_size": 1250, "tick": 0.1},
}

MIN_CONFLUENCE_SCORE = 70
MAX_SIGNALS_PER_DAY = 12
MIN_SIGNALS_FOR_PREP_ONLY = 5

TIER_LIMITS = {"A+": 3, "A": 5, "B": 2}
TIER_RISK_PCT = {"A+": 1.5, "A": 1.0, "B": 0.5}

PCR_EXTREME_LOW = 0.65
PCR_EXTREME_HIGH = 1.35
PCR_NEUTRAL_LOW = 0.85
PCR_NEUTRAL_HIGH = 1.15

DISCLAIMER = (
    "Options carry substantial risk. Sellers face theoretically unlimited risk. "
    "Buyers face time decay and volatility risk. Past performance does not "
    "guarantee future results. This analysis is for educational purposes only. "
    "Risk only capital you can afford to lose completely."
)
