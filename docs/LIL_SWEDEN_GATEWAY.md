# lil-sweden gateway notes

Date: 2026-05-09

## Purpose

Second gateway VPS in Sweden. Initial role: Hysteria 2 server candidate and later
optional Hermes/Pi agent host. This node is separate from the Petersburg
`vibe-practicum` gateway.

## Host

- SSH alias: `lil-sweden`
- Public IPv4: `84.22.149.216`
- Public DNS name: `computer.peacedata.company`
- SSH user: `root`
- Hostname observed: `lil-sweden.aeza.network`
- OS observed: Debian 12, Linux 6.1.x amd64

## SSH access paths

Configured and verified:

```text
kcnc-pc -> lil-sweden
vibe-practicum/deploy -> lil-sweden
```

Local workstation SSH config:

```sshconfig
Host lil-sweden
  HostName 84.22.149.216
  User root
  IdentityFile ~/.ssh/lil-sweden
  IdentitiesOnly yes
  PubkeyAuthentication yes
  PreferredAuthentications publickey
  PasswordAuthentication no
  ServerAliveInterval 30
  ServerAliveCountMax 3
```

`vibe-practicum` has an independent deploy-user key at
`/home/deploy/.ssh/lil-sweden` and the same `Host lil-sweden` alias in
`/home/deploy/.ssh/config`.

Verification commands:

```bash
ssh -o BatchMode=yes lil-sweden 'hostname; whoami'
ssh -o BatchMode=yes vibe-practicum 'ssh -o BatchMode=yes lil-sweden "hostname; whoami"'
```

Expected result: both print `lil-sweden.aeza.network` and `root`.

## SSH hardening applied

`/etc/ssh/sshd_config.d/99-vibe-secure.conf` on `lil-sweden`:

```sshconfig
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
MaxAuthTries 3
X11Forwarding no
```

Effective policy verified with:

```bash
ssh lil-sweden 'sshd -T | grep -E "^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication) "'
```

Current expected output:

```text
permitrootlogin without-password
pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
```

## Host key fingerprints observed by TOFU

```text
RSA     SHA256:JwdUG1wRE6isinIWUlI2xi5ykWxbncDhzF3ynB+KWPM
ECDSA   SHA256:MxMg6d6RGOMoq+rGEkKpJ+SMwU4OBH9w1Q7N74eGSiY
ED25519 SHA256:dPdsVCYkIwaFJ1pw+zpF8pFwaZlise4f6DNRm84Q4S0
```

## Public web site

`computer.peacedata.company` resolves to `84.22.149.216` and serves a small
static pixel-computer landing page over HTTPS.

Runtime layout on `lil-sweden`:

```text
/var/www/computer.peacedata.company/index.html
/etc/caddy/Caddyfile
```

Caddy manages the Let's Encrypt certificate automatically and is configured for
TLS 1.3. Do not commit Caddy private keys or certificate cache files.

## Hysteria 2 upstream

`hysteria-vibe-hy2.service` runs the official Hysteria 2 server binary on
`lil-sweden`.

Runtime layout on `lil-sweden`:

```text
/usr/local/bin/hysteria
/etc/vibe-hy2/server.yaml
/etc/vibe-hy2-xray/auth.env
```

Public endpoint for client/Xray configs:

```text
address: computer.peacedata.company
port: 18443/udp
SNI: computer.peacedata.company
ALPN: h3
TLS verification: enabled; do not use allowInsecure for the normal config
```

`vibe-vpn` includes this node through the root-only static node file on
`vibe-practicum`:

```text
/etc/vibe-vpn/extra-nodes.json
/etc/vibe-vpn/lil-sweden-hy2-auth
```

The static node uses client-side Brutal hints at `200 mbps`, which was the best
observed stable setting during quick tests.

The Hysteria server direct outbound is forced to IPv4 (`direct.mode: 4`). This
keeps the observed egress stable at `84.22.149.216` and avoids Cloudflare speed
endpoint rate-limit behavior seen on the server IPv6 egress.

The Hysteria server uses Caddy's Let's Encrypt certificate for
`computer.peacedata.company`, with `sniGuard: strict`, and masquerades unknown
HTTP/3 traffic by proxying to `https://computer.peacedata.company`.

## Security notes

- Do not commit private keys, passwords, Hysteria secrets, generated URIs, or
  QR codes.
- Password SSH login is disabled after verifying both key paths.
- Keep `vibe-practicum` and local workstation keys independent; do not copy the
  local private key to `vibe-practicum`.
- Do not commit `/etc/vibe-hy2-xray/auth.env` or any rendered config containing
  the Hysteria auth password.

## Next steps

1. Add `computer.peacedata.company:18443` as a static/extra node in
   `vibe-vpn`, using Xray `protocol: hysteria` with `version: 2`.
2. Run `sudo vibe-vpn test` and verify the node appears in normal results.
3. Only after SSH, web, and VPN rollback are stable, consider installing
   Hermes/Pi agent tooling on `lil-sweden`.
