# home-infra

Setup and security for the house hub: the hub Mac (Mac mini), the TP-Link network and remote access. Covers roadmap epics **E0.1** (network, static IP, Tailscale, lockdown), **E0.2** (always-on house hub), **E1.3** (agent egress routes), **E2.1** and **E2.6** (Mac Studio and cross-monitoring) and **E3.2** (resilience).

Nothing here opens an inbound port. Every service binds to `127.0.0.1` on the Mac and is published only to the tailnet with `tailscale serve`.

## Layout

| Path | What it does | Roadmap |
|---|---|---|
| `macos/01-compromise-check.sh` | Read-only audit of a Mac that may have been compromised: persistence, profiles, users, SSH keys, sharing services. Writes a report you review before deciding to reinstall. | S0.2.1 |
| `macos/02-server-baseline.sh` | Never sleep, restart after power loss or freeze, firewall in stealth mode, sharing services off, security updates on and macOS upgrades off. | S0.2.2, S0.1.5 |
| `macos/03-accounts.sh` | Creates the standard `hub` service user and checks that no Apple ID or Messages is signed in. | S0.2.2, S0.1.5 |
| `macos/launchd/` + `macos/install-launchd.sh` | Starts the Home Assistant VM (UTM) at boot and keeps it running. | S0.2.2, S0.2.3 |
| `services/compose.yaml` | Vaultwarden and Uptime Kuma, both on localhost only. | S0.1.5, S0.2.5 |
| `services/tailscale-serve.sh` | Publishes those services to the tailnet over HTTPS. | S0.1.4 |
| `tailscale/policy.hujson.example` | Tailnet access rules: only your phone and laptop reach admin ports. | S0.1.4, S0.1.5 |
| `scripts/check-listeners.sh` | Run on the hub Mac: fails if anything listens on a non-loopback, non-tailnet address. | S0.1.5 |
| `scripts/external-port-scan.sh` | Run from outside the house: scans the static IP and expects zero open ports. | S0.1.5 |
| `services/monitoring/` | Beszel host dashboards and a second Uptime Kuma, so the two Macs watch each other. | E2.6 |
| `docs/studio-checklist.md` | Mac Studio bring-up: same baseline, FileVault on, shuts down first on the UPS. | E2.1 |
| `docs/phase-3.md` | Backup internet line and a hot spare. | E3.2 |
| `docs/hands-on-checklist.md` | Every step that needs your hands on the hub Mac, the router or your accounts, in order. | E0.1, E0.2 |
| `docs/router.md` | TP-Link settings to apply and verify, including the Phase 1 Lab network. | S0.1.1 to S0.1.3, S1.3.3 |
| `services/egress/` | Agent egress routes: home proxy and one Gluetun NordVPN tunnel per country, with kill switch, published to the tailnet only. | S1.3.1, S1.3.2 |
| `scripts/check-routes.sh` | Checks each route's exit IP and country; fails on any mismatch. | S1.3.5 |

## Order of work

1. `docs/hands-on-checklist.md` part A (accounts, from a clean device).
2. On the hub Mac: `sudo ./macos/01-compromise-check.sh`, read the report, reinstall unless it is clean.
3. After the clean install: `sudo ./macos/02-server-baseline.sh`, then `sudo ./macos/03-accounts.sh`.
4. Install Tailscale (standalone package), UTM and OrbStack; create the HA VM; `sudo ./macos/install-launchd.sh`.
5. `cp services/.env.example services/.env`, fill it, `docker compose -f services/compose.yaml up -d`, then `./services/tailscale-serve.sh`.
6. `./scripts/check-listeners.sh` on the hub Mac and `./scripts/external-port-scan.sh` from mobile data. Both must pass.

Every script supports `--dry-run` where it changes settings, and prints what it would do.

## Rules

See `SECURITY.md`. Run `pre-commit install` after cloning.
