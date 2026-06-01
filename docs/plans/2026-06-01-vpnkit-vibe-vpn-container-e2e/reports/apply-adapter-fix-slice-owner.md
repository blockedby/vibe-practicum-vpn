## Task
- Mission: diagnose and fix the vpnkit `vibe-vpn apply best` post-switch failure.
- Target: container request-file sing-box apply path and `--switching` e2e.
- Boundaries: no VPS mutation, no secrets in tracked files, preserve VPS/systemd defaults, no broad `10.89.0.0/24` MASQUERADE, no unrelated refactor.
- Done when: real `scripts/vpnkit-vibe-vpn-e2e.sh --switching` passes after apply/restart.

## Context
- Slice stayed whole; no sub-slices. Nested implementer delegation was unavailable in this execution context, so the slice owner implemented the small fix directly.
- Task package: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/containerized-vpnkit-openvpn-singbox`
- Branch: `pi/containerized-vpnkit-openvpn-singbox`

## Spec compliance
- Diagnose with evidence: done. Initial render already pre-resolved `selected-native-out.server`, but `apply` wrote raw domain-form servers through `vless.SingBoxOutbound` into the active config; prior evidence showed this looped through selected-outbound DNS after restart.
- Small robust fix: done. `internal/singbox.ApplyWithRestart` now pre-resolves domain-form selected outbound `server` only for `request-file` restart mode, preserving TLS/SNI and leaving systemd mode unchanged.
- Switching e2e: done. Real `--switching` run passed baseline and post-switch OpenVPN DNS/HTTPS/literal-IP.

## Changed files
- `internal/singbox/singbox.go`: added request-file-mode selected outbound server pre-resolution before candidate validation/write/restart request.
- `internal/singbox/singbox_test.go`: added tests proving request-file mode pre-resolves and preserves TLS `server_name`, while systemd mode does not pre-resolve.
- `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/progress/slice-owner.md`: slice execution notes.
- `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/apply-adapter-fix.md`: redacted verification evidence.
- `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/reports/apply-adapter-fix-slice-owner.md`: this report.

## Acceptance verification
- AC1 diagnose concrete failure
  - Result: passed.
  - Evidence: code path comparison and prior verification; see `verification/apply-adapter-fix.md`.
- AC2 constrained fix preserving defaults/secrets/NAT/DNS intent
  - Result: passed.
  - Evidence: new tests and code scope; systemd mode unchanged and request-file mode resolves only proxy dial host.
- AC3 real switching e2e
  - Result: passed.
  - Evidence: `scripts/vpnkit-vibe-vpn-e2e.sh --run-id apply-adapter-fix-20260601T032716Z --switching --cleanup-on-failure --no-cleanup-images` succeeded; post-switch DNS/HTTPS/literal-IP passed; logs show `outbound/vless[selected-native-out]` for DoT/domain/literal-IP traffic and no lookup-loop evidence.
- AC4 exact blocker if e2e remains blocked
  - Result: not applicable; no current blocker remains.
- AC5 commit coherent changes
  - Result: passed; committed in this branch as `Fix vpnkit apply hostname bootstrap`. No secrets/noisy raw logs are in tracked files.

## System readiness
- Runtime / deployment wiring: ready for container request-file mode; VPS/systemd default behavior preserved.
- Config / env / secrets: ready; no tracked secrets added.
- Routes / networking: ready for this slice; no broad MASQUERADE added.
- Services / APIs, database, frontend: not relevant.

## Verification run
- Targeted:
  - `go test ./internal/singbox`: passed.
- Full/local:
  - `go test ./...`: passed.
  - `go vet ./...`: passed.
  - `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: passed.
  - `bash -n scripts/vpnkit-vibe-vpn-e2e.sh docker/vpnkit/entrypoint.sh scripts/vpnkit-render-local-configs.sh`: passed.
  - `docker compose config >/tmp/vpnkit-compose-config.txt`: passed.
  - `git diff --check`: passed.
  - Real e2e `--switching`: passed.
- Commit: `Fix vpnkit apply hostname bootstrap`.
- Remote checks / CI: not checked locally before push/PR update.

## Issues
### Issue R-01: request-file apply wrote proxy hostnames that could bootstrap-loop
- Evidence: prior failed e2e and code path; initial render pre-resolved but apply path did not.
- Resolution: pre-resolve selected outbound `server` in request-file mode before validating/writing active config and requesting supervisor restart.

### Issue R-02: post-switch OpenVPN DNS/HTTPS failure
- Evidence: prior post-switch DNS timeout; fresh fix run passed DNS, HTTPS domain, and literal-IP after apply/restart.
- Resolution: fixed by R-01.

## Side findings
- Non-blocking: sing-box 1.13.11 still warns about legacy DNS server syntax and missing `route.default_domain_resolver`/`domain_resolver`; this was pre-existing and not needed for the current acceptance after request-file pre-resolution. No follow-up issue created in this slice.

## Verdict
- Status: success.
- Goal state: fully achieved for the follow-up slice.
- Final readiness: ready for root integration after push/PR update as needed.

## Next-agent brief
- Objective: integrate/finish branch/PR.
- Settled: post-switch failure is resolved by request-file apply pre-resolution; real switching e2e passed.
- Verification target: preserve the passing checks above during target-branch preparation.
