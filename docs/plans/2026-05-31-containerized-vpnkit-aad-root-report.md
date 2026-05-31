## Task
- Mission: Own and execute the next AAD task for containerized vpn-kit based on `docs/plans/2026-05-31-containerized-vpnkit-openvpn-singbox.md` and issue #11.
- Target: Dockerized OpenVPN -> sing-box gateway, separate OpenVPN client test container, secret-safe real-data VLESS validation path.
- Boundaries: keep secrets out of git; no VPS mutation; no xray dependency; DNS under sing-box rules; no permanent broad NAT bypass for `10.89.0.0/24`.
- Done when: repo work is prepared/implemented where safe, verification is run, live-secret acceptance is either evidenced or explicitly pending.

## Context
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/containerized-vpnkit-openvpn-singbox`
- Branch: `pi/containerized-vpnkit-openvpn-singbox`
- PR: https://github.com/blockedby/vibe-practicum-vpn/pull/12 (draft)
- Related issue: https://github.com/blockedby/vibe-practicum-vpn/issues/11
- Root plan: `docs/plans/2026-05-31-containerized-vpnkit-openvpn-singbox.md`
- Task package: `docs/plans/2026-05-31-containerized-vpnkit/`
- Slice report: `docs/plans/2026-05-31-containerized-vpnkit-slice-owner-report.md`
- Acceptance audit: `docs/plans/2026-05-31-containerized-vpnkit/reports/acceptance-auditor.md`

## Slice structure used
- One implementation slice: containerized vpnkit lab scaffold and operator workflow.
- Why: one coherent runtime boundary and one acceptance story; splitting Docker/scripts/docs would add integration overhead without useful parallelism.
- Slice owner result: implemented scaffold, committed reports/evidence, and left live validation pending at the safe secret/operator boundary.

## Integrated changed files
- `docker-compose.yml`
- `docker/vpnkit/Dockerfile`, `entrypoint.sh`, `setup-routing.sh`
- `docker/ovpn-client-test/Dockerfile`, `entrypoint.sh`, `run-tests.sh`
- `config/openvpn/server.tpl`, `config/openvpn/test-client.ovpn.template`
- `config/sing-box/config.json.template`
- `scripts/vpnkit-copy-vps-secrets.sh`
- `scripts/vpnkit-render-local-configs.sh`
- `scripts/vpnkit-collect-evidence.sh`
- `docs/CONTAINERIZED_VPNKIT_RUNBOOK.md`
- `docs/plans/2026-05-31-containerized-vpnkit-openvpn-singbox.md`
- `docs/plans/2026-05-31-containerized-vpnkit/**`
- `docs/plans/2026-05-31-containerized-vpnkit-slice-owner-report.md`

## Spec compliance
- Docker gateway scaffold: done. `vpnkit` runs sing-box and OpenVPN, then installs fwmark/table-100 TPROXY routing for `tun0` traffic.
- Separate OpenVPN client test namespace: done. `ovpn-client-test` uses Docker networking with `remote vpnkit 1194` and waits for `10.89.0.x` on `tun0`.
- Secret handling: done for repo prep. Real material is only referenced under gitignored `secrets/vps/...`; no actual secrets were copied or committed.
- Current VPS source locations: done. Copy helper/runbook use the documented sing-box/OpenVPN/PKI/CCD paths from the plan.
- Native VLESS path: prepared. Render helper extracts `selected-native-out` from copied VPS sing-box JSON into a local gitignored rendered config.
- DNS under sing-box: prepared. Sing-box template has DNS server detoured through `selected-native-out`, route final `selected-native-out`, and no OpenVPN-pool NAT fallback.
- No xray reliance: passed static runtime/runbook check.
- No permanent broad NAT bypass: passed static runtime check.

## Acceptance verification
- AC1 real config copied into gitignored `secrets/`: partial/pending. Helper exists and `.gitignore` excludes `secrets/`; not run because it would copy real secrets.
- AC2 `vpnkit` starts with real native VLESS: scaffolded/pending. Requires rendered secret config and live Docker run.
- AC3 client connects and receives `10.89.0.x`: scaffolded/pending live run.
- AC4 packets visible entering `vpnkit` `tun0`: pending live tcpdump evidence.
- AC5 TPROXY counters increase: routing script and evidence collector exist; pending live before/after traffic evidence.
- AC6 sing-box inbound/tproxy logs from `10.89.0.x`: pending live logs.
- AC7 sing-box outbound `selected-native-out` to real VLESS: pending live logs.
- AC8 DNS under sing-box/no broad NAT bypass: passed statically; runtime DNS path pending.
- AC9 DNS replies return to client: pending live `dig` evidence.
- AC10 HTTPS works through native VLESS: pending live `curl` evidence.
- AC11 literal-IP TCP path works: pending live client test evidence.

## Verification run
- `bash -n docker/vpnkit/entrypoint.sh docker/vpnkit/setup-routing.sh docker/ovpn-client-test/entrypoint.sh docker/ovpn-client-test/run-tests.sh scripts/vpnkit-copy-vps-secrets.sh scripts/vpnkit-render-local-configs.sh scripts/vpnkit-collect-evidence.sh`: passed.
- `docker compose config >/tmp/vpnkit-compose-root-verify.txt`: passed.
- Runtime grep for broad `POSTROUTING ... 10.89.0.0/24 ... MASQUERADE`: passed; no forbidden runtime rule found.
- Runtime/runbook grep for `xray`: passed; no lab runtime/runbook dependency found.
- Secret-pattern grep over lab scaffold/reports for full `vless://`, private-key markers, and UUID-shaped values: passed.
- `go test ./...`: not run; no Go files changed.
- PR checks: PR #12 is open draft, mergeable, with no status checks reported by GitHub at audit time.
- Live Docker/VLESS validation: not run; requires operator-owned secret copy and privileged/TUN-capable Docker execution.

## Issues
### U-01: Live real-data validation pending
- Description: AC1-AC7 and AC9-AC11 require real VPS material in gitignored `secrets/vps/...` and a live Docker/TUN run.
- Evidence: acceptance auditor marked the branch blocked until real secret copy and runtime evidence exist; no `secrets/` files were copied or committed.
- Why unresolved: unsafe to embed/copy secrets or claim live VLESS behavior without operator action and redacted evidence.
- Needed next: run `scripts/vpnkit-copy-vps-secrets.sh vibe-practicum`, `scripts/vpnkit-render-local-configs.sh`, `docker compose build`, `docker compose up -d vpnkit`, `docker compose --profile test up ovpn-client-test`, then `scripts/vpnkit-collect-evidence.sh` and save redacted logs/counters/output under the task package.

## Side findings
- Blocking findings folded into active work: U-01 only.
- Non-blocking follow-ups: none opened; this task already tracks the live-validation gap through issue #11/PR #12.

## Verdict
- Status: partial / blocked on live-secret validation.
- Goal state: repo preparation/scaffolding achieved; final runtime acceptance not achieved yet.
- Final readiness: ready for operator real-data validation, not ready to mark issue #11 fully fixed.
- Summary: Agents were started; one slice owner implemented and committed the safe containerized vpnkit lab work, an acceptance auditor reviewed it, root verification passed, and a draft PR is open at https://github.com/blockedby/vibe-practicum-vpn/pull/12.

## Next-agent brief
- Objective: complete live validation without committing secrets.
- Target: `secrets/vps/...`, rendered configs, Docker lab runtime, `logs/`, and `docs/plans/2026-05-31-containerized-vpnkit/verification/`.
- Settled already: scaffold, render flow, routing rules, safety constraints, and acceptance checklist.
- Boundaries: no xray, no permanent broad OpenVPN NAT bypass, no VPS mutation beyond explicit copy commands, no secrets in git or reports.
- Verification target: redacted evidence for AC1-AC11, especially TPROXY counters, sing-box inbound/outbound logs, DNS replies, HTTPS, and literal-IP TCP path.
