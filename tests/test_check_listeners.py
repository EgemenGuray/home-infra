HEADER = "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\n"


def lsof(stubs, rows):
    out = HEADER + "".join(f"{r}\n" for r in rows)
    stubs.add("lsof", f"cat <<'OUT'\n{out}OUT")


def test_passes_when_only_loopback_and_tailnet_listen(stubs):
    lsof(stubs, [
        "vaultward 10 hub 3u IPv4 0x1 0t0 TCP 127.0.0.1:8222 (LISTEN)",
        "com.docke 11 hub 3u IPv6 0x1 0t0 TCP [::1]:3001 (LISTEN)",
        "tailscale 12 root 3u IPv4 0x1 0t0 TCP 100.101.102.103:443 (LISTEN)",
        "tailscale 12 root 4u IPv6 0x1 0t0 TCP [fd7a:115c:a1e0::1]:443 (LISTEN)",
    ])
    r = stubs.run("scripts/check-listeners.sh")
    assert r.returncode == 0, r.stdout
    assert "OK: nothing listens" in r.stdout


def test_fails_on_a_lan_or_wildcard_listener(stubs):
    lsof(stubs, [
        "vaultward 10 hub 3u IPv4 0x1 0t0 TCP 127.0.0.1:8222 (LISTEN)",
        "sshd 13 root 3u IPv4 0x1 0t0 TCP *:22 (LISTEN)",
        "python3 14 hub 3u IPv4 0x1 0t0 TCP 192.0.2.5:8000 (LISTEN)",
    ])
    r = stubs.run("scripts/check-listeners.sh")
    assert r.returncode == 1
    assert "EXPOSED: sshd listens on *:22" in r.stdout
    assert "EXPOSED: python3 listens on 192.0.2.5:8000" in r.stdout


def test_addresses_just_outside_the_tailnet_range_are_exposed(stubs):
    # 100.64.0.0/10 is 100.64 to 100.127; 100.128 and 100.63 are ordinary addresses.
    lsof(stubs, [
        "a 1 u 3u IPv4 0x1 0t0 TCP 100.128.0.1:80 (LISTEN)",  # gitleaks:allow (made-up boundary address)
        "b 2 u 3u IPv4 0x1 0t0 TCP 100.63.0.1:80 (LISTEN)",  # gitleaks:allow (made-up boundary address)
    ])
    r = stubs.run("scripts/check-listeners.sh")
    assert r.returncode == 1
    assert r.stdout.count("EXPOSED") == 2


def test_lan_services_needed_by_the_ha_vm_are_allowed(stubs):
    lsof(stubs, [
        "mDNSRespo 1 root 3u IPv4 0x1 0t0 TCP *:5353 (LISTEN)",
        "QEMULaunc 2 hub 3u IPv4 0x1 0t0 TCP *:8123 (LISTEN)",
    ])
    r = stubs.run("scripts/check-listeners.sh")
    assert r.returncode == 0
    assert "allowed (LAN): QEMULaunc" in r.stdout


def test_allowed_processes_can_be_narrowed(stubs):
    lsof(stubs, ["QEMULaunc 2 hub 3u IPv4 0x1 0t0 TCP *:8123 (LISTEN)"])
    r = stubs.run("scripts/check-listeners.sh", env={"ALLOW_PROC_RE": "^mDNSRespo"})
    assert r.returncode == 1
