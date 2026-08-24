from dataclasses import dataclass, field
from datetime import datetime
from typing import Any


@dataclass
class SetupResult:
    """Output of a single setup evaluation on the latest bar."""

    setup_name: str
    fired: bool
    direction: str | None = None  # bullish | bearish
    entry: float | None = None
    stop_loss: float | None = None
    targets: list[float] = field(default_factory=list)
    reason: str = ""
    metadata: dict[str, Any] = field(default_factory=dict)

    @property
    def risk_reward(self) -> float | None:
        if not self.entry or not self.stop_loss or not self.targets:
            return None
        risk = abs(self.entry - self.stop_loss)
        if risk <= 0:
            return None
        return abs(self.targets[0] - self.entry) / risk


@dataclass
class SignalPayload:
    """Full signal object streamed to clients."""

    setup_name: str
    instrument: str
    segment: str
    direction: str
    underlying_entry: float
    underlying_stop_loss: float
    underlying_target: list[float]
    suggested_strike: float
    suggested_expiry: str
    iv_percentile: float
    risk_reward: float
    position_size: int
    premium_stop_reference: float
    backtest_stats: dict[str, Any]
    timestamp: str
    tradable: bool = True
    trade_decision: str = "NO_TRADE"  # TAKE | NO_TRADE | SIT_OUT
    decision_reason: str = ""
    regime: str = ""
    strategy_fit: str = ""
    option_type: str = ""  # CE | PE
    entry_premium_estimate: float = 0.0
    days_to_expiry: int = 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "setup_name": self.setup_name,
            "instrument": self.instrument,
            "segment": self.segment,
            "direction": self.direction,
            "underlying_entry": self.underlying_entry,
            "underlying_stop_loss": self.underlying_stop_loss,
            "underlying_target": self.underlying_target,
            "suggested_strike": self.suggested_strike,
            "suggested_expiry": self.suggested_expiry,
            "iv_percentile": self.iv_percentile,
            "risk_reward": self.risk_reward,
            "position_size": self.position_size,
            "premium_stop_reference": self.premium_stop_reference,
            "backtest_stats": self.backtest_stats,
            "timestamp": self.timestamp,
            "tradable": self.tradable,
            "trade_decision": self.trade_decision,
            "decision_reason": self.decision_reason,
            "regime": self.regime,
            "strategy_fit": self.strategy_fit,
            "option_type": self.option_type,
            "entry_premium_estimate": self.entry_premium_estimate,
            "days_to_expiry": self.days_to_expiry,
        }
