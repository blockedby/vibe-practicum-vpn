# OpenVPN ASUS `asus-tproxy` -> sing-box TPROXY canary

Live incident: Android/OpenVPN Connect could connect as `asus-tproxy`, traffic entered `tun-asus`, and mangle TPROXY counters increased, but the phone initially had no internet.

## Working model

```text
Android/OpenVPN Connect
-> openvpn-server@vibe-asus UDP/1194
-> tun-asus, client IP 10.89.0.3
-> mangle PREROUTING exact rule
-> VIBE_OVPN_ASUS_TP
-> TPROXY :2082 mark 0x1
-> filter INPUT scoped ACCEPT for mark 0x1
-> shared sing-box-vibe-router :2082
-> xray :10808
-> vibe-vpn current upstream
```

The normal ASUS router profile remains separate:

- `asus` / `10.89.0.2`: direct NAT/full-tunnel or site-to-site.
- `asus-tproxy` / `10.89.0.3`: canary through sing-box/xray.
- `10.89.0.4`-`10.89.0.19`: reserved for additional fixed TPROXY OpenVPN clients.
- `10.89.0.20`-`10.89.0.254`: OpenVPN dynamic pool; do not use for fixed CCD TPROXY profiles.

See `docs/ASUS_OPENVPN_SITE_TO_SITE.md` for the canonical OpenVPN IP allocation map.

## Root cause found

UFW/filter INPUT was dropping packets after TPROXY marked them for local delivery:

```text
[UFW BLOCK] IN=tun-asus SRC=10.89.0.3 DST=8.8.8.8 ... MARK=0x1
```

This made the failure look like `sing-box receive FAIL`, even though mangle counters were growing. TPROXY delivery enters local INPUT, so marked packets from the canary client must be accepted before `ufw-before-input`.

## Required live rules

Exact canary PREROUTING rule, before broad OpenVPN NAT path:

```bash
iptables -t mangle -I PREROUTING 1 \
  -i tun-asus -s 10.89.0.3/32 \
  -m comment --comment 'vibe-vpn-openvpn-asus:tproxy-profile:asus-tproxy' \
  -j VIBE_OVPN_ASUS_TP
```

Local INPUT delivery for TPROXY-marked packets:

```bash
iptables -t filter -I INPUT 1 \
  -i tun-asus -s 10.89.0.3/32 \
  -m mark --mark 0x1/0x1 \
  -m comment --comment 'vibe-vpn-openvpn-asus:tproxy-input-accept:asus-tproxy' \
  -j ACCEPT
```

`VIBE_OVPN_ASUS_TP` bypasses private/special ranges, then TPROXYs TCP/UDP to `:2082` with mark `0x1/0x1`.

## Verification commands

```bash
ssh vibe-practicum 'sudo sed -n "1,120p" /var/log/openvpn/vibe-asus-status.log | grep -E "asus-tproxy|10.89.0.3"'
ssh vibe-practicum 'sudo iptables -t mangle -L VIBE_OVPN_ASUS_TP -v -n -x --line-numbers'
ssh vibe-practicum 'sudo iptables -t filter -L INPUT -v -n -x --line-numbers | grep tproxy-input-accept'
ssh vibe-practicum 'sudo timeout 8 tcpdump -ni tun-asus "host 10.89.0.3 and src port 443" -c 5'
```

Success evidence from the live fix:

```text
149.154.167.50.443 > 10.89.0.3.<port>  # Telegram replies on tun-asus
```

## Persistence

Patch `/usr/local/sbin/vibe-openvpn-asus-rules` or run:

```bash
scripts/openvpn-asus-tproxy-canary-rules.sh --apply-live
```

The persistent state must recreate both:

- `VIBE_OVPN_ASUS_TP` + exact `10.89.0.3/32` PREROUTING rule;
- scoped INPUT ACCEPT for `tun-asus + 10.89.0.3/32 + mark 0x1/0x1`.

## Rollback

```bash
ssh vibe-practicum 'sudo bash -lc '\''
while iptables -t filter -C INPUT -i tun-asus -s 10.89.0.3/32 -m mark --mark 0x1/0x1 -m comment --comment "vibe-vpn-openvpn-asus:tproxy-input-accept:asus-tproxy" -j ACCEPT 2>/dev/null; do
  iptables -t filter -D INPUT -i tun-asus -s 10.89.0.3/32 -m mark --mark 0x1/0x1 -m comment --comment "vibe-vpn-openvpn-asus:tproxy-input-accept:asus-tproxy" -j ACCEPT
done
while iptables -t mangle -C PREROUTING -i tun-asus -s 10.89.0.3/32 -m comment --comment "vibe-vpn-openvpn-asus:tproxy-profile:asus-tproxy" -j VIBE_OVPN_ASUS_TP 2>/dev/null; do
  iptables -t mangle -D PREROUTING -i tun-asus -s 10.89.0.3/32 -m comment --comment "vibe-vpn-openvpn-asus:tproxy-profile:asus-tproxy" -j VIBE_OVPN_ASUS_TP
done
iptables -t mangle -F VIBE_OVPN_ASUS_TP 2>/dev/null || true
iptables -t mangle -X VIBE_OVPN_ASUS_TP 2>/dev/null || true
'\'''
```
