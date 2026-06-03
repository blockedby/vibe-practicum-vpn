# Manual final report: TUN validation follow-up

## Task

Finish `next-tun-validation-task.md` after two subagent attempts stalled.

## Result

`PI_RESULT: PASS`

All feasible requested stages A-D passed with fresh isolated resources:

- Stage A: local-host client -> isolated `vibe-practicum` TUN server baseline/public UDP.
- Stage B: local-host nested OpenVPN through isolated TUN server.
- Stage C: `moscow-tiger` client -> isolated `vibe-practicum` TUN server baseline/public UDP.
- Stage D: `moscow-tiger` nested OpenVPN through isolated TUN server.

## Evidence

Primary evidence artifact:

```text
docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/tun-live-complete-matrix.md
```

Summary artifact:

```text
docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/tun-live-complete-report.md
```

## Isolated resources

Fresh resources used and cleaned:

```text
vpnkit_tun_final_21941_outer
vpnkit_tun_final_21941_inner
vpnkit_tun_final_21941_net
vpnkit_tun_final_21941_local_client
vpnkit_tun_final_21941_moscow_client
/tmp/vpnkit_tun_final_21941_src
/tmp/vpnkit_tun_final_21941_inner_src
/tmp/vpnkit_tun_final_21941_local
/tmp/vpnkit_tun_final_21941_moscow
```

## Key technical finding

TUN mode works for public non-DNS UDP and nested OpenVPN.

The earlier nested failure was caused by the inner OpenVPN test reusing outer tunnel defaults. The passing nested run used:

- outer tunnel subnet: `10.89.0.0/24`;
- inner tunnel subnet: `10.90.0.0/24`;
- inner client device: `dev tun1`;
- route-pull suppression for the inner client so the inner control channel stayed on the outer `tun0` path.

## Production safety

Production metadata stayed unchanged:

```text
vibe-practicum vpnkit: running, restart=0, start=2026-06-02T13:47:35.235471647Z
moscow-tiger current-vpnkit-1: running, restart=0, start=2026-06-02T12:07:48.941107386Z
```

No production containers were restarted, recreated, adopted, removed, or mutated. Steam Deck was not touched.

## Cleanup

Exact cleanup completed on local host, `vibe-practicum`, and `moscow-tiger`. Final exact leftover checks found no matching fresh containers/networks for prefix `vpnkit_tun_final_21941` or ports `21941/21942/21943`.

## Verification commands

Run after docs update:

```text
bash tests/vpnkit-singbox-template-test.sh
bash tests/vpnkit-setup-routing-test.sh
bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh
go test ./...
git diff --check
```

All passed.

## Recommendation

Proceed to guarded production-canary planning for opt-in `VPNKIT_ROUTING_MODE=tun`, keeping default `redirect` unchanged. Nested VPN support is validated when inner profiles avoid tunnel subnet/device conflicts.
