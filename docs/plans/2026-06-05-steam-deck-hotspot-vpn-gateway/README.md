# Steam Deck Hotspot VPN Gateway

Status: discovery in progress
Owner: AAD root/slice work in progress
Plan: [`plan.md`](./plan.md)
Reports:
- [`reports/explorer.md`](./reports/explorer.md)


Prepared scripts:
- `scripts/deck-hotspot-vpn-discover.sh` — read-only Deck inventory with redacted report.
- `scripts/deck-hotspot-vpn-up.sh` — dry-run/apply hotspot+NAT+kill-switch bring-up; apply requires explicit confirmation and password.
- `scripts/deck-hotspot-vpn-test.sh` — read-only Deck-side checks plus client-side checklist.
- `scripts/deck-hotspot-vpn-down.sh` — idempotent cleanup for this tool's NetworkManager connection and nft table.

Current implementation status:
- Discovery may be run read-only.
- `up` defaults to dry-run and does not recreate the existing `vpnkit` Podman deployment.
- Mutating `up --apply --yes` should only be run after reviewing discovery/dry-run output.
