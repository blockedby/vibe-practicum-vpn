# VPS Docker vpnkit cutover verification

Date: 2026-06-01
Target: `vibe-practicum` / `45.12.74.211`
Runtime: Docker

## Summary

Result: **passed**.

Native VPS OpenVPN/sing-box/vibe-vpn runtime was disabled and replaced with the containerized `vpnkit` runtime:

```text
OpenVPN server in Docker -> sing-box in Docker -> VLESS -> internet
```

The active VPS Docker container is:

```text
container: vpnkit
image: vpnkit:vps
port: 0.0.0.0:1194->1194/udp
remote root: /opt/vpnkit
```

## Preflight evidence

Before cutover:

```text
Docker 29.3.1 present
containerd active
/dev/net/tun present
openvpn-server@vibe-asus.service active/enabled
openvpn.service active/enabled
sing-box-vibe-router.service active/enabled
vibe-vpn.service active/enabled
UDP 1194 owned by native OpenVPN
TCP/UDP 2082 and TCP 2080 owned by native sing-box
Caddy 443 present and not touched
```

Existing Docker containers (`vibe-hy2-mvp`, `rustdesk-hbbr`, `rustdesk-hbbs`) were not touched.

## Staging/build

Staged tracked source and rendered gitignored configs under `/opt/vpnkit`:

```text
/opt/vpnkit/src
/opt/vpnkit/secrets/vps/rendered/openvpn
/opt/vpnkit/secrets/vps/rendered/sing-box
/opt/vpnkit/secrets/vps/rendered/vibe-vpn
/opt/vpnkit/state/vibe-vpn
/opt/vpnkit/state/sing-box
/opt/vpnkit/logs
```

Built image:

```text
vpnkit:vps
```

## Backup

Native runtime backup created before stopping services:

```text
/root/vpnkit-native-backup-20260601T052016Z.tar.gz
```

Backup warnings were only tar's normal leading slash notices.

## Cutover

Disabled/stopped native services:

```text
vibe-vpn.service inactive/disabled
sing-box-vibe-router.service inactive/disabled
openvpn-server@vibe-asus.service inactive/disabled
openvpn.service inactive/disabled
```

Started Docker:

```text
vpnkit Up
image vpnkit:vps
ports 0.0.0.0:1194->1194/udp, [::]:1194->1194/udp
```

Inside container:

```text
openvpn --config /etc/openvpn/server.conf
sing-box run -c /var/lib/vpnkit/sing-box/config.json
```

Health checks:

```text
sing-box check: OK with known deprecation warnings
vibe-vpn doctor: OK config, subscription_file, state_dir, sing_box_bin, sing_box_config, test_socks_free
```

Host listeners after cutover:

```text
UDP 1194 Docker-published vpnkit
443 Caddy unchanged
No native 2080/2082 listeners
```

## Node refresh

First client test connected and DNS worked, but HTTPS timed out due to the active VLESS node. Ran inside the VPS container:

```bash
vibe-vpn test --config /etc/vibe-vpn/config.yaml --limit-kib 128 --max 8
vibe-vpn apply --config /etc/vibe-vpn/config.yaml best
```

Result:

```text
Fetched 9 subscription nodes + 0 extra nodes, 8 after filters.
Done: 7 ok, 1 failed.
Applied #005 🇳🇱 Нидерланды-2 (node2.vlessi.cloud:8444 grpc/reality)
supervisor restarted sing-box
```

## Client verification from this host

Command:

```bash
scripts/vpnkit-steamdeck-client-test.sh \
  --endpoint 45.12.74.211 \
  --port 1194 \
  --runtime docker \
  --profile secrets/vps/openvpn/client/test-client.ovpn \
  --log-file logs/vps-client-test-45.12.74.211-after-apply-<timestamp>.log
```

Result: **passed**.

```text
OpenVPN connected to 45.12.74.211:1194
client tun0: 10.89.0.2/24
DNS: dig @8.8.8.8 example.com -> NOERROR
HTTPS: http_code=200 remote_ip=34.117.59.81
literal-IP HTTPS: http_code=200 remote_ip=1.1.1.1
```

Container path evidence:

```text
inbound/direct[vpnkit-dns-in] from 10.89.0.2 -> hijack-dns
outbound/vless[selected-native-out] -> 8.8.8.8:853
inbound/redirect[vpnkit-redirect-in] from 10.89.0.2 -> 34.117.59.81:443
outbound/vless[selected-native-out] -> 34.117.59.81:443
inbound/redirect[vpnkit-redirect-in] from 10.89.0.2 -> 1.1.1.1:443
outbound/vless[selected-native-out] -> 1.1.1.1:443
```

iptables counters inside container increased:

```text
OVPN_REDIRECT_TO_SINGBOX tcp redirect -> :2082
OVPN_REDIRECT_TO_SINGBOX udp/53 redirect -> :5353
```

## Rollback

To revert to native runtime:

```bash
ssh vibe-practicum '
  sudo docker rm -f vpnkit || true
  sudo systemctl enable --now sing-box-vibe-router.service
  sudo systemctl enable --now vibe-vpn.service
  sudo systemctl enable --now openvpn-server@vibe-asus.service
  sudo systemctl enable --now openvpn.service || true
'
```

If file restoration is required, restore from:

```text
/root/vpnkit-native-backup-20260601T052016Z.tar.gz
```
