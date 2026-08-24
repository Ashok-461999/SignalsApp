from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.db.session import get_sync_session
from app.services.gift_nifty import build_gift_nifty_insight
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


@router.get("/gift-nifty")
def gift_nifty(session: Session = Depends(get_sync_session)) -> dict:
    """GIFT Nifty overnight cue and Nifty 50 open probability."""
    return build_gift_nifty_insight(session)


@router.get("/predictions")
def market_predictions(
    limit: int = 30,
    session: Session = Depends(get_sync_session),
) -> dict:
    headlines = get_enriched_headlines(max_items=min(limit, 40))
    gift = build_gift_nifty_insight(session)
    news_predictions = aggregate_predictions(headlines)
    move_targets = build_move_targets(session, headlines, gift_insight=gift)
    predictions = merge_predictions_with_moves(news_predictions, move_targets)
    return {
        "count": len(predictions),
        "predictions": predictions,
        "move_targets": move_targets,
        "headlines": headlines,
        "gift_nifty": gift,
        "disclaimer": (
            "GIFT Nifty negative close → ~74% Nifty open-down (empirical). "
            "Confirm with TAKE signals."
        ),
    }
