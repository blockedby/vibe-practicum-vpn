# Apply adapter slice plan

## Goal
Implement container-safe sing-box apply/restart behavior for `vibe-vpn` in the vpnkit container while preserving production VPS defaults.

## Scope / boundaries
- In scope: `internal/config`, `internal/singbox`, CLI apply/pick/failover paths that call sing-box apply, vpnkit entrypoint/supervision, container-lab config template, render/e2e scripts, tests/docs/evidence.
- Out of scope: VPS mutation, secret fetching, broad `10.89.0.0/24` MASQUERADE, replacing OpenVPN + sing-box REDIRECT path, duplicate long-lived sing-box ownership.
- Done: production default remains systemd restart; container config can choose a non-systemd adapter; apply/pick/failover update config only after validation and request supervisor-owned restart/reload; e2e runner can exercise real switch when local gitignored inputs exist.

## Repo orientation / reuse discovery
- `internal/singbox/singbox.go` currently mutates `sing_box_config`, backs it up under `<state_dir>/backups`, then calls `systemctl restart`; rollback mirrors this.
- `internal/config/config.go` requires `sing_box_service` for singbox runtime, so add adapter config without weakening VPS validation.
- `docker/vpnkit/entrypoint.sh` is current process owner for `sing-box run` and OpenVPN; adapt it to own restarts via signal/control request.
- `config/vibe-vpn/container-lab.yaml.template` currently sets `/etc/sing-box/config.json` and a dummy service value; it should select the container adapter and writable active config if needed.
- `scripts/vpnkit-vibe-vpn-e2e.sh` already has parallel-safe run-id/project/log/cleanup behavior and should gain an optional switching path.
- Existing tests: `internal/singbox/singbox_test.go`, `internal/config/config_test.go`, CLI/service tests, plus shell syntax and docker compose checks.

## Chosen adapter design
Use a minimal configurable restart adapter in Go plus a supervisor control-file request in the container:
- Add config fields such as `sing_box_restart_mode` (`systemd` default, `command`, `touch-file`/`signal-file` acceptable) and `sing_box_restart_command` or request file path.
- Keep default empty/systemd behavior exactly equivalent to today for VPS.
- For container lab, `vibe-vpn` writes a validated candidate config to a writable active path (for example `/var/lib/vpnkit/sing-box/config.json`) and creates/touches a restart request file (for example `/run/vpnkit/restart-sing-box`).
- Entrypoint remains the only long-lived sing-box owner: it starts sing-box from the writable config, watches for restart requests, validates config, stops/starts sing-box, and removes/acks the request. `vibe-vpn` never starts long-lived sing-box.
- `internal/singbox.Apply` should validate with `sing-box check -c <candidate>` before replacing the active config and before requesting restart; on validation or restart-request failure, leave the prior active config/process usable. For a request-file adapter, restart completion is asynchronous, so Go-level acceptance is successful validated write + request creation; supervisor/e2e proves process restart.

## Missing pieces
- Config model/tests for restart adapter defaults and container values.
- Sing-box apply/rollback refactor to validate-before-replace and restart via adapter abstraction.
- Entrypoint restart request loop with one sing-box owner.
- Writable active config bootstrap from mounted rendered config.
- Container config/template/render/e2e updates for switching.
- Verification artifacts and redacted report.

## Plan tasks

### Task A: Go restart adapter and safe apply semantics
Goal:
- Preserve systemd default while allowing container-safe request-file or command adapter, with validation before active config replacement.
Acceptance criteria:
- Default config validates with systemd behavior and existing VPS config/tests keep passing.
- Container config can set non-systemd adapter without requiring a real service name beyond validation needs.
- `Apply`/`Rollback` validate candidate config before replacing active config; failed validation leaves prior config unchanged and does not request restart.
- Unit tests cover systemd restart, request-file adapter, validation failure, and rollback behavior.
Test plan:
- `go test ./internal/config ./internal/singbox` plus full `go test ./...` later.
Executor: aad-implementer.
Report: `reports/aad-implementer-apply-adapter-go.md`.

### Task B: vpnkit supervisor integration and e2e switching flag
Goal:
- Make container entrypoint own sing-box restarts via request file and expose real switching in the e2e runner.
Acceptance criteria:
- Entrypoint copies mounted `/etc/sing-box/config.json` to writable active config if configured, starts sing-box from active config, handles restart request by validating and restarting same supervised process.
- Container-lab template selects the adapter and writable config paths.
- E2E runner supports a flag/path (e.g. `--switching`) that runs `current`/`apply best` or `pick`, observes restart/reload, then reruns OpenVPN client DNS/HTTPS/literal-IP checks.
- Failure keeps artifacts and prints cleanup commands; success cleanup remains intact.
Test plan:
- `bash -n` modified scripts; `docker compose config`; container command checks where feasible; real e2e if local inputs exist.
Executor: aad-implementer.
Depends on: Task A.
Report: `reports/aad-implementer-apply-adapter-container.md`.

### Task C: final verification/reporting
Goal:
- Collect fresh verification evidence, classify limitations, commit/push useful result.
Acceptance criteria:
- `verification/apply-adapter.md` records command results, e2e result or exact local-input limitation, and secret-safety grep.
- `reports/apply-adapter-slice-owner.md` summarizes changed files, commits/push status, issues, and verdict.
Executor: slice owner after implementer reports.
Depends on: A+B.

## Dependency graph
- Wave 1: Task A.
- Wave 2: Task B after A (can be combined by one implementer because contract is small and cross-file integration is tight).
- Wave 3: owner verification/report.

## Dispatch decision
Keep as one slice; delegate implementation as one clear `aad-implementer` task covering A+B to avoid adapter contract drift. No child slice needed.
