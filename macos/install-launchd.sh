#!/usr/bin/env bash
# Installs the HA VM watchdog for the hub user and turns off App Nap for UTM.
# Usage: sudo ./macos/install-launchd.sh [--dry-run]
set -euo pipefail
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
HUB_USER="${HUB_USER:-hub}"
HERE="$(cd "$(dirname "$0")" && pwd)"
run() { echo "+ $*"; [[ $DRY -eq 1 ]] || "$@"; }

HUB_HOME=$(dscl . -read "/Users/$HUB_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
[[ -n "$HUB_HOME" ]] || { echo "User $HUB_USER not found; run 03-accounts.sh first." >&2; exit 1; }
HUB_UID=$(id -u "$HUB_USER")

run install -d -m 755 /usr/local/libexec/home-hub
run install -m 755 "$HERE/launchd/ha-vm-watchdog.sh" /usr/local/libexec/home-hub/ha-vm-watchdog.sh
run install -d -o "$HUB_USER" "$HUB_HOME/Library/LaunchAgents"
run install -m 644 -o "$HUB_USER" "$HERE/launchd/home.hub.ha-vm.plist" "$HUB_HOME/Library/LaunchAgents/"

# App Nap would throttle the VM when UTM has no visible window.
run sudo -u "$HUB_USER" defaults write com.utmapp.UTM NSAppSleepDisabled -bool YES

if launchctl print "gui/$HUB_UID" >/dev/null 2>&1; then
  run launchctl bootout "gui/$HUB_UID/home.hub.ha-vm" 2>/dev/null || true
  run launchctl bootstrap "gui/$HUB_UID" "$HUB_HOME/Library/LaunchAgents/home.hub.ha-vm.plist"
else
  echo "hub is not logged in; the agent loads at its next login."
fi

echo "Tailscale: install the standalone package from tailscale.com (not the App Store build), then:"
echo "  sudo tailscaled install-system-daemon   # starts before login"
