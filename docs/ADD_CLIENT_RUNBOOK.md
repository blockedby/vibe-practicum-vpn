# Add a new Tailscale client to VPS routing

This is the operational runbook for adding another device to the current design.

## Current design

Clients are dumb/simple:

```text
client device -> Tailscale exit-node awsbbbuslw -> VPS sing-box TProxy -> direct RU or VLESS proxy
```

Do **not** install proxy/VLESS/sing-box on normal clients. The client should only run Tailscale.

Current VPS exit node:

```text
Tailscale name: awsbbbuslw
Tailscale IP:   100.121.107.112
Public IP:      45.12.74.211
```

Current accepted clients:

```text
pixel-7-pro  100.109.247.47
kcnc-pc      100.64.19.94
```

## 1. Install and authorize Tailscale on the client

### Windows

Install:

```text
https://tailscale.com/download/windows
```

Then log in, open the tray icon, and select:

```text
Exit Nodes -> awsbbbuslw
```

### Kubuntu / Ubuntu / Linux

Install:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

Authorize:

```bash
sudo tailscale up
```

Enable the VPS as exit node:

```bash
sudo tailscale up --exit-node='100.121.107.112' --exit-node-allow-lan-access=true --accept-routes
```

Equivalent by name, if MagicDNS/name resolution works:

```bash
sudo tailscale up --exit-node='awsbbbuslw' --exit-node-allow-lan-access=true --accept-routes
```

Check:

```bash
tailscale status
tailscale ip -4
```

If non-root use of `tailscale down/up` is desired on Linux:

```bash
sudo tailscale set --operator=$USER
```

## 2. Find the new client's Tailscale IP

From the client:

```bash
tailscale ip -4
```

Or from any tailnet machine:

```bash
tailscale status
```

Example:

```text
100.x.y.z  fiance-windows  blockedby@  windows
```

Record:

```text
CLIENT_NAME='fiance-windows'
CLIENT_TS_IP='100.x.y.z'
```

Use a simple ASCII `CLIENT_NAME` because it becomes part of an iptables comment.
Good examples:

```text
fiance-windows
kubuntu-laptop
work-phone
```

## 3. Add the client to VPS TProxy capture

From repo root:

```bash
cd /home/kcnc/code/tools/vibe-practicum-vpn
```

Run:

```bash
VIBE_PRACTICUM_SUDO_PASSWORD='...' \
CLIENT_NAME='fiance-windows' \
CLIENT_TS_IP='100.x.y.z' \
./scripts/enable-tproxy-client.sh
```

This adds a VPS iptables mangle PREROUTING entry like:

```text
-s 100.x.y.z/32 -i tailscale0 -j VIBE_ROUTER_PIXEL
```

Despite the historical chain name `VIBE_ROUTER_PIXEL`, it is now the shared TProxy chain for accepted clients.

## 4. Verify routing

On the client, with exit node enabled:

```bash
curl -4 https://ifconfig.me
```

Expected for default/non-RU traffic:

```text
212.118.55.209
```

If it shows this, traffic is going through VLESS/proxy.

If it shows this instead:

```text
45.12.74.211
```

then the client is only using raw Tailscale exit-node NAT and is **not yet captured by VPS TProxy**.

Also test manually:

- Telegram
- YouTube
- ChatGPT/OpenAI
- Ozon
- `https://2ip.ru`
- bank/gosuslugi if needed

## 5. Save the state

After successful validation:

1. Add a note under `docs/` for the client, or update the accepted-client list.
2. Commit and push.

Example:

```bash
git add docs/ scripts/
git commit -m 'Add fiance Windows TProxy client'
git push
```

## Disable one client

This removes only that client's PREROUTING capture rule. It does not stop sing-box and does not affect other accepted clients.

```bash
VIBE_PRACTICUM_SUDO_PASSWORD='...' \
CLIENT_NAME='fiance-windows' \
CLIENT_TS_IP='100.x.y.z' \
./scripts/disable-tproxy-client.sh
```

## Client-side rollback

On Windows: Tailscale tray icon -> disable exit node or disconnect Tailscale.

On Linux:

```bash
sudo tailscale down
```

Or keep Tailscale connected but stop using exit node:

```bash
sudo tailscale up --exit-node=
```

## Important cautions

- Do not route all tailnet clients at once until each is tested.
- Do not capture VPS host-originated traffic.
- Do not break public SSH or Tailscale SSH.
- Only add `tailscale0` source IP rules for known clients.
- Keep rollback ready.
