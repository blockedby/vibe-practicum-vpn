# Containerized vpnkit OpenVPN -> sing-box lab

This lab isolates the issue #11 boundary:

```text
ovpn-client-test -> vpnkit:1194/udp -> vpnkit tun0
  -> scoped iptables REDIRECT rules
  -> sing-box redirect/direct inbounds
  -> selected-native-out VLESS -> internet
```

TPROXY remains available as a diagnostic mode in `docker/vpnkit/setup-routing.sh`, but the default Docker lab uses REDIRECT because this local Docker/kernel path matched TPROXY counters while neither sing-box nor a minimal `IP_TRANSPARENT` listener received accepted transparent sockets. REDIRECT is not a broad NAT bypass: TCP and UDP/53 are locally redirected to sing-box only, and there is intentionally no `POSTROUTING -s 10.89.0.0/24 -j MASQUERADE` rule.

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

The render script extracts only `selected-native-out` from the copied sing-box JSON into `secrets/vps/rendered/sing-box/config.json`, pre-resolves the outbound dial address to avoid a bootstrap DNS loop, renders the OpenVPN server config, and generates `secrets/vps/openvpn/client/test-client.ovpn` with `remote vpnkit 1194 udp`.

## Start the lab

```bash
docker compose build
docker compose up -d vpnkit
docker compose --profile test run --rm ovpn-client-test
```

The test client exits non-zero if the tunnel, DNS, domain HTTPS, or literal-IP HTTPS check fails.

If Docker refuses TUN/netfilter operations with the declared capabilities, temporarily use `privileged: true` locally to identify missing capabilities, then reduce privileges when possible. The current compose file keeps `privileged: true` because this lab is explicitly a local privileged routing harness.

## Inspect the path

```bash
docker compose exec vpnkit iptables -t nat -L OVPN_REDIRECT_TO_SINGBOX -v -n -x
docker compose exec vpnkit tcpdump -ni tun0 'host 10.89.0.2 or port 53 or port 443'
docker compose logs vpnkit | grep -E 'vpnkit-redirect-in|vpnkit-dns-in|selected-native-out|10\.89\.0\.'
scripts/vpnkit-collect-evidence.sh
```

Diagnostic TPROXY mode, if needed:

```bash
VPNKIT_ROUTING_MODE=tproxy docker compose up -d vpnkit
```

When testing TPROXY, require both `OVPN_TO_SINGBOX` counters and an actual sing-box/minimal-listener accept; counters alone are not acceptance.

## Acceptance evidence checklist

1. Secrets copied into `secrets/vps/...`: show file names only, never contents.
2. `vpnkit` starts: `docker compose ps` and `sing-box check` output.
3. Test client receives `10.89.0.x`: `docker compose --profile test run --rm ovpn-client-test` log.
4. Packets enter `vpnkit` `tun0`: tcpdump excerpt or redirect counters sourced from `10.89.0.x`.
5. Traffic reaches sing-box: `vpnkit-redirect-in` and `vpnkit-dns-in` inbound log lines.
6. sing-box outbound shows `selected-native-out`: redacted vpnkit logs.
7. DNS under sing-box rules: UDP/53 REDIRECT counter plus `vpnkit-dns-in` and `hijack-dns` evidence; no broad NAT rule.
8. DNS replies to client: `dig example.com` in client log.
9. HTTPS via VLESS: `https-test http_code=200` plus outbound log.
10. Literal-IP TCP path: `literal-ip-test http_code=200` plus outbound log to `1.1.1.1:443`.
