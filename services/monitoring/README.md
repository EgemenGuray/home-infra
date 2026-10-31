# Monitoring, logs and alarms

Prometheus (metrics), Grafana (dashboards), Loki (logs) and Alertmanager (alarms), all in Docker,
next to Uptime Kuma. Alarms reach your phone as Home Assistant pushes, with self-hosted ntfy as the
fallback. Nothing is reachable from the LAN or the internet: every port binds to `127.0.0.1` and
only Grafana and ntfy are published, to the tailnet, with `tailscale serve`.

There are two setups. Pick the one that matches the house today.

| | **Mac mini only** | **Mac mini + Mac Studio** |
|---|---|---|
| Mac mini, Docker | Prometheus, Alertmanager, ntfy, cAdvisor, Alloy, **Loki, Grafana** | Prometheus, Alertmanager, ntfy, cAdvisor, Alloy |
| Mac mini, native | node_exporter, security checks | node_exporter, security checks |
| Mac Studio, Docker | (none) | **Loki, Grafana**, cAdvisor, Alloy (`studio/compose.yaml`) |
| Mac Studio, native | (none) | node_exporter, security checks |
| Mac mini `.env` | `COMPOSE_PROFILES=ui` | `COMPOSE_PROFILES=` and `LOKI_URL` set to the Studio |
| Prometheus targets | Mac mini only | Mac mini, plus the Studio in `targets/node.yaml` and `targets/cadvisor.yaml`; the agent service in `targets/home-agents.yaml` moves to the Studio in Phase 2 |
| Tailnet ports | Mac mini: Grafana 4443, ntfy 2443 | Mac mini: ntfy 2443, Prometheus 9443, Alertmanager 9493. Studio: Grafana 4443, Loki 3143, node_exporter 9143, cAdvisor 9180 |
| Retention | Prometheus 15 days or 1 GB. Loki 7 days | Prometheus the same. Loki 30 days on the Studio |
| Memory limits | About 1.1 GB on the Mac mini | About 0.7 GB on the Mac mini, about 1.8 GB on the Studio |

Alerting always stays on the Mac mini. The Studio uses FileVault and waits for an unlock after a
power cut, so anything that must wake you (Home Assistant down, an exposed port, the spend cap)
can't depend on it. In the second setup, if the Studio is down you lose log search and dashboards
until it is back, and the Mac mini alerts you that the Studio is down.

## What is watched

| Area | Source | Alerts (in `prometheus/rules/`, `loki/rules/`) |
|---|---|---|
| Host health | node_exporter on each Mac | HostDown, HostDiskLow and HostDiskCritical, HostMemoryPressure (swap), HostCpuBusy, HostRebooted |
| Docker containers | cAdvisor | CoreContainerMissing (vault, Uptime Kuma, Alertmanager), ContainerRestarting, ContainerNearMemoryLimit |
| Home Assistant | HA's `/api/prometheus` | HomeAssistantDown (goes to ntfy), HomeAssistantEntitiesUnavailable |
| Uptime Kuma | its `/metrics` | UptimeKumaCheckDown, UptimeKumaDown |
| Agent harness | home-agents `/metrics` | AgentServiceDown, AgentTasksFailing, ApprovalWaiting, ModelProviderUnavailable |
| Spend cap (CAD) | home-agents `/metrics` | SpendDailyAlert, SpendNearMonthlyCap (80%), SpendCapReached |
| Failed logins | `macos/security-checks.sh` (unified log), Vaultwarden logs in Loki, HA's own login notice | MacFailedLogins, MacFailedLoginsBurst, VaultwardenFailedLogin(Burst), VaultwardenAdminAccess; HA logins in home-assistant-config `packages/monitoring.yaml` |
| Port exposure | `security-checks.sh` every 5 minutes | PortExposed, TailscaleFunnelOn, FirewallStealthOff, RemoteLoginEnabled, SecurityChecksStale |
| The stack itself | Alertmanager, Prometheus, Alloy | AlertDeliveryFailing (goes to ntfy), PrometheusRuleFailures, LogShippingFailing |

The scan from outside the house (`scripts/external-port-scan.sh`) still runs by hand from mobile
data once a month; nothing inside the house can see the house from the internet.

## How alarms reach you

- **Normal path:** Alertmanager posts to a Home Assistant webhook; HA sends `notify.owner_phone`.
  Critical alerts ring through quiet hours; warnings are silent during quiet hours.
- **Fallback:** ntfy on the tailnet. It gets a second copy of every critical alert, and it is the
  only path for alerts about HA itself or about pushes failing. Install the ntfy app, subscribe to
  `home-alerts` on your tailnet URL, and log in.
- **Who watches the watcher:** add Uptime Kuma HTTP checks for Prometheus (`/-/ready`),
  Alertmanager (`/-/healthy`) and Grafana (`/api/health`), with Kuma's own ntfy notification.

## Set up

On the Mac mini (both setups):

1. `brew install node_exporter` as your admin user (don't start the brew service), then
   `sudo ./macos/install-monitoring.sh`.
2. In home-assistant-config: add `monitoring_webhook_id` to `secrets.yaml` (packages/monitoring.yaml
   reads it), restart HA, and make a dedicated HA user with a long-lived token for Prometheus.
3. `cd services/monitoring && ./setup.sh`, then fill `.env`, `prometheus/targets/*.yaml` and every
   file in `secrets/` from the vault. Real values are kept in the private config repo.
4. ntfy users, once: `docker compose run --rm ntfy user add --role=admin <you>`, then
   `docker compose run --rm ntfy user add alertmanager`,
   `docker compose run --rm ntfy access alertmanager home-alerts write-only` and
   `docker compose run --rm ntfy token add alertmanager`; the token goes in `secrets/ntfy-token`.
5. `docker compose up -d`, then `../tailscale-serve.sh` (add `--with-studio` in the second setup).
6. `./scripts/check-listeners.sh` must still pass.

Mac mini + Mac Studio, additionally:

1. On the Studio: `brew install node_exporter`, `sudo ./macos/install-monitoring.sh`.
2. `cp studio/.env.example studio/.env` and fill it; `./setup.sh` for `secrets/grafana-admin-password`.
3. `docker compose -f studio/compose.yaml --env-file studio/.env up -d`, then `./studio/studio-serve.sh`.
4. On the Mac mini: set `COMPOSE_PROFILES=` and `LOKI_URL` in `.env`, fill `targets/node.yaml` and
   `targets/cadvisor.yaml` with the Studio, `docker compose up -d --remove-orphans`, and
   `../tailscale-serve.sh --with-studio`.
5. Apply the monitoring line of `tailscale/policy.hujson.example` in the Tailscale admin console.

## Tests

`tests/monitoring/run.sh` checks every config with the real tools (promtool, amtool, Loki,
Alloy, docker compose for both setups), runs unit tests for each alert rule
(`tests/monitoring/rules.test.yml`) and for `security-checks.sh`, and policy tests (every port on
localhost, every alert has a severity and summary, no inline secrets). CI runs it on every push.
