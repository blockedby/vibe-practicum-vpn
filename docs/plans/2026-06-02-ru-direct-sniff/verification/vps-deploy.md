# VPS deploy verification: RU direct sniff

Date: 2026-06-02
Target: `vibe-practicum` Docker `vpnkit` runtime (`45.12.74.211:1194/udp`)
Source commit: `0e4cbfb Add vpnkit RU domain sniff routing`

## Intended deploy path
- Deploy source from main commit `0e4cbfb` to `/opt/vpnkit/src`.
- Rebuild `vpnkit:vps` using Docker runtime only.
- Regenerate and install persisted sing-box config under `/opt/vpnkit/state/sing-box/config.json` / container `/var/lib/vpnkit/sing-box/config.json`.
- Recreate existing Docker `vpnkit` container preserving bind mounts/env/ports.
- Verify mounted config has route-action sniff plus RU rules.
- Run baseline OpenVPN smoke and `2ip.ru` smoke through the client test container.

## Actual result
Deployment was **not performed** because SSH/network access to the VPS timed out before any remote mutation was attempted.

## Evidence
- `ssh -o ConnectTimeout=10 vibe-practicum 'echo ok'`: failed with `ssh: connect to host 45.12.74.211 port 22: Connection timed out`.
- `ping -c 2 -W 2 45.12.74.211`: 100% packet loss.
- `nc -zvw5 45.12.74.211 1194`: TCP probe timed out (note: OpenVPN is UDP, this only indicates no TCP listener/reachability by this probe).
- `nc -zvw5 45.12.74.211 22`: timed out.

## Safety outcome
- No VPS Docker runtime mutation was attempted.
- No Steam Deck or native services were touched.
- Source commit was pushed to `origin/main`, so the deploy can be resumed from `0e4cbfb` once SSH access is available.
