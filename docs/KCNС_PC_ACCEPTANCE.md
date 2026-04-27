# kcnc-pc acceptance

Date: 2026-04-27
Device: `kcnc-pc`
OS: Kubuntu/Linux
Tailscale IP: `100.64.19.94`
Exit node: `awsbbbuslw` / `100.121.107.112`

## Result

Accepted as working.

Tailscale auth succeeded and the device is visible in tailnet:

```text
100.64.19.94     kcnc-pc     blockedby@  linux
100.121.107.112  awsbbbuslw  blockedby@  linux  active; exit node
```

The VPS TProxy rule was added for `kcnc-pc`:

```text
-A PREROUTING -s 100.64.19.94/32 -i tailscale0 -m comment --comment vibe-router-kcnc-pc-tproxy-entry -j VIBE_ROUTER_PIXEL
```

External IP check from `kcnc-pc` showed VLESS/proxy egress:

```text
212.118.55.209
```

This confirms `kcnc-pc` is not leaking through raw VPS IP `45.12.74.211` for default/non-RU traffic.

## Practical validation

The active assistant/API session continued working while `kcnc-pc` was using Tailscale exit-node through the VPS TProxy/sing-box/VLESS chain. That validates OpenAI/ChatGPT reachability in practice.

## Current accepted clients

| Device | Tailscale IP | Status |
| --- | --- | --- |
| pixel-7-pro | `100.109.247.47` | accepted |
| kcnc-pc | `100.64.19.94` | accepted |

## Re-enable command

If VPS firewall rules are lost after reboot or manual cleanup:

```bash
cd /home/kcnc/code/tools/vibe-practicum-vpn
VIBE_PRACTICUM_SUDO_PASSWORD='...' CLIENT_NAME='kcnc-pc' CLIENT_TS_IP='100.64.19.94' ./scripts/enable-tproxy-client.sh
```

Client-side Tailscale command:

```bash
sudo tailscale up --exit-node='100.121.107.112' --exit-node-allow-lan-access=true --accept-routes
```
