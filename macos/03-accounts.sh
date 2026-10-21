#!/usr/bin/env bash
# S0.2.2: create the standard "hub" service user and verify no personal accounts.
# The admin account stays the one created during setup, with a vault passphrase.
# Usage: sudo ./macos/03-accounts.sh [--dry-run]
set -euo pipefail

DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
HUB_USER="${HUB_USER:-hub}"
if [[ "$(uname)" != "Darwin" ]]; then echo "Run this on the Mac." >&2; exit 1; fi
if [[ $EUID -ne 0 && $DRY -eq 0 ]]; then echo "Run with sudo." >&2; exit 1; fi

if id "$HUB_USER" >/dev/null 2>&1; then
  echo "User $HUB_USER already exists."
else
  echo "Creating standard (non-admin) user '$HUB_USER'. Use a new vault-generated password."
  if [[ $DRY -eq 0 ]]; then
    read -r -s -p "Password for $HUB_USER: " PW; echo
    sysadminctl -addUser "$HUB_USER" -fullName "Hub" -password "$PW"
    unset PW
  fi
fi

if dseditgroup -o checkmember -m "$HUB_USER" admin >/dev/null 2>&1; then
  echo "WARNING: $HUB_USER is an admin. Removing admin rights."
  [[ $DRY -eq 1 ]] || dseditgroup -o edit -d "$HUB_USER" -t user admin
fi

echo
echo "== Personal-account check"
bad=0
for home in /Users/*; do
  u=$(basename "$home"); [[ "$u" == Shared ]] && continue
  if /usr/libexec/PlistBuddy -c 'Print :Accounts:0:AccountID' "$home/Library/Preferences/MobileMeAccounts.plist" >/dev/null 2>&1; then
    echo "FAIL: $u is signed in to an Apple ID. Sign out in System Settings."; bad=1
  fi
  if [[ -d "$home/Library/Application Support/Google/Chrome/Default" ]]; then
    echo "FAIL: $u has a Chrome profile. Remove it."; bad=1
  fi
done
[[ $bad -eq 0 ]] && echo "OK: no Apple ID or Chrome profile found."

echo
echo "Next, by hand: System Settings > Users & Groups > Automatically log in as '$HUB_USER'."
echo "Then add a login item for 'hub' that locks the screen: see docs/hands-on-checklist.md (B6)."
exit $bad
