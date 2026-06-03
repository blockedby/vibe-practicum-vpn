# Progress: aad-implementer TUN canary runtime

- 2026-06-03: Started Task 5 in worktree `vpnkit-tproxy-udp-nested`; read AGENTS.md, plan.md, relevant source/tests, aad task/report/devops skills. `git status --short` was clean before edits.
- 2026-06-03: Implementation plan: add tun template + mode selection/rendering/readiness, keep redirect/tproxy behavior unchanged, add RED tests for tun template/setup-routing dry-run behavior, then run owner-provided checks.
- 2026-06-03: RED evidence captured: `bash tests/vpnkit-singbox-template-test.sh` failed with missing `config/sing-box/config.tun.json.template` before production changes; setup-routing dry-run mode test already passed because a minimal tun branch existed.
- 2026-06-03: GREEN implementation added `config.tun.json.template`, entrypoint tun config/readiness selection, render-script tun output, setup-routing tun timeout, docs note, and targeted tests. Targeted template/routing tests now pass; dummy `sing-box check` passes for redirect/tproxy/tun with required deprecation env flags (warnings only).
- 2026-06-03: Required Task 5 checks passed: template test, setup-routing test, shell syntax, `go test ./...`, dummy rendered `sing-box check` with deprecation env flags, and `git diff --check`.
- 2026-06-03: Safe prerequisites for optional validation checked without printing values: Docker available and existing gitignored rendered config/profile inputs available. Proceeded only to isolated local Docker lab first with unique project/port; no production/live mutation.
- 2026-06-03: Wrote runtime and local-validation reports/verification. Created local commit `9e63d45 Add vpnkit tun routing canary`; updated reports with commit SHA.
