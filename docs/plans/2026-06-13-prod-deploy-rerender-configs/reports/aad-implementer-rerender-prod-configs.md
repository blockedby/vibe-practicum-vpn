PI_RESULT: PASS
TASK: Prod deploy rerender configs / Task 1 remote deploy rerenders tun configs before activation
TASK_PACKAGE: docs/plans/2026-06-13-prod-deploy-rerender-configs
REPORT_PATH: docs/plans/2026-06-13-prod-deploy-rerender-configs/reports/aad-implementer-rerender-prod-configs.md
PROGRESS_PATH: docs/plans/2026-06-13-prod-deploy-rerender-configs/progress/aad-implementer-rerender-prod-configs.md
COMMITS:
- ec2784e: fix(vpnkit): rerender prod configs before deploy activation
FILES_CHANGED:
- scripts/vpnkit/vpnkit-prod-deploy.sh: added bounded `render_local_configs` step after git checkout/release metadata and before compose build/activation; plan output now includes `render-local-configs:tun`.
- test/prod-deploy-helper-test.sh: extended mock deploy harness with renderer success/failure, tun env, ordering, and redaction assertions.
- docs/plans/2026-06-13-prod-deploy-rerender-configs/verification/local.md: recorded RED/GREEN/syntax evidence and outcome boundary.
- docs/plans/2026-06-13-prod-deploy-rerender-configs/progress/aad-implementer-rerender-prod-configs.md: recorded implementation progress.
- docs/plans/2026-06-13-prod-deploy-rerender-configs/README.md, plan.md, progress/slice-owner.md: included provided task package context in the implementation commit because `docs/` is gitignored locally.
AC_VERIFICATION:
- AC1: Mock deploy asserts `local_config_render=start mode=tun` and `local_config_render=ok`; renderer mock prints `token=mock-render-secret` and harness verifies only `token=<redacted>` appears, with raw token absent — passed via `test/prod-deploy-helper-test.sh`.
- AC2: Harness asserts `source_update=git resolved_ref=abc123resolved` occurs before `local_config_render=start mode=tun`, and `local_config_render=ok` occurs before `compose_build=vpnkit` — passed via `test/prod-deploy-helper-test.sh`.
- AC3: Harness runs deploy with `VPNKIT_MOCK_RENDER_FAIL=1`, expects failure logs `local_config_render=failed` and `deploy_render=failed`, and asserts no `compose_build`, `compose_up`, `activation=no_build`, or rollback activation output — passed via `test/prod-deploy-helper-test.sh`.
- AC4: Deploy helper invokes renderer as `run_bounded env VPNKIT_ROUTING_MODE=tun scripts/vpnkit/vpnkit-render-local-configs.sh`; mock harness asserts `render_invoked_routing_mode=tun` — passed via code inspection and `test/prod-deploy-helper-test.sh`.
TESTS_RUN:
- `test/prod-deploy-helper-test.sh`: passed.
- RED step: same command failed before production change with missing render status/order/failure expectations as recorded in `verification/local.md`.
QUALITY_CHECKS:
- `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh scripts/vpnkit/vpnkit-render-local-configs.sh test/prod-deploy-helper-test.sh`: passed.
- `git diff --check`: passed.
QUALITY_NOTES:
- Readability/reuse: reused existing `run_bounded` and `log` style; added one small remote helper instead of rewriting deploy flow.
- Error handling/logging: render failure logs bounded status and exits before compose build/up; existing activation failure rollback behavior is unchanged.
- Backend/API/data: not relevant.
- Frontend/UI: not relevant.
- DevOps/runtime: production deploy path now rerenders gitignored local configs for checked-out ref in tun mode before image build/recreate/config copy; no live deploy was run.
- Security: no secrets or rendered configs committed; status logs include fixed keys/path names only, and mock test proves top-level redaction covers renderer token-like output.
- Concurrency/idempotency: render step overwrites existing gitignored rendered config paths before activation; no background or concurrent behavior added.
- Compatibility/performance: existing deploy/rollback/verify command shapes preserved; one bounded render step added only to deploy path.
SIDE_FINDINGS:
- Blocking: none.
- Non-blocking follow-up candidates: none.
PARENT_ACTION_REQUIRED:
- Action: none for code-only delegated scope.
- Reason: no credentialed/live verification requested or required for this task.
- Expected evidence: none.
- Safety bounds: no live host mutation performed.
NOTES: Verification scope is mocked deploy-helper behavior and shell syntax only. Live production rollout remains a separate operator-approved action.
