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
  - Note: test/plan/report files contain intentional negative assertions/wording for removed source-mode/archive/scp behavior.
- Public-safety grep over changed tracked files:
  - Command: `git diff -- scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh README.md docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling | grep '^+' | grep -Ev '^\+\+\+|assert_|grep|public-safety|secret-like|token=mock-secret-output' | grep -E '([0-9]{1,3}\.){3}[0-9]{1,3}|(password|passwd|token|secret|private[_-]?key)[=:][^<[:space:]]|BEGIN (RSA|OPENSSH|PRIVATE)' || true`
  - Result: PASS; no suspicious added secret/private endpoint material outside intentional mock/negative-test assertions.

## Follow-up blocker evidence map

- Default deploy_id uses resolved target ref: covered by `plan --target-ref HEAD` expecting current short SHA and `plan --target-ref HEAD~1` expecting the prior commit short SHA when available. Override remains covered by `--deploy-id custom-id`.
- Deploy_id path safety: covered by `plan --target-ref main --deploy-id nested/id` failing with `deploy id contains unsupported characters`; target refs retain separate ref validation and rollback paths remain separate via `--rollback-id` tests.
- Actual image-tag activation: mocked deploy now proves `docker tag=sha256:candidatebuild vpnkit:<deploy-id>` and Compose activation uses a generated image override with `up -d --no-build`.
- Rollback no-build by image tag: mocked rollback proves a generated rollback image override and `up -d --no-build`, with no `compose_build` during rollback.
- Auto-rollback on TUN config/mode failure: forced `require_tun_pair` failure now returns nonzero explicitly and mocked deploy proves `deploy_activation_or_config=failed`, `rollback_start=...`, and `rollback_activation=no_build`.

## Existing acceptance evidence map

- Git-only CLI/deploy-id: covered by plan output tests for default and `--deploy-id`, and source-mode refusal.
- Non-mutating plan/dry-run: covered by `mutation=none` plan/dry-run assertions.
- Release/image deploy flow: covered by mocked deploy assertions for release dir, resolved git ref, `vpnkit:<deploy-id>`, build/tag, no-build activation, tun config check, and two-host sequencing.
- Rollback no-build flow: covered by mocked rollback assertions for previous image/config/mode metadata, `rollback_activation=no_build`, and absence of build during rollback.
- Tun-required smoke: covered by verify PASS with tun outputs and verify FAIL when mocked mode is `redirect`.
- Manual recovery command: covered by forced rollback-smoke failure assertion.
- No live mutation: commands used only local static checks and mocked ssh/timeout/docker/git paths.
