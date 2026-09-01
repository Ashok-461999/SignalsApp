"""Full Black-Scholes Greeks and spot-move projections."""

from __future__ import annotations

import math
from dataclasses import dataclass

from scipy.stats import norm

from app.backtest.options import black_scholes_price

RISK_FREE_RATE = 0.06


@dataclass
class GreeksSnapshot:
    delta: float
    gamma: float
    theta_daily: float
    vega: float
    fair_value: float


@dataclass
class PriceProjection:
    spot_move_pct: float
    spot_price: float
    option_price: float
    pnl_per_unit: float
    pnl_per_lot: float


def _d1_d2(spot: float, strike: float, t_years: float, iv: float, rate: float) -> tuple[float, float]:
    if t_years <= 0 or iv <= 0 or spot <= 0 or strike <= 0:
        return 0.0, 0.0
    d1 = (math.log(spot / strike) + (rate + 0.5 * iv**2) * t_years) / (iv * math.sqrt(t_years))
    d2 = d1 - iv * math.sqrt(t_years)
    return d1, d2


def compute_greeks(
    spot: float,
    strike: float,
    days_to_expiry: float,
    iv: float,
    option_type: str = "call",
    rate: float = RISK_FREE_RATE,
) -> GreeksSnapshot:
    t = max(days_to_expiry, 0.001) / 365.0
    iv = max(iv, 0.05)
    d1, d2 = _d1_d2(spot, strike, t, iv, rate)
    pdf = norm.pdf(d1)
    fair = black_scholes_price(spot, strike, days_to_expiry, iv, option_type, rate)

    if option_type.lower() in ("call", "ce", "c"):
        delta = float(norm.cdf(d1))
        theta = -(spot * pdf * iv) / (2 * math.sqrt(t)) - rate * strike * math.exp(-rate * t) * norm.cdf(d2)
    else:
        delta = float(norm.cdf(d1) - 1)
        theta = -(spot * pdf * iv) / (2 * math.sqrt(t)) + rate * strike * math.exp(-rate * t) * norm.cdf(-d2)

    gamma = pdf / (spot * iv * math.sqrt(t)) if spot > 0 and iv > 0 else 0.0
    vega = spot * pdf * math.sqrt(t) / 100.0
    return GreeksSnapshot(
        delta=round(delta, 4),
        gamma=round(gamma, 6),
        theta_daily=round(theta / 365.0, 2),
        vega=round(vega, 2),
        fair_value=round(fair, 2),
    )


def project_option_price(
    spot: float,
    strike: float,
    days_to_expiry: float,
    iv: float,
    entry_premium: float,
    spot_move_pct: float,
    option_type: str,
    lot_size: int,
    rate: float = RISK_FREE_RATE,
) -> PriceProjection:
    new_spot = spot * (1 + spot_move_pct / 100.0)
    g = compute_greeks(spot, strike, days_to_expiry, iv, option_type, rate)
    delta_s = new_spot - spot
    projected = (
        entry_premium
        + g.delta * delta_s
        + 0.5 * g.gamma * (delta_s**2)
        + g.theta_daily * 0.25
    )
    projected = max(projected, 0.05)
    pnl_unit = projected - entry_premium
    return PriceProjection(
        spot_move_pct=spot_move_pct,
        spot_price=round(new_spot, 2),
        option_price=round(projected, 2),
        pnl_per_unit=round(pnl_unit, 2),
        pnl_per_lot=round(pnl_unit * lot_size, 2),
    )


def projection_matrix(
    spot: float,
    strike: float,
    days_to_expiry: float,
    iv: float,
    entry_premium: float,
    option_type: str,
    lot_size: int,
) -> list[dict]:
    moves = (-2.0, -1.0, 1.0, 2.0)
    out = []
    for mv in moves:
        p = project_option_price(
            spot, strike, days_to_expiry, iv, entry_premium, mv, option_type, lot_size
        )
        out.append(
            {
                "spot_move_pct": mv,
                "spot_price": p.spot_price,
                "option_price": p.option_price,
                "pnl_per_lot_inr": p.pnl_per_lot,
            }
        )
    return out


def breakeven_buyer(strike: float, premium: float, option_type: str) -> float:
    if option_type.lower() in ("call", "ce", "c"):
        return round(strike + premium, 2)
    return round(strike - premium, 2)
