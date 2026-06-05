PI_RESULT: BLOCKED
TASK: Steam Deck hotspot DHCP failure
TASK_PACKAGE: docs/plans/2026-06-05-steam-deck-hotspot-dhcp-failure
REPORT_PATH: docs/plans/2026-06-05-steam-deck-hotspot-dhcp-failure/reports/aad-implementer-dhcp.md
PROGRESS_PATH: docs/plans/2026-06-05-steam-deck-hotspot-dhcp-failure/progress/aad-implementer-dhcp.md

COMMITS:
- e94a9c1: Harden Deck hotspot DHCP readiness
- bb68bf9: Record Deck DHCP live readiness evidence

FILES_CHANGED:
- scripts/deck-hotspot-vpn-up.sh: generates more robust dnsmasq config (`bind-dynamic`, explicit listen address, authoritative DHCP, durable dnsmasq log) and fails apply if hostapd/dnsmasq/UDP67 readiness is absent.
- scripts/deck-hotspot-vpn-test.sh: adds read-only hostapd/dnsmasq/listener/nft readiness evidence to the redacted test report.
- scripts/deck-hotspot-vpn-down.sh: keeps missing nft-table cleanup idempotent and quiet.
- steam-deck/hotspot-client/scripts/hotspot-entrypoint.sh: waits for hostapd `AP-ENABLED` before starting dnsmasq.
- docs/plans/2026-06-05-steam-deck-hotspot-dhcp-failure/verification/*.md: safe dry-run, live-readiness, rollback-smoke, and live-apply-blocker evidence.
- docs/plans/2026-06-05-steam-deck-hotspot-dhcp-failure/progress/aad-implementer-dhcp.md: progress notes.

AC_VERIFICATION:
- dnsmasq starts/stays running with ap0 addressed/up: current live read-only evidence in `verification/dhcp-live.md` shows `ap0` up and dnsmasq listening; fixed image was not applied because password env was missing — partially passed/current-state only.
- DHCP UDP 67 listens on intended interface/address or equivalent readiness evidence: `verification/dhcp-live.md` shows UDP 67 bound to `ap0`; updated up script would also fail if UDP67/dnsmasq readiness is absent — partially passed/current-state only.
- hostapd remains up and AP visible/up: read-only live checks show `ap0` up and hostapd `AP-ENABLED` — passed for current live state.
- rollback script remains idempotent: fake-name rollback smoke `verification/down-idempotent-check-rerun.md` exited successfully without touching live `ap0`; actual rollback was not run because re-apply is blocked by missing password — partially passed.
- no secrets/private endpoint/generated profile/log contents printed or committed: redacted reports only; did not read/reuse remote hotspot password — passed.

TESTS_RUN:
- RED static check for missing DHCP readiness wiring: failed as expected before edits.
- Targeted static green check for `bind-dynamic`, dnsmasq log-facility, test readiness reporting, AP-ENABLED wait, and quiet absent nft handling: passed.
- `bash -n scripts/*.sh steam-deck/hotspot-client/scripts/*.sh`: passed.
- `scripts/deck-hotspot-vpn-up.sh --ssh-target <redacted> --dry-run --report .../verification/up-dry-run.md`: passed.
- `scripts/deck-hotspot-vpn-up.sh --ssh-target <redacted> --apply --yes --report .../verification/up-apply.md`: not run/refused; missing `DECK_HOTSPOT_PASSWORD` after sourcing local env.
- `scripts/deck-hotspot-vpn-test.sh --ssh-target <redacted> --report .../verification/dhcp-live.md`: passed read-only, with current-state dnsmasq UDP67 evidence.
- `scripts/deck-hotspot-vpn-down.sh --ssh-target <redacted> --container vpnkit-deck-hotspot-ap-check --nft-table vpnkit_deck_hotspot_check --hotspot-iface ap0check --report .../verification/down-idempotent-check-rerun.md`: passed fake-name idempotency smoke.

QUALITY_CHECKS:
- `git diff --check`: passed.
- `shellcheck ...`: not run; `shellcheck` is not installed in this environment.

QUALITY_NOTES:
- Readability/reuse: reused existing scripts/redaction/report style; no new abstractions or dependencies.
- Error handling/logging: preserved fail-fast apply behavior; added readiness diagnostics and durable dnsmasq logging without dumping sensitive config contents.
- Backend/API/data: not relevant.
- Frontend/UI: not relevant.
- DevOps/runtime: container startup now waits for AP readiness before DHCP and verifies dnsmasq/UDP67 before declaring up; fixed runtime still needs live apply with a provided hotspot password.
- Security: no secrets/passwords/private endpoints/profile contents printed or committed; refused to scrape the existing remote hotspot passphrase.
- Concurrency/idempotency: rollback missing-table path is quiet/idempotent; actual live rollback deferred to avoid leaving AP down while re-apply is blocked.
- Compatibility/performance: no public CLI breaking changes; added optional test-script flags matching existing env defaults; startup wait bounded to 10 seconds.

SIDE_FINDINGS:
- Blocking: live apply of the fixed image requires `DECK_HOTSPOT_PASSWORD` (or owner-provided safe equivalent) in the local environment.
- Non-blocking follow-up candidates: current pre-fix live container returns `crun: open executable: Transport endpoint is not connected` for `podman exec`, while host-level `ss` still proves dnsmasq is running/listening; fixed re-apply should recreate the container.

NOTES: Code fixes are committed and pushed. Acceptance owner can provide/export the hotspot password and rerun apply/test/actual rollback, or direct an alternate safe password handoff.
