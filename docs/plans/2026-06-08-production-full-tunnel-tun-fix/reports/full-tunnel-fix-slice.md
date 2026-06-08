# Full-tunnel TUN fix slice report

## Task
Restore full-tunnel semantics for both known vpnkit production servers using sing-box TUN mode and verify the current failover OpenVPN profile including ICMP.

## Context
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/prod-full-tunnel-tun-fix`
- Branch: `prod-full-tunnel-tun-fix`
- Commits: `b12aa89` (TUN render support), `dc943a6` (OpenVPN-to-sing-box TUN forwarding)
- Profile verified: `secrets/vps/openvpn/client/rabotau-na-failover-20260608T162953Z/phone.ovpn` (gitignored; contents not printed)

## Changes
- Added tracked TUN sing-box template: `config/sing-box/config.tun.json.template`.
- Made `scripts/vpnkit-render-local-configs.sh` select the TUN template when `VPNKIT_ROUTING_MODE=tun`.
- Added TUN render/routing assertions in `tests/vpnkit-production-routing-wiring-test.sh`.
- Documented TUN template/readiness consistency in `docs/DOCKER_SETUP.md`.
- Updated `docker/vpnkit/setup-routing.sh` TUN mode to allow forwarded OpenVPN-client traffic from `tun0` to `sb-tun0` and established return traffic back.

## Acceptance verification
- AC1 source durability: passed via tracked template/render/routing/docs/tests and local checks in `verification/source-local.md`.
- AC2 production mode: passed; `vibe-practicum` and `moscow-tiger` both run `VPNKIT_ROUTING_MODE=tun`.
- AC3 production mutation safety: passed; preserved `.env`, recorded sanitized rollback/env backups, derived/set `OVPN_CIDR` from rendered OpenVPN config without printing it, cleared stale persisted sing-box config during TUN migration, and recreated only `vpnkit`.
- AC4 runtime checks: passed on both servers; see `verification/production-runtime.out`.
- AC5 failover DNS/reachability: passed; 2 distinct A records, both endpoint-forced profiles connected and passed checks. Values redacted; see `verification/failover-dns.md`.
- AC6 profile checks: passed for domain, endpoint 1 forced, endpoint 2 forced; see `verification/profile-domain.out`, `profile-endpoint1.out`, and `profile-endpoint2.out`.
- AC7 ping failure handling: resolved here. Initial domain profile check had `ping_1_1_1_1=fail` and `ping_8_8_8_8=fail`; root cause was stale/wrong production `OVPN_CIDR` preventing policy routing match. After deriving/resetting `OVPN_CIDR` and recreating `vpnkit`, all required ping checks passed.

## Sanitized profile matrix
| Variant | OpenVPN | Route via tun0 | DNS | HTTPS | literal-IP HTTPS | ping 1.1.1.1 | ping 8.8.8.8 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| domain profile | ok | ok | ok | ok | ok | ok | ok |
| endpoint 1 forced | ok | ok | ok | ok | ok | ok | ok |
| endpoint 2 forced | ok | ok | ok | ok | ok | ok | ok |

## Production rollout
| Server | Result | Sanitized rollback references |
| --- | --- | --- |
| `vibe-practicum` | updated to TUN, runtime checks passed | image tags included `vpnkit-rollback:20260608T165718Z`, `vpnkit-rollback:20260608T170518Z`; env backups included `.rollback/vpnkit/env-20260608T171243Z` |
| `moscow-tiger` | updated to TUN, runtime checks passed | image tags included `vpnkit-rollback:20260608T165508Z`, `vpnkit-rollback:20260608T170628Z`; env backups included `.rollback/vpnkit/env-20260608T171352Z` |

## Issues
- R-1: ICMP/non-TCP profile traffic failed after initial TUN deploy because production `OVPN_CIDR` did not match the OpenVPN server pool; fixed by deriving/resetting `OVPN_CIDR` from rendered server config and redeploying `vpnkit` only.
- No follow-up (`F-*`) or unresolved (`U-*`) issues for the requested goal.

## System readiness
Ready for parent/root integration. Both production servers are running TUN/full-tunnel mode, and the current failover profile passes required isolated client checks including ping for domain and both endpoints. No secrets, profiles, private endpoints, private CIDRs, or raw rendered configs were committed or printed in tracked artifacts.

## Verdict
success
