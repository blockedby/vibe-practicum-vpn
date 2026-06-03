# Slice owner report: TPROXY/UDP nested-tunnel vpnkit support

## Task

Continue and validate vpnkit TPROXY/UDP nested-tunnel runtime support after local Docker lab failure, without touching production containers.

## Context

- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vpnkit-tproxy-udp-nested`
- Branch: `vpnkit-tproxy-udp-nested`
- PR: https://github.com/blockedby/vibe-practicum-vpn/pull/18
- Slice stayed whole. Delegation was blocked by max subagent depth, so the slice owner made the scoped continuation fix directly.

## Spec compliance

- Default production mode remains `redirect`; `docker-compose.yml` remains defaulted to `VPNKIT_ROUTING_MODE:-redirect`.
- TPROXY mode now starts sing-box with UDP tproxy listener `2082`, TCP redirect listener `2083`, DNS UDP listener `5353`, and SOCKS listener `2080`.
- The local Docker lab now passes the existing tunnel smoke: OpenVPN connection, UDP DNS, HTTPS by hostname, and literal-IP HTTPS.
- No live-host mutation was attempted because `config/private-endpoints.local.env` is absent after the local lab pass.
- No generated profiles, secrets, logs, rendered configs, or private endpoint values are committed or reported.

## Files changed

- `config/sing-box/config.tproxy.json.template` — adds tproxy-mode TCP redirect inbound on `2083` while retaining UDP TPROXY inbound on `2082`.
- `docker/vpnkit/entrypoint.sh` — refreshes runtime sing-box config from the selected source on startup and waits for tproxy-mode listeners including `2083`.
- `docker/vpnkit/setup-routing.sh` — handles DNS via REDIRECT to `5353`, TCP via REDIRECT to `2083`, and keeps non-DNS UDP on TPROXY `2082` with an early fwmark rule.
- `tests/vpnkit-singbox-template-test.sh` — covers the added tproxy-mode redirect inbound.
- Task package verification/progress/report files updated.

## Acceptance verification matrix

| AC | Status | Evidence |
| --- | --- | --- |
| AC1 TPROXY mode works | Partial/pass for local runtime gate | Local lab starts tproxy-mode listeners/rules and client smoke passes. Non-DNS UDP TPROXY rule remains installed; DNS/TCP use mode-specific REDIRECT special cases. |
| AC2 UDP/nested VPN-over-VPN validated | Partial/blocked | UDP DNS through outer OpenVPN passes. Inner/live nested test not attempted because private endpoint env is absent. |
| AC3 Default production mode unchanged | Pass | Compose default remains redirect; template test covers redirect and tproxy separately. |
| AC4 Local Docker lab before live mutation | Pass | Local lab passed before any live action. |
| AC5 vibe-practicum isolated test | Blocked | `config/private-endpoints.local.env` absent. |
| AC6 moscow-tiger isolated client-test | Blocked | Depends on AC5/private endpoint env. |
| AC7 Report exact tests/names/ports/cleanup | Pass | See `verification/tproxy-udp-debug.md`. |
| AC8 No secrets committed/revealed | Pass | Evidence artifacts are sanitized; generated lab/rendered files remain gitignored. |

## Verification run

Detailed evidence: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/tproxy-udp-debug.md`.

Fresh checks:
- `bash tests/vpnkit-singbox-template-test.sh` — PASS.
- `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh` — PASS.
- `go test ./...` — PASS.
- `go vet ./...` — PASS.
- `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn` — PASS.

Local Docker lab:
- Project: `vpnkit_tproxy_udp_nested_lab`
- Host port: `21194/udp`
- Server container: `vpnkit_tproxy_udp_nested_lab-vpnkit-1`
- Passing client-test container: `vpnkit_tproxy_udp_nested_lab-ovpn-client-test-run-9e07b47b6321`
- Result: PASS — UDP DNS `NOERROR`, HTTPS hostname `http_code=200`, literal-IP HTTPS `http_code=200`.
- Cleanup: isolated lab server/client containers, volumes, and network removed; no `vpnkit_tproxy_udp_nested_lab-*` containers remain.

## Issues

### R-1 — UDP DNS through local tproxy-mode lab timed out
- Evidence: prior lab had UDP mangle counter incrementing but `dig @8.8.8.8 example.com` timed out.
- Resolution: route DNS as a protocol-level special case to sing-box DNS inbound with local REDIRECT and keep non-DNS UDP TPROXY installed.
- Verification: local lab `dig @8.8.8.8 example.com` now returns `NOERROR` over UDP.

### U-1 — Approved isolated live/nested validation cannot run from this worktree
- Evidence: `test -r config/private-endpoints.local.env` reported absent.
- Why unresolved: public-safety rules require private endpoints from the gitignored local env before live-host access/mutation; none is available here.
- Needed next: provide/populate `config/private-endpoints.local.env`, then run the approved isolated vibe-practicum server/client test and moscow-tiger client test without touching production containers.

## Side findings

- Existing non-slice containers observed and not touched: `vpnkit-compat-bypass-vpnkit-1`, `vpnkit-client-127.0.0.1-183549`.
- No follow-up issue created because the remaining gap is an explicit current-goal blocker requiring private endpoint inputs, not a non-blocking future enhancement.

## System readiness

Ready for PR review of the local runtime fix, but not ready for merge as full root acceptance because approved isolated live/nested validation is blocked by missing private endpoint env.

## Verdict

Blocked after local success. Local Docker lab TPROXY-mode UDP/TCP smoke now passes and production remained untouched, but final slice/root acceptance is blocked on absent `config/private-endpoints.local.env` for staged isolated live/nested validation.
