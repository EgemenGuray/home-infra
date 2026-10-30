#!/usr/bin/env bash
# Runs every 5 minutes as root (launchd, from install-monitoring.sh) on each Mac. Writes
# Prometheus metrics into node_exporter's textfile folder and a plain log that Alloy ships to
# Loki. Alerts are in services/monitoring/prometheus/rules/security.yml.
#   home_security_failed_logins_total       counter of failed logins (opendirectoryd, sshd, screen sharing)
#   home_security_exposed_listeners         ports listening outside loopback and the tailnet
#   home_security_funnel_on                 1 if Tailscale Funnel is on
#   home_security_firewall_stealth          1 if the firewall is in stealth mode
#   home_security_remote_login              1 if macOS Remote Login (SSH) is on
#   home_security_checks_last_run_timestamp_seconds
# Every command can be swapped through the environment, which is how tests/ runs it on Linux.
set -uo pipefail

TEXTFILE_DIR="${TEXTFILE_DIR:-/usr/local/var/node_exporter/textfile}"
STATE_DIR="${STATE_DIR:-/usr/local/var/home-hub}"
LOG_DIR="${LOG_DIR:-/usr/local/var/log/home-hub}"
LISTENERS_CMD="${LISTENERS_CMD:-/usr/local/libexec/home-hub/check-listeners.sh}"
TS="${TAILSCALE:-tailscale}"
command -v "$TS" >/dev/null 2>&1 || TS=/Applications/Tailscale.app/Contents/MacOS/Tailscale
FW_CMD="${FW_CMD:-/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode}"
REMOTE_LOGIN_CMD="${REMOTE_LOGIN_CMD:-/usr/sbin/systemsetup -getremotelogin}"
NOW="${NOW:-$(date +%s)}"
# What counts as a failed login. Check on your Mac with:  log show --last 1h --predicate '<this>'
PREDICATE="${PREDICATE:-(process == \"opendirectoryd\" AND (eventMessage CONTAINS \"Failed to authenticate\" OR eventMessage CONTAINS \"ODRecordVerifyPassword failed\")) OR (process == \"sshd\" AND (eventMessage CONTAINS \"Failed password\" OR eventMessage CONTAINS \"Invalid user\")) OR (process == \"screensharingd\" AND eventMessage CONTAINS \"FAILED\")}"
log_events() { /usr/bin/log show --style syslog --start "$1" --predicate "$PREDICATE" 2>/dev/null; }
[[ -n "${LOG_EVENTS_CMD:-}" ]] && log_events() { $LOG_EVENTS_CMD "$1"; }

mkdir -p "$TEXTFILE_DIR" "$STATE_DIR" "$LOG_DIR"
LOG="$LOG_DIR/security.log"
# Keep the log small; Loki holds the history.
[[ -f "$LOG" && $(wc -c <"$LOG") -gt 5242880 ]] && mv -f "$LOG" "$LOG.1"
say() { printf '%s %s\n' "$(date -u -r "$NOW" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$NOW" +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$LOG"; }

# Failed logins since the last run (first run: last 5 minutes). The counter survives restarts.
total=0; last=$((NOW - 300))
# shellcheck disable=SC1091
[[ -f "$STATE_DIR/security-state" ]] && . "$STATE_DIR/security-state"
since=$(date -r "$last" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$last" '+%Y-%m-%d %H:%M:%S')
events=$(log_events "$since" | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
failed=0
if [[ -n "$events" ]]; then
  failed=$(wc -l <<<"$events" | tr -d ' ')
  while IFS= read -r line; do say "failed-login: ${line:0:300}"; done <<<"$events"
fi
total=$((total + failed))
printf 'total=%d\nlast=%d\n' "$total" "$NOW" >"$STATE_DIR/security-state"

# Listeners outside loopback and the tailnet.
listeners_out=$($LISTENERS_CMD 2>&1 || true)
exposed=$(grep -c '^EXPOSED:' <<<"$listeners_out" || true)
grep '^EXPOSED:' <<<"$listeners_out" | while IFS= read -r l; do say "listener: $l"; done

funnel=0
"$TS" funnel status 2>/dev/null | grep -qi 'funnel on' && { funnel=1; say "tailscale: funnel is on"; }
stealth=0
$FW_CMD 2>/dev/null | grep -qiE 'stealth mode (is )?(on|enabled)' && stealth=1
remote=0
$REMOTE_LOGIN_CMD 2>/dev/null | grep -qi 'remote login: on' && { remote=1; say "remote login (ssh) is on"; }

tmp="$TEXTFILE_DIR/.home_security.prom.$$"
cat >"$tmp" <<PROM
# HELP home_security_failed_logins_total Failed logins seen in the macOS unified log.
# TYPE home_security_failed_logins_total counter
home_security_failed_logins_total $total
# HELP home_security_exposed_listeners TCP listeners outside loopback and the tailnet.
# TYPE home_security_exposed_listeners gauge
home_security_exposed_listeners $exposed
# HELP home_security_funnel_on Tailscale Funnel is on.
# TYPE home_security_funnel_on gauge
home_security_funnel_on $funnel
# HELP home_security_firewall_stealth Application firewall stealth mode is on.
# TYPE home_security_firewall_stealth gauge
home_security_firewall_stealth $stealth
# HELP home_security_remote_login macOS Remote Login (SSH) is on.
# TYPE home_security_remote_login gauge
home_security_remote_login $remote
# HELP home_security_checks_last_run_timestamp_seconds When these checks last ran.
# TYPE home_security_checks_last_run_timestamp_seconds gauge
home_security_checks_last_run_timestamp_seconds $NOW
PROM
chmod 644 "$tmp" && mv -f "$tmp" "$TEXTFILE_DIR/home_security.prom"
say "checks: failed=$failed exposed=$exposed funnel=$funnel stealth=$stealth remote_login=$remote"
