"""Position sizing for small capital — never risk the full account on one trade."""

from __future__ import annotations

from dataclasses import dataclass

from app.core.index_config import LOT_SIZES

# Approximate NRML margin per lot (index futures) — for small-capital affordability checks
MARGIN_PER_LOT_INR: dict[str, float] = {
    "NIFTY": 115000.0,
    "BANKNIFTY": 170000.0,
    "FINNIFTY": 42000.0,
    "SENSEX": 140000.0,
}


@dataclass
class PositionPlan:
    lots: int
    max_loss_inr: float
    premium_required_inr: float
    capital_inr: float
    can_afford: bool
    reason: str
    margin_required_inr: float = 0.0
    margin_per_lot_inr: float = 0.0


def plan_option_position(
    instrument: str,
    entry_premium: float,
    premium_at_stop: float,
    capital_inr: float,
    risk_percent: float,
    size_modifier: float = 1.0,
) -> PositionPlan:
    """
    Size lots so max loss stays within risk % of capital.
    Also caps premium deployment (max 35% of capital in one trade).
    """
    capital = max(capital_inr, 1000.0)
    risk_pct = max(0.1, min(risk_percent, 3.0))  # hard cap 3% for small accounts
    lot = LOT_SIZES.get(instrument.upper(), 25)

    max_risk_inr = capital * (risk_pct / 100.0)
    max_deploy_inr = capital * 0.35

    if entry_premium <= 0:
        return PositionPlan(
            lots=0,
            max_loss_inr=0,
            premium_required_inr=0,
            capital_inr=capital,
            can_afford=False,
            reason="Premium estimate unavailable",
        )

    prem_risk = max(entry_premium - premium_at_stop, entry_premium * 0.12, 1.0)
    loss_per_lot = prem_risk * lot
    premium_per_lot = entry_premium * lot

    lots_by_risk = int(max_risk_inr / loss_per_lot) if loss_per_lot > 0 else 0
    lots_by_deploy = int(max_deploy_inr / premium_per_lot) if premium_per_lot > 0 else 0
    lots = min(lots_by_risk, lots_by_deploy)
    lots = max(0, int(lots * size_modifier))

    if lots < 1:
        if premium_per_lot > max_deploy_inr:
            reason = (
                f"Premium ~₹{premium_per_lot:,.0f}/lot too high for ₹{capital:,.0f} capital "
                f"(max deploy ₹{max_deploy_inr:,.0f})"
            )
        else:
            reason = (
                f"Risk too high — max loss/lot ~₹{loss_per_lot:,.0f} exceeds "
                f"₹{max_risk_inr:,.0f} risk budget ({risk_pct}% of capital)"
            )
        return PositionPlan(
            lots=0,
            max_loss_inr=max_risk_inr,
            premium_required_inr=premium_per_lot,
            capital_inr=capital,
            can_afford=False,
            reason=reason,
        )

    actual_loss = loss_per_lot * lots
    actual_premium = premium_per_lot * lots
    return PositionPlan(
        lots=lots,
        max_loss_inr=round(actual_loss, 2),
        premium_required_inr=round(actual_premium, 2),
        capital_inr=capital,
        can_afford=True,
        reason=f"Risk ₹{actual_loss:,.0f} · premium ~₹{actual_premium:,.0f} · {lots} lot(s)",
    )


def plan_futures_position(
    instrument: str,
    entry: float,
    stop: float,
    capital_inr: float,
    risk_percent: float,
    size_modifier: float = 1.0,
) -> PositionPlan:
    """Size index futures lots by risk budget and estimated margin."""
    capital = max(capital_inr, 1000.0)
    risk_pct = max(0.1, min(risk_percent, 3.0))
    lot = LOT_SIZES.get(instrument.upper(), 25)
    margin_per_lot = MARGIN_PER_LOT_INR.get(instrument.upper(), 100000.0)

    max_risk_inr = capital * (risk_pct / 100.0)
    max_deploy_inr = capital * 0.35

    point_risk = abs(entry - stop)
    if point_risk <= 0:
        return PositionPlan(
            lots=0,
            max_loss_inr=0,
            premium_required_inr=0,
            capital_inr=capital,
            can_afford=False,
            margin_required_inr=0,
            margin_per_lot_inr=margin_per_lot,
            reason="Invalid stop — cannot size futures",
        )

    loss_per_lot = point_risk * lot
    lots_by_risk = int(max_risk_inr / loss_per_lot) if loss_per_lot > 0 else 0
    lots_by_margin = int(max_deploy_inr / margin_per_lot) if margin_per_lot > 0 else 0
    lots = min(lots_by_risk, lots_by_margin)
    lots = max(0, int(lots * size_modifier))

    if lots < 1:
        if margin_per_lot > max_deploy_inr:
            reason = (
                f"Futures margin ~₹{margin_per_lot:,.0f}/lot too high for ₹{capital:,.0f} capital "
                f"(max deploy ₹{max_deploy_inr:,.0f}) — options preferred"
            )
        else:
            reason = (
                f"Futures risk ~₹{loss_per_lot:,.0f}/lot exceeds "
                f"₹{max_risk_inr:,.0f} risk budget ({risk_pct}% of capital)"
            )
        return PositionPlan(
            lots=0,
            max_loss_inr=max_risk_inr,
            premium_required_inr=0,
            capital_inr=capital,
            can_afford=False,
            margin_required_inr=margin_per_lot,
            margin_per_lot_inr=margin_per_lot,
            reason=reason,
        )

    actual_loss = loss_per_lot * lots
    actual_margin = margin_per_lot * lots
    return PositionPlan(
        lots=lots,
        max_loss_inr=round(actual_loss, 2),
        premium_required_inr=0,
        capital_inr=capital,
        can_afford=True,
        margin_required_inr=round(actual_margin, 2),
        margin_per_lot_inr=margin_per_lot,
        reason=f"Risk ₹{actual_loss:,.0f} · margin ~₹{actual_margin:,.0f} · {lots} lot(s)",
    )
