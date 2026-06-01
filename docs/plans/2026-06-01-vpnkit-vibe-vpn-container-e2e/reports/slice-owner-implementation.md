## Task
- Mission: Implement the planned vibe-vpn-in-vpnkit container e2e.
- Target: Docker vpnkit image/compose, config rendering, e2e runner, runbook, and task package evidence.
- Boundaries: No VPS mutation; no committed secrets; no broad MASQUERADE bypass; no container apply/failover switching without a safe non-systemd adapter.
- Done when: Branch contains observe-mode container e2e support, fresh local validation is recorded, and changes are committed/pushed.
- Expected evidence: Build/test/config checks, e2e missing-secret behavior, image binary inspection, acceptance matrix, commit/push/PR status.

## Context
- Thread: Implement the planned vibe-vpn-in-vpnkit container e2e.
- Slice: single implementation slice; no sub-slices. Direct implementation was required because nested implementer delegation was blocked by subagent depth.
- Task name: vpnkit vibe-vpn container e2e implementation
- Task package: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e`
- Report path: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/reports/slice-owner-implementation.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/containerized-vpnkit-openvpn-singbox`
- Branch: `pi/containerized-vpnkit-openvpn-singbox`
- PR: https://github.com/blockedby/vibe-practicum-vpn/pull/12 (open)

## Changed files
- `.dockerignore` — excludes `.git`, worktrees, secrets, logs, clients, and runtime dumps from Docker build context.
- `docker/vpnkit/Dockerfile` — multi-stage Go build; runtime image contains OpenVPN, sing-box, and `/usr/local/bin/vibe-vpn` from the branch.
- `docker-compose.yml` — repo-root build context; removed fixed `container_name`; configurable manual host OpenVPN port; mounted rendered vibe-vpn config/secrets and state/log paths.
- `config/vibe-vpn/container-lab.yaml.template` — sanitized observe-mode container config.
- `scripts/vpnkit-render-local-configs.sh` — renders vibe-vpn config, copies gitignored subscription input if present, emits clear missing-subscription instructions.
- `scripts/vpnkit-vibe-vpn-e2e.sh` — tracked parallel-safe e2e runner with required flags, logs, cleanup policy, and generated no-host-port override.
- `scripts/vpnkit-collect-evidence.sh` — extends redaction and collects vibe-vpn binary/doctor evidence.
- `docs/VPNKIT_VIBE_VPN_RUNBOOK.md` — setup/run/evidence/cleanup/limitation runbook.
- Task package files: `README.md`, updated `plan.md`, `verification/local-implementation.md`, this report.

## Spec compliance
- Image contains OpenVPN, sing-box, and branch-built vibe-vpn: done.
  - Evidence: `docker compose build vpnkit` passed; `docker compose run --rm --no-deps --entrypoint /bin/sh vpnkit -c 'command -v openvpn && command -v sing-box && command -v vibe-vpn && vibe-vpn --help | head -5'` showed `/usr/sbin/openvpn`, `/usr/local/bin/sing-box`, `/usr/local/bin/vibe-vpn`.
- Sanitized templates/scripts and gitignored rendered secrets: done.
  - Evidence: tracked template has no secret values; renderer writes under `secrets/vps/rendered/vibe-vpn/`; `.gitignore` already ignores `secrets/`; `.dockerignore` excludes `secrets` and `logs`.
- Parallel-safe e2e runner with required flags/logs/cleanup: done.
  - Evidence: `scripts/vpnkit-vibe-vpn-e2e.sh` supports `--run-id`, `--log-file`, `--keep-artifacts`, `--no-build`, `--cleanup-images`, `--no-cleanup-images`; default logs under `logs/vpnkit-vibe-vpn-e2e/<run-id>.log`; uses unique Compose project and generated override.
- No fixed e2e container-name or host-port collisions: done.
  - Evidence: fixed `container_name` removed from base compose; e2e override uses `ports: !reset []`; rendered override config check showed no `ports:` for `vpnkit`.
- Cleanup behavior: done in script logic; partially runtime-verified.
  - Evidence: missing-subscription e2e failure kept artifacts by default and printed cleanup command; success path calls `down --remove-orphans --volumes --rmi local` by default.
