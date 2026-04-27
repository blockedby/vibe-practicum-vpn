# Steam / Dota direct routing

Date: 2026-04-27

## Goal

Steam and Dota do not need VLESS/proxy. They should avoid the proxy hop and go direct from the VPS when clients use the Tailscale exit node.

Important: with the current architecture, "direct" still means:

```text
client -> Tailscale -> VPS -> direct-out from VPS public IP 45.12.74.211
```

It does **not** mean bypassing Tailscale locally on the client. Clients remain simple.

## Applied policy

Added Steam direct rules before the default proxy final route:

```text
geosite-steam -> direct-out
curated Steam/Valve/Dota domain suffixes -> direct-out
```

Remote SRS:

```text
https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-steam.srs
```

Curated fallback suffixes:

```text
steamcontent.com
steampowered.com
steamstatic.com
steamserver.net
steamgames.com
steamusercontent.com
steamcommunity.com
steam-chat.com
steam.tv
valvesoftware.com
valve.net
dota2.com
```

## Expected behavior

- Steam store/community/login/download CDN should use `direct-out`.
- Dota/Valve domain-based traffic should use `direct-out`.
- Non-Steam/non-RU traffic still defaults to `xray-socks-out` / VLESS.

## Caveat

Dota game UDP may connect to raw Valve relay/game server IPs after discovery. If those packets do not carry sniffable domain metadata, domain rules alone may not catch every game-server UDP flow.

If Dota still goes through VLESS or has latency issues, inspect sing-box logs while launching/finding a match and add IP/CIDR rules for observed Valve relay ranges.

## Test checklist

On a client using exit node `awsbbbuslw` and accepted by VPS TProxy:

| Check | Expected | Status |
| --- | --- | --- |
| Steam login | works | TODO |
| Steam store | works | TODO |
| Steam download | stable/direct, no VLESS bottleneck | TODO |
| Dota launch | works | TODO |
| Dota match/relay UDP | acceptable latency; inspect logs if not | TODO |
| ChatGPT/OpenAI after change | still works via VLESS | TODO |

## Log inspection

On VPS:

```bash
journalctl -u sing-box-vibe-router --since '5 minutes ago' --no-pager | egrep 'steam|valve|dota|outbound/(direct|socks)'
```
