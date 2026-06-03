# TUN live complete report

## Summary

Executed the feasible parts of the requested TUN live validation matrix with fresh isolated resources on `21741/udp` and `21742/udp`. Stage A baseline live validation passed from a local disposable OpenVPN client to an isolated `vibe-practicum` TUN-mode vpnkit server. Stage B nested routing reached the inner endpoint through outer `tun0` and sing-box TUN, but the inner OpenVPN TLS handshake timed out before `tun1` appeared. Stage C/D were not run because `moscow-tiger` SSH was intermittently timing out during preflight/fresh setup; production metadata before/after was still captured and unchanged.

## Evidence pointers

- Complete matrix: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/tun-live-complete-matrix.md`
- Slice owner report: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/slice-owner-next-tun-validation-run.md`

## Ports and names

- Outer live TUN server: `vpnkit_tun_live_21741`, UDP `21741`.
- Inner live server: `vpnkit_tun_inner_21742`, private network `vpnkit_tun_net_21741_21742`.
- Local client project/container: `vpnkit_tun_client_21741`, `vpnkit-tun-local-nested-21741`.

## Stage results

| Stage | Result |
| --- | --- |
| A local-host outer baseline | PASS for OpenVPN, UDP DNS `NOERROR`, HTTPS `200`, literal-IP HTTPS `200`, `sb-tun0` counters, and no redirect/tproxy capture chains. Fresh public echo not rerun due moscow SSH instability; prior accepted TUN echo evidence remains the public UDP proof for this topology. |
| B local-host nested OpenVPN | FAIL/PARTIAL: route to inner endpoint used outer `tun0`; sing-box TUN logged packet connection to inner endpoint; no `tun1`; TLS handshake timeout. |
| C moscow-tiger outer baseline | BLOCKED: intermittent SSH reachability; no fresh moscow client mutation. |
| D moscow-tiger nested OpenVPN | BLOCKED: depends on C reachability; no fresh moscow client mutation. |

## Cleanup and production safety

All fresh local and `vibe-practicum` isolated resources from this run were removed by exact name/path. `vibe-practicum` production `vpnkit` and `moscow-tiger` production `current-vpnkit-1` metadata remained `running`, restart count `0`, with unchanged start times. One final moscow exact-name cleanup command for older known interrupted leftovers timed out; this run did not create fresh moscow resources.

## Recommendation

Do not treat nested OpenVPN as fully validated yet. TUN mode has strong baseline and prior public UDP evidence and can move to guarded production-canary planning if nested OpenVPN is classified as a separate limitation. Retry Stage C/D and nested validation when `moscow-tiger` SSH is stable.
