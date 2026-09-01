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

## Production deployment (AWS EC2)

See **[backend/DEPLOY.md](backend/DEPLOY.md)** for the AWS EC2 Ubuntu guide:
- Docker + docker-compose on EC2
- Security group + Elastic IP
- Caddy HTTPS (optional)
- SQLite backup cron
- SmartAPI WebSocket persistence through market hours

Build production APK with your API URL:

```bash
cd client
flutter build apk --release --dart-define=API_BASE_URL=https://api.yourdomain.com
```

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
