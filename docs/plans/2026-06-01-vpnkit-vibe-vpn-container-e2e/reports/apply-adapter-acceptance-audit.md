## Task package
- Task name: `vpnkit-vibe-vpn-container-e2e` / apply-adapter slice audit
- Task package: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e`
- Report path: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/reports/apply-adapter-acceptance-audit.md`
- Acceptance plan path: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/acceptance-plan.md`

## Acceptance verdict
- Status: not accepted
- Summary: the adapter and supervisor restart path are evidenced, but the required post-switch OpenVPN DNS/HTTPS path failed, so the root request is not done.

## Acceptance coverage
- AC1: Container-safe switching works after apply/failover
  - Evidence present: `verification/apply-adapter.md`
  - Result: failed
  - Gap: post-switch client DNS timed out after `vibe-vpn apply --config /etc/vibe-vpn/config.yaml best`; sing-box logs showed hostname-resolution looping/timeouts.
- AC2: VPS/systemd behavior remains preserved as default
  - Evidence present: `reports/apply-adapter-slice-owner.md`
  - Result: passed
  - Gap: none for default behavior; report says systemd remains default.
- AC3: No secrets or VPS mutation are introduced
  - Evidence present: `verification/apply-adapter.md`, `reports/apply-adapter-slice-owner.md`
  - Result: passed
  - Gap: none in the evidence reviewed.
- AC4: REDIRECT/DNS path remains intact
  - Evidence present: `verification/real-e2e-2026-06-01.md`
  - Result: passed for observe-mode; not proven for switched state
  - Gap: the preserved REDIRECT/DNS path was validated before switching, but the post-switch DNS path failed.
- AC5: E2E integration proves the switched path
  - Evidence present: `verification/apply-adapter.md`
  - Result: failed
  - Gap: only pre-switch baseline passed; the switched rerun did not complete DNS/HTTPS acceptance.
- AC6: Logs and cleanup behavior are preserved
  - Evidence present: `verification/apply-adapter.md`, `verification/real-e2e-2026-06-01.md`
  - Result: passed
  - Gap: none for cleanup/logging mechanics.
- AC7: Commit/push evidence exists
  - Evidence present: `reports/apply-adapter-slice-owner.md`
  - Result: passed
  - Gap: none in the evidence reviewed.

## System readiness coverage
- Routes / registration: covered for container entrypoint/supervision; switched behavior still fails.
- Services / APIs: covered at the adapter boundary; no API gap found.
- Config / env / secrets: covered; systemd default preserved and no secret mutation shown.
- Docker / containers: covered; container supervisor path exists, but switch acceptance failed.
- Permissions / access: not relevant for the audited evidence.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: partially covered; wiring exists, but post-switch runtime behavior is not accepted.

## Check freshness
- Targeted checks: fresh
- Full local checks: fresh
- Remote checks / CI: not checked

## Required before done
- Freshly rerun the container-safe apply/failover path and capture a passing post-switch OpenVPN client DNS/HTTPS/literal-IP result.
- Show the selected outbound hostname resolution no longer loops in sing-box after apply/failover.
- If the fix changes runtime wiring, re-verify logs and cleanup on the same fresh run.

## Files written
- `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/acceptance-plan.md`: created
- `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/reports/apply-adapter-acceptance-audit.md`: created
