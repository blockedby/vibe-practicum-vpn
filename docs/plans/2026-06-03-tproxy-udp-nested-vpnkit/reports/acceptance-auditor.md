## Task package
- Task name: TPROXY/UDP nested-tunnel vpnkit support
- Task package: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit
- Report path: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/acceptance-auditor.md
- Acceptance plan path: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/acceptance-plan.md

## Acceptance verdict
- Status: partial
- Summary: Local and approved live isolated TPROXY/UDP smoke evidence now passes on vibe-practicum and moscow-tiger without production mutation. Full independent inner VPN-over-VPN remains unproven because only one generated test-client identity/profile was available, making simultaneous inner reuse unsafe/non-independent.

## Acceptance coverage
- AC1: TPROXY works
  - Evidence present: `verification/tproxy-udp-debug.md`, `verification/live-isolated.md`, slice-owner report
  - Result: passed for local lab and live isolated outer-tunnel smoke
  - Gap: none for outer TPROXY/UDP runtime smoke
- AC2: UDP / nested VPN-over-VPN validation
  - Evidence present: local and live outer OpenVPN over UDP; UDP DNS over tunnel; live isolated server counters/listeners including non-DNS UDP TPROXY rule/listener
  - Result: partial
  - Gap: full independent inner tunnel was not run; needs distinct inner-client profile/cert and harness
- AC3: Default production unchanged
  - Evidence present: compose default remains redirect; production `vpnkit` safe metadata unchanged before/after live isolated run
  - Result: passed
  - Gap: none in evidence set
- AC4: Local Docker lab first
  - Evidence present: `verification/tproxy-udp-debug.md` before `verification/live-isolated.md`
  - Result: passed
  - Gap: none
- AC5: Isolated vibe-practicum server+client
  - Evidence present: `verification/live-isolated.md`
  - Result: passed
  - Gap: none
- AC6: Isolated moscow-tiger client if AC5 passes
  - Evidence present: `verification/live-isolated.md`
  - Result: passed
  - Gap: none
- AC7: Report tests/files/names/ports/cleanup/production untouched
  - Evidence present: `verification/live-isolated.md`, slice-owner report
  - Result: passed
  - Gap: none
- AC8: No secrets committed/revealed
  - Evidence present: sanitized tracked artifacts only; gitignored env/profile/rendered files not added
  - Result: passed
  - Gap: none in tracked evidence

## System readiness coverage
- Routes / registration: covered for local and live isolated runtime smoke; non-DNS UDP TPROXY path present but not exercised by a full inner tunnel
- Services / APIs: OpenVPN and sing-box live isolated server/client smoke covered
- Config / env / secrets: private env used locally only; no tracked secret changes
- Docker / containers: isolated resources created and removed; production `vpnkit` metadata unchanged
- Permissions / access: live SSH/Docker access sufficient for isolated validation
- Database / migrations: not relevant
- Frontend-backend integration: not relevant
- Runtime / deployment wiring: ready for PR review except full nested proof limitation

## Required before claiming full nested completion
- Generate/provide a distinct inner OpenVPN client identity/profile and a safe harness that starts the inner tunnel over an already-active outer tunnel.
- Capture UDP traffic through that inner tunnel and cleanup/production-untouched evidence.
