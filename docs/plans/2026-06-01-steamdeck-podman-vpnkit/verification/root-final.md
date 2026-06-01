# Root final verification

Date: 2026-06-01T03:55:12Z

## Commands
### bash -n script
```
exit=0
```

### docker compose config
```
name: steamdeck-podman-vpnkit
services:
  vpnkit:
    build:
      context: /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit
      dockerfile: docker/vpnkit/Dockerfile
    cap_add:
      - NET_ADMIN
      - NET_RAW
    devices:
      - source: /dev/net/tun
        target: /dev/net/tun
        permissions: rwm
    environment:
      ENABLE_DEPRECATED_LEGACY_DNS_SERVERS: "true"
      ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER: "true"
      VPNKIT_ROUTING_MODE: redirect
    networks:
      default: null
    ports:
      - mode: ingress
        target: 1194
        published: "1194"
        protocol: udp
    privileged: true
    restart: unless-stopped
    sysctls:
      net.ipv4.conf.all.rp_filter: "0"
      net.ipv4.conf.all.src_valid_mark: "1"
      net.ipv4.conf.default.rp_filter: "0"
      net.ipv4.ip_forward: "1"
    volumes:
      - type: bind
        source: /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit/secrets/vps/rendered/openvpn
        target: /etc/openvpn
        read_only: true
        bind: {}
      - type: bind
        source: /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit/secrets/vps/rendered/sing-box
        target: /etc/sing-box
        read_only: true
        bind: {}
      - type: bind
        source: /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit/secrets/vps/rendered/vibe-vpn
        target: /etc/vibe-vpn
        read_only: true
        bind: {}
      - type: volume
        source: vpnkit-vibe-vpn-state
        target: /var/lib/vibe-vpn
        volume: {}
      - type: volume
        source: vpnkit-sing-box-state
        target: /var/lib/vpnkit/sing-box
        volume: {}
      - type: bind
        source: /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit/logs
        target: /var/log/vpnkit
        bind: {}
      - type: bind
        source: /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit/logs/vibe-vpn
        target: /var/log/vibe-vpn
        bind: {}
networks:
  default:
    name: steamdeck-podman-vpnkit_default
volumes:
  vpnkit-sing-box-state:
    name: steamdeck-podman-vpnkit_vpnkit-sing-box-state
  vpnkit-vibe-vpn-state:
    name: steamdeck-podman-vpnkit_vpnkit-vibe-vpn-state
exit=0
```

### docker compose profile test config
```
name: steamdeck-podman-vpnkit
services:
  ovpn-client-test:
    profiles:
      - test
    build:
      context: /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit/docker/ovpn-client-test
      dockerfile: Dockerfile
    cap_add:
      - NET_ADMIN
      - NET_RAW
    command:
      - /etc/openvpn/client/test-client.ovpn
    depends_on:
      vpnkit:
        condition: service_started
        required: true
    devices:
      - source: /dev/net/tun
        target: /dev/net/tun
        permissions: rwm
    networks:
      default: null
    volumes:
      - type: bind
        source: /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit/secrets/vps/openvpn/client
        target: /etc/openvpn/client
        read_only: true
        bind: {}
      - type: bind
        source: /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit/logs
        target: /var/log/vpnkit
        bind: {}
  vpnkit:
    build:
      context: /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit
      dockerfile: docker/vpnkit/Dockerfile
    cap_add:
      - NET_ADMIN
      - NET_RAW
    devices:
      - source: /dev/net/tun
        target: /dev/net/tun
        permissions: rwm
    environment:
      ENABLE_DEPRECATED_LEGACY_DNS_SERVERS: "true"
      ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER: "true"
      VPNKIT_ROUTING_MODE: redirect
    networks:
      default: null
    ports:
      - mode: ingress
        target: 1194
        published: "1194"
        protocol: udp
    privileged: true
    restart: unless-stopped
    sysctls:
      net.ipv4.conf.all.rp_filter: "0"
      net.ipv4.conf.all.src_valid_mark: "1"
      net.ipv4.conf.default.rp_filter: "0"
      net.ipv4.ip_forward: "1"
    volumes:
      - type: bind
        source: /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit/secrets/vps/rendered/openvpn
        target: /etc/openvpn
        read_only: true
        bind: {}
      - type: bind
        source: /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit/secrets/vps/rendered/sing-box
        target: /etc/sing-box
        read_only: true
        bind: {}
      - type: bind
        source: /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit/secrets/vps/rendered/vibe-vpn
        target: /etc/vibe-vpn
        read_only: true
        bind: {}
      - type: volume
        source: vpnkit-vibe-vpn-state
        target: /var/lib/vibe-vpn
        volume: {}
      - type: volume
        source: vpnkit-sing-box-state
        target: /var/lib/vpnkit/sing-box
        volume: {}
      - type: bind
        source: /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit/logs
        target: /var/log/vpnkit
        bind: {}
      - type: bind
        source: /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit/logs/vibe-vpn
        target: /var/log/vibe-vpn
        bind: {}
networks:
  default:
    name: steamdeck-podman-vpnkit_default
volumes:
  vpnkit-sing-box-state:
    name: steamdeck-podman-vpnkit_vpnkit-sing-box-state
  vpnkit-vibe-vpn-state:
    name: steamdeck-podman-vpnkit_vpnkit-vibe-vpn-state
exit=0
```

