# Live apply blocked

- Timestamp: 2026-06-05T11:37Z
- Command attempted: `scripts/deck-hotspot-vpn-up.sh --ssh-target <redacted> --apply --yes --report docs/plans/2026-06-05-steam-deck-hotspot-dhcp-failure/verification/up-apply.md`
- Result: not run; local validation refused mutation because no `DECK_HOTSPOT_PASSWORD` was present after sourcing `config/private-endpoints.local.env`.
- Safety note: I did not read, print, reuse, or commit the existing remote hotspot password/runtime config contents.
