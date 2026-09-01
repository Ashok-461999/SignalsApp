#!/usr/bin/env bash
# Deploy / update SignalApp on AWS EC2 (run ON the server after git pull)
set -euo pipefail

REPO_DIR="${REPO_DIR:-/opt/signalapp/repo}"
cd "$REPO_DIR/backend"

if [ ! -f .env ]; then
  echo "ERROR: $REPO_DIR/backend/.env missing — copy from .env.example and add SmartAPI keys"
  exit 1
fi

sudo mkdir -p /opt/signalapp/data /opt/signalapp/logs
sudo chown -R "$USER:$USER" /opt/signalapp

docker compose pull 2>/dev/null || true
docker compose build --no-cache api
docker compose up -d api

echo "Waiting for health..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:8000/health/live >/dev/null; then
    echo "API healthy at http://$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'):8000"
    curl -s http://localhost:8000/alpha/status | head -c 500 || true
    echo ""
    exit 0
  fi
  sleep 2
done

echo "Health check failed — run: docker compose logs -f api"
exit 1
