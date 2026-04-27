# Phase 2 local sing-box router test results

Date: 2026-04-27

## What was installed

Installed `sing-box` from the official SagerNet APT repository, not from source.

Observed version on VPS:

```text
sing-box version 1.13.11
Environment: go1.25.9 linux/amd64
```

## What was started

A dedicated systemd service was created:

```text
sing-box-vibe-router.service
```

It currently runs only a local SOCKS test router:

```text
127.0.0.1:2080
```

Config path on VPS:

```text
/etc/sing-box-vibe/test-router.json
```

Tracked source config:

```text
configs/sing-box/test-router.json
```

## Safety status

No Tailscale traffic interception is enabled yet.

Current live Tailscale exit-node behavior remains unchanged:

```text
Tailscale client -> VPS tailscale0 -> Tailscale NAT -> eth0 -> direct internet
```

The sing-box router is only reachable locally from the VPS via `127.0.0.1:2080`.

## Current test routing policy

- private/local/Tailscale ranges -> direct
- Russian TLD whitelist -> direct
- BitTorrent protocol -> direct
- final/default -> Xray SOCKS `127.0.0.1:10808` -> VLESS Reality

## Manual checks

Direct VPS external IP:

```text
45.12.74.211
```

Via local sing-box SOCKS:

```text
212.118.55.209
```

This confirms default traffic through `127.0.0.1:2080` goes via Xray/VLESS.

`ya.ru` through sing-box returned headers with Yandex seeing VPS IP in cookie data, consistent with RU-domain direct routing.

`api.telegram.org` through sing-box returned HTTP 302 successfully.

## Next step

Canary routing for only `pixel-7-pro` Tailscale IP should be designed next, but not enabled until rollback commands and exact iptables/nftables rules are reviewed.
