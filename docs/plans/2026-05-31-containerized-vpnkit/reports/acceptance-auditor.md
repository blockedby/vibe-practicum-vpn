## Task package
- Task name: containerized vpnkit OpenVPN -> sing-box lab
- Task package: docs/plans/2026-05-31-containerized-vpnkit
- Report path: docs/plans/2026-05-31-containerized-vpnkit/reports/acceptance-auditor.md
- Acceptance plan path: docs/plans/2026-05-31-containerized-vpnkit/verification/acceptance-plan.md

## Acceptance verdict
- Status: blocked
- Summary: The branch has the static container/scaffold and safety checks in place, but acceptance is blocked until the real VPS-secret copy and live Docker/VLESS validation prove AC1-AC7 and AC9-AC11.

## Acceptance coverage
- AC1: Real config material copied from `vibe-practicum` into gitignored `secrets/` paths, not committed.
  - Evidence present: operator helper scripts (`scripts/vpnkit-copy-vps-secrets.sh`, `scripts/vpnkit-render-local-configs.sh`), `.gitignore` excludes `secrets/`, static secret-pattern grep passed.
  - Result: not run / partial
  - Gap: no runtime proof that the VPS material was actually copied into `secrets/vps/...` in this worktree.
- AC2: `vpnkit` container starts OpenVPN server and sing-box with the real native VLESS outbound config.
  - Evidence present: `docker-compose.yml`, `docker/vpnkit/entrypoint.sh`, rendered-config workflow.
  - Result: not run
  - Gap: no live `docker compose up` / log proof.
- AC3: `ovpn-client-test` container connects as an OpenVPN client and receives `10.89.0.x`.
  - Evidence present: `docker/ovpn-client-test/run-tests.sh`, compose test profile.
  - Result: not run
  - Gap: no live client session.
- AC4: Client packets are visible entering `vpnkit` container `tun0`.
  - Evidence present: runbook/tcpdump command documented.
  - Result: not run
  - Gap: no runtime packet capture.
- AC5: TPROXY counters increase for client traffic.
  - Evidence present: `docker/vpnkit/setup-routing.sh`, `scripts/vpnkit-collect-evidence.sh`.
  - Result: not run
  - Gap: no before/after counter evidence.
- AC6: `sing-box` logs/metrics show `inbound/tproxy` from `10.89.0.x`.
  - Evidence present: debug logging + log-grep instructions in runbook.
  - Result: not run
  - Gap: no live logs.
- AC7: `sing-box` logs/metrics show outbound traffic through `selected-native-out` to the real VLESS server.
  - Evidence present: render script extracts `selected-native-out` from copied VPS config; runbook log checks.
  - Result: not run
  - Gap: no live logs proving outbound selection.
- AC8: DNS is handled by `sing-box` rules, not by permanent direct/NAT bypass.
  - Evidence present: `config/sing-box/config.json.template`, `docker/vpnkit/setup-routing.sh`, runbook says no broad `MASQUERADE` rule; static grep found no NAT bypass and no `xray` reliance.
  - Result: passed statically / runtime not run
  - Gap: live DNS resolution path still unproven.
- AC9: DNS replies return to the OpenVPN client container.
  - Evidence present: client test script runs `dig example.com`.
  - Result: not run
  - Gap: no live DNS reply evidence.
- AC10: HTTPS works through native VLESS outbound.
  - Evidence present: client test script runs `curl https://ifconfig.me`.
  - Result: not run
  - Gap: no live HTTPS success evidence.
- AC11: Literal-IP TCP test works to prove the path is not only DNS-dependent.
  - Evidence present: client test script includes `--resolve example.com:443:1.1.1.1`.
  - Result: not run
  - Gap: no live literal-IP result.

## System readiness coverage
- Routes / registration: covered statically (`docker-compose.yml`, `docker/vpnkit/entrypoint.sh`, `docker/vpnkit/setup-routing.sh`).
- Services / APIs: covered statically (`openvpn` + `sing-box` process wiring), but no live startup proof.
- Config / env / secrets: partially covered (`secrets/vps/...` is gitignored and helper scripts/documentation exist); blocked by absence of copied real material.
- Docker / containers: covered statically (`vpnkit` + `ovpn-client-test` compose services, caps, TUN, sysctls); runtime blocked.
- Permissions / access: blocked pending safe privileged Docker/TUN execution.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: partially covered statically; no live container evidence.

## Check freshness
- Targeted checks: fresh (`2026-06-01` local `bash -n`, `docker compose config`, and static greps).
- Full local checks: missing / not needed (`go test ./...` not run because no Go files changed).
- Remote checks / CI: not available before push.

## Required before done
- Copy real VPS material into gitignored `secrets/vps/...` and render local configs.
- Run the Docker lab and collect live evidence for AC2-AC7 and AC9-AC11.
- Save redacted runtime artifacts (logs/counters/client output) under this task package.

## Files written
- `docs/plans/2026-05-31-containerized-vpnkit/verification/acceptance-plan.md`: created
- `docs/plans/2026-05-31-containerized-vpnkit/reports/acceptance-auditor.md`: created
