# UDP echo TPROXY/private-UDP blocker fix verification

Date: 2026-06-03
Executor: aad-implementer

## Safety

- Used isolated local Docker resources only; no production containers or live hosts were touched.
- Used fresh local names/ports/networks:
  - RED: project `udp_echo_fix_red2`, port `21403/udp`, network `udp_echo_fix_red2_net`.
  - GREEN echo: project `udp_echo_fix_impl`, port `21404/udp`, network `udp_echo_fix_impl_net`.
  - Nested rerun: project `udp_echo_fix_nested`, port `21405/udp`, network `udp_echo_fix_nested_net`.
- Temporary profiles/configs were copied under `/tmp/udp_echo_fix_*` and only profile `remote` lines / an inner test subnet were rewritten there.
- No profile, PKI, rendered config, endpoint value, or private log content was committed or printed.
- Cleanup verification after checks found no `udp-echo-fix*` containers or `udp_echo_fix*` networks left.

## RED reduced echo evidence

Harness shape:
- Outer vpnkit tproxy server from the current image, with a temp sing-box fixture where `selected-native-out` was intentionally `block` and DNS rule-set detours were pointed to `direct-out` to isolate non-DNS UDP behavior.
- UDP echo target on the vpnkit-side Docker network at `udp-echo-fix-red2-echo:18080`.
- OpenVPN client from a separate Docker network connected through host port `21403/udp`.

Result before the routing fix:

```text
RED2 echo target ip=172.20.0.2 port=18080
CLIENT_OUTER_UP
172.20.0.2 via 10.89.0.1 dev tun0 src 10.89.0.2 uid 0
read error: read udp4 10.89.0.2:<port>->172.20.0.2:18080: i/o timeout
RED2 status=1
udp-echo-server listening :18080
OVPN_TO_SINGBOX generic UDP TPROXY: 1 packet / 49 bytes
EXPECTED_RED2_FAILURE
```

Additional hypothesis checks:
- A sing-box private `direct-out` route alone did not make the echo pass.
- `route-options` with `udp_connect`/`udp_timeout` did not make the echo pass.
- Explicit `MARK --set-mark` and `ip_nonlocal_bind=1` did not make the echo pass.
- TPROXY was terminal in this backend; a post-TPROXY fallback did not run.
- A pre-TPROXY private UDP direct-forward/MASQUERADE hypothesis passed.

## Implemented fix

`docker/vpnkit/setup-routing.sh` now installs tproxy-mode-only private UDP bypass wiring before the generic TPROXY rule:
- `OVPN_TO_SINGBOX` private UDP `RETURN` rules for `10.0.0.0/8`, `172.16.0.0/12`, and `192.168.0.0/16` by default.
- `OVPN_TPROXY_UDP_POST` MASQUERADE chain for the same destinations.
- `OVPN_TPROXY_UDP_FWD` FORWARD accept rules for outbound and established return UDP.
- The bypass is tproxy-mode only and can be disabled with `VPNKIT_TPROXY_PRIVATE_UDP_BYPASS_ENABLED=false`; default redirect mode is unchanged.

## GREEN reduced echo evidence

Harness:
- Project `udp_echo_fix_impl`, port `21404/udp`, network `udp_echo_fix_impl_net`.
- No manual iptables edits; source implementation only.

Result:

```text
IMPL echo target ip=172.20.0.2 port=18080
CLIENT_OUTER_UP
172.20.0.2 via 10.89.0.1 dev tun0 src 10.89.0.2 uid 0
udp-echo-client success bytes=21
udp-echo-server received 21 bytes from 172.20.0.3:<port>
OVPN_TO_SINGBOX 172.16.0.0/12 private UDP bypass: 1 packet / 49 bytes
OVPN_TO_SINGBOX generic UDP TPROXY: 0 packets / 0 bytes
OVPN_TPROXY_UDP_POST 172.16.0.0/12 MASQUERADE: 1 packet / 49 bytes
OVPN_TPROXY_UDP_FWD outbound/return 172.16.0.0/12: 1 packet each
IMPL_ECHO_SUCCESS
```

Note: the passing path intentionally bypasses the terminal sing-box TPROXY target for private UDP destinations before it can blackhole the packet. Public/non-private non-DNS UDP remains on the existing TPROXY rule.

## Nested local rerun evidence

Harness:
- Project `udp_echo_fix_nested`, outer port `21405/udp`, network `udp_echo_fix_nested_net`.
- Outer vpnkit in tproxy mode with the implemented private UDP bypass.
- Inner vpnkit on the same isolated Docker network, using a temp inner OpenVPN subnet `10.90.0.0/24` to avoid tun0/tun1 address conflict.
- Client connected to outer, then started inner OpenVPN to the inner container private IP `172.20.0.2:1194/udp` through `tun0`.

Result:

```text
OUTER_UP
172.20.0.2 via 10.89.0.1 dev tun0 src 10.89.0.2 uid 0
INNER_UP
inet 10.90.0.2/24 scope global tun1
NESTED status=0
OVPN_TO_SINGBOX 172.16.0.0/12 private UDP bypass: 10 packets / 3743 bytes
OVPN_TPROXY_UDP_FWD 172.16.0.0/12 outbound: 10 packets / 3743 bytes
OVPN_TPROXY_UDP_FWD 172.16.0.0/12 return: 7 packets / 3652 bytes
inner server accepted client and assigned 10.90.0.2
```

## Automated checks

Passed:
- `bash tests/vpnkit-setup-routing-test.sh`
- `bash tests/vpnkit-singbox-template-test.sh`
- `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh`
- `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true sing-box check -c <rendered temp tproxy config>` (deprecation warnings only)

Skipped:
- `go test ./...` / Go build: not run because this task touched shell routing/tests/docs only, not Go code.
