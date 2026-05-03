# Pixel DNS leak canary

## Goal

Test DNS leak hardening on `pixel-7-pro` only, without changing the normal routing for other clients.

Pixel:

```text
pixel-7-pro 100.109.247.47
```

## What this canary changes

1. Adds two pixel-only `iptables -t mangle PREROUTING` rules before the shared TProxy jump:

```text
-i tailscale0 -s 100.109.247.47 -p udp --dport 53 -> TPROXY :2082
-i tailscale0 -s 100.109.247.47 -p tcp --dport 53 -> TPROXY :2082
```

This catches DNS to Tailscale DNS `100.100.100.100` before the shared `100.64.0.0/10` bypass can return it.

2. Backs up VPS sing-box config once:

```text
/etc/sing-box-vibe/tproxy-canary.json.pre-dns-leak-canary
```

3. Adds `detour: xray-socks-out` to each sing-box DNS server in:

```text
/etc/sing-box-vibe/tproxy-canary.json
```

This makes sing-box's own upstream DNS queries leave through Xray/VLESS rather than direct VPS egress.

## Safety

- Packet capture change is scoped to `pixel-7-pro` source IP only.
- Normal pixel TProxy canary remains intact.
- Other accepted clients are not given extra DNS hijack rules.
- Disable script removes only the DNS canary rules and restores the backed-up sing-box config.

## Enable

```bash
cd /home/kcnc/code/tools/vibe-practicum-vpn
VIBE_PRACTICUM_SUDO_PASSWORD='...' ./scripts/enable-pixel-dns-leak-canary.sh
```

## Disable / rollback

```bash
cd /home/kcnc/code/tools/vibe-practicum-vpn
VIBE_PRACTICUM_SUDO_PASSWORD='...' ./scripts/disable-pixel-dns-leak-canary.sh
```

## Test checklist on Pixel

With Tailscale exit-node enabled on Pixel:

1. Open DNS leak tests:
   - `https://browserleaks.com/dns`
   - `https://dnsleaktest.com`
   - `https://ipleak.net`
2. Expected: no Russian/home ISP DNS. Ideally only proxy/VLESS-side resolver/IPs.
3. Check normal sites:
   - Telegram
   - YouTube
   - Gemini/Google
   - ChatGPT/OpenAI
   - `2ip.ru`
   - Ozon / RU banking if needed
4. If anything breaks: run rollback command above.

## VPS verification

```bash
sudo iptables -t mangle -S PREROUTING | grep vibe-router-pixel-dns-canary
sudo journalctl -u sing-box-vibe-router --since '5 minutes ago' --no-pager
```
