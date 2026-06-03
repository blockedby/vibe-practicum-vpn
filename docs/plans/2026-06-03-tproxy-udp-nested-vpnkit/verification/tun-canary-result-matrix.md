# TUN canary validation result matrix

Date: 2026-06-03
Task: optional Task 6 staged validation continuation after Task 5 checks passed

## Scope actually run

Only the isolated local Docker lab stage was run in this implementer continuation. Live same-host, live different-host, and nested validation were not attempted; no live-host mutation was performed.

## Local lab setup

- Compose project: `vpnkit_tun_canary_lab_21510`
- Host OpenVPN UDP port: `21510/udp`
- Routing mode: `VPNKIT_ROUTING_MODE=tun`
- IPv6 policy: `VPNKIT_IPV6_POLICY=block`
- Vibe VPN daemon: `VPNKIT_ENABLE_VIBE_VPN_DAEMON=true`
- Config rendering note: full `scripts/vpnkit-render-local-configs.sh` was blocked by missing gitignored source PKI files; existing gitignored rendered OpenVPN/client configs were present. The tun sing-box rendered config was created under gitignored `secrets/vps/rendered/sing-box/config.tun.json` by extracting the existing rendered `selected-native-out` without printing contents, then checked with sing-box deprecation env flags.

## Matrix

| Stage | Evidence | Result |
| --- | --- | --- |
| TUN config syntax | `sing-box check -c secrets/vps/rendered/sing-box/config.tun.json` with deprecation env flags; warnings only. | PASS |
| Container startup/readiness | `docker compose -p vpnkit_tun_canary_lab_21510 up -d --build vpnkit`; readiness loop observed `sb-tun0`, `172.19.0.1/30`, and policy rule `from 10.89.0.0/24 lookup 101`. | PASS |
| Baseline OpenVPN connect | `docker compose -p vpnkit_tun_canary_lab_21510 --profile test run --rm ovpn-client-test`; client got `tun0` with `10.89.0.2/24`. | PASS |
| UDP DNS through tunnel | Client test `dig @8.8.8.8 example.com` returned `status: NOERROR` over UDP. | PASS |
| HTTPS hostname smoke | Client test reported `https-test http_code=200`. | PASS |
| Literal-IP HTTPS smoke | Client test reported `literal-ip-test http_code=200`. | PASS |
| TUN traffic evidence | Server `ip -s link show sb-tun0` showed RX/TX packets incremented (`61` packets each in the sampled summary). | PASS |
| No redirect/tproxy capture rules in tun mode | Server checks found `OVPN_REDIRECT_TO_SINGBOX` nat chain absent and `OVPN_TO_SINGBOX` mangle chain absent. | PASS |
| Public non-DNS UDP echo | Not run in this continuation. Baseline UDP DNS was proven; a separate public non-DNS echo endpoint/harness was not run before stopping. | NOT RUN |
| Live same-host / different-host / nested | Not run; no live-host mutation attempted. | NOT RUN |
| Cleanup | `docker compose -p vpnkit_tun_canary_lab_21510 down -v --remove-orphans`; final checks found no matching containers or networks. | PASS |
| Production boundary | No production containers, Steam Deck, or live-host runtime were touched. | PASS |

## Notes

- This matrix is partial Task 6 evidence, not a full staged-validation acceptance claim.
- No generated profile, rendered config content, private endpoint value, raw log, or secret was committed or printed here.

## 2026-06-03 operator continuation: public UDP echo reprobe

After interrupting the stalled live-validation wrapper, the isolated TUN server resources on `vibe-practicum` were still running on `21631/udp` and the moscow echo endpoint was re-tested with a Python UDP client from a local disposable OpenVPN client container.

Sanitized evidence:

```text
outer client tunnel: inet 10.89.0.2/24 on tun0
route to public echo endpoint: via 10.89.0.1 dev tun0 src 10.89.0.2
UDP_ECHO_OK: echo response received from public echo endpoint
public echo container observed datagram from 45.12.74.211:<ephemeral-port>
```

Interpretation:
- sing-box TUN mode did forward public non-DNS UDP out of the isolated `vibe-practicum` vpnkit container and returned the UDP echo response to the OpenVPN client.
- The earlier `PUBLIC_UDP_ECHO_TIMEOUT` in the interrupted wrapper was a harness/client limitation, not a confirmed TUN-mode UDP failure.
- This updates the public non-DNS UDP status for TUN mode from unknown/timeout to pass for local-host client -> isolated `vibe-practicum` TUN server -> public echo endpoint.

## Cleanup continuation status

After the operator continuation:
- `vibe-practicum` isolated TUN compose projects/containers/networks for `21631/udp` and `21632/udp` were removed; a post-cleanup check showed no matching isolated TUN containers/networks and production `vpnkit` still running.
- `moscow-tiger` cleanup command removed the known isolated echo container/temp path (`vpnkit-tun-echo-tun21631` and `/tmp/vpnkit_tun21631_moscow`). A final post-cleanup listing attempt later hit an SSH port 22 timeout, so one additional moscow recheck is pending when SSH is reachable again.
