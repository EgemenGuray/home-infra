WAN = {"HOME_WAN_IP": "203.0.113.10"}


def setup(stubs, my_ip="198.51.100.1", tcp="", udp=""):
    stubs.add("curl", f"echo {my_ip}")
    stubs.add("sudo", '"$@"')
    stubs.add("nmap", f'''if [[ "$*" == *-sU* ]]; then printf '%s\\n' "{udp}"; else printf '%s\\n' "{tcp}"; fi''')


def test_passes_with_zero_open_ports(stubs):
    setup(stubs)
    r = stubs.run("scripts/external-port-scan.sh", env=WAN)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "PASS" in r.stdout


def test_fails_on_an_open_tcp_port(stubs):
    setup(stubs, tcp="22/tcp   open  ssh")
    r = stubs.run("scripts/external-port-scan.sh", env=WAN)
    assert r.returncode == 1
    assert "FAIL: 1 TCP and 0 UDP" in r.stdout


def test_fails_on_an_open_udp_port(stubs):
    setup(stubs, udp="51820/udp open  unknown")
    r = stubs.run("scripts/external-port-scan.sh", env=WAN)
    assert r.returncode == 1
    assert "0 TCP and 1 UDP" in r.stdout


def test_open_filtered_udp_is_not_counted(stubs):
    setup(stubs, udp="500/udp open|filtered isakmp")
    r = stubs.run("scripts/external-port-scan.sh", env=WAN)
    assert r.returncode == 0


def test_refuses_to_scan_from_inside_the_house(stubs):
    setup(stubs, my_ip="203.0.113.10")
    r = stubs.run("scripts/external-port-scan.sh", env=WAN)
    assert r.returncode == 2
    assert not any(c.startswith("nmap") for c in stubs.calls())


def test_full_scan_covers_every_port(stubs):
    setup(stubs)
    stubs.run("scripts/external-port-scan.sh", "--full", env=WAN)
    assert any(c.startswith("nmap") and "-p-" in c for c in stubs.calls())


def test_needs_nmap(stubs):
    stubs.add("curl", "echo 198.51.100.1")
    r = stubs.run("scripts/external-port-scan.sh", env={**WAN, "PATH": str(stubs.bin)})
    assert r.returncode == 2
