#!/usr/bin/env bash
# Unit tests for macos/security-checks.sh. Runs on Linux or macOS with stubbed system commands.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../../macos/security-checks.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fails=0

check() {  # check <description> <file> <regex>
  if grep -qE "$3" "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; echo "  in $2:"; sed 's/^/    /' "$2"; fails=$((fails + 1)); fi
}

mkdir -p "$WORK/bin"
cat >"$WORK/bin/events" <<'S'
#!/usr/bin/env bash
cat "$EVENTS_FILE" 2>/dev/null || true
S
cat >"$WORK/bin/listeners" <<'S'
#!/usr/bin/env bash
cat "$LISTENERS_FILE"
S
cat >"$WORK/bin/tailscale" <<'S'
#!/usr/bin/env bash
cat "$FUNNEL_FILE"
S
printf '#!/usr/bin/env bash\necho "Firewall stealth mode is on"\n' >"$WORK/bin/fw-on"
printf '#!/usr/bin/env bash\necho "Firewall stealth mode is off"\n' >"$WORK/bin/fw-off"
printf '#!/usr/bin/env bash\necho "Remote Login: Off"\n' >"$WORK/bin/rl-off"
printf '#!/usr/bin/env bash\necho "Remote Login: On"\n' >"$WORK/bin/rl-on"
chmod +x "$WORK"/bin/*

run() {
  TEXTFILE_DIR="$WORK/textfile" STATE_DIR="$WORK/state" LOG_DIR="$WORK/log" \
  LOG_EVENTS_CMD="$WORK/bin/events" LISTENERS_CMD="$WORK/bin/listeners" TAILSCALE="$WORK/bin/tailscale" \
  EVENTS_FILE="$WORK/events" LISTENERS_FILE="$WORK/listeners" FUNNEL_FILE="$WORK/funnel" \
  "$@" bash "$SCRIPT"
}
PROM="$WORK/textfile/home_security.prom"

# 1. Clean Mac: nothing failed, nothing exposed.
: >"$WORK/events"
echo "OK: nothing listens outside loopback and the tailnet." >"$WORK/listeners"
echo "No serve config" >"$WORK/funnel"
run env FW_CMD="$WORK/bin/fw-on" REMOTE_LOGIN_CMD="$WORK/bin/rl-off" NOW=1700000000
check "clean: zero failed logins" "$PROM" '^home_security_failed_logins_total 0$'
check "clean: zero exposed" "$PROM" '^home_security_exposed_listeners 0$'
check "clean: funnel off" "$PROM" '^home_security_funnel_on 0$'
check "clean: stealth on" "$PROM" '^home_security_firewall_stealth 1$'
check "clean: remote login off" "$PROM" '^home_security_remote_login 0$'
check "clean: timestamp" "$PROM" '^home_security_checks_last_run_timestamp_seconds 1700000000$'

# 2. Two failed logins, one exposed port, Funnel on, stealth off, SSH on.
cat >"$WORK/events" <<'E'
Timestamp                       (process)[PID]
2026-10-30 04:00:01.000000-0400  localhost opendirectoryd[1]: Failed to authenticate user <admin> (error: 5000)
2026-10-30 04:00:09.000000-0400  localhost sshd[2]: Failed password for invalid user root
E
printf 'EXPOSED: node listens on *:3000\nallowed (LAN): UTM *:5900\n' >"$WORK/listeners"
echo "# Funnel on:" >"$WORK/funnel"
run env FW_CMD="$WORK/bin/fw-off" REMOTE_LOGIN_CMD="$WORK/bin/rl-on" NOW=1700000300
check "bad: two failed logins counted" "$PROM" '^home_security_failed_logins_total 2$'
check "bad: header line not counted" "$WORK/log/security.log" 'failed=2 '
check "bad: one exposed listener" "$PROM" '^home_security_exposed_listeners 1$'
check "bad: funnel on" "$PROM" '^home_security_funnel_on 1$'
check "bad: stealth off" "$PROM" '^home_security_firewall_stealth 0$'
check "bad: remote login on" "$PROM" '^home_security_remote_login 1$'
check "bad: failed login logged for Loki" "$WORK/log/security.log" 'failed-login: .*sshd'
check "bad: exposed port logged for Loki" "$WORK/log/security.log" 'listener: EXPOSED: node listens on \*:3000'

# 3. Counter keeps growing across runs; state remembers the last run.
cat >"$WORK/events" <<'E'
2026-10-30 04:05:01.000000-0400  localhost screensharingd[3]: Authentication: FAILED :: User Name: x
E
run env FW_CMD="$WORK/bin/fw-on" REMOTE_LOGIN_CMD="$WORK/bin/rl-off" NOW=1700000600
check "counter: 2 + 1 = 3" "$PROM" '^home_security_failed_logins_total 3$'
check "state: last run saved" "$WORK/state/security-state" '^last=1700000600$'

# 4. The metrics file is valid exposition format (every sample has a TYPE).
for m in $(grep -v '^#' "$PROM" | awk '{print $1}'); do
  grep -q "^# TYPE $m " "$PROM" || { echo "FAIL - $m has no TYPE"; fails=$((fails + 1)); }
done
echo "ok   - every metric has a TYPE line"

[[ $fails -eq 0 ]] && echo "PASS: security-checks" || { echo "$fails failure(s)"; exit 1; }
