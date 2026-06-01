# vpnkit vibe-vpn daemon + lil-sweden Hysteria2 plan

Date: 2026-06-01
Branch: `pi/vpnkit-vibe-daemon-hy2`
Base: `main` after PR #13 merge (`c3d0e58`)

## Goal

Make containerized `vpnkit` support a long-running `vibe-vpn daemon` and allow `lil-sweden` Hysteria2 to participate in `vibe-vpn` periodic tests without committing secrets.

Target runtime remains:

```text
OpenVPN clients -> vpnkit OpenVPN -> sing-box -> selected backend -> internet
```

For this slice, selected backend candidates include both VLESS subscription nodes and gitignored extra nodes such as:

```text
lil-sweden Hysteria2: UDP/443, SNI computer.peacedata.company
```

## Constraints

- Do not commit real Hysteria auth, subscription URLs, rendered configs, or client profiles.
- `lil-sweden` auth material must live under gitignored `secrets/` and be mounted/rendered to `/etc/vibe-vpn`.
- Existing stable Docker/VPS behavior must remain available if daemon is disabled.
- Local UDP path to `lil-sweden` may time out from this host; classify that separately from code/config failures.
- Preserve TCP/443 Caddy + UDP/443 Hysteria2 on `lil-sweden`.

## Task split

### T1 — Container daemon wiring

- Add a `vibe-vpn daemon` process to `docker/vpnkit/entrypoint.sh` behind an explicit env flag.
- Monitor the daemon like OpenVPN and sing-box when enabled.
- Keep default behavior stable when disabled.

Acceptance:

- Container starts without daemon by default.
- Container starts and supervises daemon with `VPNKIT_ENABLE_VIBE_VPN_DAEMON=true`.

### T2 — Production SOCKS for daemon health

- Add loopback SOCKS inbound to the container sing-box template at `127.0.0.1:2080` because `vibe-vpn daemon` health uses `production_socks`.

Acceptance:

- `sing-box check` passes.
- `vibe-vpn daemon` health can probe through production sing-box instead of immediately failing on connection refused.

### T3 — Hysteria2 extra node support for sing-box runtime

- Make extra Hysteria2 nodes produce sing-box-compatible `hysteria2` outbounds for `runtime: singbox` tests and apply.
- Preserve VLESS subscription behavior.
- Avoid DNS bootstrap loops by supporting IP dial host + TLS server name.

Acceptance:

- Unit tests cover Hysteria2 extra-node sing-box outbound shape.
- `vibe-vpn test` can test extra Hysteria2 nodes under sing-box runtime.
- `vibe-vpn apply` can apply a tested Hysteria2 extra node to sing-box.

### T4 — lil-sweden secret template/docs

- Add a sanitized extra-node template for `lil-sweden` with placeholder `auth_file`.
- Document where to put the real auth file and how to render/copy it into the container.

Acceptance:

- No real auth committed.
- Operator has exact gitignored paths/commands.

### T5 — Verification

- Run unit tests/build.
- Run container config checks.
- If local UDP to lil-sweden fails, record that as environmental and separately verify from `vibe-practicum`, where Hysteria2 was already observed working.

Acceptance evidence:

- `go test ./...`
- `go build ./cmd/vibe-vpn`
- `docker build` for vpnkit
- `sing-box check` for rendered/test config
- local/remote Hysteria result classified
