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

## 2026-06-03 continuation after UDP pre-sniff route fix

Code/config change:
- Added a tproxy-route rule for `vpnkit-tproxy-in` UDP before the sniff rule in `config/sing-box/config.tproxy.json.template`.
- This is intended to route opaque UDP/OpenVPN handshake packets directly to `selected-native-out` without waiting for or consuming protocol sniffing.

Fresh local evidence:
- Automated checks passed; see `verification/tproxy-udp-debug-2026-06-03-nondns.md`.
- Isolated local Docker tproxy smoke project `vpnkit_tproxy_udp_nested_lab2` on `21196/udp` passed OpenVPN connect, UDP DNS, HTTPS hostname, and literal-IP HTTPS, then cleanup removed containers/volumes/network.

Live nested rerun status:
- BLOCKED before live mutation. The available gitignored `config/private-endpoints.local.env` in this worktree currently provides an unresolved placeholder VPS SSH alias and lacks a remote client host value.
- Because valid private endpoint/SSH values are required for the approved isolated live-host staging, no live nested server/client containers were created and no production containers were touched.

Current AC2 status:
- The previous nested failure remains the latest live nested evidence.
- The code fix is ready for a fresh isolated live nested rerun once valid private endpoint values are available.

## 2026-06-03 rerun attempt after routing correction

Requested correction applied:
- Used the user-approved SSH aliases `vibe-practicum` and `moscow-tiger` directly; no separate remote-client env variable was required.
- Private endpoint values were sourced/used only locally and redacted from command output and this artifact.

Isolated resources attempted:
- vibe-practicum outer project/container: `vpnkit_tproxy_nested_outer_21224` / `vpnkit_tproxy_nested_outer_21224-vpnkit-1`, port `21224/udp`.
- vibe-practicum inner project/container: `vpnkit_tproxy_nested_inner_21225` / `vpnkit_tproxy_nested_inner_21225-vpnkit-1`, port `21225/udp`.
- moscow-tiger client harness container/image: `nested-debug-21224` / `vpnkit_tproxy_nested_moscow_client_21224_21225-image`.
- A second setup attempt reserved but did not start servers on `21226/udp` and `21227/udp` after the first profile issue.

Result: BLOCKED before AC2 could be re-proven.
- The isolated outer/inner vpnkit servers on `21224/udp` and `21225/udp` started with tproxy listeners present (`1194/udp`, `2082/tcp+udp`, `2083/tcp`, `5353/udp`) and production `vpnkit` metadata was unchanged.
- The moscow-tiger outer OpenVPN client did not bring up `tun0` within the wait window, so the rerun could not progress to route proof or inner `tun1` establishment.
- The most likely setup blocker is test-profile material mismatch/availability: this worktree only had a generated local `test-client.ovpn`, while the isolated live servers were bootstrapped from copied live rendered server config. A follow-up attempt to reconstruct a matching generated test-client profile from live private PKI stopped before mutation because the first discovered live rendered PKI path lacked `ignat.crt`/`ignat.key`, and continuing broad secret-path probing was not appropriate for a tracked report. No profile contents, private paths, or endpoint values were printed or committed.
- Because `tun0` never established, there is no fresh post-fix AC2 pass/fail evidence for non-DNS UDP OpenVPN-over-OpenVPN transport. The previous live nested failure remains the latest complete nested transport evidence.

Sanitized evidence captured:
- Production before attempt: `name=/vpnkit status=running restart=0 started=2026-06-02T13:47:35.235471647Z`.
- Isolated server listener/counter snapshot showed both isolated servers running and tproxy listeners present; counters were still zero because the outer client did not establish.
- Production after cleanup: `name=/vpnkit status=running restart=0 started=2026-06-02T13:47:35.235471647Z`.

Cleanup status:
- Removed moscow-tiger `nested-debug-21224`, the temporary client harness path, and the temporary client image when present.
- Removed vibe-practicum isolated Compose projects/containers/volumes/networks for `vpnkit_tproxy_nested_outer_21224`, `vpnkit_tproxy_nested_inner_21225`, `vpnkit_tproxy_nested_outer_21226`, and `vpnkit_tproxy_nested_inner_21227` when present.
- Removed temporary vibe-practicum paths `/tmp/vpnkit_tproxy_nested_21224_21225` and `/tmp/vpnkit_tproxy_nested_21226_21227` using sudo where container-created log directories required it.
- Nothing intentionally retained. Production containers were not restarted, recreated, adopted, or mutated.
