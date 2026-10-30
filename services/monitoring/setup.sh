#!/usr/bin/env bash
# Prepares the git-ignored files the monitoring stack reads: .env, prometheus/targets/*.yaml and
# secrets/. Safe to run again; it never overwrites a file you already filled.
# Usage (from services/monitoring/): ./setup.sh
set -euo pipefail
cd "$(dirname "$0")"

[[ -f .env ]] || { cp .env.example .env; echo "created .env: set the setup (COMPOSE_PROFILES) and tailnet URLs"; }
for f in prometheus/targets/*.example.yaml; do
  real="${f%.example.yaml}.yaml"
  [[ -f "$real" ]] || { cp "$f" "$real"; echo "created $real"; }
done

umask 077
mkdir -p secrets
# name | what goes in it
while IFS='|' read -r name what; do
  [[ -f "secrets/$name" ]] && continue
  : > "secrets/$name"
  echo "created secrets/$name (empty): $what"
done <<'LIST'
ha-token|HA long-lived access token for Prometheus (HA profile > Security; make a dedicated user)
agents-token|the agent service's HOME_AGENTS_SERVICE_TOKEN
kuma-api-key|Uptime Kuma API key (Settings > API Keys)
ha-webhook-url|http://<HA address>:8123/api/webhook/<monitoring_webhook_id from HA secrets.yaml>
ntfy-token|ntfy access token for the alertmanager user (see README)
grafana-admin-password|a long random password (openssl rand -base64 24)
LIST
chmod 600 secrets/*
echo "Fill the empty files from the vault, then: docker compose up -d"
