# High-level plan

## Objective

Make `vibe-practicum` a central VPN gateway for all devices:

```text
clients -> Tailscale exit node -> vibe-practicum -> direct or VLESS
```

Clients stay simple: install Tailscale, use `awsbbbuslw` as exit node. All complex routing lives on the VPS.

## Routing policy target

1. **Direct whitelist**
   - private/local/Tailscale ranges;
   - Russian services/domains;
   - maybe Steam/Valve/game traffic later;
   - management traffic must always remain direct.

2. **Fallback zone**
   - Telegram and YouTube are high-traffic and may work directly from the VPS sometimes;
   - prefer direct when health checks say direct works;
   - switch these zones to VLESS when direct breaks.

3. **Default**
   - everything not whitelisted and not handled by fallback policy goes through VLESS/proxy.

## Safety principles

- Do not change the VPS host default route.
- Do not proxy host-originated traffic.
- Only route traffic arriving from Tailscale clients, i.e. `tailscale0` forwarding traffic.
- Keep public SSH and Tailscale SSH reachable at all times.
- Every risky change needs:
  - state snapshot;
  - rollback commands/script;
  - canary test on one device before global enablement.

## Phases

### Phase 0 — documentation and snapshots

Status: in progress.

- Keep notes in this repo.
- Snapshot current VPS networking/firewall/Tailscale/Xray state.
- Commit often.
- Do not change live routing yet.

Deliverables:

- `NOTES.md`
- `docs/HIGH_LEVEL_PLAN.md`
- snapshot script and snapshots
- rollback outline

### Phase 1 — understand current baseline

Confirm and document current behavior:

```text
Tailscale exit-node traffic -> VPS NAT -> eth0 -> internet directly
```

Confirm separately:

```text
VPS local Xray SOCKS 127.0.0.1:10808 -> VLESS Reality -> internet
```

No traffic interception yet.

### Phase 2 — test routing layer without interception

Install or stage a lightweight routing layer, likely `sing-box`, but only in local test mode:

```text
127.0.0.1:2080 SOCKS -> routing policy -> direct or Xray SOCKS 127.0.0.1:10808
```

This must not touch Tailscale exit-node traffic yet.

Test with manual requests from the VPS:

- direct whitelist domain should exit as VPS IP;
- default domain should exit through VLESS;
- Telegram/YouTube fallback policy can initially be manual/static.

### Phase 3 — canary one Tailscale client

Intercept only one client, probably `pixel-7-pro`, by source Tailscale IP.

Target:

```text
pixel-7-pro -> tailscale0 -> routing layer -> direct/VLESS
other clients -> unchanged Tailscale direct NAT
VPS host traffic -> unchanged
```

If anything fails, remove canary rule and return to current direct exit-node behavior.

### Phase 4 — expand to all Tailscale clients

After canary is stable, route all Tailscale client exit-node traffic through the routing layer.

Still keep:

- private/Tailscale/management direct;
- rollback path;
- health checks.

### Phase 5 — dynamic fallback

Add health checks for fallback zones:

- Telegram direct health;
- YouTube direct health;
- maybe Docker/GitHub/OpenAI later.

Policy:

```text
if direct healthy -> fallback zone direct
if direct unhealthy -> fallback zone VLESS
default -> VLESS
```

Implementation can be simple at first: script rewrites routing config and reloads service.

### Phase 6 — refine whitelists

Grow direct whitelist carefully:

- RU domains/IPs;
- Steam/Valve if needed;
- banking/government/local services;
- high-volume services that are reliable directly from the VPS.

## Open design decisions

1. Routing layer:
   - sing-box local router;
   - nftables + transparent proxy;
   - hybrid.

2. Proxy path:
   - route to existing Xray SOCKS `127.0.0.1:10808`;
   - or move VLESS outbound into sing-box directly.

3. DNS:
   - keep simple Cloudflare/Google first;
   - later make routing-layer DNS authoritative for domain rules if needed.

4. Fallback switching:
   - manual first;
   - periodic health-check script later.

## Immediate next step

Before implementing live routing:

1. Finish rollback outline.
2. Commit snapshots and plan.
3. Decide Phase 2 routing-layer tool/config.
4. Test only local SOCKS on VPS.