### go test ./...
```
ok  	github.com/kcnc/vibe-practicum-vpn/cmd/vibe-vpn	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/config	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/extranodes	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/failover	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/health	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/ikev2	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/logging	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/nettest	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/picker	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/service	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/singbox	(cached)
?   	github.com/kcnc/vibe-practicum-vpn/internal/state	[no test files]
ok  	github.com/kcnc/vibe-practicum-vpn/internal/subscription	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/vless	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/xray	(cached)
exit=0
```

### Deck LAN check-ssh
```
steamdeck
podman version 5.3.2
1000
/dev/net/tun:present
exit=0
```

### Deck Tailscale check-ssh
```
steamdeck
podman version 5.3.2
1000
/dev/net/tun:present
exit=0
```

### Remote dir default normalization
```
/home/deck/.local/state/vpnkit
exit=0
```

### LAN ping
```
PING 192.168.50.13 (192.168.50.13) 56(84) bytes of data.
64 bytes from 192.168.50.13: icmp_seq=1 ttl=64 time=2.44 ms
64 bytes from 192.168.50.13: icmp_seq=2 ttl=64 time=60.9 ms

--- 192.168.50.13 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1001ms
rtt min/avg/max/mdev = 2.437/31.652/60.867/29.215 ms
exit=0
```

### Tailscale ping
```
PING 100.94.95.32 (100.94.95.32) 56(84) bytes of data.
64 bytes from 100.94.95.32: icmp_seq=1 ttl=64 time=2.92 ms
64 bytes from 100.94.95.32: icmp_seq=2 ttl=64 time=20.3 ms

--- 100.94.95.32 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1002ms
rtt min/avg/max/mdev = 2.915/11.601/20.287/8.686 ms
exit=0
```

### Expected blocked deploy without rendered secrets
```
missing required rendered input: secrets/vps/rendered/openvpn/server.conf
exit=1
```


## Deploy blocker classification
Expected result: deploy stops locally before remote sync/build/run because gitignored rendered configs are absent.
Observed result: `missing required rendered input: secrets/vps/rendered/openvpn/server.conf` with exit=1.
Classification: expected operator-secret blocker; no VPS mutation and no Deck build/run mutation attempted by this deploy command.

## Git state after root verification
```
## pi/steamdeck-podman-vpnkit...origin/pi/steamdeck-podman-vpnkit
?? docs/plans/2026-06-01-steamdeck-podman-vpnkit/verification/root-final.md
```
