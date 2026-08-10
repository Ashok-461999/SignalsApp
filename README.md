# SignalApp

Options signal & backtest app — Flutter client + FastAPI backend.

## Local development

```bash
cd backend
python -m venv .venv && .venv\Scripts\activate   # Windows
pip install -r requirements.txt
cp .env.example .env   # fill SmartAPI credentials
uvicorn app.main:app --reload --port 8000
```

SQLite DB is created at `./data/signalapp.db` with WAL mode enabled.

## Production deployment (Oracle Cloud ARM)

See **[backend/DEPLOY.md](backend/DEPLOY.md)** for the full Oracle Cloud Ubuntu 22.04 ARM guide:
- Docker + docker-compose on aarch64
- OCI Security List + iptables port rules
- DuckDNS + Caddy HTTPS
- SQLite backup cron
- SmartAPI WebSocket persistence through market hours

## API quick reference

| Endpoint | Description |
|----------|-------------|
| `GET /health` | DB, SmartAPI, live feed, trading safety status |
| `GET /candles?instrument=NIFTY&segment=spot&interval=5m` | Historical OHLCV |
| `POST /candles/sync-all` | Bulk historical sync |
| `WS /live-candles` | Forming 1/5/15-min candles |

## Flutter client

```bash
cd client && flutter pub get && flutter run -d windows
```
