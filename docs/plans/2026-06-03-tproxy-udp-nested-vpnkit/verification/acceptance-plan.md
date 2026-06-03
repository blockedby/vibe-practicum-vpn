# Acceptance plan: TPROXY/UDP nested-tunnel vpnkit support

## Scope
Audit whether the root task is ready for acceptance based on existing task-package evidence and fresh blocker checks only. Do not modify source code.

## Acceptance criteria mapping
- AC1: TPROXY works
  - Evidence to inspect: local lab pass after tproxy runtime fix; config/render/tests; listener/routing evidence.
- AC2: UDP / nested VPN-over-VPN validation
  - Evidence to inspect: outer UDP path validation; any inner/live nested test evidence; blocker if absent.
- AC3: Default production unchanged
  - Evidence to inspect: default routing mode remains redirect; no production-container mutation evidence.
- AC4: Local Docker lab first
  - Evidence to inspect: local lab ran before any live-host attempt.
- AC5: Isolated vibe-practicum server+client
  - Evidence to inspect: isolated live-host test evidence or blocker.
- AC6: Isolated moscow-tiger client if AC5 passes
  - Evidence to inspect: isolated client evidence or blocker/dependency on AC5.
- AC7: Report tests/files/names/ports/cleanup/production untouched
  - Evidence to inspect: report contents and cleanup evidence.
- AC8: No secrets committed/revealed
  - Evidence to inspect: sanitized artifacts only; no secret-bearing files or values.

## Fresh checks for audit
- Confirm `config/private-endpoints.local.env` is present/absent before considering live-host readiness.
- Read the latest task-package verification/report artifacts.
- Record verdict, gaps, and whether the private-endpoint absence is a valid blocker under repo safety rules.

## Audit run note
- Freshly reviewed the latest verification artifacts: `verification/tproxy-udp-debug.md`, `verification/live-isolated.md`, `verification/inner-nested.md`, `verification/tproxy-udp-debug-2026-06-03-nondns.md`, and `verification/slice.md`.
- Fresh safety gate check: `config/private-endpoints.local.env` was present in this worktree at audit time.
- Current focus: decide whether AC2 is fully closed or still blocked after the post-fix live rerun attempt.

## Slice-fix acceptance audit note
- 2026-06-03: narrowed audit scope to the UDP echo blocker fix only. Reviewed `reports/aad-implementer-udp-echo-tproxy-fix.md`, `verification/udp-echo-tproxy-fix.md`, and current git history/status for acceptance of the reduced echo + nested rerun evidence.
