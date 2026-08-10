import asyncio
import logging

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.signals.scanner import signal_scanner

logger = logging.getLogger(__name__)
router = APIRouter(tags=["signals"])


class SignalBroadcaster:
    def __init__(self) -> None:
        self._connections: set[WebSocket] = set()
        self._loop: asyncio.AbstractEventLoop | None = None

    def start(self, loop: asyncio.AbstractEventLoop) -> None:
        self._loop = loop
        signal_scanner.subscribe(self._on_signal)

    def _on_signal(self, signal: dict) -> None:
        if self._loop and self._connections:
            asyncio.run_coroutine_threadsafe(self.broadcast(signal), self._loop)

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        self._connections.add(websocket)
        active = signal_scanner.get_all_evaluations()
        await websocket.send_json({"type": "snapshot", "signals": active})

    def disconnect(self, websocket: WebSocket) -> None:
        self._connections.discard(websocket)

    async def broadcast(self, signal: dict) -> None:
        dead: set[WebSocket] = set()
        for ws in self._connections:
            try:
                await ws.send_json({"type": "signal", "data": signal})
            except Exception:
                dead.add(ws)
        for ws in dead:
            self._connections.discard(ws)


signal_broadcaster = SignalBroadcaster()


@router.websocket("/signals")
async def signals_ws(websocket: WebSocket) -> None:
    await signal_broadcaster.connect(websocket)
    try:
        while True:
            raw = await websocket.receive_text()
            if raw == "ping":
                await websocket.send_json({"type": "pong"})
    except WebSocketDisconnect:
        pass
    finally:
        signal_broadcaster.disconnect(websocket)
