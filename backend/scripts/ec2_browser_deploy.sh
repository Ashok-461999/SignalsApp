#!/bin/bash
# Paste entire script in EC2 Instance Connect browser terminal
set -e
sudo apt-get update -qq && sudo apt-get install -y git docker.io docker-compose-v2 curl
sudo mkdir -p /opt/signalapp/data /opt/signalapp/logs && sudo chown -R ubuntu:ubuntu /opt/signalapp
[ -d /opt/signalapp/repo ] || git clone https://github.com/Ashok-461999/SignalsApp.git /opt/signalapp/repo
cd /opt/signalapp/repo && git pull --ff-only
cd backend
[ -f .env ] || cp .env.example .env
grep -q SMARTAPI_API_KEY=your .env && echo "EDIT .env FIRST: nano .env" && exit 1
sudo sed -i 's/8000:8000/80:8000/' docker-compose.yml
sudo docker compose build api && sudo docker compose up -d api
sleep 10
curl -sf http://localhost/health/live && echo " DEPLOYED OK"
curl -sf http://localhost/alpha/status | head -c 300
