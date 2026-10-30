#!/usr/bin/env bash
# Publishes the localhost-only services to the tailnet over HTTPS (S0.1.4).
# `serve` is tailnet-only. Never use `tailscale funnel`, which would expose them to the internet.
# Mac mini only:         ./services/tailscale-serve.sh
# Mac mini + Mac Studio: ./services/tailscale-serve.sh --with-studio   (also publishes Prometheus
#                        and Alertmanager so the Studio's Grafana and Loki can reach them; the
#                        tailnet policy limits those two ports to the Studio and your devices)
set -euo pipefail
TS="${TAILSCALE:-tailscale}"
command -v "$TS" >/dev/null || TS=/Applications/Tailscale.app/Contents/MacOS/Tailscale

"$TS" serve --bg --https=8443 http://127.0.0.1:8222   # Vaultwarden
"$TS" serve --bg --https=3443 http://127.0.0.1:3001   # Uptime Kuma
"$TS" serve --bg --https=2443 http://127.0.0.1:2586   # ntfy (fallback alerts)
if [[ "${1:-}" == "--with-studio" ]]; then
  "$TS" serve --https=4443 off 2>/dev/null || true     # Grafana moves to the Studio
  "$TS" serve --bg --https=9443 http://127.0.0.1:9090 # Prometheus (Studio's Grafana)
  "$TS" serve --bg --https=9493 http://127.0.0.1:9093 # Alertmanager (Studio's Loki ruler and Grafana)
else
  "$TS" serve --bg --https=4443 http://127.0.0.1:3000 # Grafana
fi
"$TS" funnel status 2>/dev/null | grep -qi 'funnel on' && { echo "Funnel is on. Turn it off: $TS funnel reset" >&2; exit 1; }
"$TS" serve status
