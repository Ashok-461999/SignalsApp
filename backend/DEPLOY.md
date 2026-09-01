# SignalApp — AWS EC2 Deployment Guide

Deploy the SignalApp backend on **AWS EC2** (Ubuntu 22.04 LTS).

**Stack:** FastAPI + SQLite (WAL mode) + in-memory live cache + SmartAPI WebSocket worker. No PostgreSQL, no Redis.

---

## Prerequisites

- AWS account
- EC2 instance: **t3.small** or larger (2 vCPU, 2+ GB RAM recommended)
- Ubuntu 22.04 LTS AMI
- Security group with inbound: **22** (SSH), **80** (HTTP), **443** (HTTPS), **8000** (API direct, optional)
- Elastic IP (recommended — keeps a stable public IP)
- Domain name pointed to your Elastic IP (optional, for HTTPS via Caddy)
- Angel One SmartAPI credentials

---

## 1. Launch EC2 instance

1. AWS Console → **EC2** → **Launch instance**
2. AMI: **Ubuntu Server 22.04 LTS**
3. Instance type: **t3.small** (or t3.medium for heavier load)
4. Key pair: create/download `.pem` for SSH
5. Security group: allow ports 22, 80, 443, 8000 from your IP or `0.0.0.0/0` (restrict SSH to your IP)
6. Storage: 20–30 GB gp3
7. Allocate and associate an **Elastic IP**

SSH in:

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<ELASTIC_IP>
```

---

## 2. Install Docker

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

---

## 3. Deploy the application

```bash
sudo mkdir -p /opt/signalapp/data /opt/signalapp/backups /opt/signalapp/logs
sudo chown -R $USER:$USER /opt/signalapp

cd /opt/signalapp
git clone https://github.com/Ashok-461999/SignalsApp.git repo
cd repo/backend

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

# With HTTPS via Caddy (ports 80 + 443) — set your domain in Caddyfile first
docker compose --profile https up -d
```

Verify:

```bash
curl http://localhost:8000/health | python3 -m json.tool
```

---

## 4. HTTPS with Caddy (optional)

1. Point your domain A record to the Elastic IP
2. Edit `Caddyfile` — replace `api.yourdomain.com` with your domain
3. `docker compose --profile https up -d`

Caddy obtains Let's Encrypt TLS automatically.

---

## 5. Flutter APK — point to AWS

Build the release APK with your AWS API URL:

```bash
cd client
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.yourdomain.com
```

For HTTP testing only (not recommended for production):

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=http://<ELASTIC_IP>:8000
```

Also add your domain or IP to `client/android/app/src/main/res/xml/network_security_config.xml` if using HTTP.

---

## 6. SQLite backup (cron)

```bash
chmod +x scripts/backup_sqlite.sh

(crontab -l 2>/dev/null; echo "0 2 * * * SQLITE_PATH=/opt/signalapp/data/signalapp.db BACKUP_DIR=/opt/signalapp/backups /opt/signalapp/repo/backend/scripts/backup_sqlite.sh >> /var/log/signalapp-backup.log 2>&1") | crontab -
```

---

## 7. Useful commands

```bash
# Restart after code or .env change
cd /opt/signalapp/repo && git pull && cd backend && docker compose up -d --build api

# Logs
docker logs -f signalapp-api --tail 100

# Health
curl -s http://localhost:8000/health | python3 -m json.tool
```

---

## 8. Troubleshooting

| Symptom | Fix |
|---------|-----|
| Connection refused | Check EC2 security group inbound rules |
| SmartAPI login failed | Verify TOTP secret, password, API key in `.env` |
| WebSocket not connected | Market hours only; check `docker logs signalapp-api` |
| Caddy TLS failed | Domain must point to Elastic IP; port 80 open for ACME |
| `database is locked` | Only run 1 uvicorn worker; confirm WAL in `/health` |

---

## File reference

| File | Purpose |
|------|---------|
| `Dockerfile` | Python 3.12 API image |
| `docker-compose.yml` | API + optional Caddy |
| `Caddyfile` | HTTPS reverse proxy |
| `.env.example` | Configuration template |
| `scripts/backup_sqlite.sh` | Nightly DB backup |
