# Canary observations

## 2026-04-27: 2ip.ru routed through proxy

Observation from phone canary:

- `2ip.ru` showed proxy/VLESS IP instead of VPS direct IP.

Reason:

- The first canary used TCP `REDIRECT` only.
- In transparent redirect mode, sing-box initially sees destination IP, not the original domain name resolved by the phone.
- Domain suffix rules like `.ru` only work if sing-box receives a domain (SOCKS case) or sniffs it from HTTP Host / TLS SNI.

Change applied:

- Added a route `sniff` action for inbound `canary-redirect-in` with timeout `1s`.

Expected effect:

- HTTPS/TLS sites with SNI, e.g. `2ip.ru`, should now match `.ru` and route direct.
- This still will not solve all UDP/QUIC/DNS cases; UDP is not intercepted in the current canary.
