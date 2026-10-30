# home-infra

Setup and security for the house hub: the hub Mac (Mac mini), the TP-Link network and remote access. Covers roadmap epics **E0.1** (network, static IP, Tailscale, lockdown), **E0.2** (always-on house hub), **E1.3** (agent egress routes), **E2.1** and **E2.6** (Mac Studio and cross-monitoring) and **E3.2** (resilience).

Nothing here opens an inbound port. Every service binds to `127.0.0.1` on the Mac and is published only to the tailnet with `tailscale serve`.

## Two setups

The house runs the same way in both setups. The difference is where the AI side runs.

| | **Mac mini only** | **Mac mini + Mac Studio** |
|---|---|---|
| Mac mini (hub Mac) | Home Assistant VM, Zigbee, Vaultwarden, Uptime Kuma, Tailscale, egress routes, and the agent service with NATS (cloud models only) | Home Assistant VM, Zigbee, Vaultwarden, Uptime Kuma, Tailscale, egress routes and the credential broker. Nothing else. |
| Mac Studio | Not present | Agent service, NATS, harness, local models, voice server, Docker workspaces and macOS VMs |
| Agent workspaces | A rented Linux VM on the tailnet (`home-agents/deploy/workspace-host/`) | On the Studio; the rented VM is cancelled |
| Monitoring | Prometheus, Alertmanager, ntfy, Loki and Grafana on the hub Mac, next to Uptime Kuma | Alerting (Prometheus, Alertmanager, ntfy) stays on the hub Mac; Loki and Grafana move to the Studio; exporters and security checks on both; Uptime Kuma on each watching the other |
| UPS shutdown | The hub Mac at 20% | The Studio at 50% first, the hub Mac at 20% |
| Install | `docs/hands-on-checklist.md` | `docs/hands-on-checklist.md`, then `docs/studio-checklist.md` |

Start with the Mac mini only. Adding the Studio later changes nothing on the hub Mac except monitoring and the UPS order, so no reinstall is needed.

## Layout

The **Setup** column says where each piece applies: **Both**, or **+ Studio** for the Mac mini + Mac Studio setup only.

| Path | What it does | Setup | Roadmap |
|---|---|---|---|
| `macos/01-compromise-check.sh` | Read-only audit of a Mac that may have been compromised: persistence, profiles, users, SSH keys, sharing services. Writes a report you review before deciding to reinstall. | Both | S0.2.1 |
| `macos/02-server-baseline.sh` | Never sleep, restart after power loss or freeze, firewall in stealth mode, sharing services off, security updates on and macOS upgrades off. | Both | S0.2.2, S0.1.5 |
| `macos/03-accounts.sh` | Creates the standard `hub` service user and checks that no Apple ID or Messages is signed in. | Both | S0.2.2, S0.1.5 |
| `macos/launchd/` + `macos/install-launchd.sh` | Starts the Home Assistant VM (UTM) at boot and keeps it running. | Both | S0.2.2, S0.2.3 |
| `services/compose.yaml` | Vaultwarden and Uptime Kuma, both on localhost only. | Both | S0.1.5, S0.2.5 |
| `services/tailscale-serve.sh` | Publishes those services to the tailnet over HTTPS. | Both | S0.1.4 |
| `tailscale/policy.hujson.example` | Tailnet access rules: only your phone and laptop reach admin ports. | Both | S0.1.4, S0.1.5 |
| `scripts/check-listeners.sh` | Run on the hub Mac: fails if anything listens on a non-loopback, non-tailnet address. | Both | S0.1.5 |
| `scripts/external-port-scan.sh` | Run from outside the house: scans the static IP and expects zero open ports. | Both | S0.1.5 |
| `services/monitoring/` | Prometheus, Grafana, Loki and Alertmanager with alarms to your phone (HA push, ntfy fallback). Its README says what runs on which Mac in each setup. | Both | E0.2, E2.6 |
| `macos/install-monitoring.sh` + `macos/security-checks.sh` | node_exporter and 5-minute checks for failed logins, exposed ports, Funnel, firewall and Remote Login. On the Mac mini; on the Studio too in the second setup. | Both | S0.1.5, E2.6 |
| `services/monitoring/studio/` | The Studio's part of monitoring: Loki and Grafana move here, plus its own exporters. | + Studio | E2.6 |
| `docs/studio-checklist.md` | Mac Studio bring-up: same baseline, FileVault on, shuts down first on the UPS. | + Studio | E2.1 |
| `docs/phase-3.md` | Backup internet line and a hot spare. | Both | E3.2 |
| `docs/hands-on-checklist.md` | Every step that needs your hands on the hub Mac, the router or your accounts, in order. | Both | E0.1, E0.2 |
| `docs/router.md` | TP-Link settings to apply and verify, including the Phase 1 Lab network. | Both | S0.1.1 to S0.1.3, S1.3.3 |
| `services/egress/` | Agent egress routes: home proxy and one Gluetun NordVPN tunnel per country, with kill switch, published to the tailnet only. | Both | S1.3.1, S1.3.2 |
| `scripts/check-routes.sh` | Checks each route's exit IP and country; fails on any mismatch. | Both | S1.3.5 |

## Order of work

Steps 1 to 6 are the same in both setups.

1. `docs/hands-on-checklist.md` part A (accounts, from a clean device).
2. On the hub Mac: `sudo ./macos/01-compromise-check.sh`, read the report, reinstall unless it is clean.
3. After the clean install: `sudo ./macos/02-server-baseline.sh`, then `sudo ./macos/03-accounts.sh`.
4. Install Tailscale (standalone package), UTM and OrbStack; create the HA VM; `sudo ./macos/install-launchd.sh`.
5. `cp services/.env.example services/.env`, fill it, `docker compose -f services/compose.yaml up -d`, then `./services/tailscale-serve.sh`.
6. `./scripts/check-listeners.sh` on the hub Mac and `./scripts/external-port-scan.sh` from mobile data. Both must pass.
7. **Mac mini only:** for agents, set up `services/egress/` here and the rented workspace VM from home-agents. **Mac mini + Mac Studio:** set up `services/egress/` here, then follow `docs/studio-checklist.md`, which also switches `services/monitoring/` to its Mac mini + Mac Studio setup.
8. Monitoring and alarms: follow `services/monitoring/README.md` for your setup.

Every script supports `--dry-run` where it changes settings, and prints what it would do.

## Tests

`pip install -r requirements-test.txt && pytest` runs the scripts on Linux against stub commands, so it needs no Mac, router or network. The tests cover these points:

- The port, route and listener checks fail when they should.
- Dry runs change nothing.
- The VM watchdog behaves correctly.
- Every published port binds to localhost, and nothing turns on Tailscale Funnel.

CI runs them on every push, alongside shellcheck.

## Rules

See `SECURITY.md`. Run `pre-commit install` after cloning.
