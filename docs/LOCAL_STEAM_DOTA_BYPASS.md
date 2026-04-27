# Local Steam/Dota bypass on Linux

## Why

VPS-side `direct-out` removes the VLESS hop, but Steam/Dota still goes:

```text
PC -> Tailscale -> VPS -> Steam/Valve
```

For Dota matchmaking/game UDP this can still add too much ping.

For low ping, Steam/Dota should bypass the Tailscale exit-node locally:

```text
Steam/Dota -> local ISP directly
Other traffic -> Tailscale exit-node -> VPS routing
```

## What logs showed

From `kcnc-pc` (`100.64.19.94`) Dota/Steam UDP was going to Valve-like hosts/ports, for example:

```text
103.10.124.117:27050 -> xray-socks-out
155.133.238.194:27056 -> xray-socks-out
155.133.227.35:27017 -> xray-socks-out
155.133.252.85:27054 -> xray-socks-out
```

Some TCP Steam flows were already direct from the VPS, but game UDP still lacked domain metadata and fell through to proxy.

## Linux route-table bypass

Tailscale exit-node uses route table `52`. We can add more-specific Valve/Steam routes to that same table via the local LAN gateway. More-specific routes beat the default `tailscale0` route.

Enable on Linux client:

```bash
cd /home/kcnc/code/tools/vibe-practicum-vpn
./scripts/linux-steam-direct-on.sh
```

Disable:

```bash
cd /home/kcnc/code/tools/vibe-practicum-vpn
./scripts/linux-steam-direct-off.sh
```

## Current bypass CIDRs

```text
103.10.124.0/24
146.66.152.0/21
155.133.224.0/19
162.254.192.0/21
185.5.160.0/22
185.25.180.0/22
192.69.96.0/22
205.196.6.0/24
208.64.200.0/22
```

These are deliberately specific Steam/Valve-looking ranges, based on observed logs plus common Valve ranges.

## Verify

With Tailscale exit-node still enabled:

```bash
ip -4 route get 155.133.238.194
```

Expected after enabling bypass:

```text
155.133.238.194 via 192.168.50.1 dev wlp9s0 ...
```

Not expected:

```text
dev tailscale0
```

## Caveat

This is local client routing complexity, unlike the normal dumb-client model. Use only for gaming machines where low ping matters.
