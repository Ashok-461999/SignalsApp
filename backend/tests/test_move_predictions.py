"""Tests for index move-target models."""

from app.core.index_config import INDEX_SYMBOLS, MOVE_POINT_TARGETS
from app.services.move_predictions import merge_predictions_with_moves


def test_index_symbols_include_finnifty():
    assert "FINNIFTY" in INDEX_SYMBOLS
    assert MOVE_POINT_TARGETS["NIFTY"] == 100
    assert MOVE_POINT_TARGETS["FINNIFTY"] == 100


def test_merge_predictions_prefers_move_targets_for_indices():
    news = [{"symbol": "RELIANCE", "name": "Reliance", "type": "stock", "outlook": "bullish"}]
    moves = [
        {
            "symbol": "NIFTY",
            "name": "Nifty 50",
            "type": "index",
            "outlook": "bullish",
            "move_points": 100,
            "target_price": 25100.0,
        }
    ]
    merged = merge_predictions_with_moves(news, moves)
    symbols = [p["symbol"] for p in merged]
    assert symbols[0] == "NIFTY"
    assert "RELIANCE" in symbols
    nifty = next(p for p in merged if p["symbol"] == "NIFTY")
    assert nifty["move_points"] == 100
