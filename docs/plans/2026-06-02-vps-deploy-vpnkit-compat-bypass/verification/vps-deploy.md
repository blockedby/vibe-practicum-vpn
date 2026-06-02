# VPS deploy verification: vpnkit compat bypass

Date: 2026-06-02 UTC
Host: `vibe-practicum`
Branch/source deployed: `e452f4a029d9e3dfa8a28761a77fa28ec89c276f`

## Deployment commands run

- Snapshot/tag previous runtime image:
  - `sudo docker image tag vpnkit:vps vpnkit:vps-pre-compat-bypass-vps-test-20260602T042125Z`
  - `sudo tar -C /opt -czf /root/vpnkit-pre-compat-bypass-vps-test-20260602T042125Z.tar.gz vpnkit/src vpnkit/state/sing-box/config.json`
- Stage source from local branch with `git archive --format=tar HEAD | ssh vibe-practicum 'sudo tar -C /opt/vpnkit/src.new -xf - ...'`.
- Record deployed rev: `/opt/vpnkit/src/.deployed-git-rev` = `e452f4a029d9e3dfa8a28761a77fa28ec89c276f`.
- Build runtime image on VPS:
  - `cd /opt/vpnkit/src && sudo docker build -t vpnkit:vps -f docker/vpnkit/Dockerfile .`
- Preserve/force persisted sing-box config with IPv4-only DNS:
  - `sudo cp /opt/vpnkit/state/sing-box/config.json /opt/vpnkit/state/sing-box/config.json.pre-ipv4only-<timestamp>`
  - `sudo jq '.dns.strategy = "ipv4_only"' /opt/vpnkit/secrets/vps/rendered/sing-box/config.json | sudo tee /opt/vpnkit/state/sing-box/config.json >/dev/null`
- Restart runtime with preserved mounted directories:
  - `sudo docker rm -f vpnkit`
  - `sudo docker run -d --name vpnkit --restart unless-stopped --privileged --cap-add NET_ADMIN --cap-add NET_RAW --device /dev/net/tun:/dev/net/tun -p 1194:1194/udp ... vpnkit:vps`

## Runtime state after deploy

`sudo docker ps --filter name=^/vpnkit$`:

```text
0478c6408769 vpnkit:vps Up 3 minutes 0.0.0.0:1194->1194/udp, [::]:1194->1194/udp
```

Image:

```text
id=sha256:edf889b08567dd3580146f98f78d072f5a0891fd642ae76adc433cfe688d999d created=2026-06-02T04:23:05.291404046Z
```

Required envs present:

```text
VPNKIT_COMPAT_BYPASS_ALLOW_ICMP=false
VPNKIT_COMPAT_BYPASS_ENABLED=true
VPNKIT_COMPAT_BYPASS_ENDPOINTS=vpn.proofix.tv:1194/udp,vpn.proofix.tv:1194/tcp
VPNKIT_ENABLE_VIBE_VPN_DAEMON=true
VPNKIT_IPV6_POLICY=block
VPNKIT_ROUTING_MODE=redirect
```

Preserved mounts:

```text
/opt/vpnkit/state/vibe-vpn -> /var/lib/vibe-vpn
/opt/vpnkit/logs -> /var/log/vpnkit
/opt/vpnkit/logs/vibe-vpn -> /var/log/vibe-vpn
/opt/vpnkit/secrets/vps/rendered/openvpn -> /etc/openvpn ro
/opt/vpnkit/secrets/vps/rendered/sing-box -> /etc/sing-box ro
/opt/vpnkit/secrets/vps/rendered/vibe-vpn -> /etc/vibe-vpn ro
/opt/vpnkit/state/sing-box -> /var/lib/vpnkit/sing-box
```

Persisted DNS strategy:

```text
sudo jq -r '.dns.strategy' /opt/vpnkit/state/sing-box/config.json
ipv4_only
```

Runtime processes:

```text
sing-box run -c /var/lib/vpnkit/sing-box/config.json
openvpn --config /etc/openvpn/server.conf
vibe-vpn daemon --config /etc/vibe-vpn/config.yaml
```

Native services remained inactive:

```text
openvpn-server@vibe-asus.service: inactive
openvpn.service: inactive
sing-box-vibe-router.service: inactive
vibe-vpn.service: inactive
```

## VPS-side OpenVPN client test

Built test image on the VPS:

```bash
cd /opt/vpnkit/src && sudo docker build -t vpnkit-ovpn-client-test:vps -f docker/ovpn-client-test/Dockerfile docker/ovpn-client-test
```

Copied the gitignored local test profile to `/tmp/vpnkit-test-client.ovpn`, created a temporary VPS-local variant using `remote 172.17.0.1 1194`, and removed both temporary profiles/scripts after the test.

Command shape run on `vibe-practicum`:

```bash
sudo docker run --rm --entrypoint bash \
  --cap-add NET_ADMIN --cap-add NET_RAW \
  --device /dev/net/tun:/dev/net/tun \
  -v /tmp/vpnkit-test-client-vps.ovpn:/etc/openvpn/client/test-client.ovpn:ro \
  -v /tmp/vps_client_test.sh:/tmp/vps_client_test.sh:ro \
  vpnkit-ovpn-client-test:vps /tmp/vps_client_test.sh
```

Result:

```text
3: tun0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1500 ...
    inet 10.89.0.2/24 scope global tun0
0.0.0.0/1 via 10.89.0.1 dev tun0
128.0.0.0/1 via 10.89.0.1 dev tun0

=== A api.openai.com ===
status: NOERROR
ANSWER: 2
api.openai.com. A 162.159.140.245
api.openai.com. A 172.66.0.243

=== AAAA api.openai.com ===
status: NOERROR
ANSWER: 0

aaaa_answer_count=0

=== HTTPS example.com ===
https-test http_code=200 remote_ip=104.20.23.154

=== Literal IPv4 ===
literal-ip-test http_code=200 remote_ip=1.1.1.1
```

## Rollback status

Rollback was not needed. Available rollback artifacts:

- Image tag: `vpnkit:vps-pre-compat-bypass-vps-test-20260602T042125Z`
- Tar backup: `/root/vpnkit-pre-compat-bypass-vps-test-20260602T042125Z.tar.gz`
- Sing-box persisted config backups under `/opt/vpnkit/state/sing-box/config.json.pre-*`
