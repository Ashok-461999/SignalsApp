from fastapi import APIRouter, Query

from app.services.market_news import get_enriched_headlines, get_market_headlines
from app.services.market_predictions import aggregate_predictions, enrich_headlines

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
def market_predictions(limit: int = 15) -> dict:
    headlines = get_enriched_headlines(max_items=min(limit, 20))
    predictions = aggregate_predictions(headlines)
    return {
        "count": len(predictions),
        "predictions": predictions,
        "headlines": headlines,
        "disclaimer": "News-based outlook only — trade TAKE signals from the scanner.",
    }
