## Task package
- Task name: `vpnkit-vibe-vpn-container-e2e` / apply-adapter fix acceptance audit
- Task package: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e`
- Report path: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/reports/apply-adapter-fix-acceptance-audit.md`
- Acceptance plan path: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/acceptance-plan.md`

## Acceptance verdict
- Status: accepted
- Summary: the follow-up fix is evidenced by a fresh passing `--switching` run with baseline, apply, supervisor restart, and post-switch DNS/HTTPS/literal-IP success, while default systemd behavior and secret/NAT boundaries remain intact.

## Acceptance coverage
- AC1: Container-safe switching works after apply/failover
  - Evidence present: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/apply-adapter-fix.md`
  - Result: passed
  - Gap: none
- AC2: VPS/systemd behavior remains preserved as default
  - Evidence present: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/reports/apply-adapter-slice-owner.md`, `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/reports/apply-adapter-fix-slice-owner.md`
  - Result: passed
  - Gap: none
- AC3: No secrets or VPS mutation are introduced
  - Evidence present: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/apply-adapter-fix.md`
  - Result: passed
  - Gap: none
- AC4: REDIRECT/DNS path remains intact
  - Evidence present: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/real-e2e-2026-06-01.md`, `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/apply-adapter-fix.md`
  - Result: passed
  - Gap: none
- AC5: E2E integration proves the switched path
  - Evidence present: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/apply-adapter-fix.md`
  - Result: passed
  - Gap: none
- AC6: Logs and cleanup behavior are preserved
  - Evidence present: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/real-e2e-2026-06-01.md`, `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/apply-adapter-fix.md`
  - Result: passed
  - Gap: none
- AC7: Verification is fresh after the fix commit
  - Evidence present: root-owner fresh checks plus `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/apply-adapter-fix.md`
  - Result: passed
  - Gap: remote CI not available before push; local verification is fresh

## System readiness coverage
- Routes / registration: covered
- Services / APIs: covered
- Config / env / secrets: covered
- Docker / containers: covered
- Permissions / access: not relevant
- Database / migrations: not relevant
- Frontend-backend integration: not relevant
- Runtime / deployment wiring: covered

## Check freshness
- Targeted checks: fresh
- Full local checks: fresh
- Remote checks / CI: not available before push

## Required before done
- None.

## Files written
- `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/acceptance-plan.md`: updated
- `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/reports/apply-adapter-fix-acceptance-audit.md`: created
