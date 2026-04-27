# Pixel canary routing

## Purpose

Route only `pixel-7-pro` TCP traffic from Tailscale through the experimental sing-box router.

This does not affect:

- VPS host-originated traffic;
- public SSH;
- Tailscale SSH/control;
- other Tailscale clients.

## Known Tailscale IP

```text
pixel-7-pro: 100.109.247.47
```

## Current canary mechanism

A single iptables NAT PREROUTING rule redirects TCP traffic from the phone arriving on `tailscale0` to sing-box redirect inbound:

```text
-i tailscale0 -s 100.109.247.47 -p tcp ! --dst-type LOCAL -> REDIRECT :2081
```

The rule is marked with comment:

```text
vibe-router-pixel-canary
```

UDP is not redirected yet. This is intentional for the first canary because TCP redirect is simpler and safer than UDP/TProxy. Some apps may still use UDP/QUIC directly until we add a UDP-capable design.

## Enable

```bash
cd /home/kcnc/code/tools/vibe-practicum-vpn
VIBE_PRACTICUM_SUDO_PASSWORD='...' ./scripts/enable-pixel-canary.sh
```

## Disable

```bash
cd /home/kcnc/code/tools/vibe-practicum-vpn
VIBE_PRACTICUM_SUDO_PASSWORD='...' ./scripts/disable-pixel-canary.sh
```

## Expected behavior

On phone with Tailscale exit-node enabled:

- TCP traffic not in direct whitelist should exit via VLESS IP, currently observed as `212.118.55.209`.
- RU whitelist domains should still exit directly as VPS IP `45.12.74.211`.
- UDP/QUIC may still exit directly via VPS until we add TProxy or disable QUIC on client/app side.

## Rollback

Run disable script. If needed:

```bash
ssh vibe-practicum 'printf "%s\n" "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S systemctl restart tailscaled'
```
