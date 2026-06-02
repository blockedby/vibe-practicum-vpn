# Repository agent notes

## Steam Deck OpenVPN profiles

- Steam Deck LAN endpoint currently used for local-network profiles: `192.168.50.13:1194`.
- For user-importable `.ovpn` files, prefer the compatibility format based on the known-good profile:
  - `auth SHA256`
  - `auth-nocache`
  - `cipher AES-256-CBC`
  - `redirect-gateway def1`
  - inline `<ca>`, `<cert>`, `<key>`, and `<tls-auth>` blocks
  - simple filenames such as `steamdecklandevice1.ovpn`
  - permissions `0644` if a desktop/mobile import UI reports “File format or path is invalid”.
- Avoid giving users the newer Docker-test profile format for UI import unless specifically needed:
  - `data-ciphers ...`
  - `data-ciphers-fallback ...`
  - `cipher AES-256-GCM`
  Some import UIs accept the profile less reliably even though OpenVPN CLI can use it.
- Unique local LAN client profiles are generated from gitignored secret material only. Do not commit generated profiles, private keys, `ca.key`, archives, or logs.
- Current generated compatible profiles were placed for the operator at:
  - `~/Desktop/steamdeck-lan-compatible-ovpn-192.168.50.13/steamdecklandevice1.ovpn`
  - `~/Desktop/steamdeck-lan-compatible-ovpn-192.168.50.13/steamdecklandevice2.ovpn`
  - `~/Desktop/steamdeck-lan-compatible-ovpn-192.168.50.13/steamdecklandevice3.ovpn`
  - `~/Desktop/steamdeck-lan-compatible-ovpn-192.168.50.13/steamdecklandevice4.ovpn`
  - flat copies also under `~/Downloads/steamdecklandevice{1..4}.ovpn`
- Validate profile syntax/import with NetworkManager when available:
  ```bash
  nmcli connection import type openvpn file /path/to/profile.ovpn
  nmcli connection delete <imported-name>
  ```
- Validate runtime over LAN with:
  ```bash
  scripts/vpnkit-steamdeck-client-test.sh \
    --endpoint 192.168.50.13 \
    --profile /path/to/profile.ovpn \
    --log-file logs/steamdeck-podman/<name>.log
  ```
- If a profile imports and connects but DNS/HTTPS fails, check the active VLESS node before regenerating profiles. Re-test/apply on the Deck:
  ```bash
  ssh deck 'podman exec vpnkit /usr/local/bin/vibe-vpn test --config /etc/vibe-vpn/config.yaml --limit-kib 128 --max 8'
  ssh deck 'podman exec vpnkit /usr/local/bin/vibe-vpn apply --config /etc/vibe-vpn/config.yaml best'
  ```

## Container images and runtimes

- Steam Deck deployment is **Podman only**. Do not use Docker on the Deck.
- The Deck-side server image is built locally on the Deck by `scripts/vpnkit-steamdeck-podman.sh` and tagged by default as:
  - `localhost/vpnkit:steamdeck`
- The running Deck container is named by default:
  - `vpnkit`
- The Deck container publishes OpenVPN as:
  - `0.0.0.0:1194->1194/udp`
- The host-side OpenVPN client test helper builds a local client-test image, using Docker by default unless `--runtime podman` is passed:
  - `vpnkit-ovpn-client-test:steamdeck`
- Docker is still acceptable for local lab/client-test work on this development host, but not for Steam Deck deployment.
- VPS `vibe-practicum` container migration uses Docker intentionally:
  - remote source/config root: `/opt/vpnkit`
  - server image: `vpnkit:vps`
  - container name: `vpnkit`
  - exposed port: `0.0.0.0:1194->1194/udp`
  - native services disabled during Docker runtime: `openvpn-server@vibe-asus.service`, `openvpn.service`, `sing-box-vibe-router.service`, `vibe-vpn.service`
  - native backup created before cutover: `/root/vpnkit-native-backup-<timestamp>.tar.gz`
- Current verified VPS Docker path from this host:
  ```bash
  scripts/vpnkit-steamdeck-client-test.sh \
    --endpoint 45.12.74.211 \
    --port 1194 \
    --runtime docker \
    --profile secrets/vps/openvpn/client/test-client.ovpn \
    --log-file logs/vps-client-test-45.12.74.211.log
  ```
  Expected: OpenVPN client gets `10.89.0.2/24`, DNS `NOERROR`, HTTPS `200`, literal-IP HTTPS `200`.
- Local Docker/Podman images are build artifacts, not source artifacts. Do not commit generated image exports or logs.
- To clean Deck runtime artifacts when intentionally tearing down:
  ```bash
  scripts/vpnkit-steamdeck-podman.sh --ssh-target deck cleanup --remove-image
  ```
- To clean local Docker client-test image if needed:
  ```bash
  docker image rm vpnkit-ovpn-client-test:steamdeck
  ```
- To inspect the current VPS Docker runtime:
  ```bash
  ssh vibe-practicum 'sudo docker ps --filter name=^/vpnkit$; sudo docker logs --tail 80 vpnkit'
  ```
