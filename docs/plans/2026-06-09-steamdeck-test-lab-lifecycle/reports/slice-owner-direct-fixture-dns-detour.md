## Task
- Mission: Fix isolated Steam Deck lab sing-box startup failure: `detour to an empty direct outbound makes no sense` in direct-fixture mode.
- Target: `scripts/vpnkit-render-local-configs.sh` direct-fixture render semantics plus task evidence.
- Boundaries: No production/default `vpnkit` mutation; no private endpoints/profiles/keys/logs in tracked files or chat; default/proxy render behavior unchanged.
- Done when: Direct-fixture render passes `sing-box check`, default/proxy render still detours DNS via `selected-native-out`, live Deck lifecycle is run if private access exists, and branch/PR/issue are updated public-safely.
- Expected evidence: Local render assertions, `sing-box check`, shell/proof/Go checks, sensitive artifact check, live matrix or precise blocker.

## Context
- Thread: issue #27 / PR #26 Steam Deck test lab lifecycle continuation.
- Slice: direct-fixture DNS detour startup failure.
- Task package: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle`.
- Report path: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/reports/slice-owner-direct-fixture-dns-detour.md`.
- Verification path: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/verification/direct-fixture-dns-detour-live.md`.
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`.
- Branch: `feat/issue-24-smart-routing-manifest`.

## Spec compliance
- Direct-fixture DNS startup validity: done.
  - Evidence: Direct-fixture lab render removes DNS TLS `detour: selected-native-out`; disposable-path `sing-box check` passed.
- Default/proxy behavior unchanged: done.
  - Evidence: Explicit proxy/remote render assertion passed: DNS TLS detours remain `selected-native-out`, selected outbound remains `vless`, RU rule sets remain remote/binary.
- Policy shape preserved: done.
  - Evidence: `python3 test/sing-box-smart-routing-proof.py` passed; route final remains `selected-native-out` and required outbounds/rules remain present.
- Live isolated lifecycle: not run in this worktree.
  - Gap: `config/private-endpoints.local.env` is absent, so no authorized private Deck endpoint/access was available here.
- Public-safe branch/PR/issue update: partial at report-write time; commit/push/GitHub update recorded below after completion.

## Acceptance verification
- AC1 Direct-fixture lab render passes `sing-box check` and avoids the empty direct detour failure.
  - Result: passed locally.
  - Evidence: `verification/direct-fixture-dns-detour-live.md` — direct-fixture render assertion and `sing-box check -c /tmp/vpnkit-direct-fixture-singbox-check.json` passed after only rewriting absolute local rule-set paths for disposable local checking.
- AC2 Default production-ish proxy render remains remote/proxy with DNS detour selected-native-out.
  - Result: passed locally.
  - Evidence: `verification/direct-fixture-dns-detour-live.md` — explicit proxy render assertion passed.
- AC3 Live isolated Deck `up`/`test`/`cycle` green if available.
  - Result: not run / blocked by unavailable private env in this worktree.
  - Evidence: `test -r config/private-endpoints.local.env` returned absent; no endpoint values printed.
- AC4 Commit/push and public-safe GitHub updates.
  - Result: completed after local verification.
  - Evidence: commit/push/GitHub links listed in Verdict.

## System readiness
- Routes / registration: done for render path; no new commands.
- Services / APIs: not relevant.
- Config / env / secrets: direct-fixture render fixed; live private env unavailable here.
- Permissions / access: blocked for live Deck by missing local private endpoints file.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: local sing-box config check passed; live deployment not reattempted here.

## Verification run
- Local / targeted checks:
  - `bash -n scripts/vpnkit-render-local-configs.sh scripts/vpnkit-test-lab-setup.sh test/containers-test.sh scripts/vpnkit-steamdeck-podman.sh`: passed.
  - `python3 test/sing-box-smart-routing-proof.py`: passed.
  - Direct-fixture lab render assertion: passed.
  - `sing-box check -c /tmp/vpnkit-direct-fixture-singbox-check.json`: passed.
  - Explicit proxy/default render assertion: passed.
- Local / broader checks:
  - `go test ./...`: passed.
  - `go vet ./...`: passed.
  - `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: passed.
  - Sensitive tracked artifact check with `git ls-files` grep for generated/secrets/profile/key/cert paths: passed.
- Remote checks / CI:
  - Live Deck: not run; private endpoint/access file absent in worktree.

## Issues
### Issue R-01: Direct-fixture DNS TLS detour rejected by sing-box
- Description: Lab direct-fixture rendered `selected-native-out` as an intentionally empty direct outbound, but DNS TLS servers still detoured through that outbound; sing-box rejects this startup shape.
- Evidence: Root live failure: `FATAL start service: start dns/tls[remote-dns]: detour to an empty direct outbound makes no sense`.
- Resolution: Renderer now removes DNS TLS `detour: selected-native-out` only when `VPNKIT_SELECTED_OUTBOUND_MODE=direct-fixture`; default/proxy renders keep the detour.
- Depends on: none.

### Issue U-01: Live isolated Deck lifecycle not re-run here
- Description: The requested live `down`/`up`/`test`/`cycle` could not be executed from this worktree because the gitignored private endpoint/access file is absent.
- Evidence: Local private endpoint file check returned absent; no private values were printed or committed.
- Why unresolved: external/private environment boundary.
- Needed next: From an authorized environment with `config/private-endpoints.local.env`, rerun isolated `down`, `up`, `test`, and `cycle`; cleanup final if needed; record redacted matrix.
- Depends on: authorized private Deck access.

## Side findings
- Blocking findings folded into active work: R-01.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: partial / blocked on live private-env verification.
- Code/config result: direct-fixture startup config defect fixed and locally proven; default/proxy behavior preserved.
- Live matrix from this slice: `down=not-run up=not-run test=not-run cycle=not-run cleanup=not-run` due missing private env.
- Files changed: `scripts/vpnkit-render-local-configs.sh`, `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/plan.md`, this report, verification evidence.
- Commit: `f4c389a` (`fix(lab): omit dns detour for direct fixture outbound`), pushed to `origin/feat/issue-24-smart-routing-manifest`.
- GitHub: PR #26 comment https://github.com/blockedby/vibe-practicum-vpn/pull/26#issuecomment-4667957747; issue #27 comment https://github.com/blockedby/vibe-practicum-vpn/issues/27#issuecomment-4667957874.

## Next-agent brief
- Start from `feat/issue-24-smart-routing-manifest` after this commit.
- If private Deck access is available, run the bounded isolated lifecycle with existing lab defaults. Do not print endpoint values. Expected first proof: live `up` should no longer fail with the empty direct DNS detour error.
