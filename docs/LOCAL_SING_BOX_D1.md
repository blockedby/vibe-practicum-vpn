# D1: local sing-box TUN on kcnc-pc, VPS router over Tailscale

## Goal

Keep the normal centralized VPS policy for browsing/RU/OpenAI, but make Steam/Dota local-direct by process, not by IP lists.

```text
ChatGPT/browser -> local sing-box TUN -> SOCKS to VPS over Tailscale -> VPS sing-box -> VLESS/direct rules
Steam/Dota     -> local sing-box TUN -> local-direct -> home ISP
```

This is only for gaming/dev Linux PCs. Phones/Windows/simple clients should keep the dumb Tailscale exit-node model.

## Important difference from current dumb-client mode

For D1, the Linux PC should be connected to Tailscale **without global exit-node**:

```bash
sudo tailscale up --reset --accept-routes
```

`--reset` is intentional: if the machine previously used exit-node flags, Tailscale may refuse plain `tailscale up --accept-routes` and ask to repeat the old `--exit-node=...` flags. Do **not** repeat them for D1, because that would keep global exit-node mode enabled.

Do not use this while D1 local sing-box is active:

```bash
sudo tailscale up --exit-node='100.121.107.112' --exit-node-allow-lan-access=true --accept-routes
```

Reason: if Tailscale exit-node is globally active, even `local-direct` traffic from Steam/Dota may still be pulled through `tailscale0` by Tailscale policy routing.

## VPS side

VPS sing-box exposes a SOCKS inbound only on the VPS Tailscale IP:

```text
100.121.107.112:2080
```

Config tag:

```text
tailnet-socks-in
```

This must never listen on public `0.0.0.0`.

## Local PC side

Local config:

```text
configs/sing-box/local/kcnc-pc-tun.json
```

Local service installed by script:

```text
sing-box-vibe-local.service
```

Policy:

```text
process_name/path Steam/Dota -> local-direct
private/Tailscale/LAN IPs     -> local-direct
final                         -> vps-router SOCKS 100.121.107.112:2080
```

## Install sing-box locally

If missing, install from the official SagerNet APT repository, same as VPS, or use the package already available on the machine.

Check:

```bash
sing-box version
```

## Start D1

From repo root on the Linux PC:

```bash
cd /home/kcnc/code/tools/vibe-practicum-vpn
./scripts/d1-start.sh
```

This installs sing-box if missing, then enables D1.

Lower-level command if sing-box is already installed:

```bash
./scripts/linux-d1-enable.sh
```

The script will:

1. switch Tailscale to connected/no-exit-node mode:

   ```bash
   sudo tailscale up --reset --accept-routes
   ```

2. verify VPS SOCKS:

   ```text
   100.121.107.112:2080
   ```

3. install local config to:

   ```text
   /etc/sing-box-vibe/kcnc-pc-tun.json
   ```

4. run `sing-box check`;
5. create/start `sing-box-vibe-local.service`.

## Stop D1

```bash
cd /home/kcnc/code/tools/vibe-practicum-vpn
./scripts/d1-stop.sh
```

Lower-level command:

```bash
./scripts/linux-d1-disable.sh
```

After disabling, if you want the old dumb-client mode back:

```bash
sudo tailscale up --exit-node='100.121.107.112' --exit-node-allow-lan-access=true --accept-routes
```

## Verify

Default traffic should still use VLESS/proxy:

```bash
curl -4 https://ifconfig.me
```

Expected:

```text
212.118.55.209
```

Steam/Dota should be logged locally as `local-direct`.

Local logs:

```bash
journalctl -u sing-box-vibe-local.service --since '5 minutes ago' --no-pager | egrep 'steam|dota|local-direct|vps-router'
```

VPS logs should still show browser/default traffic entering via `tailnet-socks-in`/SOCKS and leaving by VPS rules.

## Rollback

Fast rollback:

```bash
./scripts/d1-stop.sh
sudo tailscale up --exit-node='100.121.107.112' --exit-node-allow-lan-access=true --accept-routes
```

## Known risks

- process matching on Linux may need tuning for Steam runtime / Proton / pressure-vessel process names;
- if local sing-box crashes, the TUN default route may temporarily break traffic until service is stopped or restarted;
- this intentionally adds client complexity only for `kcnc-pc` gaming use.
