# Production sing-box runtime read-only check

Date: 2026-05-27
Host: `vibe-practicum` / `awsbbbuslw`

Scope: read-only evidence only. No files were copied, no service was restarted/enabled/disabled, and no production config was changed.

## Evidence

Commands inspected service state, unit files, process list, sanitized config shape, and repo artifacts.

### VPS service state

```text
sing-box-vibe-router.service: enabled, active/running
xray.service: disabled, active/running
vibe-vpn.service: not installed / inactive
```

Running processes included:

```text
/usr/bin/sing-box run -c /etc/sing-box-vibe/tproxy-canary.json
/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
```

Important interpretation: xray is still running as a legacy SOCKS listener, but it is disabled for boot. The active production router is `sing-box-vibe-router.service`.

### Active sing-box production config shape

Sanitized parse of `/etc/sing-box-vibe/tproxy-canary.json` showed:

```text
inbounds:
  test-socks-in      socks 127.0.0.1:2080
  tailnet-socks-in   socks 100.121.107.112:2080
  canary-tproxy-in   tproxy 0.0.0.0:2082

outbounds:
  direct-out          direct
  selected-native-out vless
  block-out           block

route final: selected-native-out
```

This confirms the current production path uses native sing-box VLESS outbound `selected-native-out`, not sing-box -> xray SOCKS for the default/final route.

### Artifacts of migration/decision

Local repo artifacts found on branch `main` ahead of `origin/main`:

```text
138792d Add native sing-box migration helper
4900335 Add native sing-box deployment path
```

Files from those commits include:

```text
docs/SINGBOX_NATIVE_DEPLOY.md
scripts/deploy-native-singbox-vps.sh
scripts/singbox-native-status.sh
internal/singbox/render.go
internal/singbox/router.go
reports/singbox-production-migration-result.md
```

VPS artifacts found:

```text
/etc/sing-box-vibe/tproxy-canary.json
/etc/sing-box-vibe/backups/tproxy-canary.json.20260518T221421Z.bak
/var/lib/vibe-vpn/backups/sing-box-before-native-20260521T004234Z.json
```

The active sing-box config timestamp was 2026-05-21 00:43 UTC, matching the native migration window.

## Resulting implementation correction

The failover-service PR must target sing-box production by default:

```yaml
runtime: singbox
sing_box_bin: /usr/bin/sing-box
sing_box_config: /etc/sing-box-vibe/tproxy-canary.json
sing_box_service: sing-box-vibe-router
production_socks: 127.0.0.1:2080
```

`xray_bin` remains only for isolated temporary benchmark tests on `test_socks` and explicit legacy `runtime: xray` configs.

## Remaining production note

Because `xray.service` is still active, a future cleanup decision can stop it once we confirm no remaining consumers use `127.0.0.1:10808`. This check did not stop it.
