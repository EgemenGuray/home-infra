# Mac Studio checklist (Phase 2, E2.1)

Only for the **Mac mini + Mac Studio** setup. With the Mac mini only, skip this file: the agent service runs on the hub Mac and workspaces on a rented VM.

Same baseline as the hub Mac, with three differences: FileVault is **on**, the UPS shuts it down **first**, and it holds agent data, so it never gets personal accounts either.

| Runs on | After this checklist |
|---|---|
| Hub Mac (unchanged) | Home Assistant VM, Zigbee, Vaultwarden, Uptime Kuma, Tailscale, egress routes, credential broker |
| Moves to the Studio | Agent service and NATS (from `home-agents/deploy/hub/`), harness |
| New on the Studio | Local models (MLX), voice server (LiveKit, Whisper, Piper), SearXNG, Docker workspaces, Tart macOS VMs |
| Retired | The rented workspace VM, after a week of both running |

1. Confirm the memory option and Apple Canada's price in CAD before ordering (256 GB suggested).
2. Set up as new with no Apple ID. Admin password from the vault. Wired Ethernet on Main with a DHCP reservation.
3. `sudo ./macos/02-server-baseline.sh` and `sudo ./macos/03-accounts.sh` (same scripts as the hub Mac).
4. Turn **on** FileVault (System Settings > Privacy & Security). Planned restarts: `sudo fdesetup authrestart`. After a power cut the Studio waits for your unlock, alerts you, and voice falls back to the hub Mac.
5. Tailscale standalone package, `tag:server`, `sudo tailscaled install-system-daemon`.
6. OrbStack; Tart for macOS VM workspaces; the MLX venv for the local model (home-agents `deploy/studio/launchd/`).
7. UPS settings: the Studio shuts down at about **50%**, the hub Mac at 20%, so the house keeps running longest.
8. `services/monitoring/compose.yaml` on both Macs; Uptime Kuma on each watching the other.
9. Monthly maintenance window: update one Mac at a time, never both on the same day, after a fresh HA backup.
10. Power test: pull the plug. The Studio waits for unlock and alerts you; voice falls back to Assist on the hub Mac; services return after unlock.
11. Rehearse restoring the HA backup onto the Studio as a temporary host, then put a monthly restore test on the calendar.
