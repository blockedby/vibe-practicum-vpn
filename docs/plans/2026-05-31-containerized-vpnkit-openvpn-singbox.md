# Containerized vpn-kit: OpenVPN -> sing-box

GitHub issue: https://github.com/blockedby/vibe-practicum-vpn/issues/11

## Summary

Build an isolated `vpn-kit` Docker container where the whole routing path is simple and controlled inside the container network namespace:

```text
OpenVPN client
  -> OpenVPN server inside container
  -> tun0
  -> iptables TPROXY inside container
  -> sing-box inbound/tproxy
  -> sing-box native VLESS outbound
  -> internet
```

Goal: freely change `routing`, `iptables`, DNS handling, and `sing-box` config inside the container without touching host firewall/routing.

## What to include

### 1. OpenVPN server

Container owns the OpenVPN server and client pool.

Minimum config shape:

```conf
port 1194
proto udp
dev tun0
topology subnet
server 10.89.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 10.89.0.1"
keepalive 10 120
persist-key
persist-tun
verb 3
```

Expected client address range:

```text
10.89.0.0/24
```

### 2. sing-box

Include one active sing-box process/config only.

Required parts:

```text
inbound/tproxy :2082
DNS hijack/rules
native VLESS outbound
```

Do not carry over:

```text
xray
Tailscale-specific routing
UFW/fail2ban VPS chains
VPS NAT fallback
old systemd services
duplicate sing-box config/service setup
```

### 3. Container routing script

Inside the container:

```bash
ip rule add fwmark 0x1 table 100
ip route add local default dev lo table 100

iptables -t mangle -N OVPN_TO_SINGBOX 2>/dev/null || true
iptables -t mangle -F OVPN_TO_SINGBOX

iptables -t mangle -A PREROUTING -i tun0 -s 10.89.0.0/24 -j OVPN_TO_SINGBOX

iptables -t mangle -A OVPN_TO_SINGBOX -p tcp \
  -j TPROXY --on-port 2082 --tproxy-mark 0x1/0x1

iptables -t mangle -A OVPN_TO_SINGBOX -p udp \
  -j TPROXY --on-port 2082 --tproxy-mark 0x1/0x1
```

Important: do **not** add permanent broad NAT for the OpenVPN pool:

```bash
iptables -t nat -A POSTROUTING -s 10.89.0.0/24 -j MASQUERADE
```

That would bypass sing-box and recreate direct/NAT behavior.

## Docker layout

Suggested files:

```text
docker/vpnkit/
  Dockerfile
  entrypoint.sh
  setup-routing.sh

docker/ovpn-client-test/
  Dockerfile
  entrypoint.sh
  run-tests.sh

config/openvpn/
  server.conf
  pki/

config/sing-box/
  config.json

secrets/vps/                 # local-only, gitignored
  sing-box/tproxy-canary.json
  openvpn/server/vibe-asus.conf
  openvpn/pki/
  openvpn/client/ignat.ovpn or generated test-client.ovpn

docker-compose.yml
```

Keep real credentials and private keys under `secrets/` or another gitignored path. Do not commit VLESS UUIDs, private keys, OpenVPN client keys, `ta.key`, or full exported `.ovpn` profiles.

## Docker Compose requirements

The VPN gateway container needs network admin rights and TUN access:

```yaml
services:
  vpnkit:
    build: ./docker/vpnkit
    container_name: vpnkit
    restart: unless-stopped
    ports:
      - "1194:1194/udp"
    cap_add:
      - NET_ADMIN
      - NET_RAW
    devices:
      - /dev/net/tun:/dev/net/tun
    sysctls:
      net.ipv4.ip_forward: "1"
      net.ipv4.conf.all.src_valid_mark: "1"
      net.ipv4.conf.all.rp_filter: "0"
      net.ipv4.conf.default.rp_filter: "0"
    volumes:
      - ./config/openvpn:/etc/openvpn
      - ./config/sing-box:/etc/sing-box
      - ./logs:/var/log/vpnkit

  ovpn-client-test:
    build: ./docker/ovpn-client-test
    container_name: ovpn-client-test
    profiles: ["test"]
    depends_on:
      - vpnkit
    cap_add:
      - NET_ADMIN
      - NET_RAW
    devices:
      - /dev/net/tun:/dev/net/tun
    volumes:
      - ./secrets/vps/openvpn/client:/etc/openvpn/client:ro
      - ./logs:/var/log/vpnkit
    command: ["/etc/openvpn/client/test-client.ovpn"]
```

