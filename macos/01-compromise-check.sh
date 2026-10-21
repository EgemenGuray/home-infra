#!/usr/bin/env bash
# S0.2.1: read-only compromise check for a Mac that may have been compromised.
# Changes nothing. Writes a report to ./compromise-report-<date>.txt (ignored by git).
# Usage: sudo ./macos/01-compromise-check.sh
set -uo pipefail

if [[ "$(uname)" != "Darwin" ]]; then echo "Run this on the Mac." >&2; exit 1; fi
if [[ $EUID -ne 0 ]]; then echo "Run with sudo so system locations can be read." >&2; exit 1; fi

REPORT="compromise-report-$(date +%Y%m%d-%H%M).local.txt"
FLAGS=0
exec > >(tee "$REPORT") 2>&1

section() { printf '\n==== %s ====\n' "$1"; }
flag() { printf '  [REVIEW] %s\n' "$1"; FLAGS=$((FLAGS + 1)); }

section "System"
sw_vers
echo "SIP: $(csrutil status 2>/dev/null)"
echo "Gatekeeper: $(spctl --status 2>/dev/null)"
csrutil status 2>/dev/null | grep -q enabled || flag "System Integrity Protection is not enabled"
spctl --status 2>/dev/null | grep -q enabled || flag "Gatekeeper is disabled"

section "User accounts (UID >= 500)"
dscl . list /Users UniqueID | awk '$2 >= 500 {print}' | while read -r user uid; do
  admin=""; dseditgroup -o checkmember -m "$user" admin >/dev/null 2>&1 && admin=" (admin)"
  echo "  $user uid=$uid$admin"
done
echo "  Hidden users:"
dscl . list /Users IsHidden 2>/dev/null | awk '$2 == 1 {print "    " $1}'
echo "  -> Every account above must be one you created. Unknown or hidden admin users are a red flag."

section "Launch daemons and agents (non-Apple)"
for dir in /Library/LaunchDaemons /Library/LaunchAgents /Users/*/Library/LaunchAgents; do
  [[ -d "$dir" ]] || continue
  for f in "$dir"/*.plist; do
    [[ -e "$f" ]] || continue
    label=$(basename "$f")
    [[ "$label" == com.apple.* ]] && continue
    prog=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$f" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Print :Program' "$f" 2>/dev/null)
    echo "  $f -> ${prog:-?}"
    if [[ -n "$prog" && -e "$prog" ]]; then
      sig=$(codesign -dv "$prog" 2>&1 | awk -F= '/Authority=/{print $2; exit}')
      echo "      signed by: ${sig:-UNSIGNED}"
      [[ -z "$sig" ]] && flag "Unsigned launch item: $f"
    fi
    case "$prog" in /tmp/*|/private/tmp/*|/Users/Shared/*|*/.*) flag "Launch item runs from a suspicious path: $f";; esac
  done
done

section "Background items (login items, as macOS sees them)"
sfltool dumpbtm 2>/dev/null | grep -E 'Name:|Developer Name:|URL:|Disposition:' | sed 's/^/  /' || echo "  sfltool not available"

section "Configuration profiles"
profiles list -all 2>/dev/null | sed 's/^/  /'
profiles list -all 2>/dev/null | grep -q 'attribute' && flag "Configuration profiles are installed; each must be one you recognise"
profiles status -type enrollment 2>/dev/null | sed 's/^/  /'

section "Sharing and remote access"
echo "  Remote Login (SSH): $(systemsetup -getremotelogin 2>/dev/null)"
systemsetup -getremotelogin 2>/dev/null | grep -qi ': on' && flag "Remote Login (SSH) is on"
launchctl print system/com.apple.screensharing >/dev/null 2>&1 && flag "Screen Sharing is loaded"
pgrep -q ARDAgent && flag "Apple Remote Desktop agent is running"
for svc in com.apple.smbd com.apple.AppleFileServer; do
  launchctl print "system/$svc" >/dev/null 2>&1 && echo "  $svc loaded"
