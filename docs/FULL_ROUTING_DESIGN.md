# Full routing design

## Priority

First make the canary client fully go through VPN/proxy. Then add direct whitelist rules.

Correct priority:

```text
1. Safety/rollback
2. One canary client only
3. TCP + UDP + DNS all captured
4. Default route -> proxy/VLESS
5. Only then add direct whitelist exceptions
```

## Target policy v1

For `pixel-7-pro` only:

```text
private/local/tailscale management -> direct/bypass
all normal internet TCP/UDP/DNS -> proxy/VLESS
```

No fancy direct whitelist at first except things required for safety.

## Target policy v2

After v1 is stable:

```text
private/local/tailscale -> direct
RU whitelist -> direct
Steam/Valve/games maybe -> direct
Telegram/YouTube/default -> proxy unless proven better direct
```

## Why this order

The previous TCP-only `REDIRECT` canary was not a valid full VPN test:

- TCP only;
- UDP/QUIC not captured;
- DNS not captured;
- domain rules depended on sniffing;
- Telegram behaved inconsistently.

So the next attempt should be a full-path canary, not partial TCP redirect.

## Candidate implementation

Use sing-box as the routing layer with full TCP/UDP/DNS support.

Preferred direction to investigate:

- sing-box TUN or TProxy inbound;
- policy routing/firewall rules only for source `100.109.247.47` from `tailscale0`;
- default outbound to existing Xray SOCKS `127.0.0.1:10808` or native VLESS later;
- DNS hijack into sing-box DNS;
- no VPS host traffic capture.

## Safety constraints

Never proxy/capture:

- VPS host-originated traffic;
- public SSH `45.12.74.211:22`;
- Tailscale control/SSH traffic;
- `100.64.0.0/10` management paths;
- local/private ranges needed for management.

## Rollback requirement

Before enabling full canary:

- exact enable script;
- exact disable script;
- rules marked with comments/table names;
- tested disable path;
- SSH session kept open while testing.

## Next concrete step

Research and prepare a full canary config using sing-box TUN/TProxy, but do not enable until reviewed.