The test client container should connect to the gateway through Docker networking:

```text
remote vpnkit 1194 udp
```

It must be a separate container/network namespace so the test is close to a real OpenVPN client:

```text
ovpn-client-test eth0 -> Docker bridge -> vpnkit:1194/udp -> vpnkit tun0 -> TPROXY -> sing-box -> VLESS
```

If TPROXY fails because of container restrictions, temporarily test with:

```yaml
privileged: true
```

Then reduce privileges back to `NET_ADMIN`, `NET_RAW`, and `/dev/net/tun` once the required capabilities are known.

## Config source from `vibe-practicum`

Use the live VPS as the source for the first real-data test, but copy secrets only into local gitignored paths.

Observed source paths on `vibe-practicum`:

```text
sing-box active unit:
  sing-box-vibe-router.service
  /usr/bin/sing-box run -c /etc/sing-box-vibe/tproxy-canary.json

sing-box config source:
  /etc/sing-box-vibe/tproxy-canary.json

OpenVPN server unit:
  openvpn-server@vibe-asus.service

OpenVPN server config source:
  /etc/openvpn/server/vibe-asus.conf

OpenVPN PKI/client material source:
  /etc/vibe-vpn/openvpn-asus/ca.crt
  /etc/vibe-vpn/openvpn-asus/vibe-asus.crt
  /etc/vibe-vpn/openvpn-asus/vibe-asus.key
  /etc/vibe-vpn/openvpn-asus/ta.key
  /etc/vibe-vpn/openvpn-asus/ignat.crt
  /etc/vibe-vpn/openvpn-asus/ignat.key
  /etc/openvpn/ccd-vibe-asus/ignat
```

The current live sing-box config summary from the VPS is:

```text
inbounds:
  socks  test-socks-in    127.0.0.1:2080
  socks  tailnet-socks-in 100.121.107.112:2080
  tproxy canary-tproxy-in 0.0.0.0:2082

outbounds:
  direct direct-out
  vless  selected-native-out node5.vlessi.cloud:8444
  block  block-out

route final:
  selected-native-out
```

For the container test, keep only the relevant sing-box pieces:

```text
canary-tproxy-in / tproxy :2082
selected-native-out / native VLESS with real VPS credentials
DNS servers/rules needed by the active config
```

Do not commit the copied config as-is if it contains real UUIDs, REALITY keys, short IDs, client keys, or other credentials.

Suggested local extraction commands:

```bash
mkdir -p secrets/vps/sing-box secrets/vps/openvpn/server secrets/vps/openvpn/pki secrets/vps/openvpn/client

rsync -av --rsync-path='sudo rsync' \
  vibe-practicum:/etc/sing-box-vibe/tproxy-canary.json \
  secrets/vps/sing-box/tproxy-canary.json

rsync -av --rsync-path='sudo rsync' \
  vibe-practicum:/etc/openvpn/server/vibe-asus.conf \
  secrets/vps/openvpn/server/vibe-asus.conf

rsync -av --rsync-path='sudo rsync' \
  vibe-practicum:/etc/vibe-vpn/openvpn-asus/ca.crt \
  vibe-practicum:/etc/vibe-vpn/openvpn-asus/ta.key \
  vibe-practicum:/etc/vibe-vpn/openvpn-asus/vibe-asus.crt \
  vibe-practicum:/etc/vibe-vpn/openvpn-asus/vibe-asus.key \
  vibe-practicum:/etc/vibe-vpn/openvpn-asus/ignat.crt \
  vibe-practicum:/etc/vibe-vpn/openvpn-asus/ignat.key \
  secrets/vps/openvpn/pki/

rsync -av --rsync-path='sudo rsync' \
  vibe-practicum:/etc/openvpn/ccd-vibe-asus/ignat \
  secrets/vps/openvpn/server/ccd-ignat
```

