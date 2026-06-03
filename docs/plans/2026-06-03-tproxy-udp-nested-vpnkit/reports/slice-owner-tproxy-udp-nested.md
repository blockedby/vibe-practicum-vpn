# Slice owner report: TPROXY/UDP nested-tunnel vpnkit support

## Task

Implement and validate vpnkit TPROXY/UDP nested-tunnel support without touching production containers.

## Context

- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vpnkit-tproxy-udp-nested`
- Branch: `vpnkit-tproxy-udp-nested`
- PR: https://github.com/blockedby/vibe-practicum-vpn/pull/18
- Slice stayed whole. Implementation delegation was attempted but blocked by subagent nesting depth, so the slice owner made the scoped implementation and validation attempt directly.

## Spec compliance

- Default production mode remains `redirect` (`docker-compose.yml` unchanged; entrypoint defaults to redirect config).
- Added mode-aware tproxy sing-box config selection and readiness for TCP+UDP `2082`.
- Added rendering support for a gitignored `config.tproxy.json` alongside the existing redirect `config.json`.
- Added a template test that asserts redirect remains redirect-only and tproxy uses a `tproxy` inbound.
- Local Docker lab was attempted before live testing. It did not pass; live tests were not attempted.
- No secrets/profiles/logs/rendered configs/private endpoint values were committed or reported.

## Files changed

- `config/sing-box/config.tproxy.json.template` — new tproxy-mode sing-box template.
- `docker/vpnkit/entrypoint.sh` — selects source config by `VPNKIT_ROUTING_MODE`; tproxy readiness waits for TCP/UDP `2082` plus DNS UDP `5353`.
- `scripts/vpnkit-render-local-configs.sh` — renders both `config.json` and `config.tproxy.json` to gitignored rendered config dir.
- `tests/vpnkit-singbox-template-test.sh` — validates mode-specific sing-box templates.
- Task package plan/progress/verification/report files updated.

## Acceptance verification matrix

| AC | Status | Evidence |
| --- | --- | --- |
| AC1 TPROXY mode works | Blocked/partial | Config starts and listeners/rules are present, but tunneled UDP DNS times out in local lab. |
| AC2 UDP/nested VPN-over-VPN validated | Blocked | UDP packet reaches TPROXY rule; no response. Inner/nested test not reached. |
| AC3 Default production mode unchanged | Pass | Redirect template unchanged; compose default remains `VPNKIT_ROUTING_MODE:-redirect`; template test covers redirect inbound. |
| AC4 Local Docker lab before live mutation | Pass for ordering, fail for result | Local lab attempted first and failed; no live mutation attempted. |
| AC5 vibe-practicum isolated test | Not reached | Blocked by local lab failure and absent private endpoint env. |
| AC6 moscow-tiger isolated client-test | Not reached | Blocked by AC5/local lab. |
| AC7 Report exact tests/names/ports/cleanup | Pass | See `verification/slice.md`. |
| AC8 No secrets committed/revealed | Pass | Git status shows `secrets/` ignored; reports use sanitized names only. |

## Verification run

See detailed evidence in `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/slice.md`.

Passing checks:
- `bash tests/vpnkit-singbox-template-test.sh`
- `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh`
- `sing-box check` on rendered dummy redirect and tproxy configs with required deprecation env flags
- `go test ./...`
- `go vet ./...`
- `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`

Local Docker lab:
- Project: `vpnkit_tproxy_udp_nested_lab`
- Host test port: `21194/udp`
- Server container: `vpnkit_tproxy_udp_nested_lab-vpnkit-1`
- Client containers: `vpnkit_tproxy_udp_nested_lab-ovpn-client-test-run-*`
- Result: OpenVPN connection succeeded; UDP DNS over tunnel timed out.
- Cleanup: `docker compose -p vpnkit_tproxy_udp_nested_lab down -v --remove-orphans`; no lab containers remained afterward.

## Issues

- U-1 — Local lab UDP TPROXY delivery is not yet functionally complete. Evidence: client connects over outer OpenVPN and receives routes; `dig @8.8.8.8 example.com` times out; server TPROXY UDP mangle counter increments. This blocks live-host tests and final acceptance.

## Side findings

- `config/private-endpoints.local.env` is absent in this worktree. This is not the current blocker because local lab failed first; it would block live testing after local lab passes.
- Existing non-slice Docker containers observed and not touched: `vpnkit-compat-bypass-vpnkit-1`, `vpnkit-client-127.0.0.1-183549`.

## System readiness

Not ready for merge/deploy. Code/config checks pass, but acceptance requires local Docker lab UDP/nested behavior to pass before isolated live-host validation. Local lab currently exposes a current-goal blocker.

## Verdict

Blocked, not complete. The branch contains a coherent partial implementation for mode-aware tproxy sing-box config/readiness, but UDP TPROXY still fails in local Docker lab.

## Next-agent brief

Continue from U-1. Focus on why packets that hit `OVPN_TO_SINGBOX` UDP TPROXY do not produce client responses. Suggested next checks:
- Compare sing-box tproxy route/log behavior for UDP port 53 and arbitrary UDP.
- Test whether DNS should be intercepted with a dedicated mangle redirect to `vpnkit-dns-in` or a different sing-box rule/action for tproxy inbound.
- Inspect kernel TPROXY delivery requirements inside the Debian container (policy rule priority, mark mask, local route, INPUT path/counters, nft/iptables backend behavior).
- Re-run the same isolated local lab only; do not attempt live-host tests until local lab passes.
