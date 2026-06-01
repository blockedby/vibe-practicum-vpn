## Task
- Mission: Implement safe scaffolding for a Dockerized `vpnkit` OpenVPN -> sing-box TPROXY/native VLESS lab with a separate OpenVPN client test container.
- Target: `docker/**`, `config/**`, `scripts/vpnkit-*.sh`, `docker-compose.yml`, `docs/CONTAINERIZED_VPNKIT_RUNBOOK.md`.
- Boundaries: no real secrets, no VPS mutation, no xray runtime, no broad OpenVPN NAT bypass, no Go behavior changes.
- Done when: committed artifacts let an operator copy gitignored real configs, render local runtime configs/client profile, start containers, run validation, and capture evidence.
- Expected evidence: shell syntax, compose config, static safety greps, acceptance matrix.

## Context
- Slice: containerized vpnkit OpenVPN -> sing-box lab.
- Task package: `docs/plans/2026-05-31-containerized-vpnkit`
- Report path: `docs/plans/2026-05-31-containerized-vpnkit/reports/aad-implementer-task-1.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/containerized-vpnkit-openvpn-singbox`
- Branch: `pi/containerized-vpnkit-openvpn-singbox`

## Spec compliance
- Dockerized gateway: done; `docker/vpnkit/Dockerfile`, `entrypoint.sh`, `setup-routing.sh`, `docker-compose.yml`.
- Separate test client container: done; `docker/ovpn-client-test/*`, compose profile `test`.
- Gitignored real secrets workflow: done; `scripts/vpnkit-copy-vps-secrets.sh`, `scripts/vpnkit-render-local-configs.sh`, runbook.
- Safe VLESS validation/evidence path: done as operator-bound workflow; live run pending real secrets/privileged Docker.
- No xray/no broad NAT bypass/no committed secrets: passed static checks below.

## Acceptance verification
- AC1 real configs copied to gitignored `secrets/`: partial/pending live; helper copies documented paths into `secrets/vps`, which `.gitignore` excludes.
- AC2 `vpnkit` starts OpenVPN + sing-box with real VLESS: scaffolded; pending live run after secrets render.
- AC3 client gets `10.89.0.x`: scaffolded in client entrypoint; pending live run.
- AC4 packets visible on `tun0`: evidence commands documented; pending live tcpdump.
- AC5 TPROXY counters increase: routing script installs chain; evidence command documented; pending live traffic.
- AC6 sing-box inbound from `10.89.0.x`: debug logging/runbook capture prepared; pending live logs.
- AC7 outbound `selected-native-out`: render extracts copied native VLESS outbound; pending live logs.
- AC8 DNS handled by sing-box/no direct NAT bypass: scaffolded and static grep passed; live DNS pending.
- AC9 DNS replies to client: `run-tests.sh` runs `dig`; pending live run.
- AC10 HTTPS through native VLESS: `run-tests.sh` curls `ifconfig.me`; pending live run/log correlation.
- AC11 literal-IP TCP: `run-tests.sh` includes `--resolve example.com:443:1.1.1.1`; pending live result.

## Verification run
- `bash -n docker/vpnkit/entrypoint.sh docker/vpnkit/setup-routing.sh docker/ovpn-client-test/entrypoint.sh docker/ovpn-client-test/run-tests.sh scripts/vpnkit-copy-vps-secrets.sh scripts/vpnkit-render-local-configs.sh scripts/vpnkit-collect-evidence.sh`: passed.
- `docker compose config >/tmp/vpnkit-compose.txt`: passed.
- Runtime NAT grep over lab files for `POSTROUTING.*10.89.0.0/24.*MASQUERADE`: passed (none).
- xray grep over lab runtime files/docs: passed (none).
- secret-pattern grep for UUID/private-key/vless URL over committed lab files: passed (none).
- `go test ./...`: not run; no Go files changed.
- Live Docker/VLESS run: not run; real secrets and privileged runtime are operator-bound.

## Issues
### U-01: Live VLESS/runtime acceptance pending operator secrets and safe privileged Docker run
- Description: AC2-AC7 and AC9-AC11 require real copied VPS config/secrets and runtime network access.
- Evidence: `secrets/` intentionally absent/untracked; live commands not run.
- Why unresolved: secret and environment boundary.
- Needed next: run `scripts/vpnkit-copy-vps-secrets.sh`, `scripts/vpnkit-render-local-configs.sh`, `docker compose up -d vpnkit`, `docker compose --profile test up ovpn-client-test`, `scripts/vpnkit-collect-evidence.sh`.

## Verdict
- Status: partial success.
- Goal state: scaffolding and safe workflow achieved; real-data runtime acceptance pending operator action.
- Final readiness: ready for operator live validation, not yet proven live.
