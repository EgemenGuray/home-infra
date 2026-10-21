#!/usr/bin/env bash
# Publishes the localhost-only services to the tailnet over HTTPS (S0.1.4).
# `serve` is tailnet-only. Never use `tailscale funnel`, which would expose them to the internet.
set -euo pipefail
TS="${TAILSCALE:-tailscale}"
command -v "$TS" >/dev/null || TS=/Applications/Tailscale.app/Contents/MacOS/Tailscale

"$TS" serve --bg --https=8443 http://127.0.0.1:8222   # Vaultwarden
"$TS" serve --bg --https=3443 http://127.0.0.1:3001   # Uptime Kuma
"$TS" funnel status 2>/dev/null | grep -qi 'funnel on' && { echo "Funnel is on. Turn it off: $TS funnel reset" >&2; exit 1; }
"$TS" serve status
