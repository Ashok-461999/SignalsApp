#!/usr/bin/env bash
# One-time AWS EC2 setup for SignalApp / Options Alpha Engine
set -euo pipefail

sudo apt-get update
sudo apt-get install -y git docker.io docker-compose-v2 curl

sudo usermod -aG docker "$USER"

sudo mkdir -p /opt/signalapp/data /opt/signalapp/backups /opt/signalapp/logs
sudo chown -R "$USER:$USER" /opt/signalapp

if [ ! -d /opt/signalapp/repo ]; then
  git clone https://github.com/Ashok-461999/SignalsApp.git /opt/signalapp/repo
else
  cd /opt/signalapp/repo && git pull --ff-only
fi

cd /opt/signalapp/repo/backend
if [ ! -f .env ]; then
  cp .env.example .env
  echo ""
  echo "=== ACTION REQUIRED ==="
  echo "Edit /opt/signalapp/repo/backend/.env with SmartAPI credentials:"
  echo "  nano /opt/signalapp/repo/backend/.env"
  echo "Then run: bash scripts/deploy_aws.sh"
  exit 0
fi

bash scripts/deploy_aws.sh