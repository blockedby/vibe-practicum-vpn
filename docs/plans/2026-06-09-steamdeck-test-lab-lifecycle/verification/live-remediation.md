# Live remediation verification

Date: 2026-06-09
Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`
Branch: `feat/issue-24-smart-routing-manifest`

## Checks run

- `bash -n scripts/*.sh test/*.sh`
  - Result: PASS
- Placeholder prerequisite negative check:
  - Command (safe placeholders only): `env -u VPNKIT_TEST_ENDPOINT -u VPNKIT_TEST_SSH_TARGET VPNKIT_STEAMDECK_SSH_HOST=your-steamdeck-ssh-alias VPNKIT_STEAMDECK_LAN_ENDPOINT=192.0.2.10 VPNKIT_CONTAINERS_TEST_LOG=/tmp/vpnkit-placeholder-cycle.log VPNKIT_TEST_REMOTE_CMD_TIMEOUT=3 VPNKIT_TEST_DEPLOY_TIMEOUT=5 bash test/containers-test.sh --scenario steamdeck-host --action cycle`
  - Result: PASS for expected failure behavior; process exited `rc=1` immediately.
  - Evidence excerpt: `ssh_target_source=VPNKIT_STEAMDECK_SSH_HOST ssh_target_state=placeholder`, `endpoint_state=placeholder endpoint_source=VPNKIT_STEAMDECK_LAN_ENDPOINT`, `FAIL lifecycle:prereq-ssh` before isolated cleanup, `FAIL lifecycle:prereq-endpoint`, totals `PASS=0 FAIL=3 SKIP=0`.
- `python3 -m py_compile scripts/*.py test/*.py`
  - Result: PASS
- `python3 test/sing-box-smart-routing-proof.py`
  - Result: PASS (`PASS sing-box smart routing proof: adblock/dev-direct/RU/default decisions and template invariants`)

## Private/live state

- `config/private-endpoints.local.env`: absent in this worktree.
- Sanitized availability check: SSH fallback state was `non-placeholder` because default `deck` remains a valid final fallback, endpoint state was `missing`.
- Live bounded Deck cycle: NOT RUN because no real non-placeholder private Deck endpoint was available. No prod/default `vpnkit` mutation attempted.

## Acceptance mapping

- Placeholder SSH/endpoint values rejected for explicit `steamdeck-host`: PASS.
- SSH target precedence documents and implements `VPNKIT_TEST_SSH_TARGET` -> `VPNKIT_STEAMDECK_SSH_TARGET` -> `VPNKIT_STEAMDECK_SSH_HOST` -> `deck`: PASS by code inspection and docs update.
- Endpoint precedence requires non-placeholder `VPNKIT_TEST_ENDPOINT` or `VPNKIT_STEAMDECK_LAN_ENDPOINT`: PASS by negative check.
- Bounded timeout knobs added for SSH probes, remote harness exec, deploy, client smoke, Steam Deck build/run/logs/verify helper operations: PASS by code inspection and syntax checks.
- Live acceptance: U-01 blocked on absent real private Deck env.
