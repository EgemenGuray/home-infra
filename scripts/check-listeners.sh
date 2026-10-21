#!/usr/bin/env bash
# Run on the hub Mac. Fails if any TCP port listens on an address other than loopback or the
# tailnet (100.64.0.0/10, fd7a:115c:a1e0::/48). Use after every install (S0.1.5).
set -uo pipefail
ALLOW_RE='^(127\.|\[::1\]|localhost|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.|\[fd7a:115c:a1e0:)'
# Services that must listen on the LAN for local device control (HA VM bridge, mDNS).
ALLOW_PROC_RE="${ALLOW_PROC_RE:-^(mDNSRespo|UTM|QEMULaunc|com\.apple\.Virtua)}"

bad=0
while read -r cmd _pid _user _fd _type _dev _size _node name _state; do
  addr="${name%:*}"
  [[ "$addr" =~ $ALLOW_RE ]] && continue
  [[ "$cmd" =~ $ALLOW_PROC_RE ]] && { echo "allowed (LAN): $cmd $name"; continue; }
  echo "EXPOSED: $cmd listens on $name"; bad=1
done < <(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | tail -n +2)

if [[ $bad -eq 0 ]]; then echo "OK: nothing listens outside loopback and the tailnet."; fi
echo "Firewall stealth mode: $(/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null)"
exit $bad
