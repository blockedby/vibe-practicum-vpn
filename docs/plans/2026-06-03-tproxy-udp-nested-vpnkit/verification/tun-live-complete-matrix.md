# TUN live complete validation matrix

Date: 2026-06-03
Branch: `vpnkit-tproxy-udp-nested`
Task: finish vpnkit sing-box TUN-mode validation

## Isolated resources used

- `vibe-practicum` outer TUN server: Compose project `vpnkit_tun_live_21741`, container `vpnkit_tun_live_21741-vpnkit-1`, UDP port `21741`, temp path `/tmp/vpnkit_tun_live_21741_server`.
- `vibe-practicum` inner server: container `vpnkit_tun_inner_21742`, Docker network `vpnkit_tun_net_21741_21742`, temp path `/tmp/vpnkit_tun_live_21742_inner`.
- Local client resources: Compose project `vpnkit_tun_client_21741`, container `vpnkit-tun-local-nested-21741`, temp path `/tmp/vpnkit_tun21741_local_client`.
- Prior known cleanup targets checked/cleaned where reachable: `vpnkit_tun_live_21631`, `vpnkit_tun_inner_21632`, `vpnkit_tun_net_21631_21632`, `/tmp/vpnkit_tun21631_server`; moscow known names were attempted, but one final exact-name cleanup command timed out after production metadata had been rechecked.

No generated profiles, rendered configs, raw logs, tcpdump output, secrets, subscription URLs, or auth files are included in this artifact.

## Production metadata

| Host | Container | Before | After | Result |
| --- | --- | --- | --- | --- |
| vibe-practicum | `vpnkit` | `status=running restart=0 started=2026-06-02T13:47:35.235471647Z` | `status=running restart=0 started=2026-06-02T13:47:35.235471647Z` | unchanged |
| moscow-tiger | `current-vpnkit-1` | `status=running restart=0 started=2026-06-02T12:07:48.941107386Z` | `status=running restart=0 started=2026-06-02T12:07:48.941107386Z` | unchanged |

## Stage matrix

| Stage | Acceptance evidence | Result |
| --- | --- | --- |
| A. Local-host client -> isolated vibe-practicum TUN server | Outer OpenVPN connected and client received `tun0` address `10.89.0.2/24`; UDP DNS returned `NOERROR`; HTTPS hostname returned `200`; literal-IP HTTPS returned `200`; server `sb-tun0` existed at `172.19.0.1/30`; policy rule `from 10.89.0.0/24 lookup 101`; table 101 default via `sb-tun0`; `sb-tun0` counters incremented to RX/TX 62 packets after baseline smoke; redirect/tproxy capture chains were absent. | PASS for baseline/TUN capture. Public non-DNS UDP echo was NOT RERUN in this owner attempt because `moscow-tiger` SSH was timing out when a fresh separate-host echo endpoint was needed. Prior accepted TUN evidence in this package already proved public UDP echo for this topology. |
| B. Local-host nested OpenVPN through isolated TUN server | Outer `tun0` came up; route to inner Docker endpoint used `via 10.89.0.1 dev tun0`; inner OpenVPN attempted with `dev tun1` and non-conflicting inner subnet `10.90.0.0/24`; server `sb-tun0` RX/TX counters increased during the nested attempt; filtered sing-box evidence showed `inbound/tun[vpnkit-tun-in]` packet connection to the inner endpoint and `outbound/direct[direct-out]` packet connection. | FAIL/PARTIAL. Inner `tun1` did not appear; inner client hit TLS handshake timeout. Inner server stayed initialized but did not complete client acceptance in the observed window. |
| C. moscow-tiger client -> isolated vibe-practicum TUN server | Not safely run. `moscow-tiger` SSH timed out during preflight/fresh echo setup and later one exact cleanup command; production metadata was reachable before/after and unchanged. | BLOCKED by intermittent SSH reachability; no moscow client mutation performed. |
| D. moscow-tiger nested OpenVPN through isolated TUN server | Not safely run because Stage C setup was blocked by intermittent SSH reachability. | BLOCKED by intermittent SSH reachability; no moscow client mutation performed. |

## Cleanup status

- Local exact cleanup completed: removed `vpnkit-tun-local-nested-21741`, `vpnkit_tun_client_21741` Compose resources/volumes, and `/tmp/vpnkit_tun21741_local_client`.
- `vibe-practicum` exact cleanup completed: removed `vpnkit_tun_inner_21742`, `vpnkit_tun_live_21741` Compose resources/volumes, `vpnkit_tun_net_21741_21742`, `/tmp/vpnkit_tun_live_21741_server`, and `/tmp/vpnkit_tun_live_21742_inner`; final exact checks showed no matching fresh resources.
- `moscow-tiger` prior known cleanup was attempted; production metadata recheck succeeded and was unchanged, but the final exact known-name cleanup command later timed out. No fresh moscow validation resources were created by this run.

## Recommendation

TUN mode remains suitable for the next guarded production-canary planning step for baseline DNS/HTTPS/literal-IP and for public UDP based on prior accepted same-topology echo evidence plus this fresh baseline live TUN run. Full nested OpenVPN over the isolated TUN server remains a current limitation: local nested routing reached the TUN inbound and direct outbound path, but the inner TLS handshake did not complete. Complete different-host Stage C/D should be retried when `moscow-tiger` SSH is stable.
