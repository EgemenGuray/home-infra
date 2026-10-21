#!/usr/bin/env bash
# S1.3.5: checks each route's public IP and country through its proxy. Run every 15 minutes
# from launchd and before each job; any mismatch exits non-zero (Uptime Kuma push monitor).
# Usage: ./scripts/check-routes.sh services/egress/routes.yaml
set -uo pipefail
ROUTES="${1:-services/egress/routes.yaml}"
[[ -f "$ROUTES" ]] || { echo "No $ROUTES; copy routes.example.yaml." >&2; exit 2; }
# shellcheck disable=SC1091
[[ -f services/egress/.env ]] && source services/egress/.env
fail=0
while IFS= read -r line; do
  [[ "$line" =~ ^([a-z0-9-]+):.*port:\ *([0-9]+).*country:\ *([A-Z]{2}) ]] || continue
  route="${BASH_REMATCH[1]}"; port="${BASH_REMATCH[2]}"; want="${BASH_REMATCH[3]}"
  want_ip=""; [[ "$line" =~ ip:\ *\"([0-9.]+)\" ]] && want_ip="${BASH_REMATCH[1]}"
  auth=(); [[ "$route" != home && -n "${PROXY_USER:-}" ]] && auth=(--proxy-user "$PROXY_USER:$PROXY_PASSWORD")
  info=$(curl -fsS -m 15 -x "http://127.0.0.1:$port" "${auth[@]}" https://ipinfo.io/json 2>/dev/null)
  if [[ -z "$info" ]]; then echo "FAIL $route: no answer (tunnel down, kill switch engaged)"; fail=1; continue; fi
  ip=$(sed -n 's/.*"ip": *"\([^"]*\)".*/\1/p' <<<"$info"); country=$(sed -n 's/.*"country": *"\([^"]*\)".*/\1/p' <<<"$info")
  if [[ "$country" != "$want" ]]; then echo "FAIL $route: exits from $country, expected $want"; fail=1
  elif [[ -n "$want_ip" && "$ip" != "$want_ip" ]]; then echo "FAIL $route: unexpected exit IP"; fail=1
  else echo "ok   $route: $country"; fi
done < "$ROUTES"
exit $fail
