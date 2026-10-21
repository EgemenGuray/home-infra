#!/usr/bin/env bash
# S0.1.5: scan the home static IP from OUTSIDE the house (phone hotspot on mobile data,
# or any machine not on the home network). Expect zero open ports.
# The IP is read from the environment or a prompt; never write it into this repo.
# Usage: HOME_WAN_IP=... ./scripts/external-port-scan.sh [--full]
set -euo pipefail
command -v nmap >/dev/null || { echo "Install nmap first (brew install nmap)." >&2; exit 2; }

IP="${HOME_WAN_IP:-}"
[[ -n "$IP" ]] || read -r -p "Home static IP: " IP

mine=$(curl -fsS https://api.ipify.org || true)
if [[ "$mine" == "$IP" ]]; then
  echo "You are scanning from inside the home network; the result would be meaningless. Use mobile data." >&2
  exit 2
fi

if [[ "${1:-}" == "--full" ]]; then PORTS=(-p-); else PORTS=(--top-ports 2000); fi
echo "Scanning TCP (${PORTS[*]}) and common UDP on the home IP..."
out=$(nmap -Pn -T4 "${PORTS[@]}" --open "$IP" 2>&1)
udp=$(sudo nmap -Pn -sU --top-ports 50 --open "$IP" 2>&1 || true)

open_tcp=$(grep -cE '^[0-9]+/tcp +open' <<<"$out" || true)
open_udp=$(grep -cE '^[0-9]+/udp +open ' <<<"$udp" || true)
grep -E '^[0-9]+/(tcp|udp)' <<<"$out"$'\n'"$udp" || true

if [[ "$open_tcp" -eq 0 && "$open_udp" -eq 0 ]]; then
  echo "PASS: zero open ports. Note the date in the hands-on checklist."
else
  echo "FAIL: $open_tcp TCP and $open_udp UDP ports open. Check router port forwarding, UPnP and remote management now."
  exit 1
fi
