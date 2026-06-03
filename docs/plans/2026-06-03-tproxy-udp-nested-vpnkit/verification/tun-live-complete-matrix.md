# TUN live complete validation matrix

Date: 2026-06-03
Branch: `vpnkit-tproxy-udp-nested`
Task: finish vpnkit sing-box TUN-mode validation

## Isolated resources used

Fresh final run resources:

- `vibe-practicum` outer TUN server: Compose project `vpnkit_tun_final_21941_outer`, container `vpnkit_tun_final_21941_outer-vpnkit-1`, UDP port `21941`, temp path `/tmp/vpnkit_tun_final_21941_src`.
- `vibe-practicum` inner server: Compose project `vpnkit_tun_final_21941_inner`, container `vpnkit_tun_final_21941_inner-vpnkit-1`, UDP port `21942`, temp path `/tmp/vpnkit_tun_final_21941_inner_src`.
- Shared private Docker network: `vpnkit_tun_final_21941_net`; inner endpoint address observed as `172.24.0.3` on that network.
- Local disposable client: container `vpnkit_tun_final_21941_local_client`, temp path `/tmp/vpnkit_tun_final_21941_local`.
- `moscow-tiger` disposable client: container `vpnkit_tun_final_21941_moscow_client`, temp path `/tmp/vpnkit_tun_final_21941_moscow`.

Important implementation detail for nested validation:

- The inner isolated OpenVPN server used a temp-only non-conflicting tunnel subnet `10.90.0.0/24` instead of the outer `10.89.0.0/24`.
- The inner client profile was temp-only with `dev tun1` and route-pull suppression for pushed routes/DNS, so the inner control channel continued to use the outer `tun0` route.

No generated profiles, rendered configs, raw logs, tcpdump output, secrets, subscription URLs, or auth files are included in this artifact.

## Production metadata

| Host | Container | Before cleanup | After cleanup | Result |
| --- | --- | --- | --- | --- |
| vibe-practicum | `vpnkit` | `status=running restart=0 started=2026-06-02T13:47:35.235471647Z` | `status=running restart=0 started=2026-06-02T13:47:35.235471647Z` | unchanged |
| moscow-tiger | `current-vpnkit-1` | `status=running restart=0 started=2026-06-02T12:07:48.941107386Z` | `status=running restart=0 started=2026-06-02T12:07:48.941107386Z` | unchanged |

## Stage matrix

| Stage | Acceptance evidence | Result |
| --- | --- | --- |
| A. Local-host client -> isolated `vibe-practicum` TUN server | Outer OpenVPN connected; client got `tun0` address `10.89.0.2/24`; route to public NTP endpoint `162.159.200.123` used `via 10.89.0.1 dev tun0`; route to inner endpoint `172.24.0.3` used `via 10.89.0.1 dev tun0`; UDP DNS returned `NOERROR`; HTTPS hostname returned `200`; literal-IP HTTPS returned `200`; public non-DNS UDP NTP returned 48-byte response from `162.159.200.123:123`; server `sb-tun0` existed at `172.19.0.1/30`; policy rule `from 10.89.0.0/24 lookup 101`; table 101 default via `sb-tun0`; `sb-tun0` counters incremented; redirect/tproxy capture chains were absent. | PASS |
| B. Local-host nested OpenVPN through isolated TUN server | Outer `tun0` up; route to inner endpoint used outer `tun0`; filtered sing-box logs showed `inbound/tun[vpnkit-tun-in]` packet connection to `172.24.0.3:1194` and `outbound/direct[direct-out]`; inner server accepted client and assigned `10.90.0.2`; inner client got `tun1` address `10.90.0.2/24`. | PASS |
| C. `moscow-tiger` client -> isolated `vibe-practicum` TUN server | Disposable moscow client connected; client got `tun0` address `10.89.0.2/24`; route to public NTP endpoint used `via 10.89.0.1 dev tun0`; route to inner endpoint used `via 10.89.0.1 dev tun0`; UDP DNS returned `NOERROR`; HTTPS hostname returned `200`; literal-IP HTTPS returned `200`; public non-DNS UDP NTP returned 48-byte response from Cloudflare NTP. | PASS |
| D. `moscow-tiger` client nested OpenVPN through isolated TUN server | Outer `tun0` up on moscow disposable client; route to inner endpoint used outer `tun0`; filtered sing-box logs showed packet connection to `172.24.0.3:1194`; inner server accepted second client session and assigned `10.90.0.2`; moscow client got inner `tun1` address `10.90.0.2/24`. | PASS |

## Cleanup status

- Local exact cleanup completed: removed `/tmp/vpnkit_tun_final_21941_local`; disposable local client exited/removed.
- `vibe-practicum` exact cleanup completed: removed both fresh Compose projects/volumes, both fresh containers, shared network `vpnkit_tun_final_21941_net`, and temp paths `/tmp/vpnkit_tun_final_21941_src` and `/tmp/vpnkit_tun_final_21941_inner_src`.
- `moscow-tiger` exact cleanup completed: removed disposable moscow client container/temp path and any same-prefix echo container if present.
- Final exact leftover checks for `vpnkit_tun_final_21941` and ports `21941/21942/21943` showed no matching containers/networks on `vibe-practicum` or `moscow-tiger`.
- Production containers remained running with restart count `0` and unchanged start times.

## Recommendation

TUN mode is ready for a guarded production-canary planning step. The final isolated validation passed baseline DNS/HTTPS/literal checks, public non-DNS UDP via NTP, and nested OpenVPN-over-OpenVPN from both a local disposable client and a different-host disposable client on `moscow-tiger`. The earlier nested failure was caused by the inner tunnel reusing the outer OpenVPN subnet/profile defaults; using a separate inner subnet (`10.90.0.0/24`) and `dev tun1` resolves that validation issue.
