# Containerized vpnkit OpenVPN -> sing-box lab

This lab isolates the issue #11 boundary:

```text
ovpn-client-test -> vpnkit:1194/udp -> vpnkit tun0 -> iptables TPROXY :2082 -> sing-box selected-native-out -> internet
```

Real VPS material must stay under gitignored `secrets/vps/`; never commit VLESS UUIDs, private keys, `ta.key`, full profiles, tokens, or copied VPS configs.

## Prepare secrets (operator-bound)

```bash
scripts/vpnkit-copy-vps-secrets.sh vibe-practicum
scripts/vpnkit-render-local-configs.sh
```

Source paths copied by the helper:

- `/etc/sing-box-vibe/tproxy-canary.json`
- `/etc/openvpn/server/vibe-asus.conf`
- `/etc/vibe-vpn/openvpn-asus/{ca.crt,vibe-asus.crt,vibe-asus.key,ta.key,ignat.crt,ignat.key}`
- `/etc/openvpn/ccd-vibe-asus/ignat`

The render script extracts only `selected-native-out` from the copied sing-box JSON into `secrets/vps/rendered/sing-box/config.json`, renders the OpenVPN server config, and generates `secrets/vps/openvpn/client/test-client.ovpn` with `remote vpnkit 1194 udp`.

## Start the lab

```bash
docker compose build
docker compose up -d vpnkit
docker compose --profile test up ovpn-client-test
```

If Docker refuses TPROXY/TUN operations with the declared capabilities, temporarily add `privileged: true` locally to identify missing capabilities, then remove it before committing.

## Inspect the path

```bash
docker compose exec vpnkit ip rule show
docker compose exec vpnkit ip route show table 100
docker compose exec vpnkit iptables -t mangle -L OVPN_TO_SINGBOX -v -n -x
docker compose exec vpnkit tcpdump -ni tun0 'host 10.89.0.2 or port 53 or port 443'
docker compose logs vpnkit | grep -E 'canary-tproxy-in|selected-native-out|10\.89\.0\.'
scripts/vpnkit-collect-evidence.sh
```

There is intentionally no broad `POSTROUTING -s 10.89.0.0/24 -j MASQUERADE` rule in this lab. DNS is pushed to `10.89.0.1` and routed through sing-box rules/outbound instead of a direct NAT fallback.

## Acceptance evidence checklist

1. Secrets copied into `secrets/vps/...`: show `find secrets/vps -maxdepth 3 -type f` with names only.
2. `vpnkit` starts: `docker compose ps` and `sing-box check` output in logs.
3. Test client receives `10.89.0.x`: `docker compose logs ovpn-client-test` / `ip addr show tun0`.
4. Packets enter `vpnkit` `tun0`: tcpdump excerpt.
5. TPROXY counters increase: before/after `iptables -t mangle -L OVPN_TO_SINGBOX -v -n -x`.
6. sing-box inbound shows `10.89.0.x`: redacted vpnkit logs.
7. sing-box outbound shows `selected-native-out`: redacted vpnkit logs.
8. DNS under sing-box rules: no broad NAT rule plus DNS query log/counter evidence.
9. DNS replies to client: `dig example.com` in client log.
10. HTTPS via VLESS: `curl https://ifconfig.me` in client log plus outbound log.
11. Literal-IP TCP path: `run-tests.sh` `--resolve example.com:443:1.1.1.1` result; TLS/HTTP-layer errors after connect are useful, routing timeouts are not.