done
echo "  Third-party remote tools found:"
ls -d /Applications/{TeamViewer,AnyDesk,"Chrome Remote Desktop Host",RustDesk,Splashtop*,LogMeIn*,ScreenConnect*,ngrok}* 2>/dev/null | sed 's/^/    /' && flag "Third-party remote access software is installed"
ls /Library/PrivilegedHelperTools 2>/dev/null | sed 's/^/  helper: /'

section "SSH keys and config"
for home in /var/root /Users/*; do
  [[ -d "$home/.ssh" ]] || continue
  echo "  $home/.ssh:"; ls -la "$home/.ssh" | sed 's/^/    /'
  [[ -s "$home/.ssh/authorized_keys" ]] && flag "authorized_keys exists in $home/.ssh"
done
[[ -s /etc/ssh/sshd_config.d/100-macos.conf ]] && grep -v '^#' /etc/ssh/sshd_config.d/*.conf 2>/dev/null | sed 's/^/  sshd: /'

section "Scheduled jobs"
for u in $(dscl . list /Users | grep -v '^_'); do
  c=$(crontab -l -u "$u" 2>/dev/null); [[ -n "$c" ]] && { echo "  crontab for $u:"; echo "$c" | sed 's/^/    /'; flag "crontab exists for $u"; }
done
ls /etc/periodic/*/ 2>/dev/null | sed 's/^/  /'
for f in /etc/sudoers.d/*; do [[ -s "$f" ]] && { ls -la "$f"; flag "Custom sudoers rule: $f"; }; done

section "Kernel and system extensions"
systemextensionsctl list 2>/dev/null | sed 's/^/  /'
kmutil showloaded --list-only 2>/dev/null | grep -v com.apple | sed 's/^/  /'

section "Shell startup files (look for curl, base64, nc, python one-liners)"
for f in /etc/zshrc /etc/profile /etc/bashrc /var/root/.zshrc /Users/*/.zshrc /Users/*/.zprofile /Users/*/.bash_profile /Users/*/.bashrc; do
  [[ -f "$f" ]] || continue
  if grep -nE 'curl|wget|base64|nc |ncat|/dev/tcp|python[0-9.]* -c|osascript' "$f" >/dev/null; then
    echo "  $f:"; grep -nE 'curl|wget|base64|nc |ncat|/dev/tcp|python[0-9.]* -c|osascript' "$f" | sed 's/^/    /'
    flag "Suspicious command in $f"
  fi
done

section "Network: listening sockets and DNS"
lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR==1 || $9 !~ /^(127\.0\.0\.1|\[::1\]):/' | sed 's/^/  /'
echo "  DNS servers:"; scutil --dns | awk '/nameserver/ {print "    " $3}' | sort -u
echo "  Proxy settings:"; scutil --proxy | sed 's/^/    /'
scutil --proxy | grep -qE 'HTTPEnable : 1|HTTPSEnable : 1|SOCKSEnable : 1|ProxyAutoConfigEnable : 1' && flag "A system proxy is configured"
grep -vE '^\s*(#|$)|localhost|broadcasthost' /etc/hosts | sed 's/^/  hosts: /'

section "Accounts signed in on this Mac"
for home in /Users/*; do
  u=$(basename "$home")
  [[ -f "$home/Library/Preferences/MobileMeAccounts.plist" ]] && \
    /usr/libexec/PlistBuddy -c 'Print :Accounts:0:AccountID' "$home/Library/Preferences/MobileMeAccounts.plist" >/dev/null 2>&1 && \
    flag "User $u is signed in to an Apple ID"
  [[ -d "$home/Library/Messages" ]] && [[ -n "$(ls -A "$home/Library/Messages" 2>/dev/null)" ]] && flag "User $u has Messages data"
  [[ -d "$home/Library/Application Support/Google/Chrome/Default" ]] && flag "User $u still has a Chrome profile"
done

section "Summary"
echo "Items to review: $FLAGS"
echo "Report saved to $REPORT"
if [[ $FLAGS -gt 0 ]]; then
  echo "Recommendation: erase and reinstall (Erase All Content and Settings, or a DFU restore), set up as new, no Migration Assistant."
else
  echo "Nothing flagged. A clean reinstall is still the safer choice, because a scan can miss what an erase cannot."
fi
