#!/usr/bin/env bash
# All monitoring tests. Needs promtool, amtool, loki and alloy on PATH (CI downloads pinned
# releases; see .github/workflows/monitoring.yml), docker compose, python3 with pytest + pyyaml.
# Usage: tests/monitoring/run.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MON="$ROOT/services/monitoring"
T="$ROOT/tests/monitoring"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
step() { printf '\n== %s\n' "$*"; }

step "Prometheus rules: syntax and unit tests"
promtool check rules "$MON"/prometheus/rules/*.yml
(cd "$T" && promtool test rules rules.test.yml)

step "Prometheus config (paths mapped to a temp folder, as the container would see them)"
mkdir -p "$WORK/prom/secrets" "$WORK/prom/targets"
cp -r "$MON/prometheus/rules" "$WORK/prom/rules"
for f in "$MON"/prometheus/targets/*.example.yaml; do cp "$f" "$WORK/prom/targets/$(basename "${f%.example.yaml}").yaml"; done
touch "$WORK/prom/secrets/"{ha-token,agents-token,kuma-api-key}
sed "s#/etc/prometheus#$WORK/prom#g" "$MON/prometheus/prometheus.yml" >"$WORK/prom/prometheus.yml"
promtool check config "$WORK/prom/prometheus.yml"
for f in "$WORK"/prom/targets/*.yaml; do python3 -c "import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); assert d is None or isinstance(d, list), sys.argv[1]" "$f"; done

step "Alertmanager config and routing"
mkdir -p "$WORK/am/secrets"; touch "$WORK/am/secrets/"{ha-webhook-url,ntfy-token}
sed "s#/etc/alertmanager#$WORK/am#g" "$MON/alertmanager/alertmanager.yml" >"$WORK/am/alertmanager.yml"
amtool check-config "$WORK/am/alertmanager.yml"
route() {  # route <expected receivers> <labels...>
  local want="$1"; shift
  got=$(amtool config routes test --config.file="$WORK/am/alertmanager.yml" "$@" | tail -n1)
  if [[ "$got" == "$want" ]]; then echo "ok   - $* -> $got"; else echo "FAIL - $* -> $got (want $want)"; exit 1; fi
}
route "ha-push"        alertname=HostDiskLow severity=warning host=hub
route "ha-push,ntfy"   alertname=PortExposed severity=critical host=hub
route "ntfy"           alertname=HomeAssistantDown severity=critical notify=ntfy
route "ntfy"           alertname=AlertDeliveryFailing severity=warning notify=ntfy
route "ha-push"        alertname=VaultwardenFailedLogin severity=warning

step "Loki config"
LOKI_RETENTION=168h ALERTMANAGER_URL=http://alertmanager:9093 \
  loki -config.file="$MON/loki/loki.yaml" -config.expand-env=true -verify-config
python3 - "$MON/loki/rules" <<'PY'
import pathlib, sys, yaml
for f in pathlib.Path(sys.argv[1]).rglob("*.yml"):
    for g in yaml.safe_load(f.read_text())["groups"]:
        for r in g["rules"]:
            assert r["expr"].lstrip().startswith(("sum(", "count_over_time(", "rate(")), (f, r["alert"])
print("ok   - loki rules parse")
PY

step "Alloy config"
alloy fmt "$MON/alloy/config.alloy" >/dev/null && echo "ok   - alloy fmt"

step "Compose files, both setups"
cp "$MON/.env.example" "$WORK/mini.env"
(cd "$MON" && COMPOSE_PROFILES=ui docker compose --env-file "$WORK/mini.env" config -q && echo "ok   - Mac mini only (profile ui)")
(cd "$MON" && COMPOSE_PROFILES='' docker compose --env-file "$WORK/mini.env" config --services | sort | tr '\n' ' ' | grep -qx 'alertmanager alloy cadvisor ntfy prometheus ' \
  && echo "ok   - Mac mini + Mac Studio: mini runs no Loki or Grafana")
(cd "$MON" && docker compose -f studio/compose.yaml --env-file studio/.env.example config -q && echo "ok   - Mac Studio")

step "Security checks script"
bash "$T/security-checks.test.sh"

step "Policy tests"
python3 -m pytest -q "$T"

printf '\nAll monitoring tests passed.\n'
