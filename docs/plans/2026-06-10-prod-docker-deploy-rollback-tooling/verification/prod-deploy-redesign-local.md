# Production deploy redesign local verification

Date: 2026-06-13
Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`
Branch: `feat/issue-24-smart-routing-manifest`

No live production SSH/deploy/rollback/verify was performed. All runtime evidence is local/static or mocked remote execution.

## Commands

- `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh`
  - Result: PASS
- `test/prod-deploy-helper-test.sh`
  - Result: PASS (no output)
- `git diff --check`
  - Result: PASS
- `! grep -RInE 'source_update=archive|source-before\.tar|git archive|scp ' scripts/vpnkit/vpnkit-prod-deploy.sh README.md`
  - Result: PASS; no forbidden helper/docs source-transfer strings found.
  - Note: test/plan contain intentional negative assertions/wording for removed source-mode/archive/scp behavior.
- Public-safety grep over changed tracked files:
  - Command: `git diff --name-only | xargs grep -InE 'BEGIN (RSA|OPENSSH|PRIVATE)|PRIVATE KEY|password=[^<[:space:]]+|token=[^<[:space:]]+|secret=[^<[:space:]]+|vless://|trojan://|vmess://' || true`
  - Result: PASS with expected mock/negative-test matches only:
    - `test/prod-deploy-helper-test.sh` asserts token redaction and negative secret patterns using `mock-secret-output`.
    - No real private key/token/password/subscription/profile content was found.

## Acceptance evidence map

- Git-only CLI/deploy-id: covered by plan output tests for default and `--deploy-id`, and source-mode refusal.
- Non-mutating plan/dry-run: covered by `mutation=none` plan/dry-run assertions.
- Release/image deploy flow: covered by mocked deploy assertions for release dir, resolved git ref, `vpnkit:<deploy-id>`, build/tag, no-build activation, tun config check, and two-host sequencing.
- Rollback no-build flow: covered by mocked rollback assertions for previous image/config/mode metadata, `rollback_activation=no_build`, and absence of build during rollback.
- Tun-required smoke: covered by verify PASS with tun outputs and verify FAIL when mocked mode is `redirect`.
- Manual recovery command: covered by forced rollback-smoke failure assertion.
- No live mutation: commands used only local static checks and mocked ssh/timeout/docker/git paths.
