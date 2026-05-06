# Hysteria 2 MVP

Isolated Hysteria 2 MVP for `positions.peacedata.company`.

Server side uses the existing VPS Docker runtime and publishes only IPv4 UDP
`18443`. It does not use host networking, NET_ADMIN, TUN, TProxy, policy routing,
or broad iptables chains. Hysteria outbound traffic is forced through the
existing sing-box SOCKS listener at `100.121.107.112:2080` by default.

Client-side onboarding avoids host route changes: the local sandbox client runs
in a Podman container and exposes only loopback proxies on the workstation.

## VPS install

Review first:

```sh
HY2_PUBLIC_HOST=positions.peacedata.company ./install-vps.sh --dry-run
```

Install on the VPS as root:

```sh
HY2_PUBLIC_HOST=positions.peacedata.company ./install-vps.sh
```

Useful overrides:

```sh
HY2_PUBLIC_PORT=18443
HY2_LISTEN_PORT=8443
SING_BOX_SOCKS_ADDR=100.121.107.112:2080
HY2_IMAGE=tobyxdd/hysteria:v2.8.2
```

Status and rollback:

```sh
./status-vps.sh
./rollback-vps.sh --dry-run
./rollback-vps.sh
```

The installer writes private state to `/opt/vibe-hy2-mvp`, including
`server.env`, self-signed TLS material, and the rendered server config. It checks
that `tailscaled.service` and `sing-box-vibe-router.service` are active but never
restarts/stops/disables them.

## Inputs from the server

Copy or create a server env file locally, for example:

```sh
scp root@VPS:/opt/vibe-hy2-mvp/server.env ./server.env
```

Expected keys:

```sh
HY2_HOST=positions.peacedata.company # or VPS IP; alternatively set HY2_SERVER=host:18443
HY2_PORT=18443                       # optional, defaults to 18443
HY2_AUTH_PASSWORD=...
HY2_OBFS_PASSWORD=...
HY2_PIN_SHA256=BA:88:45:17:A1:... # or HY2_CERT_PIN_SHA256 from server state
HY2_SNI=positions.peacedata.company # optional default
HY2_INSECURE=true                   # required for the self-signed MVP cert
```

If `HY2_PIN_SHA256` is missing, the scripts also accept `HY2_CERT_PIN_SHA256`,
`HY2_CERT_SHA256`, or `CERT_SHA256`, or compute it from a readable `server.crt`
next to the env file.
On the server the fingerprint can be generated with:

```sh
openssl x509 -noout -fingerprint -sha256 -in /opt/vibe-hy2-mvp/server.crt | sed 's/^.*=//'
```

The MVP server uses a self-signed certificate, so client configs intentionally
set `insecure: true` / `insecure=1` while also setting `pinSHA256` to pin that
exact certificate. Salamander obfuscation is enabled with `obfs=salamander` and
`HY2_OBFS_PASSWORD`.

## Generate a URI and optional QR

```sh
./make-client-uri.sh --env-file ./server.env
```

The script prints a `hysteria2://` URI. If `qrencode` is installed, it also
prints an ANSI QR code.

## Local Podman sandbox client

Render `client.yaml` and run Hysteria in Podman:

```sh
./run-client-podman.sh --env-file ./server.env
```

The container publishes only:

- SOCKS5: `127.0.0.1:1080`
- HTTP proxy: `127.0.0.1:8081`

It does not use host networking, NET_ADMIN, TUN, TPROXY, policy routing, or host
route changes.

To render without starting Podman:

```sh
./run-client-podman.sh --env-file ./server.env --render-only
```

Local proxy tests, without changing default routes:

```sh
curl --socks5-hostname 127.0.0.1:1080 https://ifconfig.me
curl -x http://127.0.0.1:8081 https://ifconfig.me
```

Both commands should return the expected sing-box/Xray exit IP when the server is reachable; because server egress is forced through sing-box, this may differ from the VPS public IP.

## Android: Hiddify Next

1. Install Hiddify Next.
2. Run `./make-client-uri.sh --env-file ./server.env` and copy the URI or scan
   the QR code.
3. In Hiddify Next, import from clipboard or QR.
4. Connect the profile.
5. Check `https://ifconfig.me` in the browser.

The URI carries the MVP settings: `insecure=1`, `pinSHA256`,
`obfs=salamander`, `obfs-password`, and `sni`.

## Android: NekoBox

1. Install NekoBox for Android.
2. Import the generated `hysteria2://` URI from clipboard or QR.
3. Verify the profile shows Hysteria 2 with Salamander obfuscation.
4. Connect and check `https://ifconfig.me`.

If import drops any TLS fields, edit the profile manually and ensure insecure TLS
is allowed for the self-signed cert, the SHA-256 certificate pin is present, SNI
is set to `positions.peacedata.company` unless overridden, and Salamander password matches
`HY2_OBFS_PASSWORD`.

## iOS: Streisand

1. Install Streisand.
2. Import the generated URI/QR.
3. Connect the profile.
4. Check `https://ifconfig.me`.

Confirm the imported profile preserves the self-signed-cert settings
(`insecure=1` plus `pinSHA256`) and Salamander obfuscation.

## iOS: Shadowrocket

1. Install Shadowrocket.
2. Add/import the generated `hysteria2://` URI.
3. If manual fields are required, use:
   - server: `HY2_HOST`/`HY2_SERVER` and UDP port `18443` (or `HY2_PORT`)
   - auth/password: `HY2_AUTH_PASSWORD`
   - TLS: allow insecure for the self-signed MVP cert and set the SHA-256 pin
   - SNI: `positions.peacedata.company` unless overridden
   - obfs: Salamander with `HY2_OBFS_PASSWORD`
4. Connect and check `https://ifconfig.me`.

## Troubleshooting

- A wrong Salamander password usually looks like a timeout.
- A changed or mismatched certificate causes pin verification failures; regenerate
  the URI after rotating the server cert.
- Some networks block UDP or QUIC-like traffic. Test another network before
  changing the server.
- Do not import `client.yaml` into GUI apps unless they explicitly support full
  Hysteria YAML; use the URI/QR for normal onboarding.
