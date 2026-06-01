# Live Steam Deck Podman deployment verification

Date: 2026-06-01
Worktree: `.worktrees/steamdeck-podman-vpnkit`
Branch: `pi/steamdeck-podman-vpnkit`

## Summary

Result: **passed**.

Steam Deck target:

- LAN SSH alias: `deck`
- LAN IP: `192.168.50.13`
- Tailscale SSH alias: `steamdeck-ts -p 2222`
- Tailscale IP: `100.94.95.32`

The Steam Deck has Podman 5.3.2 and `/dev/net/tun`. The vpnkit container was built and started on the Deck with Podman. It runs OpenVPN + sing-box + vibe-vpn.

No VPS mutation was performed. Real config material stayed in gitignored `secrets/` and was transferred as files without printing contents.

## Commands run

### Deploy over LAN SSH

```bash
mkdir -p logs/steamdeck-podman
scripts/vpnkit-steamdeck-podman.sh \
  --ssh-target deck \
  --lan-endpoint 192.168.50.13 \
  deploy \
  2>&1 | tee logs/steamdeck-podman/deploy-lan-<timestamp>.log
```

The deployment script:

1. created `/home/deck/.local/state/vpnkit` subdirectories on the Deck;
2. transferred tracked repo build context via `git archive`;
3. transferred rendered gitignored configs from `secrets/vps/rendered`;
4. built `localhost/vpnkit:steamdeck` with Podman;
5. started container `vpnkit` with `/dev/net/tun`, `NET_ADMIN`, `NET_RAW`, `--privileged`, sysctls, and UDP `1194` published;
6. ran verification.

### Steam Deck service verification

```bash
scripts/vpnkit-steamdeck-podman.sh --ssh-target deck status
scripts/vpnkit-steamdeck-podman.sh --ssh-target deck verify
scripts/vpnkit-steamdeck-podman.sh --ssh-target deck logs
```

Evidence excerpts:

```text
NAMES       STATUS             IMAGE                       PORTS
vpnkit      Up                 localhost/vpnkit:steamdeck  0.0.0.0:1194->1194/udp

openvpn --config /etc/openvpn/server.conf
sing-box run -c /var/lib/vpnkit/sing-box/config.json
vibe-vpn doctor: OK config, subscription_file, state_dir, sing_box_bin, sing_box_config, test_socks_free
```

OpenVPN/sing-box startup:

```text
OpenVPN tun0: 10.89.0.1/24
sing-box redirect inbound: 0.0.0.0:2082
sing-box DNS inbound: 0.0.0.0:5353
OVPN_REDIRECT_TO_SINGBOX counters installed
```

### vibe-vpn on the Deck

```bash
ssh deck 'podman exec vpnkit /usr/local/bin/vibe-vpn test --config /etc/vibe-vpn/config.yaml --limit-kib 64 --max 2'
ssh deck 'podman exec vpnkit /usr/local/bin/vibe-vpn apply --config /etc/vibe-vpn/config.yaml best'
ssh deck 'podman exec vpnkit /usr/local/bin/vibe-vpn current --config /etc/vibe-vpn/config.yaml'
ssh deck 'podman exec vpnkit /usr/local/bin/sing-box check -c /var/lib/vpnkit/sing-box/config.json'
```

Result:

```text
Fetched 9 subscription nodes + 0 extra nodes, 8 after filters, testing first 2.
Done: 1 ok, 1 failed.
BEST: #002, 2.43 Mbps
Applied to production singbox. Backup: /var/lib/vibe-vpn/backups/...
current node: node4.vlessi.cloud:8444 grpc/reality
sing-box check: passed with known legacy DNS warnings
```

Supervisor log showed:

```text
restart requested for sing-box
started sing-box pid=... config=/var/lib/vpnkit/sing-box/config.json
```

## Client tests from this host

A tracked helper was added for host-to-Deck client tests:

```bash
scripts/vpnkit-steamdeck-client-test.sh --endpoint <host> --log-file logs/steamdeck-podman/<name>.log
```

The helper builds/runs the existing OpenVPN client test image, rewrites only the temporary `remote <endpoint> <port>` line, and mounts the temporary profile into the client container. It removes the temporary profile by default.

### LAN endpoint test

```bash
scripts/vpnkit-steamdeck-client-test.sh \
  --endpoint 192.168.50.13 \
  --log-file logs/steamdeck-podman/client-script-lan-<timestamp>.log
```

Result: **passed**.

```text
OpenVPN remote: 192.168.50.13:1194
client tun0: 10.89.0.2/24
DNS: dig @8.8.8.8 example.com -> NOERROR
HTTPS: http_code=200 remote_ip=34.117.59.81
literal-IP HTTPS: http_code=200 remote_ip=1.1.1.1
```

### Tailscale endpoint test

```bash
scripts/vpnkit-steamdeck-client-test.sh \
  --endpoint 100.94.95.32 \
  --log-file logs/steamdeck-podman/client-script-tailscale-<timestamp>.log
```

Result: **passed**.

```text
OpenVPN remote: 100.94.95.32:1194
client tun0: 10.89.0.2/24
DNS: dig @8.8.8.8 example.com -> NOERROR
HTTPS: http_code=200 remote_ip=34.117.59.81
literal-IP HTTPS: http_code=200 remote_ip=1.1.1.1
```

### Post-apply client checks

After `vibe-vpn apply best` restarted sing-box, both endpoints were tested again.

LAN post-apply: **passed**.

```text
DNS: NOERROR
HTTPS: http_code=200
literal-IP HTTPS: http_code=200
```

Tailscale post-apply: **passed**.

```text
DNS: NOERROR
HTTPS: http_code=200
literal-IP HTTPS: http_code=200
```

## Sing-box path evidence

Deck logs showed OpenVPN clients connecting from both LAN and Tailscale source addresses and traffic entering sing-box:

```text
inbound/direct[vpnkit-dns-in] from 10.89.0.2 -> hijack-dns
outbound/vless[selected-native-out] -> 8.8.8.8:853
inbound/redirect[vpnkit-redirect-in] from 10.89.0.2 -> 34.117.59.81:443
outbound/vless[selected-native-out] -> 34.117.59.81:443
inbound/redirect[vpnkit-redirect-in] from 10.89.0.2 -> 1.1.1.1:443
outbound/vless[selected-native-out] -> 1.1.1.1:443
```

## Acceptance mapping

- Steam Deck SSH/Podman discovery: **passed**.
- Podman image build on Deck: **passed**.
- Server container starts on Deck: **passed**.
- Server container includes OpenVPN + sing-box + vibe-vpn: **passed**.
- OpenVPN/sing-box/vibe-vpn health on Deck: **passed**.
- `vibe-vpn test` on Deck: **passed**.
- `vibe-vpn apply best` on Deck with supervisor sing-box restart: **passed**.
- Host-to-Deck LAN OpenVPN e2e: **passed**.
- Host-to-Deck Tailscale OpenVPN e2e: **passed**.
- Post-apply LAN/Tailscale e2e: **passed**.
- Logs written under ignored `logs/`: **passed**.
- No committed secrets: **passed**.

## Notes

- One early Tailscale client run timed out at DNS immediately after replacing the prior LAN session with the same client certificate/CN. A manual retry and the tracked helper rerun both passed; subsequent post-apply Tailscale e2e also passed.
- The running Steam Deck container is intentionally left up for follow-up use.
