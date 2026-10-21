#!/usr/bin/env bash
# Publishes the egress proxies to the tailnet as raw TCP. The tailnet policy allows only
# tag:workspace to reach these ports (tailscale/policy.hujson.example).
set -euo pipefail
TS="${TAILSCALE:-tailscale}"
for port in 8888 8889 8890; do
  "$TS" serve --bg --tcp="$port" "tcp://127.0.0.1:$port"
done
"$TS" serve status
