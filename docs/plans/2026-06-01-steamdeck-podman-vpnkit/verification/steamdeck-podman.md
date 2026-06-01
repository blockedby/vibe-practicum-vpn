# Steam Deck Podman verification

## Local checks
```
bash -n scripts/vpnkit-steamdeck-podman.sh: PASS
docker compose config: PASS
docker compose --profile test config: PASS
ok  	github.com/kcnc/vibe-practicum-vpn/cmd/vibe-vpn	1.030s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/config	0.004s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/extranodes	0.004s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/failover	0.006s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/health	0.007s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/ikev2	0.871s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/logging	0.003s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/nettest	0.003s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/picker	0.002s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/service	0.013s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/singbox	0.006s
?   	github.com/kcnc/vibe-practicum-vpn/internal/state	[no test files]
ok  	github.com/kcnc/vibe-practicum-vpn/internal/subscription	0.007s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/vless	0.004s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/xray	0.005s
go test ./...: PASS
```

## Remote read-only checks
```
+ scripts/vpnkit-steamdeck-podman.sh --ssh-target deck check-ssh
/bin/bash: line 6: scripts/vpnkit-steamdeck-podman.sh: Permission denied
deck check failed
+ scripts/vpnkit-steamdeck-podman.sh --ssh-target steamdeck-ts --ssh-option -p 2222 check-ssh
/bin/bash: line 8: scripts/vpnkit-steamdeck-podman.sh: Permission denied
steamdeck-ts check failed
```

## Remote read-only checks rerun after chmod
```
+ scripts/vpnkit-steamdeck-podman.sh --ssh-target deck check-ssh
steamdeck
podman version 5.3.2
1000
/dev/net/tun:present
+ scripts/vpnkit-steamdeck-podman.sh --ssh-target steamdeck-ts --ssh-option -p 2222 check-ssh
steamdeck
podman version 5.3.2
1000
/dev/net/tun:present
```

## Deploy attempt
```
+ scripts/vpnkit-steamdeck-podman.sh --ssh-target deck --lan-endpoint 192.168.50.13 deploy
missing required rendered input: secrets/vps/rendered/openvpn/server.conf
deploy blocked/failed as shown above
```

## Host connectivity
```
+ ping -c 2 -W 2 192.168.50.13
PING 192.168.50.13 (192.168.50.13) 56(84) bytes of data.
64 bytes from 192.168.50.13: icmp_seq=1 ttl=64 time=2.46 ms
64 bytes from 192.168.50.13: icmp_seq=2 ttl=64 time=200 ms

--- 192.168.50.13 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1005ms
rtt min/avg/max/mdev = 2.462/101.080/199.698/98.618 ms
+ ping -c 2 -W 2 100.94.95.32
PING 100.94.95.32 (100.94.95.32) 56(84) bytes of data.
64 bytes from 100.94.95.32: icmp_seq=1 ttl=64 time=3.51 ms
64 bytes from 100.94.95.32: icmp_seq=2 ttl=64 time=224 ms

--- 100.94.95.32 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1001ms
rtt min/avg/max/mdev = 3.507/113.683/223.859/110.176 ms
```

## Secret safety and Docker e2e
```
+ git status --short --ignored secrets logs | sed -n 1,80p
+ grep scan tracked changed files for obvious secret markers (redacted patterns only)
+ scripts/vpnkit-vibe-vpn-e2e.sh --switching
SKIPPED: rendered secrets/vps inputs are absent; running would fail before Docker runtime checks.
```

## Follow-up script syntax/SSH option parsing
```
+ bash -n scripts/vpnkit-steamdeck-podman.sh
PASS
+ scripts/vpnkit-steamdeck-podman.sh --ssh-target steamdeck-ts --ssh-option '-p 2222' check-ssh
steamdeck
podman version 5.3.2
1000
/dev/net/tun:present
```

## Follow-up remote-dir normalization fix
```
+ bash -n scripts/vpnkit-steamdeck-podman.sh
PASS
+ scripts/vpnkit-steamdeck-podman.sh --ssh-target deck check-ssh
steamdeck
podman version 5.3.2
1000
/dev/net/tun:present
+ scripts/vpnkit-steamdeck-podman.sh --ssh-target deck resolve-remote-dir
/home/deck/.local/state/vpnkit
+ scripts/vpnkit-steamdeck-podman.sh --ssh-target deck --remote-dir '~' resolve-remote-dir
/home/deck
+ scripts/vpnkit-steamdeck-podman.sh --ssh-target deck --remote-dir /tmp/vpnkit-test resolve-remote-dir
/tmp/vpnkit-test
+ scripts/vpnkit-steamdeck-podman.sh --ssh-target deck --remote-dir relative/path resolve-remote-dir
remote dir must be absolute or start with ~/: relative/path
EXPECTED_FAIL
```
