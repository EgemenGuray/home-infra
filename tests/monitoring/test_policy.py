"""Policy tests for the monitoring stack: `python3 -m pytest tests/monitoring`.

They check the rules every alert and service must follow, so a future edit can't quietly break
delivery or open a port: every alert has a severity and a summary, every port binds to
127.0.0.1, secrets only come from files, and Grafana panels point at provisioned datasources.
"""

import json
import re
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]
MON = ROOT / "services" / "monitoring"
PROM_RULES = sorted((MON / "prometheus" / "rules").glob("*.yml"))
LOKI_RULES = sorted((MON / "loki" / "rules").rglob("*.yml"))
COMPOSE = [MON / "compose.yaml", MON / "studio" / "compose.yaml"]


def alerts(files):
    for f in files:
        for group in yaml.safe_load(f.read_text())["groups"]:
            for rule in group["rules"]:
                if "alert" in rule:
                    yield f.name, rule


@pytest.mark.parametrize("fname,rule", list(alerts(PROM_RULES + LOKI_RULES)), ids=lambda v: v if isinstance(v, str) else v["alert"])
def test_every_alert_has_severity_and_summary(fname, rule):
    assert rule["labels"]["severity"] in {"warning", "critical"}, f"{fname}: {rule['alert']}"
    assert rule["annotations"]["summary"].strip()
    if "notify" in rule["labels"]:
        assert rule["labels"]["notify"] == "ntfy"


def test_alert_names_are_unique():
    names = [r["alert"] for _, r in alerts(PROM_RULES + LOKI_RULES)]
    assert len(names) == len(set(names))


def test_every_prometheus_alert_has_a_unit_test():
    tested = set(re.findall(r"alertname: (\w+)", (Path(__file__).parent / "rules.test.yml").read_text()))
    untested = {r["alert"] for _, r in alerts(PROM_RULES)} - tested
    # Plain up==0 checks and self-monitoring are covered by the same pattern elsewhere.
    allowed = {"CadvisorDown", "UptimeKumaDown", "AgentServiceDown", "HostDiskCritical", "HostCpuBusy",
               "HomeAssistantEntitiesUnavailable", "ModelProviderUnavailable", "FirewallStealthOff",
               "RemoteLoginEnabled", "PrometheusRuleFailures", "LogShippingFailing"}
    assert untested <= allowed, f"add tests for {sorted(untested - allowed)}"


@pytest.mark.parametrize("path", COMPOSE, ids=lambda p: p.parent.name + "/" + p.name)
def test_ports_bind_to_localhost_only(path):
    for name, svc in yaml.safe_load(path.read_text())["services"].items():
        assert svc.get("network_mode") != "host", name
        for port in svc.get("ports", []):
            assert str(port).startswith("127.0.0.1:"), f"{name} publishes {port} beyond localhost"
        assert "mem_limit" in svc, f"{name} needs a memory limit"
        assert ":latest" not in svc["image"] and ":" in svc["image"], f"{name} must pin its image"


def test_no_inline_credentials():
    am = yaml.safe_load((MON / "alertmanager" / "alertmanager.yml").read_text())
    for r in am["receivers"]:
        for w in r.get("webhook_configs", []):
            if "url" in w:
                assert w["url"].startswith("http://ntfy/"), "external webhook URLs belong in secrets/"
            auth = w.get("http_config", {}).get("authorization", {})
            assert "credentials" not in auth
    prom = yaml.safe_load((MON / "prometheus" / "prometheus.yml").read_text())
    for job in prom["scrape_configs"]:
        assert "credentials" not in job.get("authorization", {}), job["job_name"]
        assert "password" not in job.get("basic_auth", {}), job["job_name"]


def test_alertmanager_routes_critical_to_both_channels():
    route = yaml.safe_load((MON / "alertmanager" / "alertmanager.yml").read_text())["route"]
    crit = [r for r in route["routes"] if r["matchers"] == ['severity="critical"']]
    assert [r["receiver"] for r in crit] == ["ha-push", "ntfy"] and crit[0]["continue"] is True


def test_dashboards_use_provisioned_datasources():
    ds = yaml.safe_load((MON / "grafana" / "provisioning" / "datasources" / "datasources.yaml").read_text())
    uids = {d["uid"] for d in ds["datasources"]}
    for f in (MON / "grafana" / "dashboards").glob("*.json"):
        dash = json.loads(f.read_text())
        for p in dash["panels"]:
            if "datasource" in p:
                assert p["datasource"]["uid"] in uids, f"{f.name}: {p['title']}"


def test_targets_examples_have_no_real_addresses():
    for f in (MON / "prometheus" / "targets").glob("*.example.yaml"):
        text = f.read_text()
        for host in re.findall(r'"([\w.-]+):\d+"', text):
            assert host in {"host.docker.internal"} or host.endswith(".example") or ".example-tailnet." in host, f"{f.name}: {host}"