- REDIRECT path and Google DoT through `selected-native-out` preserved: done.
  - Evidence: `config/sing-box/config.json.template` and `docker/vpnkit/setup-routing.sh` were not changed; static grep over `docker config scripts` found no broad `10.89.0.0/24` MASQUERADE final solution.
- vibe-vpn doctor/test inside container: implemented, but full real run blocked by absent local subscription input.
  - Evidence: runner executes both commands when `secrets/vps/rendered/vibe-vpn/sub_url` exists; missing-input path fails clearly.
- OpenVPN client/DNS/HTTPS/literal-IP e2e: implemented in runner; not fully run locally due missing subscription input.
  - Evidence: existing `ovpn-client-test` still performs `10.89.0.x`, DNS, HTTPS, and literal-IP checks; runner invokes it after vibe-vpn checks.
- Go tests/build and shell/config checks: done.
  - Evidence: see Verification run.
- Commit/push: local commit created; push status below.

## Acceptance verification
- AC: Image contains OpenVPN, sing-box, and `/usr/local/bin/vibe-vpn` built from branch.
  - Covered by: Docker build and image command inspection.
  - Result: passed.
  - Evidence: `docker compose build vpnkit`; `command -v openvpn/sing-box/vibe-vpn` inside image.
- AC: No tracked real secrets; rendered configs/secrets stay gitignored.
  - Covered by: path review and static grep of changed tracked paths.
  - Result: passed, with one expected redaction-pattern match in `scripts/vpnkit-collect-evidence.sh`.
  - Evidence: changed-path grep only matched the redaction regex `vless://[^[:space:]]+`; no real URLs/keys.
- AC: E2E runner exists and supports required flags/logs/cleanup.
  - Covered by: script syntax check and missing-secret execution.
  - Result: passed.
  - Evidence: `bash -n ...`; `scripts/vpnkit-vibe-vpn-e2e.sh --run-id missing-sub-test --no-build --no-cleanup-images` wrote `logs/vpnkit-vibe-vpn-e2e/missing-sub-test.log` and printed cleanup instructions.
- AC: Parallel-safe compose behavior.
  - Covered by: compose file review and override render check.
  - Result: passed.
  - Evidence: no `container_name`; generated e2e override uses `ports: !reset []`.
- AC: REDIRECT/DNS selected-native-out path preserved; no broad MASQUERADE.
  - Covered by: unchanged routing/sing-box template and static grep.
  - Result: passed.
  - Evidence: `git grep -nE 'MASQUERADE.*10\.89\.0\.0/24|10\.89\.0\.0/24.*MASQUERADE' -- docker config scripts` returned no matches.
- AC: vibe-vpn doctor/test against real inputs or clear failure if missing.
  - Covered by: missing-input e2e run.
  - Result: passed for absence path; real-input path not run.
  - Evidence: script failed with `missing required vibe-vpn subscription input: secrets/vps/rendered/vibe-vpn/sub_url` and documented source paths.
- AC: OpenVPN client receives `10.89.0.x`, DNS/HTTPS/literal-IP succeed, logs show selected-native-out.
  - Covered by: runner wiring and existing client test; full runtime evidence not available.
  - Result: not run, blocked by absent local subscription input.
  - Evidence: runner invokes `ovpn-client-test`; no real full e2e log was produced.

## System readiness
- Routes / registration: done for observe-mode runner; base REDIRECT routing unchanged.
- Services / APIs: done; no new API.
- Config / env / secrets: ready except local real subscription input absent in this environment.
- Permissions / access: Docker privileged/tun behavior unchanged; no VPS access used.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: ready for observe-mode e2e; apply/failover switching intentionally deferred.

## Verification run
- Local / targeted checks:
  - `bash -n scripts/vpnkit-vibe-vpn-e2e.sh scripts/vpnkit-render-local-configs.sh scripts/vpnkit-collect-evidence.sh`: passed.
  - `scripts/vpnkit-render-local-configs.sh`: passed with warning for absent subscription input.
  - `docker compose config >/tmp/vpnkit-compose-config.txt`: passed.
  - `docker compose build vpnkit`: passed.
  - Image command inspection for OpenVPN/sing-box/vibe-vpn: passed.
  - E2E missing-subscription run: failed as expected with clear instructions.
