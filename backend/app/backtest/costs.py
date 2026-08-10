"""Transaction cost model for Indian index options."""

from dataclasses import dataclass


@dataclass
class CostConfig:
    brokerage_per_order: float = 20.0
    stt_rate: float = 0.00125  # on sell side premium
    exchange_charges_rate: float = 0.00053
    gst_rate: float = 0.18  # on brokerage + exchange
    slippage_pct: float = 0.001  # 0.1% of premium
    iv_crush_pct: float = 0.15  # proxy on event days (expiry, RBI, etc.)


def apply_slippage(premium: float, side: str, slippage_pct: float) -> float:
    if side == "buy":
        return premium * (1 + slippage_pct)
    return premium * (1 - slippage_pct)


def round_trip_costs(
    entry_premium: float,
    exit_premium: float,
    lot_size: int,
    cfg: CostConfig,
    iv_crush: bool = False,
) -> float:
    """Total costs in rupees for one round trip."""
    qty_premium_entry = entry_premium * lot_size
    qty_premium_exit = exit_premium * lot_size

    brokerage = cfg.brokerage_per_order * 2
    stt = qty_premium_exit * cfg.stt_rate
    exchange = (qty_premium_entry + qty_premium_exit) * cfg.exchange_charges_rate
    gst = (brokerage + exchange) * cfg.gst_rate
    slippage = (qty_premium_entry + qty_premium_exit) * cfg.slippage_pct

    crush = 0.0
    if iv_crush:
        crush = qty_premium_entry * cfg.iv_crush_pct

    return brokerage + stt + exchange + gst + slippage + crush
