# Hysteria 2 MVP implementation plan

Goal: prove a small, isolated Hysteria 2 path from a client to the VPS without touching the existing Tailscale/sing-box routing stack. The MVP must be easy to roll back and must produce a one-link/QR client onboarding path.

## Non-negotiable guardrails

- Do not stop, disable, purge, or restart `tailscaled.service`.
- Do not stop, disable, purge, or restart `sing-box-vibe-router.service`.
- Do not edit existing Tailscale/sing-box iptables chains or policy rules.
- Do not install Podman on the VPS just for this MVP; use the already-present Docker runtime to save disk.
- Do not use host-level TUN, TPROXY, default-route changes, or policy routing in the first MVP.
- First server bind must use a new high UDP port, not `443/udp`, because `caddy` already owns UDP/TCP 443.
- All server state must live under one prefix, e.g. `/opt/vibe-hy2-mvp`, so cleanup is one command.

## Evidence from docs

- Official image: `tobyxdd/hysteria`, small image, documented Docker usage.
- Hysteria server can listen on any UDP port with `listen: :PORT`.
- Client supports `hysteria2://...` URIs containing auth, SNI, insecure flag, certificate pin, and Salamander obfuscation parameters.
- Client modes include SOCKS5/HTTP for sandbox tests and TUN mode in GUI apps for device-wide usage.
- Port hopping and TProxy exist, but both require firewall/routing privileges; postpone them.

## MVP shape

### Server: Docker container on VPS

Use existing Docker, with only UDP port publish:

```sh
docker run -d --name vibe-hy2-mvp \
  --restart unless-stopped \
  -p 18443:8443/udp \
  -v /opt/vibe-hy2-mvp:/etc/hysteria:ro \
  tobyxdd/hysteria:v2.8.2 \
  server -c /etc/hysteria/server.yaml
```

No `--network host`, no `--cap-add NET_ADMIN`, no TUN, no TProxy.

### Server config MVP

Use a self-signed certificate plus SHA-256 certificate pin in the client URI. This avoids manual CA installation on clients while still protecting against trivial MITM better than `insecure` alone.

```yaml
listen: :8443

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
  sniGuard: disable

auth:
  type: password
  password: ${HY2_AUTH_PASSWORD}

obfs:
  type: salamander
  salamander:
    password: ${HY2_OBFS_PASSWORD}

ignoreClientBandwidth: true
congestion:
  type: bbr
  bbrProfile: standard

resolver:
  type: udp
  udp:
    addr: 1.1.1.1:53
    timeout: 4s

masquerade:
  type: string
  string:
    content: ok
    statusCode: 200
```

Notes:

- With Salamander enabled, Hysteria is intentionally not a valid HTTP/3 masquerade endpoint; it looks like obfuscated UDP. This is acceptable for the MVP.
- For a later stealth profile, run a second non-obfuscated HTTP/3-masquerade instance on a separate port or migrate to `443/udp` only after auditing Caddy.

### Firewall

Open only the chosen UDP port:

```sh
ufw allow 18443/udp comment 'vibe hy2 mvp'
```

Verification must confirm no Tailscale/sing-box rules changed:

```sh
systemctl is-active tailscaled.service sing-box-vibe-router.service
iptables-save | grep -E 'VIBE_ROUTER_PIXEL|tailscale0|vibe-router-pixel'
ip rule show
ss -lunp | grep 18443
```

## Client onboarding options

### Human-friendly primary path

Give the user one QR / one link:

```text
hysteria2://<AUTH_PASSWORD>@<VPS_IP_OR_DOMAIN>:18443/?insecure=1&pinSHA256=<CERT_SHA256>&obfs=salamander&obfs-password=<OBFS_PASSWORD>&sni=www.cloudflare.com
```

Recommended apps:

- Android: Hiddify Next or NekoBox for Android.
- iOS/macOS: Streisand, Shadowrocket, Stash, or Hiddify Next.
- Windows/Linux/macOS: Hiddify Next.

