# Apply adapter follow-up root run

## Task
- Mission: diagnose and fix the vpnkit `vibe-vpn apply best` post-switch failure from the prior partial apply-adapter run.
- Target: branch `pi/containerized-vpnkit-openvpn-singbox`, worktree `.worktrees/containerized-vpnkit-openvpn-singbox`, container request-file sing-box apply path.
- Boundaries: do not mutate VPS; do not print/commit secrets; preserve production systemd behavior; keep no broad `10.89.0.0/24` MASQUERADE; preserve Google DoT/client DNS through `selected-native-out` except safe proxy bootstrap handling.
- Done when: real `scripts/vpnkit-vibe-vpn-e2e.sh --switching` passes baseline, apply, supervisor restart, post-switch OpenVPN DNS/HTTPS/literal-IP, with selected-native-out log evidence.

## Slice structure
- Used one slice owner because there was one blocker and one verification story: container request-file apply writes and switched data-path proof.
- Slice report: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/reports/apply-adapter-fix-slice-owner.md`.
- Verification artifact: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/apply-adapter-fix.md`.
- Acceptance audit: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/reports/apply-adapter-fix-acceptance-audit.md`.

## Integrated result
- Diagnosis: initial render pre-resolved `selected-native-out.server`, but `vibe-vpn apply` wrote raw domain-form selected outbound hostnames into the active sing-box config in container `request-file` mode, recreating a DNS bootstrap loop after supervisor restart.
- Fix: `internal/singbox.ApplyWithRestart` now pre-resolves the selected outbound `server` only for `request-file` mode before candidate validation/write/restart request. TLS/SNI fields are preserved. Systemd/VPS mode remains unchanged.
- Implementation commit: `20f1ce7 Fix vpnkit apply hostname bootstrap`.
- Report/audit artifacts were added after the implementation commit; branch should be pushed after final review if remote PR update is desired.

## Changed files
- `internal/singbox/singbox.go`
- `internal/singbox/singbox_test.go`
- `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/progress/slice-owner.md`
- `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/apply-adapter-fix.md`
- `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/acceptance-plan.md`
- `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/reports/apply-adapter-fix-slice-owner.md`
- `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/reports/apply-adapter-fix-acceptance-audit.md`
- `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/apply-adapter-fix-root-run.md`

## Acceptance verification
- AC1: Diagnose concrete post-switch failure.
  - Result: passed.
  - Evidence: slice report and `verification/apply-adapter-fix.md` map the failure to request-file apply writing raw domain hostnames while initial render pre-resolved them.
- AC2: Robust constrained fix preserving VPS/systemd behavior and secrets/NAT boundaries.
  - Result: passed.
  - Evidence: new `internal/singbox` tests prove request-file pre-resolution and systemd non-pre-resolution; diff is scoped to apply-path bootstrap resolution and tests.
- AC3: Real switching e2e passes.
  - Result: passed.
  - Evidence: `scripts/vpnkit-vibe-vpn-e2e.sh --run-id apply-adapter-fix-20260601T032716Z --switching --cleanup-on-failure --no-cleanup-images` passed baseline, `apply best`, supervisor restart, post-switch DNS, HTTPS domain, and literal-IP checks. Logs showed `outbound/vless[selected-native-out]` for Google DoT/domain/literal-IP traffic with no lookup-loop evidence in the excerpt.
- AC4: Preserve production systemd behavior.
  - Result: passed.
  - Evidence: systemd mode leaves domain server unchanged and does not pre-resolve; targeted root check passed.
- AC5: No VPS mutation, no committed secrets, no broad MASQUERADE.
  - Result: passed.
  - Evidence: reports contain redacted e2e evidence only; no runtime MASQUERADE additions; commands were local/container-only.

## Verification run
- Slice verification passed:
  - `go test ./internal/singbox`
  - `go test ./...`
  - `go vet ./...`
  - `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`
  - `bash -n scripts/vpnkit-vibe-vpn-e2e.sh docker/vpnkit/entrypoint.sh scripts/vpnkit-render-local-configs.sh`
  - `docker compose config >/tmp/vpnkit-compose-config.txt`
  - `git diff --check`
  - real `--switching` e2e above
- Root-owner fresh checks in the implementation worktree passed:
  - `go test -count=1 ./internal/singbox ./internal/config ./cmd/vibe-vpn`
  - `bash -n scripts/vpnkit-vibe-vpn-e2e.sh docker/vpnkit/entrypoint.sh scripts/vpnkit-render-local-configs.sh && docker compose config >/tmp/vpnkit-compose-config-root.txt && git diff --check HEAD~1..HEAD`
- Acceptance auditor verdict: accepted.
- Remote CI: not available before push/update.

## System readiness and risks
- Container runtime readiness: ready for request-file mode; supervisor restart path passed real e2e.
- VPS/runtime compatibility: ready; systemd remains the default restart mode and apply path is unchanged for production mode.
- Security/secrets: ready; reports omit real subscription URLs/full links/hostnames.
- Non-blocking note: sing-box still warns about legacy DNS server syntax and missing `route.default_domain_resolver`/`domain_resolver`; this existed before and did not block acceptance after pre-resolution.

## Issues
### R-01: Apply path recreated selected outbound hostname DNS bootstrap loop
- Resolution: pre-resolve selected outbound `server` for container `request-file` apply mode before validation/write/restart.
- Evidence: `20f1ce7`, targeted tests, and passing real `--switching` e2e.

## Verdict
- Status: success / accepted.
- Goal state: fully achieved for the follow-up root task.
- Final readiness: ready to push/update PR if desired; no current-goal blockers remain.
