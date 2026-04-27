# TProxy canary results

Date: 2026-04-27

## Status

Successful.

User tested `pixel-7-pro` with Tailscale exit-node enabled and TProxy canary active.

Reported result:

```text
Everything works great. Pixel is fast and stable.
Telegram works. YouTube works. 2ip.ru shows Russia/direct.
A non-RU IP check shows Netherlands/proxy. Ozon works and does not block as VPN.
```

Detailed checklist: [`PIXEL_ACCEPTANCE_CHECKLIST.md`](PIXEL_ACCEPTANCE_CHECKLIST.md).

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
- multicast/reserved ranges;
- Russian IPs via `geoip-ru`;
- Russian-only domains via `geosite-ru-available-only-inside`;
- Russian TLDs and a small curated list for Yandex/2GIS/Avito infra.

Everything else:

```text
xray-socks-out -> 127.0.0.1:10808 -> VLESS
```

## Conclusion

TProxy canary is the correct direction. The earlier TCP-only REDIRECT canary should be considered deprecated.

Next steps:

1. Keep phone canary running for longer stability testing.
2. Add more devices one-by-one through the same Tailscale exit-node + VPS routing model.
3. Run [`PIXEL_ACCEPTANCE_CHECKLIST.md`](PIXEL_ACCEPTANCE_CHECKLIST.md) or a copy of it for each new device.
4. Keep rollback scripts ready and do not expand to all devices at once.