User flow:

1. Install app.
2. Import from QR/link.
3. Press connect.
4. Check `https://ifconfig.me`.

### Local sandbox client path

For testing from our workstation without changing host routes, run Hysteria client in a Podman container exposing only a SOCKS/HTTP proxy on localhost:

```sh
podman run --rm --name vibe-hy2-client \
  -p 127.0.0.1:1080:1080/tcp \
  -p 127.0.0.1:8081:8081/tcp \
  -v "$PWD/.hermes/hysteria2/client.yaml:/etc/hysteria/client.yaml:ro,Z" \
  tobyxdd/hysteria:v2.8.2 \
  client -c /etc/hysteria/client.yaml
```

Client config:

```yaml
server: <VPS_IP_OR_DOMAIN>:18443
auth: <AUTH_PASSWORD>

tls:
  insecure: true
  pinSHA256: <CERT_SHA256>
  sni: www.cloudflare.com

obfs:
  type: salamander
  salamander:
    password: <OBFS_PASSWORD>

ignoreClientBandwidth: true
congestion:
  type: bbr
  bbrProfile: standard

socks5:
  listen: 0.0.0.0:1080

http:
  listen: 0.0.0.0:8081
```

Test without touching default routes:

```sh
curl --socks5-hostname 127.0.0.1:1080 https://ifconfig.me
curl -x http://127.0.0.1:8081 https://ifconfig.me
```

## Repo implementation tasks

Create `deploy/hysteria2-mvp/`:

- `server.yaml.template` — server config template.
- `client.yaml.template` — local sandbox client config template.
- `install-vps.sh` — guarded script that creates `/opt/vibe-hy2-mvp`, generates secrets/cert, opens UDP port, starts Docker container.
- `status-vps.sh` — prints Docker, port, firewall, Tailscale and sing-box status.
- `rollback-vps.sh` — removes only `vibe-hy2-mvp`, `/opt/vibe-hy2-mvp`, and `ufw delete allow 18443/udp`.
- `make-client-uri.sh` — prints `hysteria2://...` and optional QR if `qrencode` exists.
- `run-client-podman.sh` — local sandbox client runner.
- `README.md` — exact runbook.

All scripts must have dry-run mode first or be small/readable enough to review before execution.

## Acceptance criteria

### Server acceptance

- `docker ps` shows `vibe-hy2-mvp` running.
- `ss -lunp` shows UDP `18443` bound by Docker proxy/container path.
- `tailscaled.service` is still active.
- `sing-box-vibe-router.service` is still active.
- No new `ip rule` except pre-existing Tailscale/sing-box rules.
- No new broad iptables mangle chains.

### Client acceptance

- Local Podman sandbox client connects and logs `connected to server`.
- `curl --socks5-hostname 127.0.0.1:1080 https://ifconfig.me` returns VPS public IP.
- Android/iOS app can import the URI/QR and connect.
- If one network blocks it, test another network before changing server.

## Rollback

```sh
docker rm -f vibe-hy2-mvp || true
ufw delete allow 18443/udp || true
rm -rf /opt/vibe-hy2-mvp
```

Post-rollback checks:

```sh
systemctl is-active tailscaled.service sing-box-vibe-router.service
ss -lunp | grep 18443 || true
docker ps --filter name=vibe-hy2-mvp
```

## Later phases

1. Real domain + real TLS cert, so client URI can avoid `insecure=1`.
2. Non-obfuscated HTTP/3 masquerade profile on a domain if HTTP/3 camouflage works better.
3. Salamander fallback profile on a high UDP port.
4. Port hopping only after MVP works and only if we accept controlled firewall changes.
5. Subscription/landing page that shows platform buttons and QR codes.
6. Optional full-device TUN profiles via Hiddify/Streisand, not via our shell scripts.
