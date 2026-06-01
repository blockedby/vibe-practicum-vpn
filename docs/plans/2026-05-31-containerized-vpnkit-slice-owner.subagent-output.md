## Task
- Mission: Prepare repo scaffolding and safe operator workflow for a containerized OpenVPN -> sing-box native VLESS lab for issue #11.
- Target: Docker gateway/test-client lab, sanitized templates, operator scripts, runbook, and AAD task package.
- Boundaries: no committed secrets, no VPS mutation, no xray lab runtime, no permanent broad NAT bypass, no unrelated Go changes.
- Done when: scaffold is committed, safe checks pass, and live ACs are mapped to exact operator validation steps.
- Expected evidence: changed files, local checks, acceptance matrix, blockers/risks, next commands.

## Context
- Thread: root owner delegated containerized vpn-kit issue #11 slice.
- Slice: containerized vpnkit OpenVPN -> sing-box lab.
- Task package: `docs/plans/2026-05-31-containerized-vpnkit`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/containerized-vpnkit-openvpn-singbox`
- Branch: `pi/containerized-vpnkit-openvpn-singbox`
- Commit: `cdbdcb8 Add containerized vpnkit lab scaffold`

## Changed files
- `docker-compose.yml`
- `docker/vpnkit/{Dockerfile,entrypoint.sh,setup-routing.sh}`
- `docker/ovpn-client-test/{Dockerfile,entrypoint.sh,run-tests.sh}`
- `config/openvpn/{server.tpl,test-client.ovpn.template}`
- `config/sing-box/config.json.template`
- `scripts/vpnkit-copy-vps-secrets.sh`
- `scripts/vpnkit-render-local-configs.sh`
- `scripts/vpnkit-collect-evidence.sh`
- `docs/CONTAINERIZED_VPNKIT_RUNBOOK.md`
- `docs/plans/2026-05-31-containerized-vpnkit-openvpn-singbox.md`
- `docs/plans/2026-05-31-containerized-vpnkit/**`

## Spec compliance
- Docker `vpnkit` gateway: done; starts sing-box then OpenVPN and installs TPROXY routing after `tun0` appears.
- Separate client namespace: done; `ovpn-client-test` compose profile connects to `remote vpnkit 1194`.
- Native VLESS path: prepared; render script extracts real `selected-native-out` VLESS outbound from gitignored copied VPS sing-box JSON.
- DNS under sing-box: prepared; template uses sing-box DNS detoured via `selected-native-out`, no OpenVPN pool NAT fallback.
- Secret safety: done by design; real material only under ignored `secrets/vps/...`.

## Acceptance verification
- AC1 real config copied to `secrets/`: implemented as operator helper; not run. Evidence: `scripts/vpnkit-copy-vps-secrets.sh`, `.gitignore` contains `secrets/`.
- AC2 `vpnkit` starts with real VLESS: scaffolded, pending live run. Evidence: `docker/vpnkit/entrypoint.sh`, `scripts/vpnkit-render-local-configs.sh`.
- AC3 client gets `10.89.0.x`: scaffolded, pending live run. Evidence: `docker/ovpn-client-test/entrypoint.sh` waits for `tun0` address.
- AC4 packets visible on `tun0`: pending live run. Evidence command documented in runbook.
- AC5 TPROXY counters increase: routing installed; pending live traffic. Evidence: `docker/vpnkit/setup-routing.sh` and collect script.
- AC6 inbound/tproxy logs from `10.89.0.x`: pending live logs. Evidence: sing-box debug log and grep commands in runbook.
- AC7 outbound `selected-native-out`: pending live logs. Evidence: renderer preserves copied outbound tag.
- AC8 DNS handled by sing-box/no broad NAT: passed static checks; live DNS pending.
- AC9 DNS replies to client: pending live run. Evidence: client `run-tests.sh` runs `dig example.com`.
- AC10 HTTPS through VLESS: pending live run. Evidence: client `run-tests.sh` runs `curl https://ifconfig.me`.
- AC11 literal-IP TCP: pending live run. Evidence: client `run-tests.sh` includes `--resolve example.com:443:1.1.1.1`.

## Verification run
- `bash -n` on all new shell scripts: passed.
- `docker compose config >/tmp/vpnkit-compose.txt`: passed.
- Static grep for lab runtime broad NAT `POSTROUTING.*10.89.0.0/24.*MASQUERADE`: passed.
- Static grep for `xray` in lab runtime/docs: passed.
- Static grep for UUID/private-key/vless URL patterns in committed lab files: passed.
- `go test ./...`: not run; no Go files changed.
- Live Docker/VLESS validation: not run; requires operator secrets and privileged container execution.

## Issues
### U-01: Live real-data validation pending
- Description: AC2-AC7 and AC9-AC11 need real copied secrets/configs and runtime network privileges.
- Evidence: no `secrets/` material is present/committed; live Docker commands were intentionally not run.
- Why unresolved: safe operator/secret boundary.
- Needed next: run `scripts/vpnkit-copy-vps-secrets.sh vibe-practicum`, `scripts/vpnkit-render-local-configs.sh`, `docker compose build`, `docker compose up -d vpnkit`, `docker compose --profile test up ovpn-client-test`, then `scripts/vpnkit-collect-evidence.sh` and compare against runbook checklist.

## Side findings
- Blocking findings folded into active work: none beyond U-01.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: partial success.
- Goal state: repo scaffolding/operator workflow achieved and committed; live VLESS acceptance not yet achieved.
- Final readiness: ready for operator real-data validation, not ready to claim runtime success.
- Summary: The slice stayed whole; implementation was completed directly after nested implementer dispatch was blocked by depth limits.

## Next-agent brief
- Objective: perform live operator validation with real gitignored VPS material and capture redacted evidence.
- Target: `secrets/vps/...`, Docker compose lab, `logs/` evidence.
- Settled already: scaffold, render path, routing rules, and acceptance checklist are in place; do not reintroduce xray or NAT bypass.
- Boundaries: keep secrets out of git; do not mutate the VPS beyond explicit copy commands.
- Verification target: all AC1-AC11 with redacted logs/counters/client command output.
- Expected output: update `docs/plans/2026-05-31-containerized-vpnkit/verification/` and issue #11/PR with redacted evidence.
