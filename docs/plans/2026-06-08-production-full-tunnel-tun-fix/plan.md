# Production full-tunnel TUN fix plan

## Intake

Goal: urgent approved production fix to restore full-tunnel semantics for OpenVPN clients on all known vpnkit production servers (`vibe-practicum`, `moscow-tiger`) after production regressed to redirect-only routing where ICMP/non-TCP traffic fails.

Public-safety constraints:
- Do not print or commit secrets, private keys, generated OpenVPN profile contents, rendered configs, subscription URLs, auth files, raw logs, private CIDRs, keys, private endpoint values, or private IPs/domains.
- Real endpoint values must stay in gitignored `config/private-endpoints.local.env` or existing gitignored `secrets/` paths.
- Production mutation is explicitly approved for this fix, but only for the known vpnkit production servers and service.
- Discover remote Compose working directories from Docker labels; do not assume paths.
- Preserve private `.env` values and derive `OVPN_CIDR` from the server config when needed without printing it.
- Backup rollback image/env before mutation.
- Clear or replace persisted stale redirect sing-box runtime config so the recreated service actually runs TUN mode.
- Keep the root checkout on `main` if touched and preserve unrelated untracked files.

## Acceptance criteria

AC1. Durable repo/source support exists for TUN/full-tunnel production mode; it is not only a remote one-off hack.
AC2. `VPNKIT_ROUTING_MODE=tun` (or equivalent all-IP mode) is deployed on all known vpnkit production servers: `vibe-practicum` and `moscow-tiger`.
AC3. Each production server mutation preserves private `.env` values, derives/sets `OVPN_CIDR` safely where needed, records rollback image/env references, clears stale persisted redirect sing-box config, and recreates only the vpnkit service.
AC4. Per-server runtime checks pass: SSH reachable, Docker/Compose service running, UDP 1194 listening/mapped, OpenVPN up, sing-box up, `sb-tun0`/TUN up, policy routing/routing table correct for the OpenVPN CIDR.
AC5. Current failover domain has both A records and both endpoints are reachable, reported without printing endpoint values.
AC6. Current `phone.ovpn` failover profile under `secrets/vps/openvpn/client/rabotau-na-failover-20260608T162953Z` passes isolated client-container tests for domain profile, endpoint 1 forced, endpoint 2 forced: OpenVPN connects, route goes through `tun0`, DNS OK, HTTPS OK, literal-IP HTTPS OK, ping 1.1.1.1 OK, and ping 8.8.8.8 OK.
AC7. If ping fails at any point, classify and fix before claiming done.
AC8. Final report summarizes plan, changed files/commits/PR if any, servers updated, rollback tags, sanitized verification matrix including ping results for both endpoints and domain profile, current profile path, and caveats.

## Ownership / slice structure

Use one slice owner for the end-to-end production full-tunnel fix. The work has multiple execution phases (source support, deploy, verify), but a single acceptance story and high coupling between config source, production rollout, stale persisted config, and profile verification. Splitting deploy and source would increase coordination risk in an urgent fix.

### Slice 1: full-tunnel source, production deploy, and profile verification
- Owner: `aad-slice-owner`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/prod-full-tunnel-tun-fix`
- Branch: `prod-full-tunnel-tun-fix`
- Report path: `docs/plans/2026-06-08-production-full-tunnel-tun-fix/reports/full-tunnel-fix-slice.md`
- Progress path: `docs/plans/2026-06-08-production-full-tunnel-tun-fix/progress/full-tunnel-fix-slice.md`
- Goal: make TUN/full-tunnel production mode durable in tracked source if missing, then deploy merged/current fix to both known servers and verify actual client behavior including ICMP.
- Depends on: none.
- Blocks: root final report.

Expected implementation approach:
1. Inspect existing repo support for `VPNKIT_ROUTING_MODE=tun`, sing-box TUN config rendering/templates, setup routing, client profile check tooling, and previous production-routing follow-up.
2. If tracked TUN sing-box template/source is missing, add public-safe render/config support (for example a TUN template or mode-aware renderer) and tests/docs. Do not commit rendered configs.
3. Run local safe tests sufficient for the source change: shell syntax, targeted wiring/render tests, `sing-box check` if available, and Docker lab/profile check if practical before live deploy. If local lab cannot be run due environment/time, record limitation and compensate with source checks plus production verification.
4. Commit durable source/task-package changes on `prod-full-tunnel-tun-fix`; push/PR/merge if practical. If urgent production deploy must use the branch before merge, record it and keep branch for follow-up merge.
5. Source `config/private-endpoints.local.env` silently for private SSH aliases/endpoints. Do not echo env or endpoint values.
6. For each known server, safely discover the existing `vpnkit` container and Compose working directory from Docker labels; back up image/env; update env/source to `VPNKIT_ROUTING_MODE=tun` and correct `OVPN_CIDR`; copy/pull source as needed; remove/replace stale persisted `/var/lib/vpnkit/sing-box/config.json` redirect config; recreate only the vpnkit service.
7. Verify per-server runtime health with sanitized checks.
8. Verify failover DNS A-record count and reachability without printing IPs.
9. Test the current `phone.ovpn` profile from `secrets/vps/openvpn/client/rabotau-na-failover-20260608T162953Z` using isolated Docker client containers for domain, endpoint 1 forced, and endpoint 2 forced. Use copied temporary profiles if needed but never print or commit profile contents. Required checks include `ping_1_1_1_1=ok` and `ping_8_8_8_8=ok`.
10. If any acceptance check fails, classify and fix in scope; do not report done until ping and all required smokes pass.

Do-not-touch boundaries:
- Do not mutate unrelated containers/services.
- Do not remove/recreate production `vpnkit` except as required for this approved deploy with rollback backup.
- Do not print private endpoint values, profile contents, raw logs, private CIDRs, or rendered configs.
- Do not alter generated profile secrets except temporary copied variants used for verification.

## Verification ledger

- Plan/package created in isolated worktree: done.
- Slice delegated: pending.
- Root integration/final verification: pending.
