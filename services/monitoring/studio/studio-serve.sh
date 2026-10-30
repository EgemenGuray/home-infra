#!/usr/bin/env bash
# Mac mini + Mac Studio setup only. Run on the Studio: publishes its monitoring pieces to the
# tailnet over HTTPS. `serve` is tailnet-only; never use `tailscale funnel`.
set -euo pipefail
TS="${TAILSCALE:-tailscale}"
command -v "$TS" >/dev/null || TS=/Applications/Tailscale.app/Contents/MacOS/Tailscale

"$TS" serve --bg --https=4443 http://127.0.0.1:3000    # Grafana (you)
"$TS" serve --bg --https=3143 http://127.0.0.1:3100    # Loki (Mac mini's Alloy pushes logs here)
"$TS" serve --bg --https=9143 http://127.0.0.1:9100    # node_exporter (Mac mini's Prometheus)
"$TS" serve --bg --https=9180 http://127.0.0.1:8081    # cAdvisor (Mac mini's Prometheus)
"$TS" funnel status 2>/dev/null | grep -qi 'funnel on' && { echo "Funnel is on. Turn it off: $TS funnel reset" >&2; exit 1; }
"$TS" serve status
