# Pixel acceptance checklist

Date: 2026-04-27
Device: `pixel-7-pro`
Tailscale IP: `100.109.247.47`
Mode: Tailscale exit-node `awsbbbuslw` + VPS TProxy canary

## Current expected routing

Default path:

```text
pixel-7-pro -> Tailscale -> VPS tailscale0 -> sing-box TProxy :2082 -> Xray SOCKS :10808 -> VLESS
```

Direct/RU path:

```text
pixel-7-pro -> Tailscale -> VPS tailscale0 -> sing-box TProxy :2082 -> direct-out -> VPS public IP 45.12.74.211
```

## Manual checks

Run these with Tailscale enabled on Pixel and exit-node set to `awsbbbuslw`.

| Check | Expected | Status |
| --- | --- | --- |
| Telegram | works | PASS |
| YouTube | works | PASS |
| 2ip.ru | shows Russia / VPS direct IP `45.12.74.211` when matched direct/RU | PASS |
| 2ip.io / non-RU IP check | shows proxy/VLESS location, observed Netherlands / `212.118.55.209` | PASS |
| Ozon | works, not blocked as VPN | PASS |
| General browsing | fast and stable | PASS |
| DNS/UDP apps | no obvious breakage | PASS |

## Additional optional checks before expanding

| Check | Expected | Status |
| --- | --- | --- |
| Госуслуги | opens/logs in normally | TODO |
| Main bank app/site | opens normally | TODO |
| Yandex Maps | works/direct | TODO |
| 2GIS app/site | works/direct | TODO |
| Avito | opens normally | TODO |
| Tele2 app/site | opens normally | TODO |

## Acceptance result

Pixel canary is accepted as the baseline configuration.

User feedback:

```text
On Pixel everything works, very fast, Telegram works, YouTube works,
2ip.ru shows Russia, non-RU IP check shows Netherlands/proxy,
Ozon works and does not block as VPN.
```

## Expansion policy

Do not switch all devices at once.

Next devices should be added one-by-one to this same Tailscale-exit-node + VPS-routing design. For each device:

1. Add/identify its Tailscale IP.
2. Add it to the canary capture rules.
3. Run this checklist.
4. Keep rollback ready.
5. Commit docs/config after successful validation.
