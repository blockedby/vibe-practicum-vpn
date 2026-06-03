## Task package
- Task name: TPROXY/UDP nested-tunnel vpnkit support
- Task package: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit
- Report path: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/acceptance-auditor.md
- Acceptance plan path: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/acceptance-plan.md

## Acceptance verdict
- Status: not accepted
- Summary: Outer TPROXY/UDP validation is proven locally and on both isolated live hosts, but AC2 still lacks a successful independent inner VPN-over-VPN proof and remains blocked.

## Acceptance coverage
- AC1: tproxy works
  - Evidence present: `verification/tproxy-udp-debug.md`, `verification/tproxy-udp-debug-2026-06-03-nondns.md`, `verification/live-isolated.md`
  - Result: passed
  - Gap: none for outer TPROXY/UDP runtime smoke
- AC2: UDP/nested VPN-over-VPN validation with inner tunnel where feasible
  - Evidence present: `verification/inner-nested.md`, `verification/live-isolated.md`, `verification/tproxy-udp-debug.md`, `verification/tproxy-udp-debug-2026-06-03-nondns.md`
  - Result: blocked
  - Gap: the latest post-fix live rerun did not bring up the outer client `tun0` on the nested path, so no successful inner tunnel exists; earlier nested attempt also failed after the outer tunnel reached the outer server's non-DNS UDP TPROXY path. A distinct safe inner-client/profile harness or equivalent matching material is still missing.
- AC3: Default production unchanged
  - Evidence present: `verification/live-isolated.md`, `verification/inner-nested.md`
  - Result: passed
  - Gap: none
- AC4: Local Docker lab first
  - Evidence present: `verification/tproxy-udp-debug.md`, `verification/tproxy-udp-debug-2026-06-03-nondns.md`
  - Result: passed
  - Gap: none
- AC5: Isolated vibe-practicum server+client
  - Evidence present: `verification/live-isolated.md`
  - Result: passed
  - Gap: none
- AC6: Isolated moscow-tiger client
  - Evidence present: `verification/live-isolated.md`
  - Result: passed
  - Gap: none
- AC7: Report tests/files/names/ports/cleanup/production untouched
  - Evidence present: `verification/live-isolated.md`, `verification/inner-nested.md`, `verification/slice.md`
  - Result: passed
  - Gap: none
- AC8: No secrets committed/revealed
  - Evidence present: `verification/live-isolated.md`, `verification/inner-nested.md`, `verification/tproxy-udp-debug.md`, `verification/tproxy-udp-debug-2026-06-03-nondns.md`
  - Result: passed
  - Gap: none in tracked evidence

## System readiness coverage
- Routes / registration: covered; tproxy-mode TCP/UDP listeners and UDP route rules are evidenced
- Services / APIs: covered; OpenVPN and sing-box isolated smoke passed on vibe-practicum and moscow-tiger
- Config / env / secrets: covered; `config/private-endpoints.local.env` was present and sourced locally without disclosure; no tracked secret changes
- Docker / containers: covered; isolated projects/ports/networks/volumes were used and cleaned up
- Permissions / access: covered; SSH/Docker access was sufficient for isolated live validation
- Database / migrations: not relevant
- Frontend-backend integration: not relevant
- Runtime / deployment wiring: covered for the outer tproxy path; inner nested transport wiring remains unproven

## Check freshness
- Targeted checks: fresh
- Full local checks: fresh
- Remote checks / CI: not checked

## Required before done
- Provide a safe, distinct inner OpenVPN client identity/profile (or an explicit owner waiver) and rerun the nested inner-tunnel validation until a successful inner handshake/traffic proof is captured.
- If the owner wants to accept AC2 with a limitation, record the waiver source/scope/risk explicitly; otherwise AC2 stays blocked.

## Files written
- docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/acceptance-plan.md: updated
- docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/acceptance-auditor.md: updated
