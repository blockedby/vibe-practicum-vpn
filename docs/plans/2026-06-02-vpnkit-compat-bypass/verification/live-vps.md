# Live VPS verification: vpnkit compatibility bypass

## Deployment

- Host: `vibe-practicum` / `45.12.74.211`.
- Branch deployed to `/opt/vpnkit/src`: `vpnkit-compat-bypass`.
- Backup before mutation: `/root/vpnkit-compat-bypass-backup-20260602T025622Z.tar.gz`.
- Previous image tag during rollout: `vpnkit:vps-prev-compat-20260602T025841Z`.
- Runtime image: `vpnkit:vps`.

## Runtime environment

Container `vpnkit` was restarted with:

```text
VPNKIT_ROUTING_MODE=redirect
VPNKIT_ENABLE_VIBE_VPN_DAEMON=true
VPNKIT_COMPAT_BYPASS_ENABLED=true
VPNKIT_COMPAT_BYPASS_ENDPOINTS=vpn.proofix.tv:1194
VPNKIT_COMPAT_BYPASS_ALLOW_ICMP=false
```

`vpn.proofix.tv` resolved on the VPS/container path to:

```text
185.241.192.190
```

## Installed scoped rules

`iptables -t nat -S OVPN_REDIRECT_TO_SINGBOX`:

```text
-N OVPN_REDIRECT_TO_SINGBOX
-A OVPN_REDIRECT_TO_SINGBOX -d 185.241.192.190/32 -p udp -m udp --dport 1194 -j RETURN
-A OVPN_REDIRECT_TO_SINGBOX -p tcp -j REDIRECT --to-ports 2082
-A OVPN_REDIRECT_TO_SINGBOX -p udp -m udp --dport 53 -j REDIRECT --to-ports 5353
```

`iptables -t nat -S OVPN_COMPAT_POST`:

```text
-N OVPN_COMPAT_POST
-A OVPN_COMPAT_POST -d 185.241.192.190/32 -p udp -m udp --dport 1194 -j MASQUERADE
```

`iptables -S OVPN_COMPAT_FWD`:

```text
-N OVPN_COMPAT_FWD
-A OVPN_COMPAT_FWD -s 10.89.0.0/24 -d 185.241.192.190/32 -p udp -m udp --dport 1194 -j ACCEPT
-A OVPN_COMPAT_FWD -s 185.241.192.190/32 -d 10.89.0.0/24 -p udp -m udp --sport 1194 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

This is endpoint-scoped NAT/forwarding, not broad `10.89.0.0/24` direct NAT.

## Process checks

Container processes observed:

```text
sing-box run -c /var/lib/vpnkit/sing-box/config.json
openvpn --config /etc/openvpn/server.conf
vibe-vpn daemon --config /etc/vibe-vpn/config.yaml
```

## OpenVPN client regression

Command:

```bash
scripts/vpnkit-steamdeck-client-test.sh \
  --endpoint 45.12.74.211 \
  --port 1194 \
  --runtime docker \
  --profile /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit/secrets/vps/openvpn/client/test-client.ovpn
```

Result after switching the current backend back to `lil-sweden hy2` and replacing the flaky `ifconfig.me` test target with `example.com`:

```text
OpenVPN connected
client tun0: 10.89.0.2/24
DNS @8.8.8.8 example.com: NOERROR
https-test http_code=200
literal-ip-test http_code=200 remote_ip=1.1.1.1
```

## Follow-up required

- User should test the real KDE/NetworkManager work VPN from behind the router.
- Expected work VPN protocol is UDP because OpenVPN defaults to UDP when protocol is omitted.
- If the real work VPN uses TCP instead, set `VPNKIT_COMPAT_BYPASS_ENDPOINTS=vpn.proofix.tv:1194/tcp` or include both UDP and TCP entries.
