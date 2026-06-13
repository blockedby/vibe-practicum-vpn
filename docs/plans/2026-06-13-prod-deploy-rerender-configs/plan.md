# Prod deploy rerender configs plan

## Task intake
Goal: Carefully update `scripts/vpnkit/vpnkit-prod-deploy.sh` so remote deploys rerender local gitignored configs after checking out the requested ref and before build/recreate/config copy, using existing `scripts/vpnkit/vpnkit-render-local-configs.sh` with `VPNKIT_ROUTING_MODE=tun`.

In scope:
- Minimal deploy-helper change only.
- Ensure render/check failure stops before compose build/recreate.
- Preserve redacted output/no secret printing behavior.
- Add/extend existing shell/static tests where practical.
- No live host mutation.

Out of scope:
- No deploy/verify/rollback commands against production hosts.
- No rewrite of deploy helper release model.
- No committing generated secrets/rendered configs/logs.

Done state:
- Helper rerenders remote `secrets/vps/rendered/*` from tracked templates after checkout in deploy path before build/recreate.
- Test coverage proves ordering and failure-before-recreate behavior in the existing mock deploy test.
- Fresh syntax/targeted checks pass.

Blocking unknowns: none.

## Repo orientation
- Root guidance: production deploy helper must be used for prod flows, output redacted, real host/endpoint values stay local/gitignored, prod mutation requires explicit approval. This task explicitly forbids live mutation.
- Relevant files:
  - `scripts/vpnkit/vpnkit-prod-deploy.sh`: remote deploy helper; `deploy()` currently calls `discover; create_release; activate_image && require_tun_pair; ...`.
  - `scripts/vpnkit/vpnkit-render-local-configs.sh`: existing renderer; default mode is redirect, so deploy must invoke it with `VPNKIT_ROUTING_MODE=tun`.
  - `test/prod-deploy-helper-test.sh`: existing mocked shell test for plan/deploy/rollback ordering/redaction.
- Relevant checks:
  - `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh scripts/vpnkit/vpnkit-render-local-configs.sh test/prod-deploy-helper-test.sh`
  - `test/prod-deploy-helper-test.sh`

## Reuse discovery
- Reuse `run_bounded` for timeout-wrapped remote commands.
- Reuse existing `log` output style with status keys only; do not print rendered config content or env values.
- Reuse existing mock remote `git`/`docker` in `test/prod-deploy-helper-test.sh`; add a mock renderer script in the mock workdir and assertions for ordering/failure.
- Existing `require_tun_pair` already copies/checks rendered `secrets/vps/rendered/sing-box/config.json` after activation; new rerender should happen before activation so stale persisted config is not copied.

## Missing pieces
- Add a remote helper function such as `render_local_configs()` after checkout/metadata and before build.
- Invoke with `VPNKIT_ROUTING_MODE=tun scripts/vpnkit/vpnkit-render-local-configs.sh` through `run_bounded`.
- Fail if renderer missing/non-executable/fails, before `compose build`/`compose up`.
- Extend plan/dry-run step text to include rerender.
- Extend mock test coverage for success ordering and failure-before-recreate.

## Plan tasks

### Task 1: Remote deploy rerenders tun configs before activation
Goal:
- Make deploy path rerender local configs for the checked-out ref with tun routing before build/recreate/config copy.

Boundary:
- System area: production deploy helper runtime/deployment wiring.
- Primary verification: existing mocked `test/prod-deploy-helper-test.sh` plus syntax checks.

Existing pattern / reuse:
- `run_bounded`, `log`, `create_release`, `activate_image`, `require_tun_pair` in `scripts/vpnkit/vpnkit-prod-deploy.sh`.
- `scripts/vpnkit/vpnkit-render-local-configs.sh` renderer.

Missing change:
- Add render step after checkout and before compose build/up.

Scope / likely files:
- `scripts/vpnkit/vpnkit-prod-deploy.sh`
- `test/prod-deploy-helper-test.sh`

Acceptance criteria:
- AC1: Deploy logs a bounded status showing local config render occurred without printing secret values.
- AC2: Render occurs after `source_update=git resolved_ref=...` and before `compose_build=`/activation.
- AC3: If render fails, deploy exits failure and does not run compose build/up/recreate.
- AC4: Renderer is invoked with `VPNKIT_ROUTING_MODE=tun`.

Evidence route:
- Existing automated checks first: `test/prod-deploy-helper-test.sh` and `bash -n`.
- If existing checks lack coverage: extend mock test to simulate renderer success and failure.
- Bounded acceptance probe: no live deploy; mock remote harness only.
- Access/runtime needed: none beyond local shell/git.
- Outcome boundary: PASS proves local deploy helper logic/order in mock and shell syntax; it does not prove live host deployment, which remains user-approved future action.

Test plan:
- Positive: mocked deploy asserts render status, tun env, ordering before compose build, existing deploy success.
- Negative: mocked render failure asserts deploy fails and no compose build/up occurs.
- Edge: no secret/raw token output in render logs (mock can print token and top-level redaction should redact).
- Manual: none.

Dependencies:
- Depends on: none.
- Blocks: final verification/report.
- Can run parallel with: none.

Executor:
- aad-implementer.

## Dependency graph / execution ledger
- Task 1 -> aad-implementer, report `reports/aad-implementer-rerender-prod-configs.md`, progress `progress/aad-implementer-rerender-prod-configs.md`.
- Owner final verification/report after Task 1.

Status:
- Task 1: pending dispatch.
