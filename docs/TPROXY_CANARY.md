# Pixel TProxy canary

## Goal

Canary full TCP+UDP routing for only `pixel-7-pro`:

```text
pixel-7-pro 100.109.247.47 -> tailscale0 -> TProxy :2082 -> sing-box -> Xray/VLESS default
```

This is intended to replace the earlier TCP-only REDIRECT canary.

## Why TProxy

- Captures TCP and UDP.
- Preserves original destination better than plain REDIRECT.
- Can include DNS UDP/TCP 53.
- Scoped by source IP and interface.

## Policy v1

- private/local/Tailscale ranges bypass TProxy/direct.
- all other TCP+UDP goes to sing-box.
- sing-box final/default is Xray SOCKS `127.0.0.1:10808` -> VLESS Reality.

No RU/Telegram/YouTube direct whitelist in v1. First we prove full proxy path works.

## Files

Tracked config:

```text
configs/sing-box/tproxy-canary.json
```

VPS config path:

```text
/etc/sing-box-vibe/tproxy-canary.json
```

Scripts:

```text
scripts/enable-pixel-tproxy-canary.sh
scripts/disable-pixel-tproxy-canary.sh
```

## Enable

```bash
cd /home/kcnc/code/tools/vibe-practicum-vpn
VIBE_PRACTICUM_SUDO_PASSWORD='...' ./scripts/enable-pixel-tproxy-canary.sh
```

## Disable

```bash
cd /home/kcnc/code/tools/vibe-practicum-vpn
VIBE_PRACTICUM_SUDO_PASSWORD='...' ./scripts/disable-pixel-tproxy-canary.sh
```

## Linux mechanics

Policy routing:

```text
fwmark 0x1 -> table 100
local 0.0.0.0/0 dev lo table 100
```

iptables mangle:

```text
PREROUTING -i tailscale0 -s 100.109.247.47 -> VIBE_ROUTER_PIXEL
VIBE_ROUTER_PIXEL private ranges -> RETURN
VIBE_ROUTER_PIXEL tcp/udp -> TPROXY --on-port 2082 --tproxy-mark 0x1/0x1
```

## Rollback

Disable script removes:

- PREROUTING jump;
- custom `VIBE_ROUTER_PIXEL` chain;
- `ip rule` for fwmark;
- route table 100 contents.

Public SSH and host-originated VPS traffic should not be affected because capture is only `PREROUTING -i tailscale0 -s 100.109.247.47`.
