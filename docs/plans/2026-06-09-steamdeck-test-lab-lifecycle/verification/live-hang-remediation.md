# Live hang remediation verification

Date: 2026-06-10
Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`
Branch: `feat/issue-24-smart-routing-manifest`

## Root cause / diagnosis

Resolved script hang risks:
- `scripts/deck/vpnkit-steamdeck-podman.sh verify_container` had an outer remote verify timeout, but several inner `podman` operations were not individually bounded, including `podman exec ... pgrep`, `podman exec ... test -r /etc/vibe-vpn/sub_url`, and `podman exec ... /usr/local/bin/vibe-vpn doctor`. If a container exec path or doctor process stalled after finite log output, the caller could appear hung until a much larger outer timeout or terminal kill.
- `test/containers-test.sh --scenario steamdeck-host --action test` could still launch the OpenVPN client smoke when the isolated server container was not running, causing a needless long wait after a failed `up`/deploy. It now skips client smoke when the explicit Steam Deck server container is unavailable.

Current live blocker:
- Fresh bounded `up` reached isolated deploy/build/run/finite logs and returned quickly; it did not hang. The isolated container exited because sing-box failed while downloading remote RU rule-set `.srs` files from `raw.githubusercontent.com` with `unexpected EOF`. This is an environment/network/outbound rule-set fetch failure during container startup, not the previous unbounded verify/doctor hang.

## Commands and results

### Static/local checks

- `bash -n scripts/deck/vpnkit-steamdeck-podman.sh test/containers-test.sh`: PASS
- `bash -n scripts/*.sh test/*.sh`: PASS
- `python3 test/sing-box-smart-routing-proof.py`: PASS (`PASS sing-box smart routing proof: adblock/dev-direct/RU/default decisions and template invariants`)
- `go test ./...`: PASS
- `go vet ./...`: PASS
- `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: PASS
- `git ls-files | grep -Ei '(\.ovpn$|\.pem$|\.key$|logs/|secrets/)' || true`: PASS/no tracked sensitive artifact paths printed

### Live bounded Steam Deck lab sequence

Private endpoint handling: local private env was sourced if present; when no usable endpoint var was present, the Deck IPv4 endpoint was discovered with `ssh deck ip -4 -o addr show scope global ...` and stored only in process-local env. The endpoint was not printed or committed. Console/log output was redacted by the harness.

Environment summary (public-safe):
- `VPNKIT_TEST_SSH_TARGET=deck`
- `VPNKIT_TEST_RUNTIME=podman`
- `VPNKIT_TEST_SERVER_CONTAINER=vpnkit-test-steamdeck-host`
- `VPNKIT_STEAMDECK_LOGS_TIMEOUT=20`
- `VPNKIT_STEAMDECK_VERIFY_TIMEOUT=45`
- isolated lab defaults for image, port, profile, remote state

Results:
- `test/containers-test.sh --scenario steamdeck-host --action down`: PASS, isolated lab container cleanup completed.
- `test/containers-test.sh --scenario steamdeck-host --action up`: FAIL but bounded/returned. Prepare and deploy/build ran; isolated container exited during startup after sing-box remote rule-set downloads failed with `unexpected EOF`; no indefinite log/doctor hang observed.
- `test/containers-test.sh --scenario steamdeck-host --action test`: FAIL bounded. SSH reachable, isolated server container exists but is not running, server checks skipped, client smoke skipped because server container unavailable.
- `test/containers-test.sh --scenario steamdeck-host --action cycle`: NOT RUN after `up` failed; running full cycle would repeat the same current startup blocker.
- Final cleanup `test/containers-test.sh --scenario steamdeck-host --action down`: PASS, isolated lab container cleanup completed.

## Acceptance mapping

- AC1 root cause diagnosed: PASS for hang risks; current remaining startup blocker classified separately.
- AC2 bounded lifecycle commands: PASS for touched verify/doctor/client-smoke paths; live `up` and `test` returned boundedly.
- AC3 live sequence: PARTIAL. `down`, `up`, and `test` were run; `cycle` withheld because `up` failed on current network/rule-set startup blocker.
- AC4 private endpoint safety: PASS; endpoint only process-local, output redacted.
- AC5 client smoke failure classification: PASS; client smoke skipped because server unavailable; server unavailable due sing-box outbound rule-set fetch `unexpected EOF`.
- AC6 repo checks / sensitive artifacts: PASS.
- AC7 PR/issue updates: PASS. Commit `b723068` pushed; public-safe issue update https://github.com/blockedby/vibe-practicum-vpn/issues/27#issuecomment-4667492219 and PR update https://github.com/blockedby/vibe-practicum-vpn/pull/26#issuecomment-4667492399 posted. PR checks reported no checks configured for the branch.

## Cleanup

Isolated lab cleanup was run after failed startup. Default/prod `vpnkit` was not targeted.
