import re


def test_services_are_served_on_the_tailnet_only(stubs):
    ts = stubs.add("tailscale", 'case "$1" in funnel) echo "No funnel config" ;; esac')
    r = stubs.run("services/tailscale-serve.sh", env={"TAILSCALE": str(ts)})
    assert r.returncode == 0, r.stderr
    serves = [c for c in stubs.calls() if c.startswith("tailscale serve --bg")]
    assert len(serves) == 2
    for c in serves:
        assert re.search(r"http://127\.0\.0\.1:\d+$", c), c
    assert not any(re.match(r"tailscale funnel (on|--bg|\d)", c) for c in stubs.calls())


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
