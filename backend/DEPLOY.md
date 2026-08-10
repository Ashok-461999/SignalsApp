# SignalApp — Oracle Cloud ARM Deployment Guide

Deploy the SignalApp backend on an **Oracle Cloud always-free ARM VM** (Ubuntu 22.04).

**Stack:** FastAPI + SQLite (WAL mode) + in-memory live cache + SmartAPI WebSocket worker. No PostgreSQL, no Redis.

---

## Prerequisites

- Oracle Cloud account with an **Ampere A1** VM (1–4 OCPU, 6–24 GB RAM recommended)
- Ubuntu 22.04 ARM64 image
- SSH key pair
- [DuckDNS](https://www.duckdns.org/) account (free subdomain for HTTPS)
- Angel One SmartAPI credentials

---

## 1. Create the Oracle VM

1. Oracle Cloud Console → **Compute** → **Instances** → **Create Instance**
2. Image: **Canonical Ubuntu 22.04** (aarch64)
3. Shape: **VM.Standard.A1.Flex** — 2 OCPU, 12 GB RAM is a good starting point
4. Networking: assign a **public IP**
5. Download your SSH private key

SSH in:

```bash
ssh -i ~/.ssh/your_key ubuntu@<VM_PUBLIC_IP>
```

---

## 2. Open ports (both layers required)

Oracle blocks traffic at **two** levels. Missing either layer = connection refused.

### Layer A — OCI Security List (cloud firewall)

1. Networking → Virtual Cloud Networks → your VCN → **Security Lists**
2. Edit **Ingress Rules**, add:

| Source CIDR | Protocol | Dest Port | Description |
|-------------|----------|-----------|-------------|
| `0.0.0.0/0` | TCP | 22 | SSH |
| `0.0.0.0/0` | TCP | 80 | HTTP (Caddy) |
| `0.0.0.0/0` | TCP | 443 | HTTPS (Caddy) |
| `0.0.0.0/0` | TCP | 8000 | API direct (optional) |

### Layer B — VM iptables (Oracle Ubuntu default)

Oracle's Ubuntu image ships with `iptables` rules that block inbound traffic even after the security list is open. Run:

```bash
sudo apt-get update
sudo apt-get install -y iptables-persistent

# Allow inbound on required ports
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 22 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 8000 -j ACCEPT

# Persist across reboots
sudo netfilter-persistent save
```

Verify:

```bash
sudo iptables -L INPUT -n --line-numbers | head -20
```

---

## 3. Install Docker on Ubuntu 22.04 ARM

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

sudo usermod -aG docker $USER
newgrp docker
```

Verify ARM Docker:

```bash
docker run --rm python:3.11-slim-bookworm uname -m
# Expected: aarch64
```

---

## 4. DuckDNS setup

1. Go to [duckdns.org](https://www.duckdns.org/), sign in
2. Create a subdomain, e.g. `signalapp` → `signalapp.duckdns.org`
3. Set the IP to your VM's **public IP**
4. Note your DuckDNS token (for auto-update cron, optional):

```bash
# Optional: auto-update DuckDNS IP on reboot
echo '0 */6 * * * curl -s "https://www.duckdns.org/update?domains=signalapp&token=YOUR_TOKEN&ip=" >> /var/log/duckdns.log 2>&1' | crontab -
```

5. Edit `Caddyfile` — replace `signalapp.duckdns.org` with your subdomain

---

## 5. Deploy the application

```bash
# Create persistent data directory
sudo mkdir -p /opt/signalapp/data /opt/signalapp/backups /opt/signalapp/logs
sudo chown -R $USER:$USER /opt/signalapp

# Clone repo
cd /opt/signalapp
git clone <your-repo-url> repo
cd repo/backend

# Configure environment
cp .env.example .env
nano .env   # fill SmartAPI credentials
```

**Critical `.env` settings for production:**

```env
SQLITE_PATH=/data/signalapp.db
APP_ENV=production
PAPER_TRADING=true
LIVE_EXECUTION_ENABLED=false
KILL_SWITCH=false
RISK_PERCENT=1.0
ENABLE_LIVE_FEED=true
ENABLE_SCHEDULER=true
```

Build and start:

```bash
# API only (port 8000)
docker compose up -d api

# With HTTPS via Caddy (ports 80 + 443)
docker compose --profile https up -d
```

Verify:

```bash
curl http://localhost:8000/health | python3 -m json.tool
```

Check live feed status in the response:

```json
{
  "live_feed": { "running": true, "connected": true },
  "database": { "engine": "sqlite", "wal_mode": true },
  "trading": { "paper_trading": true, "execution_allowed": false }
}
```

---

## 6. SQLite WAL mode

The WebSocket worker writes completed candles while the API reads concurrently. Default SQLite journal mode causes `database is locked` errors under this pattern.

The app sets on every connection:

```sql
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA busy_timeout=5000;
```

WAL allows one writer + multiple readers simultaneously. Do not disable this.

---

## 7. Nightly SQLite backup

```bash
sudo cp scripts/backup_sqlite.sh /opt/signalapp/backup_sqlite.sh
sudo chmod +x /opt/signalapp/backup_sqlite.sh

# Edit backup script env if needed
export SQLITE_PATH=/opt/signalapp/data/signalapp.db
export BACKUP_DIR=/opt/signalapp/backups
# export BACKUP_REMOTE=user@backup-host:/backups/signalapp/

# Cron: daily at 2 AM IST (adjust timezone as needed)
(crontab -l 2>/dev/null; echo "0 2 * * * SQLITE_PATH=/opt/signalapp/data/signalapp.db BACKUP_DIR=/opt/signalapp/backups /opt/signalapp/backup_sqlite.sh >> /var/log/signalapp-backup.log 2>&1") | crontab -
```

Manual backup:

```bash
SQLITE_PATH=/opt/signalapp/data/signalapp.db /opt/signalapp/backup_sqlite.sh
```

---

## 8. SmartAPI WebSocket persistence

The backend runs as a **single long-lived process** (`restart: unless-stopped`):

- SmartAPI WebSocket connects on startup (market hours)
- Session auto-refreshes every 6 hours via refresh token + TOTP fallback
- WebSocket reconnects automatically on disconnect
- Scheduler runs gap backfill every 12 hours

Monitor during market hours:

```bash
# Feed status
curl -s http://localhost:8000/health | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['live_feed'])"

# Container logs
docker logs -f signalapp-api --tail 100
```

Expected log lines:

```
SmartAPI session established for <client_code>
Live feed service started
SmartAPI WebSocket connected, subscribing to indices
Scheduled SmartAPI session refresh completed
```

If the feed disconnects, it auto-reconnects within ~10 seconds. Session refresh runs before token expiry (8h session, 6h refresh interval).

---

## 9. Trading safety gates

| Flag | Default | Effect |
|------|---------|--------|
| `PAPER_TRADING` | `true` | No real orders placed |
| `LIVE_EXECUTION_ENABLED` | `false` | Must be `true` for live orders |
| `KILL_SWITCH` | `false` | Set `true` to halt all execution immediately |
| `RISK_PERCENT` | `1.0` | Max risk per trade (backend sizing) |

Live execution requires **all three**: `PAPER_TRADING=false`, `LIVE_EXECUTION_ENABLED=true`, `KILL_SWITCH=false`.

Check at runtime: `GET /health` → `trading.execution_allowed`

---

## 10. ARM64 package compatibility

| Package | ARM64 wheel | Notes |
|---------|-------------|-------|
| fastapi, uvicorn, sqlalchemy | Yes | Pure Python / wheels |
| aiosqlite | Yes | SQLite async driver |
| numpy, pandas, scipy | Yes | Pre-built aarch64 wheels |
| pandas-ta | Yes | Pure Python |
| smartapi-python | Yes | Pure Python + websocket-client |
| vectorbt | Partial | Commented out in requirements.txt; may need `build-essential` if enabled |

Dockerfile installs `build-essential gcc g++` as fallback for any source builds.

---

## 11. Memory footprint

Target: **< 2 GB RSS** on a 6–12 GB VM.

- Single uvicorn worker (`--workers 1`) — required for in-memory cache + WebSocket
- SQLite page cache capped at ~8 MB
- Live candle ring buffer capped at 500 events
- Do not run multiple API replicas on this single-VM build

Monitor:

```bash
docker stats signalapp-api
```

---

## 12. Useful commands

```bash
# Restart after .env change
docker compose up -d --build api

# Sync all historical candles
docker exec signalapp-api python -m scripts.sync_candles sync-all --days 5

# Gap backfill
docker exec signalapp-api python -m scripts.sync_candles backfill --days 5

# View live WebSocket (from another machine)
wscat -c ws://signalapp.duckdns.org/live-candles
```

---

## 13. Troubleshooting

| Symptom | Fix |
|---------|-----|
| Connection refused on 80/443 | Check OCI Security List **and** iptables (Section 2) |
| `database is locked` | Confirm WAL mode in `/health` response; only run 1 worker |
| SmartAPI login failed | Verify TOTP secret, trading password, API key in `.env` |
| WebSocket not connected | Check market hours; review `docker logs signalapp-api` |
| Caddy TLS failed | Confirm DuckDNS points to VM IP; port 80 must be open for ACME |
| Container won't start | `docker logs signalapp-api`; check `/opt/signalapp/data` permissions |

---

## File reference

| File | Purpose |
|------|---------|
| `Dockerfile` | ARM64 Python 3.11 image |
| `docker-compose.yml` | API + optional Caddy, persistent `/opt/signalapp/data` bind mount |
| `Caddyfile` | DuckDNS HTTPS reverse proxy |
| `.env.example` | All configuration variables |
| `requirements.txt` | Python deps with ARM64 notes |
| `scripts/backup_sqlite.sh` | Nightly DB backup cron job |
