from fastapi import APIRouter

from app.services.market_news import get_market_headlines

router = APIRouter(prefix="/market", tags=["market"])


@router.get("/news")
def market_news(limit: int = 12) -> dict:
    items = get_market_headlines(max_items=min(limit, 20))
    return {"count": len(items), "headlines": items}
