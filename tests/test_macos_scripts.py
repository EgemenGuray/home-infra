"""The macOS scripts run on Linux here against stubs: dry runs must change nothing."""
import os
import plistlib

import pytest

from conftest import ROOT

MUTATING = ("pmset", "systemsetup", "socketfilterfw", "launchctl", "defaults", "cupsctl",
            "sysadminctl", "kickstart", "install", "sudo")


def darwin(stubs):
    stubs.add("uname", "echo Darwin")


def test_baseline_dry_run_changes_nothing(stubs):
    darwin(stubs)
    for cmd in MUTATING:
        stubs.add(cmd)
    stubs.add("networksetup", "printf 'Hardware Port: Wi-Fi\\nDevice: en1\\n'")
    r = stubs.run("macos/02-server-baseline.sh", "--dry-run")
    assert r.returncode == 0, r.stderr
    assert [c for c in stubs.calls() if not c.startswith("uname")] == ["networksetup -listallhardwareports"]
    for expected in ("+ pmset -a sleep 0", "autorestart 1", "--setstealthmode on", "-setremotelogin off",
                     "AutomaticallyInstallMacOSUpdates -bool false", "-setairportpower en1 off"):
        assert expected in r.stdout, expected


def test_baseline_refuses_other_systems(stubs):
    stubs.add("uname", "echo Linux")
    r = stubs.run("macos/02-server-baseline.sh", "--dry-run")
    assert r.returncode == 1


@pytest.mark.skipif(os.geteuid() == 0, reason="checks the non-root refusal")
def test_baseline_needs_root_when_not_dry(stubs):
    darwin(stubs)
    r = stubs.run("macos/02-server-baseline.sh")
    assert r.returncode == 1 and "sudo" in r.stderr


def test_accounts_dry_run_creates_no_user(stubs, tmp_path):
    darwin(stubs)
    stubs.add("id", "exit 1")
    stubs.add("dseditgroup", "exit 1")
    stubs.add("sysadminctl")
    users = tmp_path / "Users"
    (users / "hub").mkdir(parents=True)
    r = stubs.run("macos/03-accounts.sh", "--dry-run", env={"USERS_DIR": str(users)})
    assert r.returncode == 0, r.stdout + r.stderr
    assert not any(c.startswith("sysadminctl") for c in stubs.calls())
    assert "OK: no Apple ID or Chrome profile" in r.stdout


def test_accounts_flags_a_chrome_profile(stubs, tmp_path):
    darwin(stubs)
    stubs.add("id")
    stubs.add("dseditgroup", "exit 1")
    users = tmp_path / "Users"
    (users / "hub/Library/Application Support/Google/Chrome/Default").mkdir(parents=True)
    r = stubs.run("macos/03-accounts.sh", "--dry-run", env={"USERS_DIR": str(users)})
    assert r.returncode == 1
    assert "FAIL: hub has a Chrome profile" in r.stdout


def test_accounts_dry_run_keeps_admin_rights_but_warns(stubs, tmp_path):
    darwin(stubs)
    stubs.add("id")
    stubs.add("dseditgroup", 'case "$*" in *checkmember*) exit 0 ;; esac')
    (tmp_path / "Users").mkdir()
    r = stubs.run("macos/03-accounts.sh", "--dry-run", env={"USERS_DIR": str(tmp_path / "Users")})
    assert "WARNING: hub is an admin" in r.stdout
    assert not any("-d hub" in c for c in stubs.calls())


def test_install_launchd_dry_run(stubs):
    stubs.add("dscl", "echo 'NFSHomeDirectory: /Users/hub'")
    stubs.add("id", "echo 501")
    stubs.add("launchctl", "exit 1")
    for cmd in ("install", "sudo"):
        stubs.add(cmd)
    r = stubs.run("macos/install-launchd.sh", "--dry-run")
    assert r.returncode == 0, r.stderr
    assert "home.hub.ha-vm.plist /Users/hub/Library/LaunchAgents/" in r.stdout
    assert not any(c.startswith(("install", "sudo")) for c in stubs.calls())


def test_compromise_check_refuses_other_systems(stubs):
    stubs.add("uname", "echo Linux")
    assert stubs.run("macos/01-compromise-check.sh").returncode == 1


def watchdog(stubs, status):
    utm = stubs.add("utmctl", f'[[ "$1" == status ]] && echo {status}; exit 0')
    stubs.add("pgrep")
    stubs.add("open")
    r = stubs.run("macos/launchd/ha-vm-watchdog.sh", env={"UTMCTL": str(utm)})
    assert r.returncode == 0, r.stdout
    return [c for c in stubs.calls() if c.startswith("utmctl") and not c.startswith("utmctl status")]


def test_watchdog_leaves_a_running_vm_alone(stubs):
    assert watchdog(stubs, "started") == []


def test_watchdog_resumes_a_paused_vm(stubs):
    assert watchdog(stubs, "paused") == ["utmctl resume Home Assistant"]


def test_watchdog_starts_a_stopped_vm(stubs):
    assert watchdog(stubs, "stopped") == ["utmctl start Home Assistant"]


def test_watchdog_launch_agent_points_at_the_installed_script():
    plist = plistlib.load(open(ROOT / "macos/launchd/home.hub.ha-vm.plist", "rb"))
    assert plist["ProgramArguments"] == ["/usr/local/libexec/home-hub/ha-vm-watchdog.sh"]
    assert plist["RunAtLoad"] is True and plist["StartInterval"] == 120
