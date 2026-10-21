# TP-Link router settings (S0.1.1 to S0.1.3, S0.1.5)

Feature names differ between Archer, Deco and Omada; record your model here once confirmed. Do not write real SSIDs, passwords, the WAN IP or MAC addresses in this file.

Model line: _to confirm_ · Firmware: _to confirm_ · Supports VLANs / mDNS reflection / VPN client with policy routing: _to confirm_

## Apply

| Area | Setting | Why |
|---|---|---|
| Admin | Long unique password from the vault; 2FA on the TP-Link cloud account | Weak admin passwords are the usual way in |
| Admin | Remote management (cloud and WAN) **off** | No way in from the internet |
| WAN | Port forwarding table **empty**; DMZ **off**; UPnP **off**; WPS **off** | Zero open ports |
| WAN | Built-in VPN server (OpenVPN, WireGuard, PPTP) **off** | Tailscale is the only remote access |
| Networks | Main, IoT and Guest SSIDs or VLANs (Lab comes in Phase 1) | One compromised device can't spread |
| Main | WPA3 (WPA2/3 mixed only if a device needs it); Wi-Fi 7 MLO on | Phones, laptops, Macs, Apple TV, Plex, Windows PC |
| IoT | WPA2/3, 2.4 GHz allowed, band steering off; client isolation **off** | HA must discover devices |
| IoT | Internet only for devices that need it (Nest, Dreame, Govee); reach only the hub Mac's service ports | Limits what a hacked bulb can do |
| Guest | Isolated from all local networks | Visitors reach nothing local |
| Lab (Phase 1, S1.3.3) | VLAN or SSID for workspaces that must always exit from one country; internet only through the router's VPN client (NordLynx) with its kill switch; reaches only the hub Mac's proxy and NATS ports | The `router-vpn` route |
| Discovery | mDNS reflection Main ↔ IoT; if missing, give the hub Mac a second interface (USB Ethernet) on IoT | Hue, Apple TV, ESPHome, Cast discovery |
| DHCP | Reservations for the hub Mac, voice devices, Hue Bridge, SwitchBot Hub, TVs, soundbars, Apple TV, Plex, Windows PC | Stable addresses for HA |
| DNS | Local names for the hub Mac and HA, or AdGuard Home add-on in HA | |
| WoL | Allow Wake on LAN to the Windows PC on the LAN only | No WAN WoL |
| Backup | Export the config after every change; store it in the vault as an attachment, not in git | It contains passwords |

## Verify

- `scripts/external-port-scan.sh` from mobile data: zero open ports. Repeat after every router change and monthly.
- A phone on Guest cannot open the HA page; a phone on IoT cannot reach the hub Mac's SSH port.
- Firmware auto-update on, or a monthly reminder.
- Phase 1: Main and IoT still exit from the static IP after the Lab VPN is on (`curl ipinfo.io` from a Main device), and Lab stops when the router VPN is disconnected.
