# Public non-DNS UDP vpnkit TPROXY variants matrix

Date: 2026-06-03
Executor: aad-implementer
Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vpnkit-tproxy-udp-nested`
Branch: `vpnkit-tproxy-udp-nested`

## Safety and topology

- Loaded `config/private-endpoints.local.env` without printing values.
- Isolated vpnkit test servers ran on `vibe-practicum`; the OpenVPN client ran on the local host in disposable Docker client containers.
- A separate isolated UDP echo container ran on the secondary host as an echo server only, not as a client. This was required because a same-host echo target routes over the OpenVPN transport interface rather than through outer `tun0`.
- Steam Deck was not touched.
- Production containers were not restarted, recreated, adopted, or mutated.
- Generated profiles, rendered configs, raw logs, tcpdump logs, tarballs, and temp contexts were kept under `/tmp` and removed; only this sanitized matrix/report is retained.

## Production untouched metadata

| Host | Container | Before | After | Result |
|---|---|---|---|---|
| vibe-practicum | `vpnkit` | `status=running restart=0 started=2026-06-02T13:47:35.235471647Z` | `status=running restart=0 started=2026-06-02T13:47:35.235471647Z` | unchanged |
| secondary echo host | `current-vpnkit-1` | `status=running restart=0 started=2026-06-02T12:07:48.941107386Z` | `status=running restart=0 started=2026-06-02T12:07:48.941107386Z` | unchanged |

## Valid separate-host run matrix

All ports below are high UDP ports from fresh isolated runs. `generic` and `private_*` counters are packet/byte summaries only. No endpoint values or raw packet logs are retained.

| # | Variant | Config delta / mode | Isolated resources | Route proof | Echo result | TPROXY / bypass counters | sing-box/debug summary | tcpdump / echo summary | Cleanup | Status |
|---:|---|---|---|---|---|---|---|---|---|---|
| 1 | Current tproxy public UDP baseline | Existing source behavior; temp-only live run. | vibe project `vpnkit_pubudp_v1_23442`, OpenVPN `23442/udp`; echo container `vpnkit-pubudp-echo-v1-23443`, echo `23443/udp`; local client image/container temp-only. | Client `ip route get` to echo target selected `dev tun0`. | Timeout. | Generic public UDP TPROXY `1/51`; private mangle `0/0`; private NAT post `0/0`; private forward `0/0`. | sing-box listeners present `udp/2082`, `udp/5353`, `tcp/2083`; logs had 111 total lines, 10 UDP-related, 10 tproxy-related; no raw logs retained. | tcpdump summaries captured `tun0=0`, `eth0=0` packet lines for echo port; echo server received `0` datagrams. | Server project/temp path removed; echo container removed after follow-up cleanup; local temp logs/profiles/tarballs removed. | FAIL: public UDP entered generic TPROXY and no response arrived. |
| 2 | Explicit tproxy inbound `network: [tcp, udp]` + `udp_timeout` | Temp rendered sing-box config changed only for this variant. | vibe project `vpnkit_pubudp_v2_23444`, OpenVPN `23444/udp`; echo container `vpnkit-pubudp-echo-v2-23445`, echo `23445/udp`; local client temp-only. | Client route selected `dev tun0`. | Timeout. | Generic public UDP TPROXY `1/51`; private mangle `0/0`; private NAT post `0/0`; private forward `0/0`. | listeners present `1/1/1`; logs total 111, UDP 10, tproxy 10. | tcpdump `tun0=0`, `eth0=0`; echo receive count `0`. | Removed; echo cleanup required follow-up due temp harness quoting bug. | FAIL: explicit inbound UDP fields did not restore echo. |
| 3 | Route-options `udp_connect` / `udp_timeout` before route | Temp rendered sing-box config inserted a non-final `route-options` rule before UDP route. | vibe project `vpnkit_pubudp_v3_23446`, OpenVPN `23446/udp`; echo container `vpnkit-pubudp-echo-v3-23447`, echo `23447/udp`; local client temp-only. | Client route selected `dev tun0`. | Timeout. | Generic public UDP TPROXY `1/51`; private mangle `0/0`; private NAT post `0/0`; private forward `0/0`. | listeners present `1/1/1`; logs total 111, UDP 10, tproxy 10. | tcpdump `tun0=0`, `eth0=0`; echo receive count `0`. | Removed; echo cleanup required follow-up due temp harness quoting bug. | FAIL: route-options did not restore echo. |
| 4 | Force UDP route to `direct-out` | Temp rendered sing-box config changed the `vpnkit-tproxy-in` UDP route and final outbound to `direct-out`. | vibe project `vpnkit_pubudp_v4_23448`, OpenVPN `23448/udp`; echo container `vpnkit-pubudp-echo-v4-23449`, echo `23449/udp`; local client temp-only. | Client route selected `dev tun0`. | Timeout. | Generic public UDP TPROXY `1/51`; private mangle `0/0`; private NAT post `0/0`; private forward `0/0`. | listeners present `1/1/1`; logs total 111, UDP 10, tproxy 10. | tcpdump `tun0=0`, `eth0=0`; echo receive count `0`. | Removed; echo cleanup required follow-up due temp harness quoting bug. | FAIL: forcing direct outbound did not restore echo, so failure is not only selected-native outbound choice. |
| 5 | nftables TPROXY runtime canary | Temp-only runtime replacement attempt: after startup, flush iptables mangle TPROXY chain and install nftables prerouting TPROXY chain. | First attempt `vpnkit_pubudp_v5_23450`/`23450` + echo `23451`; retry `vpnkit_pubudp_v5_23550`/`23550` + echo `23551`. | Not run; nft setup failed before client probe. | Not run. | Not collected. | Not collected. | Not collected. | Both isolated attempts cleaned; retry echo container removed after follow-up cleanup. | SETUP-FAIL/INFEASIBLE in this temp harness: nft rule syntax was rejected (`return` in a base chain, then `tcp accept` form); a safe nft variant needs a validated nft TPROXY ruleset before live probing. |
| 6 | sing-box TUN-mode canary | Marked infeasible before live mutation. | No live resources. | Not run. | Not run. | Not collected. | Current entrypoint `tun` mode uses `config.json` unless a new source template is introduced, and `setup-routing.sh` waits for `sb-tun0`; current tracked config has no tun inbound. | Not run. | No resources created. | INFEASIBLE in scope: requires source/runtime template changes beyond a temp canary to avoid startup deadlock. |
| 7 | Pragmatic port-based public UDP bypass fallback comparison | Temp-only runtime iptables insertion before generic TPROXY for the echo endpoint/port, with MASQUERADE/FORWARD rules; no source change. | vibe project `vpnkit_pubudp_v7_23454`, OpenVPN `23454/udp`; echo container `vpnkit-pubudp-echo-v7-23455`, echo `23455/udp`; local client temp-only. | Client route selected `dev tun0`. | Timeout. | Generic public UDP TPROXY `0/0`; private mangle `0/0`; private NAT post `0/0`; private forward `0/0`. | listeners present `1/1/1`; logs total 111, UDP 10, tproxy 10. | tcpdump `tun0=0`, `eth0=0`; echo receive count `0`. | Removed; echo cleanup required follow-up due temp harness quoting bug. | FAIL as a response path; useful distinction: the temp bypass kept the packet off generic TPROXY, but still did not produce an echo response in this topology. |

## Invalid same-host topology pre-run

A pre-run used the echo endpoint on the same public host as the outer OpenVPN server. It was discarded as acceptance evidence because the local client route to that target selected the OpenVPN transport interface (`eth0`) rather than outer `tun0`. Resources from that pre-run were cleaned with follow-up `sudo` for root-owned temp log directories.

## Interpretation and recommendation

- Variants 1-4 consistently show the required distinction: the public echo target routes through the outer tunnel (`tun0`), generic public UDP TPROXY increments exactly one packet, private UDP bypass counters remain zero, and no response reaches the echo server.
- Variant 4 indicates the failure is not simply the configured `selected-native-out` versus `direct-out` outbound choice.
- Variant 7 shows that a narrow runtime bypass can avoid the generic TPROXY rule (`0/0` generic counter), but the quick temp bypass did not prove a working public UDP fallback.
- No robust source/config fix emerged from this matrix. Recommendation: keep the existing private UDP bypass for nested private targets; do not claim generic public UDP TPROXY support. A follow-up should prototype a validated nftables TPROXY ruleset or an explicit operator-configured public UDP endpoint bypass in a dedicated source/test slice.
