#!/usr/bin/env bash
# Starts UTM and the Home Assistant VM if they are not running. Run every 2 minutes by launchd.
set -uo pipefail
VM_NAME="${HA_VM_NAME:-Home Assistant}"
UTMCTL="/Applications/UTM.app/Contents/MacOS/utmctl"

[[ -x "$UTMCTL" ]] || { echo "$(date) utmctl not found"; exit 1; }
pgrep -xq UTM || { open -g -a UTM; sleep 15; }

status=$("$UTMCTL" status "$VM_NAME" 2>/dev/null || echo unknown)
case "$status" in
  started) ;;
  paused) echo "$(date) resuming VM"; "$UTMCTL" resume "$VM_NAME" ;;
  *) echo "$(date) VM status '$status', starting"; "$UTMCTL" start "$VM_NAME" ;;
esac
