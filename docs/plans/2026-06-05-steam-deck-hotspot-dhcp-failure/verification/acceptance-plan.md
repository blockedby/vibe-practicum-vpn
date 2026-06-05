# Acceptance plan: Steam Deck hotspot DHCP failure

## Criteria under audit
1. `dnsmasq` starts/stays running with `ap0` addressed/up.
2. DHCP UDP 67 listens on the intended interface/address or equivalent `dnsmasq` readiness evidence exists.
3. `hostapd` remains up and the AP stays visible/up.
4. Rollback script remains idempotent.
5. No secrets/private endpoint/generated profile/log contents are printed or committed.
6. Branch has script fixes committed/pushed; live Deck fixed state if possible.

## Evidence sources to check
- `docs/plans/2026-06-05-steam-deck-hotspot-dhcp-failure/verification/dhcp-live.md`
- `docs/plans/2026-06-05-steam-deck-hotspot-dhcp-failure/verification/up-dry-run.md`
- `docs/plans/2026-06-05-steam-deck-hotspot-dhcp-failure/verification/up-apply-blocked.md`
- `docs/plans/2026-06-05-steam-deck-hotspot-dhcp-failure/verification/down-idempotent-check-rerun.md`
- `docs/plans/2026-06-05-steam-deck-hotspot-dhcp-failure/reports/aad-implementer-dhcp.md`
- Fresh repo state: `git status --short --branch`, `git log --oneline --decorate -n 6`, `git branch -vv`

## Audit focus
- Confirm whether the live read-only evidence is sufficient for DHCP/server readiness.
- Confirm whether the missing `DECK_HOTSPOT_PASSWORD` blocks live apply and client-DHCP proof.
- Confirm whether the rollback evidence shows safe idempotent behavior without leaking secrets.
- Confirm branch state is committed/pushed and whether any remaining limitation is explicitly documented.
