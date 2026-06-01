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
