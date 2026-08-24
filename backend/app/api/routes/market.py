from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.db.session import get_sync_session
from app.services.market_news import get_enriched_headlines, get_market_headlines
from app.services.market_predictions import aggregate_predictions, enrich_headlines
from app.services.move_predictions import build_move_targets, merge_predictions_with_moves

router = APIRouter(prefix="/market", tags=["market"])


@router.get("/news")
def market_news(limit: int = 12, enriched: bool = Query(False)) -> dict:
    cap = min(limit, 20)
    if enriched:
        items = get_enriched_headlines(max_items=cap)
    else:
        items = get_market_headlines(max_items=cap)
        items = enrich_headlines(items)
    return {"count": len(items), "headlines": items}


@router.get("/predictions")
def market_predictions(
    limit: int = 15,
    session: Session = Depends(get_sync_session),
) -> dict:
    headlines = get_enriched_headlines(max_items=min(limit, 20))
    news_predictions = aggregate_predictions(headlines)
    move_targets = build_move_targets(session, headlines)
    predictions = merge_predictions_with_moves(news_predictions, move_targets)
    return {
        "count": len(predictions),
        "predictions": predictions,
        "move_targets": move_targets,
        "headlines": headlines,
        "disclaimer": "Move targets are model-based (~100pt NIFTY/FINNIFTY). Confirm with TAKE signals.",
    }
