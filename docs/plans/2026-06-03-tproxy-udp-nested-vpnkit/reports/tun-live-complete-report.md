# TUN live complete report

## Summary

Completed the full requested TUN live validation matrix with fresh isolated resources on `21941/udp` and `21942/udp`.

Result: **PASS** for all stages A-D.

TUN mode successfully carried:

- OpenVPN client baseline traffic from a local disposable client.
- Public non-DNS UDP using Cloudflare NTP (`udp/123`) with route proof through outer `tun0`.
- Nested OpenVPN-over-OpenVPN from the local disposable client.
- OpenVPN client baseline traffic from a different-host disposable client on `moscow-tiger`.
- Nested OpenVPN-over-OpenVPN from the `moscow-tiger` disposable client.

## Evidence pointers

- Complete matrix: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/tun-live-complete-matrix.md`
- Root owner report from prior partial run: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/root-owner-next-tun-validation-run.md`
- Follow-up progress: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/progress/aad-implementer-tun-validation-followup.md`

## Ports and names

- Outer live TUN server: `vpnkit_tun_final_21941_outer`, UDP `21941`.
- Inner live server: `vpnkit_tun_final_21941_inner`, UDP `21942`.
- Shared network: `vpnkit_tun_final_21941_net`.
- Local client container: `vpnkit_tun_final_21941_local_client`.
- Moscow client container: `vpnkit_tun_final_21941_moscow_client`.

## Stage results

| Stage | Result |
| --- | --- |
| A local-host outer baseline | PASS: outer `tun0`, UDP DNS `NOERROR`, HTTPS `200`, literal-IP HTTPS `200`, public UDP NTP response, `sb-tun0` route/counters, no redirect/tproxy capture chains. |
| B local-host nested OpenVPN | PASS: route to inner endpoint used outer `tun0`; sing-box TUN forwarded to inner endpoint; inner server accepted client; inner `tun1` appeared with `10.90.0.2/24`. |
| C moscow-tiger outer baseline | PASS: different-host disposable client got outer `tun0`; UDP DNS `NOERROR`; HTTPS `200`; literal-IP HTTPS `200`; public UDP NTP response with route via outer `tun0`. |
| D moscow-tiger nested OpenVPN | PASS: moscow disposable client routed inner endpoint via outer `tun0`; inner server accepted client; inner `tun1` appeared with `10.90.0.2/24`. |

## Key fix for nested validation

The previous nested timeout was not a generic TUN UDP failure. The passing run used a temp-only inner OpenVPN server subnet `10.90.0.0/24` and an inner client profile using `dev tun1` plus route-pull suppression. That avoided conflict with the outer `10.89.0.0/24` tunnel and allowed nested OpenVPN to complete.

## Cleanup and production safety

All fresh local, `vibe-practicum`, and `moscow-tiger` isolated resources were removed by exact name/path. Final exact leftover checks found no matching `vpnkit_tun_final_21941` containers/networks or ports `21941/21942/21943` on either live host.

Production metadata stayed unchanged:

- `vibe-practicum` production `vpnkit`: `running`, restart count `0`, unchanged start time `2026-06-02T13:47:35.235471647Z`.
- `moscow-tiger` production `current-vpnkit-1`: `running`, restart count `0`, unchanged start time `2026-06-02T12:07:48.941107386Z`.

No production containers were restarted, recreated, adopted, removed, or otherwise mutated. Steam Deck was not touched. No generated profiles, rendered configs, raw logs, tarballs, or secrets were committed.

## Recommendation

Proceed to guarded production-canary planning for opt-in `VPNKIT_ROUTING_MODE=tun`. Keep default `redirect` mode unchanged. Treat nested VPN support as validated only when inner profiles avoid subnet/device conflicts (for example, separate inner subnet and `dev tun1`).