Then generate a local `test-client.ovpn` from the copied `ca.crt`, `ta.key`, `ignat.crt`, and `ignat.key`, with:

```conf
client
dev tun
proto udp
remote vpnkit 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-256-CBC
verb 3
```

## Entrypoint shape

```bash
#!/usr/bin/env bash
set -euo pipefail

sing-box run -c /etc/sing-box/config.json &
SINGBOX_PID=$!

openvpn --config /etc/openvpn/server.conf &
OVPN_PID=$!

until ip link show tun0 >/dev/null 2>&1; do
  sleep 0.5
done

/usr/local/bin/setup-routing.sh

wait -n "$SINGBOX_PID" "$OVPN_PID"
```

## OpenVPN client test container

Add a second test-only container that runs an OpenVPN client with the copied/generated real client profile.

Purpose:

```text
prove the gateway from a real separate network namespace, not from inside vpnkit itself
```

Expected test path:

```text
ovpn-client-test
  -> OpenVPN UDP session to vpnkit:1194
  -> receives 10.89.0.x
  -> default route through VPN tunnel
  -> vpnkit tun0
  -> vpnkit TPROXY :2082
  -> vpnkit sing-box native VLESS
  -> real VLESS server from copied VPS config
  -> internet
```

The client container image should include:

```text
openvpn
iproute2
iptables or nft tools for inspection
curl
dig/drill/nslookup
tcpdump
bash
ca-certificates
```

Test commands from inside `ovpn-client-test`:

```bash
ip addr
ip route
curl -4 --max-time 20 https://ifconfig.me
dig example.com
curl -4 --max-time 20 https://1.1.1.1 --connect-to example.com:443:1.1.1.1:443 || true
```

Observability commands from inside `vpnkit` during the test:

```bash
ip rule show
ip route show table 100
iptables -t mangle -L OVPN_TO_SINGBOX -v -n -x
sing-box check -c /etc/sing-box/config.json
tcpdump -ni tun0 'host 10.89.0.2 or port 53 or port 443'
```

## Real VLESS acceptance test

Run at least one test using the real native VLESS outbound copied from `vibe-practicum`:

```text
selected-native-out -> node5.vlessi.cloud:8444
```

Success requires evidence that traffic exits through the sing-box VLESS outbound, not via direct Docker NAT from the OpenVPN pool.

Evidence to capture:

```text
ovpn-client-test gets 10.89.0.x
vpnkit TPROXY counters increase
sing-box logs show inbound/tproxy for 10.89.0.x
sing-box logs show outbound selected-native-out
DNS query succeeds under sing-box DNS/routing
HTTPS succeeds
literal-IP TCP/HTTPS test succeeds or gives a TLS/HTTP-layer error after TCP connect, not a routing timeout
```

## Acceptance criteria

- [ ] Real config material is copied from `vibe-practicum` into gitignored `secrets/` paths, not committed.
- [ ] `vpnkit` container starts OpenVPN server and sing-box with the real native VLESS outbound config.
- [ ] `ovpn-client-test` container connects as an OpenVPN client and receives `10.89.0.x`.
- [ ] Client packets are visible entering `vpnkit` container `tun0`.
- [ ] TPROXY counters increase for client traffic.
- [ ] `sing-box` logs/metrics show `inbound/tproxy` from `10.89.0.x`.
- [ ] `sing-box` logs/metrics show outbound traffic through `selected-native-out` to the real VLESS server.
- [ ] DNS is handled by `sing-box` rules, not by permanent direct/NAT bypass.
- [ ] DNS replies return to the OpenVPN client container.
- [ ] HTTPS works through native VLESS outbound.
- [ ] Literal-IP TCP test works to prove the path is not only DNS-dependent.

Final expected path:

```text
OpenVPN client -> tun0 -> TPROXY :2082 -> sing-box -> VLESS -> internet
```
