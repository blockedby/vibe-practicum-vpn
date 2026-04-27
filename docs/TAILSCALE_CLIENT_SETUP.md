# Tailscale client setup

Goal: clients stay dumb/simple. Install Tailscale, log in to the same tailnet, and select VPS `awsbbbuslw` / `vibe-practicum` as the exit node. All routing decisions then happen on the VPS.

Current VPS exit node:

```text
hostname: awsbbbuslw
VPS public IP: 45.12.74.211
VPS Tailscale IP: 100.121.107.112
Tailscale exit node name to select: awsbbbuslw
```

## Before adding a new device

Do not enable complicated proxy apps on the client. The client should only run Tailscale.

For each new device:

1. Install Tailscale.
2. Log in to the same tailnet.
3. Select exit node `awsbbbuslw`.
4. Tell the VPS operator the new device name and Tailscale IP.
5. Add the device to the VPS TProxy capture rules if we are still in per-device canary mode.
6. Run the acceptance checklist.

Checklist template:

```text
docs/PIXEL_ACCEPTANCE_CHECKLIST.md
```

## Android / Pixel

1. Install **Tailscale** from Google Play.
2. Log in.
3. Open Tailscale app.
4. Find `awsbbbuslw`.
5. Enable **Use exit node** / **Exit node** and select `awsbbbuslw`.
6. If Android asks for VPN permission, allow it.
7. Keep other VPN/proxy apps disabled while testing.

## Windows

1. Download Tailscale:

   ```text
   https://tailscale.com/download/windows
   ```

2. Install and log in to the same tailnet.
3. Open Tailscale from the system tray.
4. Choose:

   ```text
   Exit Nodes -> awsbbbuslw
   ```

5. Enable if prompted:

   ```text
   Use exit node
   ```

6. Optional but useful: enable **Run unattended** / start with Windows if this PC should always use the VPN.
7. Test:

   - Telegram
   - YouTube
   - Ozon
   - `https://2ip.ru`
   - a non-RU IP-check site

Expected:

- RU/direct resources show the VPS/direct Russian route where matched.
- General/non-RU resources go through VLESS/proxy.

## Kubuntu / Ubuntu Linux

### Install

Recommended official install command:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

Or via package manager after the repo is installed by the script:

```bash
sudo apt update
sudo apt install tailscale
```

### Log in

```bash
sudo tailscale up
```

Open the login URL in the browser and authenticate.

### Use VPS as exit node

```bash
sudo tailscale up --exit-node=awsbbbuslw --exit-node-allow-lan-access=true
```

If name resolution does not work, use the VPS Tailscale IP:

```bash
sudo tailscale up --exit-node=100.121.107.112 --exit-node-allow-lan-access=true
```

Check status:

```bash
tailscale status
```

Check current exit IP:

```bash
curl -4 https://ifconfig.me
```

### Disable exit node if needed

```bash
sudo tailscale up --exit-node=
```

Or fully disconnect Tailscale:

```bash
sudo tailscale down
```

## Acceptance checklist for a new device

Copy this table into a new note or issue for each device.

| Check | Expected | Status |
| --- | --- | --- |
| Tailscale connected | device visible in `tailscale status` | TODO |
| Exit node selected | `awsbbbuslw` selected | TODO |
| Telegram | works | TODO |
| YouTube | works | TODO |
| 2ip.ru | RU/direct behavior as expected | TODO |
| non-RU IP-check | proxy/VLESS behavior as expected | TODO |
| Ozon | works, not blocked as VPN | TODO |
| Госуслуги/bank if needed | opens normally | TODO |
| General browsing | fast/stable | TODO |

## Rollback on client

Fast rollback is client-side:

1. Open Tailscale.
2. Disable exit node, or disconnect Tailscale.

Server-side rollback for Pixel canary:

```bash
cd /home/kcnc/code/tools/vibe-practicum-vpn
VIBE_PRACTICUM_SUDO_PASSWORD='...' ./scripts/disable-pixel-tproxy-canary.sh
```
