# TProxy canary results

Date: 2026-04-27

## Status

Successful.

User tested `pixel-7-pro` with Tailscale exit-node enabled and TProxy canary active.

Reported result:

```text
Everything works great.
```

## Active canary behavior

Only `pixel-7-pro` Tailscale IP is captured:

```text
100.109.247.47
```

Captured traffic:

- TCP
- UDP
- DNS traffic as UDP/TCP traffic

Path:

```text
pixel-7-pro -> Tailscale -> VPS tailscale0 -> iptables TPROXY :2082 -> sing-box -> Xray SOCKS 127.0.0.1:10808 -> VLESS Reality
```

Bypass/direct:

- private/local ranges;
- Tailscale CGNAT range `100.64.0.0/10`;
- multicast/reserved ranges.

Everything else:

```text
xray-socks-out -> 127.0.0.1:10808 -> VLESS
```

## Conclusion

TProxy canary is the correct direction. The earlier TCP-only REDIRECT canary should be considered deprecated.

Next steps:

1. Keep phone canary running for longer stability testing.
2. Add a status/check script to show active rules and service health.
3. Add optional direct whitelist rules carefully.
4. Later expand from one phone to selected devices or all Tailscale clients.
