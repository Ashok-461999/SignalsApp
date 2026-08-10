import asyncio
import logging
from typing import Any

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.data.memory_cache import memory_cache
from app.data.tick_aggregator import tick_aggregator

logger = logging.getLogger(__name__)
router = APIRouter(tags=["live"])


class LiveCandleBroadcaster:
    """Broadcasts in-memory live candle updates to connected WebSocket clients."""

    def __init__(self) -> None:
        self._connections: set[WebSocket] = set()
        self._loop: asyncio.AbstractEventLoop | None = None

    def start(self, loop: asyncio.AbstractEventLoop) -> None:
        self._loop = loop
        memory_cache.subscribe(self._on_candle_from_thread)

    def _on_candle_from_thread(self, candle: dict[str, Any]) -> None:
        if self._loop and self._connections:
            asyncio.run_coroutine_threadsafe(self.broadcast(candle), self._loop)

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        self._connections.add(websocket)

        forming = tick_aggregator.get_all_forming()
        cached = memory_cache.get_all_forming()
        snapshot = {f"{c['instrument']}:{c['segment']}:{c['interval']}": c for c in forming}
        for candle in cached:
            snapshot[f"{candle['instrument']}:{candle['segment']}:{candle['interval']}"] = candle

        await websocket.send_json({"type": "snapshot", "candles": list(snapshot.values())})

    def disconnect(self, websocket: WebSocket) -> None:
        self._connections.discard(websocket)

    async def broadcast(self, message: dict[str, Any]) -> None:
        dead: set[WebSocket] = set()
        for ws in self._connections:
            try:
                await ws.send_json({"type": "candle", "data": message})
            except Exception:
                dead.add(ws)
        for ws in dead:
            self._connections.discard(ws)

    async def stop(self) -> None:
        self._connections.clear()


broadcaster = LiveCandleBroadcaster()


@router.websocket("/live-candles")
async def live_candles_ws(websocket: WebSocket) -> None:
    """Stream forming 1/5/15-min candles for all subscribed indices."""
    await broadcaster.connect(websocket)
    try:
        while True:
            raw = await websocket.receive_text()
            if raw == "ping":
                await websocket.send_json({"type": "pong"})
    except WebSocketDisconnect:
        pass
    finally:
        broadcaster.disconnect(websocket)
