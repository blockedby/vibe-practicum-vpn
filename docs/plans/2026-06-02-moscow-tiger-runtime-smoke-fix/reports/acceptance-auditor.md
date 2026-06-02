## Task package
- Task name: Moscow tiger OpenVPN MTU/MSS cleanup/finalization
- Task package: `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix`
- Report path: `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix/reports/acceptance-auditor.md`
- Acceptance plan path: `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix/verification/acceptance-plan.md`

## Acceptance verdict
- Status: blocked
- Summary: The MTU/MSS source fix and public-safe docs/tests are in place, but source-based deploy plus fresh baseline/2ip smokes are still blocked by unusable private endpoint access, so final acceptance is not ready.

## Acceptance coverage
- AC1: Persistent source change for OpenVPN MTU/MSS in the tracked render template/config, and rendered output from source includes both.
  - Evidence present: `config/openvpn/server.tpl`, `internal/config/openvpn_template_test.go`, throwaway render grep in `verification/runtime-smoke.md`.
  - Result: passed.
  - Gap: none on source durability.
- AC2: Tests/docs/evidence updated public-safely for the moscow-tiger MTU/MSS fix.
  - Evidence present: `go test ./internal/config`, `go test ./...`, `bash -n scripts/*.sh`, `docs/DOCKER_SETUP.md`, task-package reports.
  - Result: passed.
  - Gap: none for public-safe source/docs evidence.
- AC3: Source-based deploy/render on `moscow-tiger` confirmed, not just live hotfix.
  - Evidence present: live gate attempt in `verification/runtime-smoke.md` and `reports/slice-owner-runtime-diagnosis-fix.md`.
  - Result: blocked / not confirmed.
  - Gap: the gitignored endpoint inventory still resolves to the example SSH placeholder, so live access and source-based deploy could not run.
- AC4: `sub_url` / `extra-nodes` handling remains public-safe, no values/logs/generated artifacts committed.
  - Evidence present: `docs/DOCKER_SETUP.md` documents gitignored `sub_url`; render path writes `extra-nodes.json` as `[]` when absent; no secret artifacts are tracked.
  - Result: passed.
  - Gap: none in tracked/public-safe evidence.
- AC5: Fresh host Docker client baseline smoke passes after source-based deploy: tunnel, DNS NOERROR, HTTPS 200, literal-IP HTTPS 200.
  - Evidence present: none fresh from a source-based deploy.
  - Result: blocked / not run.
  - Gap: no usable live target/profile access, so the post-source-deploy baseline smoke was not executed here.
- AC6: Explicit 2ip smoke passes after source-based deploy with redacted route evidence.
  - Evidence present: none fresh from a source-based deploy.
  - Result: blocked / not run.
  - Gap: same live access blocker; no sanitized 2ip route evidence from this branch.
- AC7: Relevant repo checks and public-safety check passed.
  - Evidence present: `go test ./...`, `go test ./internal/config`, `bash -n scripts/*.sh`, `git status --short` and the report's public-safety notes.
  - Result: passed for local checks/public-safety.
  - Gap: remote CI not available before push.

## System readiness coverage
- Routes / registration: not relevant.
- Services / APIs: not relevant.
- Config / env / secrets: blocked; `config/private-endpoints.local.env` in this worktree still yields the example SSH placeholder, so live access cannot start.
- Docker / containers: partially covered locally by render checks; live runtime container state not verified from this environment.
- Permissions / access: blocked by unusable private endpoint values.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: blocked; source render exists, but live source-based deploy/smoke was not executable here.

## Check freshness
- Targeted checks: fresh.
- Full local checks: fresh.
- Remote checks / CI: not available before push.

## Required before done
- Populate the gitignored endpoint inventory with usable `moscow-tiger` access values, rerun source-based deploy/render, then rerun fresh baseline and explicit 2ip smokes with sanitized evidence.

## Files written
- `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix/verification/acceptance-plan.md`: created
- `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix/reports/acceptance-auditor.md`: created
