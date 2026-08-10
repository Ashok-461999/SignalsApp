"""Black-Scholes option pricing for backtest and signal reference."""

import math
from datetime import date, datetime

from scipy.stats import norm


def _d1(S: float, K: float, T: float, r: float, sigma: float) -> float:
    if T <= 0 or sigma <= 0 or S <= 0 or K <= 0:
        return 0.0
    return (math.log(S / K) + (r + 0.5 * sigma**2) * T) / (sigma * math.sqrt(T))


def black_scholes_price(
    spot: float,
    strike: float,
    days_to_expiry: float,
    iv: float,
    option_type: str = "call",
    rate: float = 0.07,
) -> float:
    """Return option premium (per unit)."""
    T = max(days_to_expiry, 0.001) / 365.0
    if iv <= 0:
        iv = 0.15
    d1 = _d1(spot, strike, T, rate, iv)
    d2 = d1 - iv * math.sqrt(T)
    if option_type.lower() in ("call", "ce", "c"):
        return spot * norm.cdf(d1) - strike * math.exp(-rate * T) * norm.cdf(d2)
    return strike * math.exp(-rate * T) * norm.cdf(-d2) - spot * norm.cdf(-d1)


def atm_strike(spot: float, step: int = 50) -> float:
    """Round to nearest index strike (50 for NIFTY, 100 for BANKNIFTY)."""
    return round(spot / step) * step


def otm_strike(spot: float, direction: str, step: int = 50, otm_steps: int = 1) -> float:
    atm = atm_strike(spot, step)
    if direction == "bullish":
        return atm + step * otm_steps
    return atm - step * otm_steps


def strike_step(instrument: str) -> int:
    return 100 if instrument.upper() == "BANKNIFTY" else 50


def nearest_weekly_expiry(from_date: date | None = None, holding_days: int = 5) -> date:
    """Approximate nearest weekly expiry (Thursday for NSE indices)."""
    d = from_date or date.today()
    # Next Thursday at least holding_days out
    for offset in range(holding_days, holding_days + 14):
        candidate = d.toordinal() + offset
        dt = date.fromordinal(candidate)
        if dt.weekday() == 3:  # Thursday
            return dt
    return d


def premium_at_underlying_stop(
    spot: float,
    strike: float,
    underlying_stop: float,
    days_to_expiry: float,
    iv: float,
    direction: str,
) -> float:
    """Info-only premium reference when underlying hits stop."""
    opt = "call" if direction == "bullish" else "put"
    return black_scholes_price(underlying_stop, strike, days_to_expiry, iv, opt)
