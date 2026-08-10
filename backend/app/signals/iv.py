"""IV percentile computation from historical realized volatility proxy."""

import logging

import numpy as np
import pandas as pd
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.data.models import Candle
from app.signals.indicators import atr

logger = logging.getLogger(__name__)

DEFAULT_IV = 0.14


def realized_vol_proxy(df: pd.DataFrame, window: int = 20) -> pd.Series:
    returns = df["close"].pct_change()
    return returns.rolling(window).std() * np.sqrt(252 * 78)  # ~78 5m bars/day


def compute_iv_percentile(
    session: Session,
    instrument: str,
    segment: str = "spot",
    interval: str = "5m",
    lookback: int = 252,
) -> dict:
    stmt = (
        select(Candle)
        .where(
            Candle.instrument == instrument.upper(),
            Candle.segment == segment,
            Candle.interval == interval,
        )
        .order_by(Candle.timestamp.desc())
        .limit(lookback * 2)
    )
    candles = list(session.execute(stmt).scalars().all())
    if len(candles) < 30:
        return {
            "instrument": instrument,
            "iv_percentile": 50.0,
            "current_iv_proxy": DEFAULT_IV,
            "note": "insufficient data — using default",
        }

    rows = [
        {"close": c.close, "high": c.high, "low": c.low, "open": c.open, "volume": c.volume}
        for c in reversed(candles)
    ]
    df = pd.DataFrame(rows)
    vol = realized_vol_proxy(df)
    current = float(vol.iloc[-1]) if not pd.isna(vol.iloc[-1]) else DEFAULT_IV
    hist = vol.dropna().values
    if len(hist) < 10:
        percentile = 50.0
    else:
        percentile = float((hist < current).sum() / len(hist) * 100)

    return {
        "instrument": instrument.upper(),
        "segment": segment,
        "iv_percentile": round(percentile, 1),
        "current_iv_proxy": round(current, 4),
        "lookback_bars": len(hist),
    }
