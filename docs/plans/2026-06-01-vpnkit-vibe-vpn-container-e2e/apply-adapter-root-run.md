# Apply adapter root run report

## Task
- Mission: Plan and try a container-safe `vibe-vpn` apply/failover switching adapter inside the vpnkit container.
- Target: `pi/containerized-vpnkit-openvpn-singbox` worktree/branch, vpnkit OpenVPN + sing-box + `vibe-vpn` container lab.
- Boundaries: no VPS mutation, no committed/printed secrets, preserve VPS systemd behavior, no duplicate sing-box process ownership, no broad `10.89.0.0/24` MASQUERADE.
- Done when: the container can switch the selected sing-box outbound through `vibe-vpn` and the OpenVPN client still passes DNS/HTTPS/literal-IP after switch.

## Context
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/containerized-vpnkit-openvpn-singbox`
- Branch: `pi/containerized-vpnkit-openvpn-singbox`
- PR: https://github.com/blockedby/vibe-practicum-vpn/pull/12
- Root note: repo-root `AGENTS.md` and child `AGENTS.md` were requested but are absent in this repo/worktree; `README.md` was read.
- Slice used: one slice owner, because the work had one primary ownership boundary: container-safe sing-box apply/restart plus e2e switching proof.

## Plan and artifacts
- Plan written first: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/apply-adapter-plan.md`
- Slice report: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/reports/apply-adapter-slice-owner.md`
- Verification: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/apply-adapter.md`
- Acceptance audit: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/reports/apply-adapter-acceptance-audit.md`

## Changed files
- `internal/config/config.go`
- `internal/singbox/singbox.go`
- `internal/singbox/singbox_test.go`
- `cmd/vibe-vpn/main.go`
- `docker/vpnkit/entrypoint.sh`
- `docker-compose.yml`
- `config/vibe-vpn/container-lab.yaml.template`
- `scripts/vpnkit-vibe-vpn-e2e.sh`
- Task package plan/report/verification files.

## Commit / push
- Implementation commit pushed: `f611019 Add vpnkit sing-box apply adapter`
- Branch status at integration: `pi/containerized-vpnkit-openvpn-singbox...origin/pi/containerized-vpnkit-openvpn-singbox`

## Spec compliance
- Plan before implementation: done (`apply-adapter-plan.md`).
- Preserve VPS systemd behavior: done in implementation; restart adapter defaults to systemd and targeted tests pass.
- Container-safe adapter: partially done; request-file adapter exists, and supervisor owns the long-lived sing-box process.
- Validate before replacement/restart: done per slice evidence; post-apply `sing-box check` passed in real e2e.
- REDIRECT/OpenVPN path: passed before switching; not accepted after switching.
- E2E switching: attempted with real gitignored local inputs; failed after switch.
- Logs/cleanup/parallel-safe runner: preserved; e2e runner used per-run logs and cleanup controls.
- No secrets/no VPS mutation: passed by reports/audit; real secrets were not printed or committed.

## Acceptance verification
- AC1: Container-safe switching works after apply/failover.
  - Covered by: `scripts/vpnkit-vibe-vpn-e2e.sh --switching` real run.
  - Result: failed.
  - Evidence: `verification/apply-adapter.md` records `apply best` succeeded, state/config updated, supervisor restart requested, but post-switch OpenVPN client DNS timed out; preserved logs indicated sing-box selected-outbound hostname DNS lookup loop/timeouts.
- AC2: Production VPS path remains systemd-coupled by default.
  - Covered by: config/singbox unit tests and slice report.
  - Result: passed.
  - Evidence: fresh root `go test -count=1 ./internal/config ./internal/singbox ./cmd/vibe-vpn` passed.
- AC3: No duplicate sing-box ownership in container.
  - Covered by: entrypoint design and real e2e evidence.
  - Result: passed for adapter mechanics.
  - Evidence: slice report says entrypoint remains sole long-lived sing-box owner; `vibe-vpn` writes request file rather than starting sing-box.
- AC4: OpenVPN + sing-box REDIRECT, DNS via Google DoT through selected-native-out, no broad MASQUERADE.
  - Covered by: baseline e2e and static checks.
  - Result: partial.
  - Evidence: pre-switch DNS/HTTPS/literal-IP passed; post-switch DNS failed.
- AC5: Real e2e integrated with logs, parallel-safe project/run-id, and cleanup.
  - Covered by: e2e runner and real run.
  - Result: partial.
  - Evidence: runner supports `--switching`; failure path captured blocker evidence. Passing switched path not yet achieved.
- AC6: Commit and push useful result.
  - Covered by: git status/log.
  - Result: passed.
  - Evidence: `f611019` pushed to origin; PR #12 open.

## Verification run
- Slice verification passed:
  - `go test ./...`
  - `go vet ./...`
  - `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`
  - shell syntax checks
  - `docker compose config`
  - real e2e baseline before switching
  - real `apply best` updated state/config and requested supervisor restart
- Root targeted verification passed:
  - `go test -count=1 ./internal/config ./internal/singbox ./cmd/vibe-vpn`
  - `bash -n scripts/vpnkit-vibe-vpn-e2e.sh docker/vpnkit/entrypoint.sh scripts/vpnkit-render-local-configs.sh`
  - `git diff --check`
- Acceptance audit verdict: not accepted until post-switch OpenVPN DNS/HTTPS/literal-IP passes.

## Issues
### U-01: Post-switch OpenVPN DNS/HTTPS path fails
- Description: Real `apply best` switched config/state and requested a supervisor restart, but the OpenVPN client failed DNS after the switch.
- Evidence: `verification/apply-adapter.md` records post-switch DNS timeout and sing-box DNS lookup loop/timeouts for the selected outbound server hostname.
- Why unresolved: the applied real winning node uses a domain-form upstream; resolving that hostname appears to loop through the outbound whose hostname is being resolved.
- Needed next: adjust and verify safe proxy-server hostname resolution after apply without bypassing the required client DNS-over-selected-out behavior, then rerun switching e2e through post-switch DNS/HTTPS/literal-IP.

## Verdict
- Status: partial.
- Goal state: not fully achieved.
- Final readiness: not accepted for working switching.
- Summary: A useful container-safe apply adapter was implemented and pushed, and real e2e proved the apply/restart mechanics, but the root request remains blocked because post-switch client traffic fails DNS/HTTPS after applying the available real node.

## Next-agent brief
- Objective: make switched container data path pass after `vibe-vpn apply`/failover.
- Target: sing-box DNS/resolver behavior for selected outbound server hostnames after apply; likely `internal/singbox` config rendering and/or container lab DNS resolver settings.
- Settled already: request-file adapter, supervisor-owned sing-box restart, VPS systemd default, no broad MASQUERADE, baseline REDIRECT path.
- Boundaries: no VPS mutation; no secrets in tracked artifacts; preserve Google DoT for client DNS through `selected-native-out` unless an explicit safe exception is needed only for proxy-server bootstrap resolution.
- Verification target: fresh `--switching` e2e where post-switch OpenVPN client receives `10.89.0.x` and DNS/HTTPS/literal-IP pass, with logs showing no selected outbound hostname resolution loop.
