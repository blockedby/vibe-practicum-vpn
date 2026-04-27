# vibe-practicum VPN / routing notes

Date: 2026-04-27

## Goal

Use VPS `vibe-practicum` as a simple, stable VPN gateway for multiple devices.
Clients should stay dumb/simple: ideally Tailscale only. Complex routing, DNS,
proxy fallback, and future policy should live on the VPS.

Desired policy direction:

- Direct whitelist: traffic that should leave directly from the VPS public IP.
- Fallback zone: high-traffic services like Telegram/YouTube that may work direct
  today but sometimes stop working from the VPS/provider; prefer direct while
  healthy, fall back to VLESS when unhealthy.
- Default: everything else goes through VLESS/proxy.

Important safety constraint:

- Do not route the VPS host's own management traffic through proxy.
- Only experiment with traffic arriving from Tailscale clients (`tailscale0`).
- Do not break public SSH (`45.12.74.211:22`) or Tailscale SSH/access.

## VPS

- Host/IP: `45.12.74.211`
- SSH alias: `vibe-practicum`
- SSH user currently used: `deploy`
- Hostname: `awsbbbuslw`
- Domain noted: `baza.peacedata.company`

## Existing services observed

### Tailscale

Installed and running on VPS.

- Tailscale hostname: `awsbbbuslw`
- Tailscale IPv4: `100.121.107.112`
- Tailscale IPv6: `fd7a:115c:a1e0::cc01:6bb2`
- VPS advertises/offers exit node.
- Android `pixel-7-pro` connected and tested with `awsbbbuslw` as exit node.
- With exit node enabled on phone, external IP is VPS IP `45.12.74.211`.
- Telegram eventually worked through this direct exit-node path.

Current exit-node path is direct NAT, not VLESS:

```text
client -> Tailscale tunnel -> VPS tailscale0 -> Linux forwarding/NAT -> eth0 -> internet
```

Observed Tailscale/iptables behavior:

```text
-A ts-forward -i tailscale0 -j MARK --set-xmark 0x40000/0xff0000
-A ts-forward -m mark --mark 0x40000/0xff0000 -j ACCEPT
-A POSTROUTING -j ts-postrouting
-A ts-postrouting -m mark --mark 0x40000/0xff0000 -j MASQUERADE
```

### Xray / VLESS

Xray is installed as a systemd service and running.

- Service: `xray.service`
- Config: `/usr/local/etc/xray/config.json`
- Inbound: SOCKS on `0.0.0.0:10808`, UDP enabled
- Outbound: VLESS Reality to `212.118.55.209:4443`
- UUID currently in config: `4c112d14-0f11-4dc9-898a-ddb2e53936da`
- Reality SNI: `github.com`
- Flow: `xtls-rprx-vision`

Manual check from VPS through SOCKS to Telegram succeeded earlier.

Important: current Tailscale exit-node traffic does **not** automatically enter Xray.
Xray is just a standalone SOCKS/VLESS proxy right now.

### Caddy / web

Caddy is running.

Caddyfile observed:

```text
baza.peacedata.company {
    reverse_proxy localhost:8080
}

positions.peacedata.company {
    reverse_proxy http://100.94.95.32:8880
}
```

### Docker

Docker is running. Observed containers include:

- rustdesk-hbbr
- rustdesk-hbbs
- landing-nginx-1
- landing-app-1
- landing-db-1

### WireGuard fallback

A plain WireGuard server was installed/configured as a fallback path, but is not
being used for the current Tailscale plan.

- Interface: `wg0`
- Address: `10.66.66.1/24`
- Port: UDP `51820`
- Client config generated for `kcnc-pc` at `/root/wg-clients/kcnc-pc.conf` and
  copied locally to `/tmp/vibe-practicum-kcnc-pc.conf`.

This should not affect Tailscale/Xray routing except for the added interface and
NAT rule for `10.66.66.0/24`.

## Current important discovery

Telegram and YouTube currently work directly from the VPS IP path. This was not
always true historically: the provider/network behavior appears to change over
time. Therefore direct routing for Telegram/YouTube may be useful as a preferred
path because it saves proxy traffic, but it needs fallback to VLESS if health
checks fail.

## Desired target topology

```text
Devices (Android/laptops/friends)
  -> Tailscale client, use awsbbbuslw as exit node
  -> VPS receives traffic on tailscale0
  -> VPS routing layer handles only Tailscale-client traffic:
       1. management/private/tailscale ranges: direct/bypass
       2. direct whitelist: direct via eth0
       3. fallback zone: Telegram/YouTube direct if healthy, otherwise VLESS
       4. final/default: VLESS/proxy
  -> direct: eth0 -> internet as 45.12.74.211
  -> proxy: local Xray SOCKS 127.0.0.1:10808 -> VLESS Reality upstream
```

## Direct whitelist candidates

From existing local sing-box config:

- Russian TLDs/domains: `.ru`, `.рф` / `xn--p1ai`, `.su`, `.moscow`, `.tatar`, and other punycode Russian zones from existing config.
- Private/local ranges: `127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `100.64.0.0/10`.
- Maybe Steam/Valve later: `steampowered.com`, `steamcommunity.com`, `steamcontent.com`, `steamstatic.com`, `valvesoftware.com`, `steamserver.net`.
- Game/Steam-ish ports from previous sing-box config: `3659`, `1935`, `5001`, `5795`, `5796`, `7000`, `7777`, `9000`, `10039`, `10040`, `27000-27100`.

## Fallback zone candidates

- Telegram: `telegram.org`, `t.me`, `telegram.me`, `telegram.dog`; IP ranges `149.154.160.0/20`, `91.108.4.0/22`, `91.108.8.0/22`, `91.108.12.0/22`, `91.108.16.0/22`, `91.108.20.0/22`, `91.108.56.0/22`.
- YouTube/Google video: `youtube.com`, `youtu.be`, `googlevideo.com`, `ytimg.com`, `youtubei.googleapis.com`.

## DNS thinking

DNS is not the central problem right now. A simple reliable upstream may be enough: Cloudflare `1.1.1.1`, Google `8.8.8.8`, optionally Quad9/Yandex later.

If using a routing layer such as sing-box, DNS should be configured there so domain rules work consistently. Avoid overbuilding DNS first.

## Possible implementation approaches

### Approach A: sing-box on VPS as routing layer

Pros: domain-aware rules, direct whitelist/default proxy are easy, can route to Xray SOCKS or native VLESS.

Cons: needs careful integration with Tailscale exit-node traffic; must avoid capturing VPS host management traffic.

Safe rollout:
1. Install/run sing-box only as local test SOCKS/HTTP inbound. No traffic capture.
2. Configure direct whitelist -> direct, fallback zone initially manual/static, final -> `socks` outbound to `127.0.0.1:10808`.
3. Test from VPS through local sing-box inbound.
4. Intercept only one test Tailscale client (`pixel-7-pro`) if possible.
5. Expand to all Tailscale clients after validation.

### Approach B: nftables/ipset + transparent proxy

Pros: lightweight at packet level, can scope to `tailscale0` traffic only.

Cons: domain routing requires DNS->ipset/nftset integration; more moving parts and harder to debug for domain/fallback behavior.

## Open questions / next plan

1. Choose routing layer: likely sing-box first, but in test mode only.
2. Decide how to intercept only Tailscale-client traffic without touching VPS host traffic.
3. Decide whether final default should go to Xray SOCKS or native VLESS in sing-box.
4. Design fallback-zone health checks for Telegram and YouTube.
5. Preserve rollback: backup iptables/nftables before changes; no persistent firewall redirect until tested; keep SSH public IP and Tailscale SSH direct.