- VPS rollback from Docker to native services:
  ```bash
  ssh vibe-practicum '
    sudo docker rm -f vpnkit || true
    sudo systemctl enable --now sing-box-vibe-router.service
    sudo systemctl enable --now vibe-vpn.service
    sudo systemctl enable --now openvpn-server@vibe-asus.service
    sudo systemctl enable --now openvpn.service || true
  '
  ```

## Default testing workflow before VPS deploy

For `vpnkit` runtime, routing, OpenVPN, sing-box, DNS, IPv6, or `vibe-vpn` daemon changes, do **not** deploy directly to `vibe-practicum` first. Use the local Docker lab and client-test container as the default acceptance path, then deploy live only after local evidence passes.

Recommended workflow from the target worktree:

```bash
# 1. Make gitignored local secrets available in this worktree.
# Prefer a copy from an existing local worktree; never commit secrets/.
rm -rf secrets
cp -a /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit/secrets ./secrets

# 2. Render local configs from the current branch.
scripts/vpnkit-render-local-configs.sh

# 3. Start from clean compose state so persisted sing-box config cannot hide template changes.
docker compose down -v --remove-orphans || true

# 4. Build/start local vpnkit with the same feature flags intended for VPS.
VPNKIT_ENABLE_VIBE_VPN_DAEMON=true \
VPNKIT_ROUTING_MODE=redirect \
VPNKIT_IPV6_POLICY=block \
VPNKIT_COMPAT_BYPASS_ENABLED=true \
VPNKIT_COMPAT_BYPASS_ENDPOINTS='vpn.proofix.tv:1194/udp,vpn.proofix.tv:1194/tcp' \
docker compose up -d --build vpnkit

# 5. Confirm all three runtime processes are alive.
docker compose exec vpnkit ps auxww | grep -E '[o]penvpn|[s]ing-box|[v]ibe-vpn'

# 6. Run the OpenVPN client regression through the compose test container.
VPNKIT_ENABLE_VIBE_VPN_DAEMON=true \
VPNKIT_ROUTING_MODE=redirect \
VPNKIT_IPV6_POLICY=block \
VPNKIT_COMPAT_BYPASS_ENABLED=true \
VPNKIT_COMPAT_BYPASS_ENDPOINTS='vpn.proofix.tv:1194/udp,vpn.proofix.tv:1194/tcp' \
docker compose --profile test run --rm ovpn-client-test
```

Expected client-test result: OpenVPN connects, client gets `10.89.0.2/24`, DNS returns `NOERROR`, HTTPS returns `200`, literal-IP HTTPS returns `200`.

For IPv4-only / IPv6 policy changes, also run an explicit AAAA check inside a client-test container connected through OpenVPN. Expected with `dns.strategy=ipv4_only`: A records are returned, while AAAA returns `NOERROR` with zero answers.

```bash
VPNKIT_ENABLE_VIBE_VPN_DAEMON=true VPNKIT_IPV6_POLICY=block docker compose --profile test run --rm --entrypoint bash ovpn-client-test -lc '
set -euo pipefail
openvpn --config /etc/openvpn/client/test-client.ovpn >/tmp/openvpn.log 2>&1 & pid=$!
trap "kill $pid 2>/dev/null || true" EXIT
for i in $(seq 1 60); do
  ip -4 addr show tun0 2>/dev/null | grep -q "10\\.89\\.0\\." && break
  if ! kill -0 $pid 2>/dev/null; then cat /tmp/openvpn.log; wait $pid; fi
  sleep 0.5
done
dig +time=10 +tries=1 @8.8.8.8 api.openai.com A
dig +time=10 +tries=1 @8.8.8.8 api.openai.com AAAA
curl -4 --max-time 20 -sS -o /dev/null -w "code=%{http_code} ip=%{remote_ip}\\n" https://api.openai.com/v1/models || true
'
```

Only after local evidence passes should the VPS Docker runtime be mutated. When live-deploying sing-box template changes, remember `/var/lib/vpnkit/sing-box/config.json` is persisted; rerender or recreate it intentionally and verify the live file, not only `/etc/sing-box/config.json`.

## vibe-vpn daemon and lil-sweden Hysteria2

- `vpnkit` can run `vibe-vpn daemon` inside the container when explicitly enabled with:
  ```bash
  -e VPNKIT_ENABLE_VIBE_VPN_DAEMON=true
  ```
- The daemon needs production sing-box SOCKS on `127.0.0.1:2080`; keep the container sing-box template's `vpnkit-socks-in` inbound when changing configs.
- `lil-sweden` Hysteria2 extra node uses gitignored auth material only. Do not commit real auth. Expected operator files before rendering:
  ```text
  secrets/vps/vibe-vpn/extra-nodes.json
  secrets/vps/vibe-vpn/lil-sweden-hy2-auth
  ```
- The tracked sanitized template is:
  ```text
  config/vibe-vpn/extra-nodes.lil-sweden.hy2.json.template
  ```
- The `host` field intentionally dials `84.22.149.216` while `server_name` stays `computer.peacedata.company` to avoid DNS bootstrap loops when sing-box is using the selected outbound for DNS.
