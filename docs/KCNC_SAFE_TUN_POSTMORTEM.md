# kcnc-pc safe TUN attempt postmortem

Date: 2026-05-01

## Status

The local sing-box TUN attempt is marked unsafe and disabled by default.

Rollback script:

```bash
/home/kcnc/code/tools/vibe-practicum-vpn/scripts/kcnc-safe-tun-disable.sh
```

The enable script now refuses to run unless explicitly forced with:

```bash
KCNC_ALLOW_UNSAFE_TUN=1 sudo -E /home/kcnc/code/tools/vibe-practicum-vpn/scripts/kcnc-safe-tun-enable.sh
```

Do not force it during normal work.

## What happened

The intended path was:

```text
normal traffic -> local sing-box TUN -> VPS SOCKS 100.121.107.112:2080 over tailscale0 -> VPS -> VLESS
RU/Steam/Dota -> local sing-box TUN -> wlan0 direct
VPS tailnet IP -> tailscale0 direct
```

The service started, but user traffic broke and the setup was rolled back.

## Evidence saved

Full local postmortem snapshot:

```text
/home/kcnc/code/tools/vibe-practicum-vpn/snapshots/kcnc-safe-tun/postmortem-20260501-022148.txt
```

Relevant observed log line from tailscaled:

```text
open-conn-track: timeout opening (TCP 100.68.65.56:45524 => 198.18.0.0:80); no associated peer node
```

## Likely cause

V2RayA is active as the current rescue/workaround and appears to use fake-IP style addresses in `198.18.0.0/15`.

The local sing-box TUN attempt was introduced on top of that active V2RayA environment. That created a conflict between:

- V2RayA's local proxy/fake-IP behavior;
- sing-box TUN packet capture;
- Tailscale mesh routing table/rules.

So this was not a clean test of the proposed architecture. It was a mixed stack.

## Mistakes in the attempt

1. The enable script only checked TCP reachability to `100.121.107.112:2080`, not a real SOCKS HTTP request through it.
2. There was no pre/post snapshot built into the enable path.
3. The script started full TUN capture before proving DNS and upstream proxy behavior.
4. The design did not account for V2RayA fake-IP mode.
5. The script was left runnable after failure; this has now been fixed with an explicit unsafe guard.

## Next rules

Before any future network-changing script:

1. Save pre-snapshot to `snapshots/`.
2. Prove upstream proxy with a real request, not just TCP connect.
3. Detect V2RayA and either refuse or explicitly design around it.
4. Do not start TUN capture until all preflight checks pass.
5. Keep automatic rollback command printed and tested.

## Next safer direction

Do not stack local sing-box TUN on top of active V2RayA fake-IP mode.

Prefer either:

1. VPS-side Tailscale exit-node + TProxy, with local Steam/Dota CIDR bypass; or
2. a clean local TUN test only after V2RayA interaction is understood and isolated.
