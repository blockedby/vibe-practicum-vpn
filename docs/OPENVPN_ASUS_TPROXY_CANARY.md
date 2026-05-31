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
-> native sing-box VLESS outbound (`selected-native-out`)
-> internet

Legacy note: older canary notes used `xray :10808` behind sing-box. For issue #9 dynamic OpenVPN clients, xray is not the success path; it is a deprecated/legacy side service only.
```

The normal ASUS router profile remains separate:

- `asus` / `10.89.0.2`: direct NAT/full-tunnel or site-to-site.
- `asus-tproxy` / `10.89.0.3`: fixed canary through sing-box TPROXY; legacy docs may mention xray, but issue #9 success is native sing-box VLESS.
- `10.89.0.4`-`10.89.0.19`: reserved for additional fixed TPROXY OpenVPN clients.
- `10.89.0.20`-`10.89.0.254`: OpenVPN dynamic pool for friend/phone/laptop profiles; final issue #9 path is `tun-asus -> TPROXY :2082 -> sing-box hijack-dns/rules -> native VLESS`, not xray and not broad VPS NAT.

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

Nested VPN exception: Proofix work VPN (`185.241.192.190:1194/udp`, `vpn.proofix.tv`) must be a scoped `RETURN` before generic UDP TPROXY rules. For dynamic-pool clients, add it in **both** `VIBE_OVPN_ASUS_TP` and the broad `VIBE_ROUTER_OPENVPN_ASUS`: after `RETURN` from the first chain, PREROUTING continues and can hit the broad chain again. Missing the broad-chain bypass caused server replies to reach `eth0` but not return to `tun-asus`; with both bypasses, tcpdump shows `eth0 In` replies forwarded as `tun-asus Out` and OpenVPN reaches `PUSH_REPLY`.

## Verification commands

```bash
ssh vibe-practicum 'sudo sed -n "1,120p" /var/log/openvpn/vibe-asus-status.log | grep -E "asus-tproxy|10.89.0.3"'
ssh vibe-practicum 'sudo iptables -t mangle -L VIBE_OVPN_ASUS_TP -v -n -x --line-numbers'
ssh vibe-practicum 'sudo iptables -t filter -L INPUT -v -n -x --line-numbers | grep tproxy-input-accept'
ssh vibe-practicum 'sudo timeout 8 tcpdump -ni tun-asus "host 10.89.0.3 and src port 443" -c 5'
```

If the whole apartment/full-tunnel path drops while services are still `active`, also check conntrack saturation:

```bash
ssh vibe-practicum 'cat /proc/sys/net/netfilter/nf_conntrack_count; cat /proc/sys/net/netfilter/nf_conntrack_max'
ssh vibe-practicum 'journalctl -k --since "30 min ago" --no-pager | grep -E "nf_conntrack: table full|oom|killed process"'
```

See `docs/VPS_CONNTRACK_INCIDENT.md` for the 2026-05-16 live incident and sysctl fix.

Success evidence from the live fix:

```text
149.154.167.50.443 > 10.89.0.3.<port>  # Telegram replies on tun-asus
```

## Dynamic-pool friend profiles

For one-off phone/laptop profiles for friends, use the reusable generator instead of hand-assembling `.ovpn` files:

```bash
PUBLIC_ENDPOINT=45.12.74.211 \
OUT_DIR=/home/kcnc/vibe-openvpn-asus-profile \
  ./scripts/openvpn-asus-pool-tproxy-profile.sh --export friend-phone
```

The script:

- creates/reuses EasyRSA client credentials for the chosen CN;
- writes CCD pushes for DNS and `redirect-gateway def1 bypass-dhcp`;
- intentionally does **not** write `ifconfig-push`, so OpenVPN assigns from `10.89.0.20-10.89.0.254`;
- exports a single embedded `.ovpn` with mode `0600`;
- validates that `<ca>`, `<cert>`, `<key>`, and `<tls-auth>` blocks are present and not redacted;
- never intentionally prints private key/profile contents.

Use a unique CN per person/device, e.g. `misha-phone`, `dima-laptop`. Do not use reserved CNs `asus` or `asus-tproxy`.

Prerequisite: the live/persistent `vibe-openvpn-asus-rules` dynamic-pool capture must exist for `10.89.0.20-10.89.0.254`, with the matching INPUT accept for mark `0x1`. The INPUT accept is required because TPROXY packets are locally delivered to sing-box; a fixed `10.89.0.3/32` accept alone is insufficient for dynamic clients such as `ignat` (`10.89.0.23`).


## Issue #9 dynamic-client DNS and NAT policy

OpenVPN may push public resolver IPs such as `8.8.8.8` / `8.8.4.4` as DNS targets to simple phone clients. That does **not** mean final DNS is allowed to bypass sing-box. For dynamic-pool TPROXY clients, UDP/TCP port 53 must be intercepted by the sing-box `hijack-dns` route rule and resolved by sing-box DNS rules/detoured resolvers under the selected native VLESS policy. Direct or NATed DNS is diagnostic/emergency only and must be removed or disabled before claiming final success.

Broad `10.89.0.0/24 -> eth0 MASQUERADE` can remain as an emergency fallback during investigation, but it is not issue #9 acceptance evidence. Final proof must show dynamic-pool client traffic entering `tun-asus`, hitting TPROXY/local INPUT, and leaving according to sing-box/native VLESS policy.

## Persistence

Patch `/usr/local/sbin/vibe-openvpn-asus-rules` or run:

```bash
scripts/openvpn-asus-tproxy-canary-rules.sh --apply-live
```

The persistent state must recreate:

- `VIBE_OVPN_ASUS_TP` + exact `10.89.0.3/32` PREROUTING rule for the fixed canary;
- dynamic-pool PREROUTING capture for `10.89.0.20-10.89.0.254` when issue #9 clients are in scope;
- scoped INPUT ACCEPT for `tun-asus + 10.89.0.3/32 + mark 0x1/0x1`;
- scoped INPUT ACCEPT for marked dynamic-pool traffic (`tun-asus + 10.89.0.20-10.89.0.254 + mark 0x1/0x1`), not only the fixed canary;
- Proofix nested-VPN bypass before UDP TPROXY in both chains:
  `VIBE_OVPN_ASUS_TP` and `VIBE_ROUTER_OPENVPN_ASUS`, each with
  `-p udp -d 185.241.192.190/32 --dport 1194 -j RETURN`.

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
