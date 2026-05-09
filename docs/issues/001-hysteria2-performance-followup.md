# Issue: Future Hysteria2 performance tuning for lil-sweden

Date: 2026-05-09

## Context

`lil-sweden` is running the official Hysteria2 server as an upstream candidate for
`vibe-vpn`.

Public endpoint:

```text
computer.peacedata.company:18443/udp
TLS SNI: computer.peacedata.company
ALPN: h3
```

The current performance is acceptable for now, so this is a follow-up idea, not
active work.

## Current acceptable baseline

Measured from `vibe-practicum` through Xray Hysteria2 outbound to `lil-sweden`:

```text
Xray -> Hysteria2 -> lil-sweden -> internet
Cloudflare 50MB download: roughly 120-150 Mbit/s
best observed single-run: ~152 Mbit/s
```

This is enough for the current use case.

## What was already tried

- Switched Hysteria server side from Xray inbound experiments to the official
  `apernet/hysteria` binary.
- Added real domain and TLS certificate:
  - `computer.peacedata.company`
  - Let's Encrypt certificate managed by Caddy
  - Hysteria `sniGuard: strict`
  - client no longer needs `allowInsecure`.
- Tested Xray Hysteria2 outbound with `address: computer.peacedata.company` and
  `serverName: computer.peacedata.company`.
- Tried Xray `finalmask.quicParams` Brutal variants:
  - default / BBR-ish behavior: ~120 Mbit/s average
  - `force-brutal` 150 Mbit/s: similar
  - `force-brutal` 200 Mbit/s: best so far, ~140 Mbit/s average, ~152 Mbit/s max
  - `force-brutal` 300 Mbit/s: less stable, no clear improvement
- Changed Hysteria server from `ignoreClientBandwidth: true` to
  `ignoreClientBandwidth: false`, so client-side Brutal bandwidth hints can take
  effect.
- Raised UDP/QUIC socket buffers on both `lil-sweden` and `vibe-practicum`:

```text
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 262144
net.core.wmem_default = 262144
```

## Related raw link observations

The direct `vibe-practicum -> lil-sweden` path looks stronger than the current
proxied single-download result:

```text
ping: ~43 ms, 0% loss
UDP iperf 100-200 Mbit/s: 0% loss
TCP iperf multi-stream: previously observed around ~492 Mbit/s one direction
reverse TCP iperf: previously observed around ~98 Mbit/s
```

External test endpoints vary significantly. `proof.ovh` is a poor benchmark for
this host; Cloudflare speed endpoint is more representative.

## Future ideas, if more speed/stability is needed

1. Compare Xray Hysteria outbound against the official Hysteria client on
   `vibe-practicum` using the same domain/cert/auth.
   - If the official client is much faster, Xray's Hysteria outbound is likely
     the bottleneck.
2. Enable Hysteria's built-in `speedTest: true` temporarily to measure the tunnel
   itself without external HTTP endpoints.
3. Benchmark multi-connection downloads through the tunnel, not only single TCP
   downloads.
4. Re-test Brutal values around 175-250 Mbit/s; avoid setting values above the
   stable path capacity because that can reduce stability.
5. Investigate MTU / PMTUD if instability appears.
6. If needed later, consider a local official Hysteria client or sing-box path on
   `vibe-practicum` instead of Xray's Hysteria outbound.

## Decision for now

Do not spend more time on this now. Treat ~120 Mbit/s as good enough and proceed
with integrating `lil-sweden` into normal `vibe-vpn` test/list/pick flows.
