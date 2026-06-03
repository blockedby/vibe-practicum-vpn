# Inner/nested OpenVPN-over-OpenVPN validation attempt

Date: 2026-06-03

## Scope and safety gates

- Private endpoints were loaded with the approved local-only pattern and were not printed.
- Steam Deck was not touched.
- Production `vpnkit` on vibe-practicum was inspected only with safe Docker metadata. It was not restarted, recreated, adopted, or mutated.
- All generated/reused client profiles and logs remained in temp/gitignored locations and were cleaned up; profile contents and real endpoints are not recorded here.

## Isolated resources used

vibe-practicum:
- Temporary source/state path: `/tmp/vpnkit_tproxy_nested_21202_21203` (removed during cleanup).
- Outer isolated server project: `vpnkit_tproxy_nested_outer_21202`.
- Outer isolated server container: `vpnkit_tproxy_nested_outer_21202-vpnkit-1`.
- Outer OpenVPN test port: `21202/udp`.
- Inner isolated server project: `vpnkit_tproxy_nested_inner_21203`.
- Inner isolated server container: `vpnkit_tproxy_nested_inner_21203-vpnkit-1`.
- Inner OpenVPN test port: `21203/udp`.

moscow-tiger:
- Temporary client harness path: `/tmp/vpnkit_tproxy_nested_client_21202_21203` (removed during cleanup).
- Client Compose project: `vpnkit_tproxy_nested_moscow_client_21202_21203`.
- Debug client container name used for the blocker-capture run: `nested-debug-21202` (removed during cleanup).

## Harness approach

The repo/local bundle still did not include a CA private key or documented tooling path that could safely issue a distinct second client identity from this worktree. To make a real nested attempt anyway, the harness used two separate isolated vpnkit server containers on two distinct UDP ports:

1. Start an outer OpenVPN connection from an isolated moscow-tiger client container to `vpnkit_tproxy_nested_outer_21202`.
2. Rewrite the inner profile to target a different endpoint spelling for the same isolated host on port `21203/udp`; after the outer connection, `ip route get <inner-endpoint>` resolved via `dev tun0`, proving the inner OpenVPN transport attempt was routed through the already-established outer tunnel rather than directly through Docker `eth0`.
3. Start a second OpenVPN client process in the same isolated client container with `dev tun1` against `vpnkit_tproxy_nested_inner_21203`.

This avoids simultaneous reuse of one client identity against the same server process. It is still not a fully independent client-identity proof because the available bundle only had the existing `test-client` profile.

## Result

Result: BLOCKED for full AC2 inner VPN-over-VPN closure.

Evidence from the nested attempt:
- Outer tunnel came up successfully: client printed `OUTER_UP`.
- Route to the inner endpoint after outer tunnel establishment went through the outer tunnel: `ip route get <inner-endpoint>` showed `dev tun0` with a tunnel source address.
- The inner OpenVPN client attempted UDP to `<inner-endpoint>:21203`, but `tun1` never appeared within the wait window.
- The inner OpenVPN client log reached `UDPv4 link remote: [AF_INET]<inner-endpoint>:21203` and then made no successful handshake progress before the timeout.
- Outer isolated server `OVPN_TO_SINGBOX` non-DNS UDP TPROXY rule incremented during the inner attempt: `9` packets / `738` bytes on the UDP TPROXY rule to port `2082`.
- Outer DNS redirect counters remained `0`, as expected for an OpenVPN UDP transport attempt rather than DNS.
- Inner isolated server logs showed startup/listeners only and no accepted OpenVPN client session during the attempt.

Interpretation:
- The harness proved that the inner UDP OpenVPN transport attempt was injected into the outer tunnel and reached the outer server's non-DNS UDP TPROXY path.
- The current TPROXY/UDP path did not successfully carry that non-DNS UDP OpenVPN handshake to the second isolated OpenVPN server, so full independent inner VPN-over-VPN validation cannot be claimed.
- This is a concrete AC2 blocker, not the previous one-profile-only limitation alone.

## Production untouched evidence

vibe-practicum production container `vpnkit` safe metadata:
- Before isolated start: `name=/vpnkit status=running restart=0 started=2026-06-02T13:47:35.235471647Z`.
- After nested test: `name=/vpnkit status=running restart=0 started=2026-06-02T13:47:35.235471647Z`.
- After cleanup: `name=/vpnkit status=running restart=0 started=2026-06-02T13:47:35.235471647Z`.

No production container was restarted, recreated, adopted, or mutated.

## Cleanup status

- Removed isolated moscow-tiger client container/project and `/tmp/vpnkit_tproxy_nested_client_21202_21203`.
- Removed outer isolated server project `vpnkit_tproxy_nested_outer_21202`, containers, volumes, and network.
- Removed inner isolated server project `vpnkit_tproxy_nested_inner_21203`, containers, volumes, and network.
- Removed vibe-practicum temp path `/tmp/vpnkit_tproxy_nested_21202_21203`.
- Nothing retained intentionally.