- Local / full checks:
  - `go test ./...`: passed.
  - `go vet ./...`: passed.
  - `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: passed.
- Remote checks / CI:
  - PR status: open PR #12. CI status not checked after final push yet in this report.

## Issues
### Issue R-01: Container image previously could not include branch-built vibe-vpn
- Description: Existing vpnkit Dockerfile used `docker/vpnkit` as build context and only installed OpenVPN/sing-box.
- Evidence: prior `docker/vpnkit/Dockerfile` had no Go build or binary copy.
- Resolution: switched compose build context to repo root and added multi-stage Go build copying `/usr/local/bin/vibe-vpn`.
- Depends on: none.

### Issue R-02: E2E compose path had fixed names/host port
- Description: Base compose used fixed `container_name` values and fixed `1194:1194/udp`.
- Evidence: prior `docker-compose.yml`.
- Resolution: removed fixed container names; made manual port configurable; e2e runner applies generated `ports: !reset []` override and unique project name.
- Depends on: none.

### Issue R-03: Missing subscription input needed a clear, safe failure path
- Description: Real local vibe-vpn subscription input was absent.
- Evidence: renderer warning and e2e run reported missing `secrets/vps/rendered/vibe-vpn/sub_url`.
- Resolution: renderer writes a missing-subscription README; e2e fails before compose with exact gitignored source paths and no secret disclosure.
- Depends on: operator-provided local secret for full run.

### Issue U-01: Full real container e2e not run locally
- Description: The full OpenVPN client/DNS/HTTPS/literal-IP plus vibe-vpn doctor/test run requires real gitignored subscription input.
- Evidence: `scripts/vpnkit-render-local-configs.sh` warned missing subscription; `scripts/vpnkit-vibe-vpn-e2e.sh --run-id missing-sub-test --no-build --no-cleanup-images` failed clearly before Docker lifecycle.
- Why unresolved: Required local secret is intentionally outside git and absent in this worktree; fabricating it would not prove acceptance.
- Needed next: Add a real subscription to one documented gitignored path, rerun render, then run `scripts/vpnkit-vibe-vpn-e2e.sh --run-id <id>` and attach redacted log/evidence.
- Depends on: operator secret availability.

### Issue U-02: Container-safe apply/failover switching remains deferred
- Description: Current production apply path uses systemd service restart (`internal/singbox`), which is unsafe/conflicting inside the container supervisor model.
- Evidence: plan/repo orientation; this implementation keeps `service.enabled: false` in container template and only runs `doctor`/`test`.
- Why unresolved: Implementing a safe adapter is explicitly out of this observe-mode slice unless bounded; no such adapter existed.
- Needed next: Add a container runtime adapter that updates selected sing-box config and asks the single container supervisor to reload/restart sing-box without `systemctl` or duplicate process ownership.
- Depends on: design/implementation follow-up.

## Side findings
- Blocking findings folded into active work: R-01, R-02, R-03.
- Non-blocking findings tracked separately: none created; U-02 is an explicit current-goal limitation/deferred capability from the original boundaries.

## Commits / push / PR
- Commit: `a56b0a2 Add vpnkit vibe-vpn container e2e`.
- Push: pending at time this report section was first written; update after final push.
- PR: https://github.com/blockedby/vibe-practicum-vpn/pull/12.

## Verdict
- Status: partial success.
- Goal state: observe-mode implementation achieved; full real e2e acceptance awaits local subscription input; switching/failover adapter remains deferred by design.
- Final readiness: ready for operator-run observe-mode e2e with real gitignored inputs; not yet fully accepted as real end-to-end proven.
- Summary: The branch now contains the container image wiring, sanitized config rendering, parallel-safe runner, cleanup policy, runbook, and local validation needed to run the planned e2e once a real subscription secret is present.

## Next-agent brief
- Objective: Complete full real e2e evidence once local subscription input is available.
- Target: `scripts/vpnkit-render-local-configs.sh`, `scripts/vpnkit-vibe-vpn-e2e.sh`, logs under `logs/vpnkit-vibe-vpn-e2e/`.
- Settled already: observe-mode design; no systemd/container apply; REDIRECT path preserved; runner and config workflow implemented.
- Boundaries: Do not commit or paste secrets; do not mutate VPS; do not add broad MASQUERADE.
- Verification target: Full runner passes and evidence shows vibe-vpn doctor/test, client `10.89.0.x`, DNS, HTTPS, literal-IP, and selected-native-out logs.
- Expected output: Redacted evidence update in the task package and PR/CI status.
