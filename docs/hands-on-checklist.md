# Hands-on checklist (Phase 0)

Steps that need you physically at the hub Mac, the router, or signed in to your own accounts. Code in this repo does the rest. Do them in order; tick them in the roadmap as you go.

Never run any of this on a personal laptop as a server step: personal machines are only clients (Bitwarden app, Tailscale).

This checklist is the same for both setups (see the README): the hub Mac is set up identically whether or not a Mac Studio joins later. **Mac mini only:** you are done after part D. **Mac mini + Mac Studio:** after part D, continue with `studio-checklist.md`. The hub Mac's settings don't change, but the UPS order and monitoring do.

## A. Accounts, from a clean device (S0.1.5, S0.1.6). Do this first.

1. From your phone or a device you trust, review the password and 2FA on your main email, shopping, Apple and banking accounts.
2. On each of those accounts: sign out all other sessions and remove unknown devices.
3. Email: check forwarding rules, filters, app passwords, recovery email and phone.
4. Shopping accounts: check saved addresses and payment methods.
5. Buy two hardware security keys (for example YubiKey 5C NFC, about CA$75 each). Add passkeys or keys to your main accounts; remove SMS 2FA where allowed.
6. iPhone: Settings > Messages > Text Message Forwarding: turn off every Mac.
7. Cards: alerts for every transaction and order notifications to your phone.

## B. The hub Mac (Mac mini), at the machine (S0.2.1 to S0.2.3)

1. Clone this repo onto a USB stick from another machine, or download it over the browser once the hub Mac has network.
2. `sudo ./macos/01-compromise-check.sh` and read the report.
3. Reinstall unless the report is clean (recommended either way): System Settings > General > Transfer or Reset > Erase All Content and Settings. Set up as new: **no Apple ID, no Migration Assistant, no Time Machine restore**. Admin account password from the vault.
4. Plug in wired Ethernet on the Main network; confirm the DHCP reservation.
5. `sudo ./macos/02-server-baseline.sh`, then set the three Energy switches in System Settings by hand.
6. `sudo ./macos/03-accounts.sh`; set automatic login to `hub`. Log in as `hub` once and add a login item that locks the screen: Shortcuts app > new shortcut with "Lock Screen", add it to Login Items.
7. Install Tailscale (standalone package from tailscale.com), sign in with your account, `sudo tailscaled install-system-daemon`, tag the node `tag:server`, turn off key expiry for it. Advertise the home subnet route and approve it in the admin console.
8. Paste `tailscale/policy.hujson.example` into the Tailscale admin console with your real email.
9. Install UTM, create the Home Assistant OS VM (aarch64 image, 3 GB RAM, bridged network on the Ethernet port), set it to start with UTM, then `sudo ./macos/install-launchd.sh`.
10. Buy and plug in the Zigbee/Thread stick (SMLIGHT SLZB-06M is network-based and avoids USB passthrough; or a Sonoff dongle passed through in UTM).
11. Install OrbStack; `cd services && cp .env.example .env`, set `VAULT_DOMAIN`, `docker compose up -d`, `./tailscale-serve.sh`.
12. Create your vault account: `VAULT_SIGNUPS_ALLOWED=true docker compose up -d vaultwarden`, sign up in the Bitwarden app on your phone (server URL = the vault address), then `docker compose up -d vaultwarden` again so sign-ups close. Import your browser's password export, delete the export file, turn off browser password saving.
13. Uptime Kuma (tailnet address, port 3443): add checks for HA, Vaultwarden, Tailscale and an internet target.
14. `./scripts/check-listeners.sh` must pass.
15. Buy a UPS (CA$140 to 285) for the hub Mac, the router and the Zigbee stick; connect it by USB and set shutdown at 20% in Energy > UPS. **Mac mini + Mac Studio:** size the UPS for the Studio's rated power too, and give it its own USB link so it shuts down first (see `studio-checklist.md`).
16. Power test: pull the plug. HA, Tailscale and the VM must be back within 5 minutes without touching anything.

## C. Router (S0.1.1 to S0.1.3, S0.1.5)

Apply everything in `docs/router.md`, then:

1. From mobile data: `HOME_WAN_IP=... ./scripts/external-port-scan.sh`. Must pass.
2. Phone on mobile data with Tailscale on: open HA and the vault.

## D. Rotate

Vault-generated passwords for the router admin, Mac accounts, Home Assistant, Tailscale, the VPN provider, your main email, Apple, shopping and banking accounts, and Anthropic. 2FA on Tailscale, the VPN provider, Anthropic and the router's cloud account.
