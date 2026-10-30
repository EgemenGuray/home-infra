import shutil

from conftest import ROOT

ROUTES = """home:       {port: 8888, country: CA, ip: "203.0.113.10"}
nord-us-ny: {port: 8889, country: US}
"""


def curl_answers(stubs, by_port):
    """Fake curl: answers per proxy port; an empty answer means the tunnel is down."""
    cases = "\n".join(f'  *127.0.0.1:{p}*) {"echo " + repr(a) if a else "exit 7"} ;;' for p, a in by_port.items())
    stubs.add("curl", f'case "$*" in\n{cases}\nesac')


def write_routes(stubs, text=ROUTES):
    (stubs.cwd / "routes.yaml").write_text(text)


def info(ip, country):
    return f'{{"ip": "{ip}", "country": "{country}"}}'


def test_all_routes_match(stubs):
    write_routes(stubs)
    curl_answers(stubs, {8888: info("203.0.113.10", "CA"), 8889: info("198.51.100.7", "US")})
    r = stubs.run("scripts/check-routes.sh", "routes.yaml")
    assert r.returncode == 0, r.stdout
    assert "ok   home: CA" in r.stdout and "ok   nord-us-ny: US" in r.stdout


def test_wrong_country_fails(stubs):
    write_routes(stubs)
    curl_answers(stubs, {8888: info("203.0.113.10", "CA"), 8889: info("198.51.100.7", "CA")})
    r = stubs.run("scripts/check-routes.sh", "routes.yaml")
    assert r.returncode == 1
    assert "FAIL nord-us-ny: exits from CA, expected US" in r.stdout


def test_wrong_home_ip_fails_without_printing_it(stubs):
    write_routes(stubs)
    curl_answers(stubs, {8888: info("198.51.100.99", "CA"), 8889: info("198.51.100.7", "US")})
    r = stubs.run("scripts/check-routes.sh", "routes.yaml")
    assert r.returncode == 1
    assert "FAIL home: unexpected exit IP" in r.stdout
    assert "198.51.100.99" not in r.stdout


def test_dead_tunnel_fails_closed(stubs):
    write_routes(stubs)
    curl_answers(stubs, {8888: info("203.0.113.10", "CA"), 8889: ""})
    r = stubs.run("scripts/check-routes.sh", "routes.yaml")
    assert r.returncode == 1
    assert "FAIL nord-us-ny: no answer" in r.stdout


def test_vpn_routes_use_proxy_auth_but_home_does_not(stubs):
    write_routes(stubs)
    (stubs.cwd / "services/egress").mkdir(parents=True)
    (stubs.cwd / "services/egress/.env").write_text("PROXY_USER=u\nPROXY_PASSWORD=p\n")
    curl_answers(stubs, {8888: info("203.0.113.10", "CA"), 8889: info("198.51.100.7", "US")})
    stubs.run("scripts/check-routes.sh", "routes.yaml")
    calls = stubs.calls()
    assert any("127.0.0.1:8889" in c and "--proxy-user u:p" in c for c in calls)
    assert not any("127.0.0.1:8888" in c and "--proxy-user" in c for c in calls)


def test_missing_routes_file_exits_2(stubs):
    r = stubs.run("scripts/check-routes.sh", "nope.yaml")
    assert r.returncode == 2


def test_example_routes_file_parses(stubs):
    shutil.copy(ROOT / "services/egress/routes.example.yaml", stubs.cwd / "routes.yaml")
    curl_answers(stubs, {8888: info("203.0.113.10", "CA"), 8889: info("x", "US"), 8890: info("x", "DE")})
    r = stubs.run("scripts/check-routes.sh", "routes.yaml")
    assert r.returncode == 0, r.stdout
    assert r.stdout.count("ok   ") == 3
