#!/usr/bin/env bash
# Installs the native parts of monitoring on a Mac: node_exporter (host health) and the
# 5-minute security checks. Run on the Mac mini in both setups, and on the Mac Studio in the
# Mac mini + Mac Studio setup. The Docker part is services/monitoring/.
# Usage: sudo ./macos/install-monitoring.sh [--dry-run]
set -euo pipefail
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
HUB_USER="${HUB_USER:-hub}"
HERE="$(cd "$(dirname "$0")" && pwd)"
run() { echo "+ $*"; [[ $DRY -eq 1 ]] || "$@"; }

NE=""
for p in /opt/homebrew/bin/node_exporter /usr/local/bin/node_exporter; do [[ -x "$p" ]] && NE="$p"; done
if [[ -z "$NE" ]]; then
  echo "node_exporter not found. As your admin user: brew install node_exporter (do not start the brew service)." >&2
  [[ $DRY -eq 1 ]] || exit 1
  NE=/opt/homebrew/bin/node_exporter
fi
id "$HUB_USER" >/dev/null 2>&1 || { echo "User $HUB_USER not found; run 03-accounts.sh first." >&2; [[ $DRY -eq 1 ]] || exit 1; }

run install -d -m 755 /usr/local/libexec/home-hub /usr/local/var/home-hub /usr/local/var/log/home-hub
run install -d -m 755 /usr/local/var/node_exporter/textfile
run install -m 755 "$HERE/security-checks.sh" /usr/local/libexec/home-hub/security-checks.sh
run install -m 755 "$HERE/../scripts/check-listeners.sh" /usr/local/libexec/home-hub/check-listeners.sh

for name in node-exporter security-checks; do
  src="$HERE/launchd/home.hub.$name.plist"
  dst="/Library/LaunchDaemons/home.hub.$name.plist"
  echo "+ install $src -> $dst"
  if [[ $DRY -eq 0 ]]; then
    sed -e "s#__NODE_EXPORTER__#$NE#" -e "s#__USER__#$HUB_USER#" "$src" >"$dst"
    chown root:wheel "$dst"; chmod 644 "$dst"
    launchctl bootout "system/home.hub.$name" 2>/dev/null || true
    launchctl bootstrap system "$dst"
  fi
done

echo "Check: curl -s 127.0.0.1:9100/metrics | grep home_security_"
