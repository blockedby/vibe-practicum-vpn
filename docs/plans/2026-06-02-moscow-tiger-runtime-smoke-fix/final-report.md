# Final report — Moscow tiger OpenVPN MTU/MSS cleanup/finalization

## Task
- Mission: Make the user-confirmed `moscow-tiger` MTU/MSS live hotfix durable in repo source, keep docs/evidence public-safe, and verify source-based deploy plus baseline/2ip smokes.
- Target: OpenVPN render source, Docker setup docs, task-package evidence, and `moscow-tiger` source-based runtime readiness.
- Boundaries: No Vercel/DNS, no Steam Deck, no unrelated `vibe-practicum` mutation, and no committed/revealed private endpoints, generated profiles/configs, subscriptions, auth files, logs, snapshots, or secrets.
- Done when: tracked source renders `tun-mtu 1400` and `mssfix 1360`; `moscow-tiger` is redeployed from that source; fresh host Docker baseline and explicit 2ip smokes pass with sanitized evidence.

## Context
- Task package: `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix`
- Plan: `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix/plan.md`
- Slice report: `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix/reports/slice-owner-runtime-diagnosis-fix.md`
- Acceptance audit: `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix/reports/acceptance-auditor.md`
- Verification: `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix/verification/runtime-smoke.md`
- Worktree: `.worktrees/moscow-tiger-runtime-smoke-fix`
- Branch: `aad/moscow-tiger-runtime-smoke-fix`
- Source commit: `cd7562e` (`Persist moscow-tiger OpenVPN MTU fix`)

## Slice structure used
- One slice: source/runtime finalization.
- Reason: the source template, render path, live deploy, and host-client smokes share one runtime acceptance story and one live target; parallel slices would add coordination without reducing risk.

## Integrated slice outcome
- Source durability completed: `config/openvpn/server.tpl` now includes `tun-mtu 1400` and `mssfix 1360`.
- Guard completed: `internal/config/openvpn_template_test.go` checks both directives remain in the OpenVPN server template.
- Docs/evidence completed: `docs/DOCKER_SETUP.md` and task-package reports record the public-safe MTU/MSS rationale and gitignored `sub_url` / `extra-nodes.json` handling.
- Local render guard completed: a throwaway render from this branch contained both MTU/MSS directives and wrote `extra-nodes.json` as `[]` when no gitignored extra-nodes input exists.
- Live source-based deploy and fresh smokes remain blocked: `config/private-endpoints.local.env` in this environment still resolves to the example SSH placeholder, so SSH fails before `moscow-tiger` access.

## Acceptance verification
- AC1 Persistent source MTU/MSS fix:
  - Result: passed locally.
  - Evidence: `config/openvpn/server.tpl`; `grep -nE '^(tun-mtu 1400|mssfix 1360)$' config/openvpn/server.tpl`; throwaway rendered `server.conf` grep.
- AC2 Tests/docs/evidence updated public-safely:
  - Result: passed locally.
  - Evidence: `internal/config/openvpn_template_test.go`, `docs/DOCKER_SETUP.md`, updated task package.
- AC3 Source-based deploy/render on `moscow-tiger`:
  - Result: blocked / not confirmed.
  - Evidence: SSH gate fails before live access because the gitignored endpoint file contains the example SSH placeholder.
- AC4 `sub_url` / `extra-nodes` safety:
  - Result: passed locally.
  - Evidence: docs mention only gitignored paths; throwaway render verified `extra-nodes=[]`; no values or generated artifacts tracked.
- AC5 Fresh host Docker baseline smoke after source deploy:
  - Result: blocked / not run here.
  - Evidence: no usable live target/profile access. User-provided manual-hotfix smoke pass is historical evidence only, not source-based acceptance.
- AC6 Explicit 2ip smoke after source deploy:
  - Result: blocked / not run here.
  - Evidence: same live access blocker.
- AC7 Repo checks/public safety:
  - Result: passed locally.
  - Evidence: root reran `go test ./internal/config`, `bash -n scripts/*.sh`, `git diff --check HEAD~1..HEAD`, template grep, and `go test ./...`; worktree clean before acceptance audit files/final report.

## System readiness
- Config / env / secrets: source config ready; live endpoint inventory unusable in this environment.
- Docker / containers: local render path verified; live container state not verified from source deploy.
- Runtime / deployment wiring: not ready to claim complete until source-based deploy and smokes run.
- CI / remote checks: not available before push; branch not pushed because final runtime acceptance is blocked.

## Issues
### R-01: Live MTU/MSS hotfix was not persistent in source
- Resolution: Added MTU/MSS directives to tracked OpenVPN server template and a guard test.
- Evidence: commit `cd7562e`; local render and tests passed.

### U-01: Source-based deploy and fresh baseline/2ip smokes blocked by endpoint inventory
- Description: The environment's gitignored `config/private-endpoints.local.env` still contains the example SSH placeholder, preventing live access.
- Evidence: slice report, runtime verification, and acceptance audit record the sanitized SSH gate failure.
- Needed next: populate usable operator-local `moscow-tiger` access/profile values, deploy/re-render from branch `aad/moscow-tiger-runtime-smoke-fix`, then rerun baseline and 2ip smokes with sanitized evidence.

## Side findings
- Blocking findings folded into active work: U-01.
- Non-blocking follow-ups: none.

## Verdict
- Status: blocked / partial.
- Goal state: source durability achieved; final runtime readiness not achieved from this environment.
- Final readiness: not ready to claim complete runtime finalization.
- Merge/push: not performed because the user allowed merge/push only if successful and source-based live deploy/smokes are still blocked.

## Next-agent brief
- Objective: Complete live source-based deploy and final smokes once usable gitignored endpoint values are available.
- Target: `moscow-tiger` Docker `vpnkit` runtime from branch `aad/moscow-tiger-runtime-smoke-fix` / commit `cd7562e` or later.
- Settled already: MTU/MSS root cause accepted from user live evidence; source template and guard are in place; do not reopen broad diagnosis first.
- Boundaries: Keep endpoints, profiles, rendered configs, subscriptions, auth files, logs, snapshots, and private values out of tracked files/chat.
- Verification target: running OpenVPN config contains `tun-mtu 1400` and `mssfix 1360` from source render; fresh host Docker client tunnel/DNS/HTTPS/literal-IP; explicit 2ip route evidence.
