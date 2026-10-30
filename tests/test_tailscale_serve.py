import re


def test_services_are_served_on_the_tailnet_only(stubs):
    ts = stubs.add("tailscale", 'case "$1" in funnel) echo "No funnel config" ;; esac')
    r = stubs.run("services/tailscale-serve.sh", env={"TAILSCALE": str(ts)})
    assert r.returncode == 0, r.stderr
    serves = [c for c in stubs.calls() if c.startswith("tailscale serve --bg")]
    # Mac mini only: Vaultwarden, Uptime Kuma, ntfy and Grafana.
    assert [re.search(r"--https=(\d+)", c).group(1) for c in serves] == ["8443", "3443", "2443", "4443"]
    for c in serves:
        assert re.search(r"http://127\.0\.0\.1:\d+$", c), c
    assert not any(re.match(r"tailscale funnel (on|--bg|\d)", c) for c in stubs.calls())


def test_with_studio_moves_grafana_and_publishes_alerting(stubs):
    ts = stubs.add("tailscale", 'case "$1" in funnel) echo "No funnel config" ;; esac')
    r = stubs.run("services/tailscale-serve.sh", "--with-studio", env={"TAILSCALE": str(ts)})
    assert r.returncode == 0, r.stderr
    serves = [c for c in stubs.calls() if c.startswith("tailscale serve --bg")]
    assert [re.search(r"--https=(\d+)", c).group(1) for c in serves] == ["8443", "3443", "2443", "9443", "9493"]
    assert "tailscale serve --https=4443 off" in stubs.calls()
    assert all(re.search(r"http://127\.0\.0\.1:\d+$", c) for c in serves)


def test_studio_serves_monitoring_to_the_tailnet_only(stubs):
    ts = stubs.add("tailscale", 'case "$1" in funnel) echo "No funnel config" ;; esac')
    r = stubs.run("services/monitoring/studio/studio-serve.sh", env={"TAILSCALE": str(ts)})
    assert r.returncode == 0, r.stderr
    serves = [c for c in stubs.calls() if c.startswith("tailscale serve --bg")]
    assert [re.search(r"--https=(\d+)", c).group(1) for c in serves] == ["4443", "3143", "9143", "9180"]
    assert all(re.search(r"http://127\.0\.0\.1:\d+$", c) for c in serves)


def test_fails_when_funnel_is_on(stubs):
    ts = stubs.add("tailscale", 'case "$1" in funnel) echo "Funnel on: https://x" ;; esac')
    r = stubs.run("services/tailscale-serve.sh", env={"TAILSCALE": str(ts)})
    assert r.returncode == 1
    assert "Funnel is on" in r.stderr


def test_egress_routes_are_tcp_to_localhost(stubs):
    ts = stubs.add("tailscale")
    r = stubs.run("services/egress/tailscale-serve-egress.sh", env={"TAILSCALE": str(ts)})
    assert r.returncode == 0
    serves = [c for c in stubs.calls() if "--tcp=" in c]
    assert [re.search(r"--tcp=(\d+)", c).group(1) for c in serves] == ["8888", "8889", "8890"]
    assert all("tcp://127.0.0.1:" in c for c in serves)
