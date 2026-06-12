## Task
- Mission: Implement public-safe Steam Deck `steamdeck-host` test-lab lifecycle runner for issue #27.
- Target: `test/containers-test.sh`, Steam Deck Podman helper, isolated lab generation, docs/templates, verification artifacts.
- Boundaries: Did not touch prod/default `vpnkit`; did not commit generated secrets/profiles/configs/logs; no live Deck mutation without private local env.
- Done when: `up|test|down|cycle` UX exists, isolated defaults are enforced, local safety checks pass, and live cycle is run or precisely blocked.
- Expected evidence: local checks, prerequisite FAIL behavior, ignored artifact proof, live Deck result/blocker.

## Context
- Thread: new standalone scope after PR #26 / issue #24; issue #27 lifecycle runner.
- Slice: L1 Steam Deck test-lab lifecycle runner; stayed whole (no sub-slices; no implementer delegation available due nesting limit).
- Task package: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle`
- Report path: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/reports/slice-owner-lifecycle.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`
- Branch: `feat/issue-24-smart-routing-manifest`
- Verify scope: safe local checks plus live Deck cycle when `config/private-endpoints.local.env` is present.

## Spec compliance
- AC1 lifecycle command: done; `test/containers-test.sh --scenario steamdeck-host --action up|test|down|cycle`.
- AC2 isolation/default-prod safety: done; lab container/image/port/remote-dir defaults are distinct and `vpnkit-steamdeck-podman.sh run` refuses container `vpnkit` unless explicitly overridden.
- AC3 gitignored artifacts: done; generated layout is `secrets/vpnkit-labs/steamdeck-host/...`, under ignored `secrets/`; docs/template updated.
- AC4 test PKI/templates/rules: done; `scripts/vpnkit/vpnkit-test-lab-setup.sh` creates throwaway PKI/profile and invokes existing production-like renderer/templates/rule sets.
- AC5 lab tun mode: done; lifecycle defaults to `tun`, passes routing mode to Podman, and checks `sb-tun0` only for tun.
- AC6 disabled daemon paths: done; missing `sub_url` is optional for server smoke; Deck verify skips `vibe-vpn doctor` when no lab subscription is mounted.
- AC7 missing prerequisites: done locally; explicit `steamdeck-host` missing endpoint exits nonzero with `FAIL lifecycle:prereq-endpoint`.
- AC8 honest matrix: partial; existing policy-visible proof remains SKIP/TODO and does not count as PASS.
- AC9 safe repo checks: partial pass; shell/python/go/route checks pass, manifest validation blocked by missing public `jsonschema` dependency.
- AC10 live Deck cycle: blocked; `config/private-endpoints.local.env` absent, so no authorized private Deck target/endpoint values available.
- AC11 PR update: not completed in this local pass; commit prepared locally, push/PR update still needed after final owner decision.

## Acceptance verification
- AC1-AC8: Covered by code inspection plus `bash -n` and missing-prereq lifecycle run. Result: passed/partial as above. Evidence: `verification/local.md`.
- AC9: Covered by local checks. Result: partial. Evidence: `bash -n`, `py_compile`, `sing-box-smart-routing-proof`, `go test/vet/build` pass; manifest check needs `jsonschema`.
- AC10: Result: not run/blocked by missing `config/private-endpoints.local.env`. Evidence: `verification/live-deck.md`.
- AC11: Result: not yet pushed/commented.

## System readiness
- Routes / registration: CLI flags and docs done.
- Services / APIs: not relevant.
- Config / env / secrets: public template/docs done; private env absent for live.
- Permissions / access: blocked for live Deck by missing private local env.
- Runtime / deployment wiring: implemented but live cycle unverified.

## Verification run
- Local / targeted checks:
  - `bash -n scripts/*.sh test/*.sh`: passed.
  - `scripts/vpnkit/vpnkit-test-lab-setup.sh --endpoint 127.0.0.1 --port 21194`: passed, generated ignored artifacts only.
  - `VPNKIT_TEST_SSH_TARGET= VPNKIT_TEST_ENDPOINT= test/containers-test.sh --scenario steamdeck-host --action test`: expected nonzero with clear FAIL diagnostic.
- Local / full checks:
  - `python3 -m py_compile scripts/*.py test/*.py`: passed.
  - `python3 test/sing-box-smart-routing-proof.py`: passed.
  - `go test ./...`, `go vet ./...`, `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: passed.
  - Manifest validation: not completed; missing `jsonschema` dependency.
- Remote checks / CI: not checked before push.

## Issues
### Issue R-01: Partial interrupted lifecycle work completed into coherent runner
- Description: Existing partial edits were normalized into documented lifecycle UX and isolated lab generator.
- Evidence: changed scripts/docs and local syntax/setup checks.
- Resolution: kept useful partial routing-mode/daemon-relaxation changes, added scenario/action orchestration and docs.
- Depends on: none.

### Issue U-01: Live Steam Deck cycle not run
- Description: Required private Deck bindings were unavailable in this worktree.
- Evidence: `config/private-endpoints.local.env` absent.
- Why unresolved: external/private local environment boundary.
- Needed next: source authorized local env and run `test/containers-test.sh --scenario steamdeck-host --action cycle`; fix script bugs if any, otherwise classify environment/network precisely.
- Depends on: private local Deck SSH/endpoint values.

### Issue U-02: Manifest validation dependency missing locally
- Description: manifest validation could not run because Python `jsonschema` is not installed.
- Evidence: command reported `Missing Python dependency for manifest validation: jsonschema`.
- Why unresolved: local tool dependency absent.
- Needed next: install public deps (`PyYAML jsonschema`) and rerun manifest validation commands.
- Depends on: local Python environment.

## Side findings
- Blocking findings folded into active work: R-01.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: partial / blocked.
- Goal state: implementation mostly achieved locally; final acceptance not achieved because live Deck cycle and manifest dependency verification are blocked.
- Final readiness: not ready for full issue #27 closure until AC10 live cycle is green (or precisely classified after authorized run) and AC11 PR update is done.
- Summary: Lifecycle runner and isolated lab generation are implemented with safe defaults and local checks, but live Deck acceptance remains a private-environment handoff.

## Next-agent brief
- Objective: Finish issue #27 acceptance.
- Target: current branch/worktree and PR #26.
- Settled already: command UX, isolated defaults, gitignored layout, tun default, disabled daemon relaxation.
- Boundaries: do not touch prod/default `vpnkit`; do not print/commit private values/generated artifacts.
- Verification target: install public Python deps if needed, rerun manifest validation, source `config/private-endpoints.local.env`, run `test/containers-test.sh --scenario steamdeck-host --action cycle`, push commit, update PR #26 with issue #27 status.
- Expected output: live matrix result, pushed commit/PR update, final blocker classification if cycle is not green.
