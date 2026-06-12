## Task
- Mission: Own AC5-AC6 for Issue #24 Slice B: sing-box smart routing/adblock/dev-direct policy and route-decision proofs.
- Target: `config/sing-box/`, `scripts/vpnkit/vpnkit-render-local-configs.sh`, local route proof harness.
- Boundaries: Repo-local tests only; no live Deck/prod mutation; no private endpoint file read; no Slice A manifest/profile CLI changes.
- Done when: Templates/rendering include narrow adblock/dev-direct policy, existing full-tunnel/RU/final behavior is preserved, and local proofs map route decisions to expected outbounds.
- Expected evidence: report + verification artifact under task package with commands/results.

## Context
- Thread: GitHub issue #24 root implementation.
- Slice: Slice B — smart routing/adblock/dev-direct.
- Task name: Issue #24 smart routing + manifest/profile matrix implementation.
- Task package: `docs/plans/2026-06-09-issue-24-smart-routing-manifest`.
- Report path: `docs/plans/2026-06-09-issue-24-smart-routing-manifest/reports/slice-b-smart-routing.md`.
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-slice`.
- Branch: `feat/issue-24-smart-routing-slice`.
- Verify scope: repo-local shell/Python/render checks only.

## Spec compliance
- AC5: done.
  - Evidence: redirect and TUN sing-box templates add local `vpnkit-adblock` -> `block-out` and `vpnkit-dev-direct` -> `direct-out` before existing RU direct rules; final remains `selected-native-out`; proof asserts DNS hijack/sniff order and OpenVPN `redirect-gateway`, `tun-mtu 1400`, `mssfix 1360` remain present.
  - Gap if any: live sing-box runtime behavior not claimed.
- AC6: done for repo-local scope.
  - Evidence: `test/sing-box-smart-routing-proof.py` simulates sample route decisions and asserts RU remote rule-set metadata/download detour.
  - Gap if any: remote download/cache/failure is config-level proof only, not a network/runtime proof.

## Acceptance verification
- AC5: sing-box templates implement narrow adblock/dev-direct sets/rules and preserve existing routing invariants.
  - Covered by: `python3 test/sing-box-smart-routing-proof.py`; temp dummy render probe.
  - Result: passed.
  - Evidence: `PASS sing-box smart routing proof: adblock/dev-direct/RU/default decisions and template invariants`; render probe parsed generated config and found copied rule-set files.
- AC6: local route-decision proof coverage.
  - Covered by: `test/sing-box-smart-routing-proof.py` samples and assertions.
  - Result: passed with explicit limitation.
  - Evidence: ad domains -> `block-out`; dev/package domains -> `direct-out`; `example.ru` -> `direct-out`; `foreign-news.example.com` -> `selected-native-out`; RU remotes use HTTPS binary rule sets with `download_detour: direct-out`.

## System readiness
- Routes / registration: done for tracked sing-box templates.
- Services / APIs: not relevant.
- Config / env / secrets: done for repo-local rendering; no secrets read; rendered rule sets copied under existing sing-box mount.
- Permissions / access: done for rendered local rule-set files (`chmod 600` with config).
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: ready for root local integration checks; live production runtime acceptance remains out of scope.

## Verification run
- Local / targeted checks:
  - `python3 test/sing-box-smart-routing-proof.py`: passed.
    - Evidence: `PASS sing-box smart routing proof: adblock/dev-direct/RU/default decisions and template invariants`.
  - Temp dummy render probe with `VPNKIT_ROUTING_MODE=tun scripts/vpnkit/vpnkit-render-local-configs.sh`: passed with expected missing-subscription warning.
    - Evidence: rendered config parsed, policy order asserted, local rule-set files existed.
- Local / full checks:
  - `bash -n scripts/*.sh test/*.sh`: passed.
- Remote checks / CI:
  - Status: not available before push.

## Issues
### Issue R-01: Smart-routing policy had no adblock/dev-direct proof
- Description: Existing templates only contained RU direct rules and final selected-native behavior.
- Evidence: initial `config/sing-box/config*.json.template` rule lists.
- Resolution: added dedicated local rule-set files, wired templates/rendering, and added deterministic proof harness.
- Depends on: none.

## Side findings
- Blocking findings folded into active work: none.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: success.
- Goal state: achieved for AC5-AC6 repo-local scope.
- Final readiness: ready for root integration with explicit limitation that live/prod/runtime remote-download acceptance is unclaimed.
- Summary: Slice B stayed whole; implementation was completed directly by the slice owner after nested implementer dispatch was blocked, with fresh local proof evidence.

## Next-agent brief
- Objective: root owner should integrate this slice branch into parent and run final cross-slice verification.
- Target: files listed in the implementer report.
- Settled already: policy order, rule-set paths, local route-decision proof, and no-live-scope boundary.
- Boundaries: do not broaden dev direct list or claim live runtime acceptance without separate approved live proof.
- Verification target: rerun `python3 test/sing-box-smart-routing-proof.py`, `bash -n scripts/*.sh test/*.sh`, and any root-level final checks after Slice A integration.
- Expected output: root final report/PR evidence.
