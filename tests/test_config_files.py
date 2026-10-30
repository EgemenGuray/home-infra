"""Security invariants in the config files: nothing binds outside localhost, nothing uses funnel."""
import re

import pytest
import yaml

from conftest import ROOT

COMPOSE = sorted(ROOT.glob("services/**/compose.yaml"))


@pytest.mark.parametrize("path", COMPOSE, ids=lambda p: str(p.relative_to(ROOT)))
def test_every_published_port_binds_to_localhost(path):
    services = yaml.safe_load(path.read_text())["services"]
    for name, svc in services.items():
        for port in svc.get("ports", []):
            assert str(port).startswith("127.0.0.1:"), f"{name} publishes {port}"
        assert svc.get("network_mode") != "host" or not svc.get("ports"), name


@pytest.mark.parametrize("path", COMPOSE, ids=lambda p: str(p.relative_to(ROOT)))
def test_services_restart_on_their_own(path):
    services = yaml.safe_load(path.read_text())["services"]
    for name, svc in services.items():
        assert svc.get("restart") in ("unless-stopped", "always"), name


def test_no_script_turns_on_funnel():
    for path in ROOT.glob("**/*.sh"):
        for line in path.read_text().splitlines():
            if line.lstrip().startswith("#"):
                continue
            # Only `funnel status` and `funnel reset` are allowed; anything else would expose a port.
            for m in re.finditer(r"""(?:\$TS"?|\btailscale)\s+funnel\s+([^\s"']+)""", line):
                assert m.group(1) in ("status", "reset"), f"{path}: {line}"


def test_tailnet_policy_example_has_no_wildcard_access():
    text = (ROOT / "tailscale/policy.hujson.example").read_text()
    assert '"*:*"' not in text
    assert '"funnel"' not in text  # no node attribute that would allow funnel


def test_example_files_hold_no_real_values():
    for path in ROOT.glob("**/*.example*"):
        text = path.read_text()
        for ip in re.findall(r"\b(\d{1,3}(?:\.\d{1,3}){3})\b", text):
            assert ip.startswith(("127.", "100.64.", "192.0.2.", "198.51.100.", "203.0.113.", "0.", "10.", "192.168.")), f"{path}: {ip}"
