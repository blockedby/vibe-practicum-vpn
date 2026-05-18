# Steam / Dota direct routing

Date: 2026-04-27
Updated: 2026-05-19

## Goal

Steam and Dota do not need VLESS/proxy. They should avoid the proxy hop and go direct from the VPS when clients use the Tailscale exit node.

Important: with the current architecture, "direct" still means:

```text
client -> Tailscale -> VPS -> direct-out from VPS public IP 45.12.74.211
```

It does **not** mean bypassing Tailscale locally on the client. Clients remain simple.

## Applied policy

Added Steam/game direct rules before the default proxy final route:

```text
geosite-steam -> direct-out
geosite-category-games -> direct-out
geosite-game-platforms-download -> direct-out
curated Steam/Valve/Dota domain suffixes -> direct-out
```

Remote SRS:

```text
https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-steam.srs
https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-games.srs
https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-game-platforms-download.srs
```

`category-games.srs` and `category-game-platforms-download.srs` are intentionally broader than only Steam/Dota. They are used on the VPS-side router because clients stay dumb and Dota/Steam traffic may surface as Steam CDN, Valve, or generic game-platform domains.

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
steam-api.com
steam.tv
s.team
steamdeck.com
steamchina.com
valvesoftware.com
valve.net
dota2.com
historyofdota.com
historyofdota.net
historyofdota.org
```

## Expected behavior

- Steam store/community/login/download CDN should use `direct-out`.
- Dota/Valve domain-based traffic should use `direct-out` when it has sniffable domain metadata.
- Known game-platform download domains from MetaCubeX should use `direct-out`.
- Non-game/non-RU traffic still defaults to `xray-socks-out` / VLESS.

## Caveat

Dota game UDP may connect to raw Valve relay/game server IPs after discovery. If those packets do not carry sniffable domain metadata, domain/rule-set rules alone may not catch every game-server UDP flow.

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
