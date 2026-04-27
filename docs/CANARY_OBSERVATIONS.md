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

## 2026-04-27: Telegram stopped in canary, YouTube works

Observation from phone canary:

- YouTube works.
- Telegram stopped working after TCP canary routing was enabled.

Immediate mitigation:

- Added Telegram public IPv4 ranges to direct routing.
- Added Telegram domains to direct routing.

Reasoning:

- Telegram currently works from the VPS direct exit-node path.
- The canary default routes unknown TCP through VLESS, and Telegram may dislike or fail on that path.
- For now Telegram belongs to the fallback/direct-preferred zone, so canary should route it direct.

Tracked Telegram IP ranges:

- `149.154.160.0/20`
- `91.108.4.0/22`
- `91.108.8.0/22`
- `91.108.12.0/22`
- `91.108.16.0/22`
- `91.108.20.0/22`
- `91.108.56.0/22`

## 2026-04-27: Telegram still failed, canary disabled

After adding Telegram direct rules, Telegram still did not work from the phone.
Canary was disabled to restore the baseline phone path.

Observed sing-box logs showed Telegram IPs like `149.154.167.50:443` being routed direct, but direct dial timed out inside sing-box:

```text
outbound/direct[direct-out]: dial tcp 149.154.167.50:443: i/o timeout
```

This suggests the transparent redirect/direct outbound path is not equivalent to normal Linux forwarding/NAT path, or Telegram app has additional flows not covered by TCP-only redirect. The baseline Tailscale exit-node direct NAT path should be re-tested after disabling canary.

Current state after this observation:

- Pixel canary iptables rule removed.
- sing-box service remains running locally (`127.0.0.1:2080`, redirect `:2081`) but no Tailscale traffic is redirected into it.

Next investigation options:

1. Keep canary disabled and verify Telegram recovers on phone.
2. Avoid transparent REDIRECT for Telegram by excluding Telegram IP ranges at iptables level before redirect.
3. Consider sing-box TUN/auto_route or TProxy instead of TCP REDIRECT if we continue transparent routing.
