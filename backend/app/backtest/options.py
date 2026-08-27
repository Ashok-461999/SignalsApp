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
    from app.core.index_config import STRIKE_STEPS

    return STRIKE_STEPS.get(instrument.upper(), 50)


def expiry_weekday_for(instrument: str) -> int:
    """NSE index weeklies/monthlies: Tuesday. BSE SENSEX: Thursday."""
    return 3 if instrument.upper() == "SENSEX" else 1  # Mon=0 … Thu=3, Tue=1


def nearest_expiry_min_days(
    from_date: date | None = None,
    min_days: int = 20,
    expiry_weekday: int = 1,
) -> date:
    """Nearest listed expiry with at least min_days remaining (20+ DTE style)."""
    d = from_date or date.today()
    start_ordinal = d.toordinal() + min_days
    for ordinal in range(start_ordinal, start_ordinal + 90):
        dt = date.fromordinal(ordinal)
        if dt.weekday() == expiry_weekday:
            return dt
    return date.fromordinal(start_ordinal)


def days_until_expiry(expiry: date, from_date: date | None = None) -> int:
    d = from_date or date.today()
    return max((expiry - d).days, 1)


def nearest_weekly_expiry(from_date: date | None = None, holding_days: int = 5) -> date:
    """Legacy helper — prefer nearest_expiry_min_days for live signals."""
    return nearest_expiry_min_days(from_date=from_date, min_days=holding_days, expiry_weekday=3)


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


def scalp_expiry(instrument: str, from_date: date | None = None) -> date:
    """Nearest weekly expiry for scalp option pricing (higher gamma, less index move needed)."""
    return nearest_expiry_min_days(
        from_date=from_date,
        min_days=0,
        expiry_weekday=expiry_weekday_for(instrument),
    )


def build_option_trade_plan(
    instrument: str,
    entry: float,
    stop: float,
    target: float,
    direction: str,
    iv: float,
    lots: int = 1,
    use_weekly: bool = True,
) -> dict[str, float | str | int]:
    """
  Broker-style option plan: small index move → larger premium move (weekly ATM).
  Example: Buy ~₹130 · Target ₹160 · SL below ₹100
  """
    from app.core.index_config import LOT_SIZES

    step = strike_step(instrument)
    lot_size = LOT_SIZES.get(instrument.upper(), 25)
    strike = atm_strike(entry, step)
    expiry = scalp_expiry(instrument) if use_weekly else nearest_expiry_min_days(
        min_days=20, expiry_weekday=expiry_weekday_for(instrument)
    )
    days = float(days_until_expiry(expiry))
    opt = "call" if direction == "bullish" else "put"
    iv_use = max(0.10, min(0.40, iv if iv > 0.05 else 0.16))

    entry_prem = black_scholes_price(entry, strike, days, iv_use, opt)
    prem_target = black_scholes_price(target, strike, days, iv_use, opt)
    prem_stop = black_scholes_price(stop, strike, days, iv_use, opt)

    # Floor realistic scalp premiums for index weeklies
    entry_prem = max(entry_prem, 15.0)
    prem_stop = max(min(prem_stop, entry_prem * 0.78), entry_prem * 0.55)
    if prem_target <= entry_prem:
        prem_target = entry_prem * 1.22

    index_pts = abs(target - entry)
    index_pct = (index_pts / entry * 100) if entry > 0 else 0.0
    prem_gain = prem_target - entry_prem
    prem_gain_pct = (prem_gain / entry_prem * 100) if entry_prem > 0 else 0.0
    prem_loss = entry_prem - prem_stop
    expected_profit_inr = round(prem_gain * lot_size * max(lots, 1), 2)
    max_loss_inr = round(prem_loss * lot_size * max(lots, 1), 2)

    return {
        "suggested_strike": strike,
        "suggested_expiry": expiry.isoformat(),
        "days_to_expiry": int(days),
        "option_type": "CE" if direction == "bullish" else "PE",
        "premium_entry": round(entry_prem, 2),
        "premium_target": round(prem_target, 2),
        "premium_stop": round(prem_stop, 2),
        "premium_gain_pct": round(prem_gain_pct, 1),
        "index_move_pts": round(index_pts, 1),
        "index_move_pct": round(index_pct, 2),
        "expected_profit_inr": expected_profit_inr,
        "max_loss_premium_inr": max_loss_inr,
        "option_trade_plan": (
            f"Buy ~₹{entry_prem:.0f} · Target ₹{prem_target:.0f} · STRICT SL ₹{prem_stop:.0f}"
        ),
        "option_trade_plan_en": (
            f"Index only {index_pct:.2f}% ({index_pts:.0f} pts) → premium +{prem_gain_pct:.0f}% "
            f"(~₹{expected_profit_inr:,.0f} profit on {max(lots, 1)} lot)"
        ),
    }
