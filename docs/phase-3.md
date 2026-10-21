# Phase 3 backlog for infrastructure (E3.2)

- **4G/5G backup line** on the TP-Link router (failover WAN). Re-run the external port scan on the backup IP too; the backup line must forward nothing either.
- **Hot spare or second HA host** so the hub Mac is no longer a single point of failure: keep a restorable HA backup current on the Studio (rehearsed in E2.6), or add a small second host with HA's backup restored nightly.
