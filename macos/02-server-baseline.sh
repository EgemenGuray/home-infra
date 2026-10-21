#!/usr/bin/env bash
# S0.2.2 + S0.1.5: always-on server baseline for the hub Mac (Mac mini).
# Safe to run more than once. Usage: sudo ./macos/02-server-baseline.sh [--dry-run]
set -euo pipefail

DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
if [[ "$(uname)" != "Darwin" ]]; then echo "Run this on the Mac." >&2; exit 1; fi
if [[ $EUID -ne 0 && $DRY -eq 0 ]]; then echo "Run with sudo." >&2; exit 1; fi

run() { echo "+ $*"; [[ $DRY -eq 1 ]] || "$@"; }
FW=/usr/libexec/ApplicationFirewall/socketfilterfw

echo "== Power: never sleep, restart after power loss, wake on network"
run pmset -a sleep 0 disksleep 0 displaysleep 10 powernap 0 autorestart 1 womp 1
run pmset -a lowpowermode 0 || true
run systemsetup -setrestartfreeze on

echo "== Firewall on, stealth mode, block unsigned incoming"
run "$FW" --setglobalstate on
run "$FW" --setstealthmode on
run "$FW" --setallowsigned on
run "$FW" --setallowsignedapp off

echo "== Sharing services off (Tailscale is the only way in)"
run systemsetup -f -setremotelogin off
run launchctl disable system/com.apple.screensharing || true
run launchctl bootout system/com.apple.screensharing 2>/dev/null || true
run /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate -stop || true
run launchctl disable system/com.apple.smbd || true
run launchctl disable system/com.apple.AEServer || true   # Remote Apple Events
run cupsctl --no-share-printers || true

echo "== Updates: security responses on, automatic macOS upgrades off"
SU=/Library/Preferences/com.apple.SoftwareUpdate
run defaults write "$SU" AutomaticCheckEnabled -bool true
run defaults write "$SU" AutomaticDownload -bool true
run defaults write "$SU" CriticalUpdateInstall -bool true
run defaults write "$SU" ConfigDataInstall -bool true
run defaults write "$SU" AutomaticallyInstallMacOSUpdates -bool false
run defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool false

echo "== No Handoff, no AirDrop, no Bluetooth discoverability for services"
run defaults write /Library/Preferences/com.apple.NetworkBrowser DisableAirDrop -bool true

echo "== Wi-Fi off (the hub Mac is wired on the Main network)"
WIFI_DEV=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
[[ -n "$WIFI_DEV" ]] && run networksetup -setairportpower "$WIFI_DEV" off

echo "== Screen locks immediately"
run defaults write /Library/Preferences/com.apple.screensaver askForPassword -int 1
run defaults write /Library/Preferences/com.apple.screensaver askForPasswordDelay -int 0

echo
echo "Done. Do these by hand in System Settings (no reliable CLI):"
echo "  - Energy: Prevent automatic sleeping, Start up automatically after a power failure, Wake for network access"
echo "  - General > Sharing: confirm every switch is off"
echo "  - Users & Groups: automatic login as 'hub' (after 03-accounts.sh) and FileVault stays off"
echo "Verify: pmset -g; $FW --getstealthmode; systemsetup -getremotelogin"
