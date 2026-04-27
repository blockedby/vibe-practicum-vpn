# Implementation plan

## Phase 0 — safety baseline

- Create rollback/backup scripts.
- Snapshot VPS routing/firewall/Tailscale/Xray state before changes.
- Do not install packet interception yet.

## Phase 1 — local test router on VPS

Run sing-box only with a local SOCKS inbound on `127.0.0.1:2080`:

```text
curl --socks5-hostname 127.0.0.1:2080 ...
```

Routing policy inside sing-box:

- private/tailscale/RU whitelist -> direct
- fallback zone initially static/direct or manual
- final -> Xray SOCKS `127.0.0.1:10808`

No Tailscale client traffic is captured in this phase.

## Phase 2 — one-client canary

Intercept only `pixel-7-pro` traffic from `tailscale0`, if safe.
Keep public SSH and host-originated VPS traffic untouched.

## Phase 3 — expand

After canary works, route all Tailscale client exit-node traffic through the routing layer.
