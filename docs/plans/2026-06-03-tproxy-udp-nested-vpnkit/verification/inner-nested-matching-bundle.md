# Matching-bundle nested TPROXY/UDP validation

Date: 2026-06-03
Executor: aad-implementer

## Scope and safety gates

- Used only the matching gitignored local bundle named in the delegation:
  - `secrets/vps/rendered/openvpn/server.conf`
  - `secrets/vps/rendered/openvpn/pki/*`
  - `secrets/vps/rendered/sing-box/config.tproxy.json`
  - `secrets/vps/openvpn/client/test-client.ovpn`
- Did not print profile, PKI, rendered sing-box config, private endpoint, or auth material contents.
- Sanitized grep was limited to non-secret OpenVPN directives.
- Rewrote only `remote` lines in temporary copied client profiles.
- Production containers were inspected only with safe Docker metadata; no production container was restarted, recreated, adopted, or mutated.
- Steam Deck was not touched.

## Isolated resources used

vibe-practicum:
- Temp server/source path: `/tmp/vpnkit_match_nested_21342_21343` (removed during cleanup).
- Shared Docker network: `vpnkit_match_net_21342_21343` (removed).
- Outer project/container: `vpnkit_match_outer_21342` / `vpnkit_match_outer_21342-vpnkit-1`.
- Outer published OpenVPN port: `21342/udp`.
- Inner project/container: `vpnkit_match_inner_21343` / `vpnkit_match_inner_21343-vpnkit-1`.
- Inner published diagnostic OpenVPN port: `21343/udp`.
- Inner client target for the nested attempt: inner container Docker-network IP on `1194/udp` (sanitized below as `<inner-container-ip>`).

moscow-tiger:
- Temp client path: `/tmp/vpnkit_match_nested_client_21342_21343` (removed).
- Client image: `vpnkit_match_nested_client_21342_21343-image` (removed).
- Client container: `nested-match-21342` (removed).

Harness note:
- The matching server config requires `/etc/openvpn/ccd`. The delegated allowed bundle did not include ccd contents, so the isolated temp server bundles used empty ccd directories only. No ccd secret content was inspected or copied.

## Preflight evidence

Sanitized local bundle checks:
- Required files/directories were readable.
- Sanitized server directives included `port 1194`, `proto udp`, `dev tun0`, `server 10.89.0.0 255.255.255.0`, `tun-mtu 1400`, `mssfix 1360`, redirect-gateway and DNS pushes.
- Sanitized client directives included `client`, `dev tun`, `proto udp`, `remote-cert-tls server`, `auth SHA256`, and configured data ciphers.

Remote availability:
- `ssh vibe-practicum` succeeded; Docker and Docker Compose were available.
- `ssh moscow-tiger` succeeded; Docker and Docker Compose were available.

Production before isolated start:
- `name=/vpnkit status=running restart=0 started=2026-06-02T13:47:35.235471647Z`.

## Server startup evidence

After adding empty temp ccd directories, both isolated servers started with OpenVPN and tproxy-mode listeners:
- Outer and inner OpenVPN servers reached `Initialization Sequence Completed`.
- TPROXY runtime listeners were present on `1194/udp`, `2082/tcp+udp`, `2083/tcp`, and `5353/udp`.
- Initial outer `OVPN_TO_SINGBOX` counters before the inner attempt were zero for UDP DNS return, TCP return, and non-DNS UDP TPROXY.

## Nested client result

Result: **FAIL for full inner OpenVPN-over-OpenVPN**.

Sanitized moscow-tiger client evidence:

```text
OUTER_UP
ROUTE_TO_INNER
<inner-container-ip> via <ip> dev tun0 src <ip> uid 0
    cache
INNER_TIMEOUT
```

Inner client log excerpt, sanitized:

```text
UDPv4 link remote: [AF_INET]<inner-container-ip>:1194
TLS Error: TLS key negotiation failed to occur within 60 seconds (check your network connectivity)
TLS Error: TLS handshake failed
UDPv4 link remote: [AF_INET]<inner-container-ip>:1194
TLS Error: TLS key negotiation failed to occur within 60 seconds (check your network connectivity)
TLS Error: TLS handshake failed
```

Interpretation:
- The outer tunnel established successfully.
- The client route to the inner container endpoint went through `dev tun0`, proving the inner OpenVPN UDP attempt was injected into the outer tunnel path.
- The inner tunnel did not establish; `tun1` never appeared within the wait window.

## Failure-path packet evidence

Outer isolated server counters after the inner attempt:

```text
Chain OVPN_TO_SINGBOX (1 references)
    pkts      bytes target     prot opt in     out     source               destination
       0        0 RETURN     udp  --  *      *       0.0.0.0/0            0.0.0.0/0            udp dpt:53
       0        0 RETURN     tcp  --  *      *       0.0.0.0/0            0.0.0.0/0
      15     1230 TPROXY     udp  --  *      *       0.0.0.0/0            0.0.0.0/0            TPROXY redirect 0.0.0.0:2082 mark 0x1/0x1
```

Outer DNS/TCP special-case counters stayed at zero:

```text
OVPN_TPROXY_DNS: 0 packets / 0 bytes
OVPN_TPROXY_TCP: 0 packets / 0 bytes
```

Tcpdump summaries:
- Outer-container tcpdump for traffic to `<inner-container-ip>:1194/udp` started and listened, but captured no packet lines.
- Inner-container tcpdump on `udp port 1194` started and listened, but captured no packet lines.
- Inner server log showed startup/listeners only and no accepted OpenVPN client session during the nested attempt.

Interpretation:
- Non-DNS UDP packets from the inner OpenVPN attempt reached the outer server's `OVPN_TO_SINGBOX` TPROXY rule.
- No matching UDP packets were observed leaving the outer container toward the inner container or arriving at the inner OpenVPN server.
- This is a concrete non-DNS UDP TPROXY forwarding failure for nested OpenVPN handshakes, not an outer-connect failure.

## Cleanup and production safety

Cleanup completed:
- Removed moscow-tiger container `nested-match-21342`, image `vpnkit_match_nested_client_21342_21343-image`, and temp path `/tmp/vpnkit_match_nested_client_21342_21343`.
- Removed vibe-practicum Compose projects `vpnkit_match_outer_21342` and `vpnkit_match_inner_21343`, their containers, volumes, local images, shared network `vpnkit_match_net_21342_21343`, and temp path `/tmp/vpnkit_match_nested_21342_21343`.
- Post-cleanup isolated-resource checks found no matching containers/network and confirmed the temp base path was removed.

Production after cleanup:
- `name=/vpnkit status=running restart=0 started=2026-06-02T13:47:35.235471647Z`.
- Production `vpnkit` restart count and start time were unchanged before/after.

## Current AC2 status

AC2 full inner OpenVPN-over-OpenVPN remains **not proven / failing** with decisive sanitized evidence:
- Outer tunnel: passed.
- Route to inner via outer `tun0`: passed.
- Outer non-DNS UDP TPROXY counter increment: passed as failure-path evidence.
- Packet egress from outer to inner / ingress at inner: not observed.
- Inner tunnel `tun1`: failed to appear.
