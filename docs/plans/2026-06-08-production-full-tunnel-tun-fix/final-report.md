# Root final report: Production full-tunnel TUN fix

## Task
- Mission: Restore full-tunnel semantics for all known vpnkit production servers after redirect-mode regression broke ICMP/non-TCP traffic.
- Target: `vibe-practicum`, `moscow-tiger`, vpnkit source/render/routing, and current `phone.ovpn` failover profile.
- Boundaries: no secrets/profile contents/private endpoints/raw logs printed or committed; mutate only approved production vpnkit service.
- Done when: both servers run TUN/full-tunnel mode and domain/endpoint-forced profile checks pass including ping to `1.1.1.1` and `8.8.8.8`.

## Context
- Task package: `docs/plans/2026-06-08-production-full-tunnel-tun-fix`
- Slice report: `reports/full-tunnel-fix-slice.md`
- PR: https://github.com/blockedby/vibe-practicum-vpn/pull/23
- Merge commit on `main`: `562fe5e` (`Restore vpnkit production full-tunnel TUN mode`)
- Remote feature branch: kept as `origin/prod-full-tunnel-tun-fix`
- Current profile path: `secrets/vps/openvpn/client/rabotau-na-failover-20260608T162953Z/phone.ovpn`

## Slice structure used
- One end-to-end slice owner was used because source rendering, production rollout, stale persisted config cleanup, `OVPN_CIDR` correction, and profile verification had one tightly coupled acceptance story.
- Slice result: success; source durability, both-server deployment, and profile checks passed.

## Files changed
- `config/sing-box/config.tun.json.template`
- `scripts/vpnkit-render-local-configs.sh`
- `docker/vpnkit/setup-routing.sh`
- `tests/vpnkit-production-routing-wiring-test.sh`
- `docs/DOCKER_SETUP.md`
- Task package evidence under `docs/plans/2026-06-08-production-full-tunnel-tun-fix/`

## Spec compliance
- Durable TUN source support: done. Evidence: tracked TUN sing-box template, mode-aware renderer, routing/docs/tests, PR #23 merged.
- All known production servers updated: done. Evidence: `verification/production-runtime.out` reports both `vibe-practicum` and `moscow-tiger` running `routing_mode=tun` with OpenVPN, sing-box, `sb_tun0`, policy rule, and route table OK.
- Safe production mutation: done. Evidence: slice report records preserved env, derived `OVPN_CIDR` without printing it, stale persisted sing-box config cleared, vpnkit-only recreate, and rollback refs.
- Failover DNS/endpoints: done. Evidence: `verification/failover-dns.md` reports 2 distinct A records and both endpoint-forced connections passed.
- Profile acceptance: done. Evidence: root final rerun in `verification/root-final-profile-rerun.out`.

## Acceptance verification
| Criterion | Result | Evidence |
| --- | --- | --- |
| Source is durable, public-safe TUN mode | passed | `bash -n scripts/*.sh docker/vpnkit/*.sh tests/*.sh`; `tests/vpnkit-production-routing-wiring-test.sh`; `go test ./...`; merge commit `562fe5e` |
| `vibe-practicum` runtime full-tunnel/TUN | passed | `production-runtime.out`: SSH/container/UDP1194/OpenVPN/sing-box/`sb_tun0`/policy route OK |
| `moscow-tiger` runtime full-tunnel/TUN | passed | `production-runtime.out`: SSH/container/UDP1194/OpenVPN/sing-box/`sb_tun0`/policy route OK |
| Failover domain has both records and endpoints reachable | passed | `failover-dns.md`: 2 distinct A records; both endpoint-forced profile checks passed |
| Domain profile OpenVPN/DNS/HTTPS/literal-IP/ICMP | passed | `root-final-profile-rerun.out`: domain `openvpn_status=ready`, routes via `tun0`, DNS OK, HTTPS OK, literal-IP HTTPS OK, `ping_1_1_1_1=ok`, `ping_8_8_8_8=ok` |
| Endpoint 1 forced profile OpenVPN/DNS/HTTPS/literal-IP/ICMP | passed | `root-final-profile-rerun.out`: endpoint1 all required checks OK; ping loss 0% |
| Endpoint 2 forced profile OpenVPN/DNS/HTTPS/literal-IP/ICMP | passed | `root-final-profile-rerun.out`: endpoint2 all required checks OK; ping loss 0% |

## Sanitized profile matrix from root final rerun
| Variant | OpenVPN | route to 1.1.1.1 | route to 8.8.8.8 | DNS | HTTPS | literal-IP HTTPS | ping 1.1.1.1 | ping 8.8.8.8 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| domain | ready | tun0 | tun0 | ok | ok | ok | ok, 0% loss | ok, 0% loss |
| endpoint1 | ready | tun0 | tun0 | ok | ok | ok | ok, 0% loss | ok, 0% loss |
| endpoint2 | ready | tun0 | tun0 | ok | ok | ok | ok, 0% loss | ok, 0% loss |

## Production rollout / rollback refs
| Server | Updated | Rollback refs |
| --- | --- | --- |
| `vibe-practicum` | TUN mode deployed; runtime checks passed | image tags included `vpnkit-rollback:20260608T165718Z`, `vpnkit-rollback:20260608T170518Z`; env backup `.rollback/vpnkit/env-20260608T171243Z` |
| `moscow-tiger` | TUN mode deployed; runtime checks passed | image tags included `vpnkit-rollback:20260608T165508Z`, `vpnkit-rollback:20260608T170628Z`; env backup `.rollback/vpnkit/env-20260608T171352Z` |

## System readiness
- Config/env/secrets: ready; private `.env` preserved and no secret values committed.
- Runtime/deployment wiring: ready; both servers recreated vpnkit in TUN mode and stale persisted redirect config was cleared.
- Network behavior: ready; DNS/HTTPS/literal-IP HTTPS and ICMP pings pass through OpenVPN full tunnel.
- Repo state: root checkout remains on `main`; PR #23 merged; remote feature branch kept.

## Issues
### Issue R-01: ICMP failed after initial TUN rollout
- Description: Initial profile run still failed pings because production `OVPN_CIDR` did not match the OpenVPN server pool, so packets missed the source policy rule.
- Evidence: slice report and `source-local.md` record initial ping failure and classification.
- Resolution: derived/reset `OVPN_CIDR` from rendered OpenVPN server config without printing it, recreated only vpnkit, reran profile checks; all ping checks passed.

## Side findings / caveats
- `duplicate_redirect_warning=yes` appears in profile checks; it is non-blocking because OpenVPN still initializes and all route/DNS/HTTPS/ICMP checks pass.
- GitHub PR had no status checks configured (`statusCheckRollup` empty), so CI evidence is not available beyond local/source and production verification.
- Unrelated pre-existing untracked docs under other task packages remain untouched in the root checkout.

## Verdict
- Status: success.
- Goal state: fully achieved.
- Final readiness: ready; full-tunnel production behavior restored and ping passed for domain, endpoint 1, and endpoint 2 profile variants.
