PI_RESULT: PASS
TASK: B1 sing-box smart-routing policy and route-decision proof harness
TASK_PACKAGE: docs/plans/2026-06-09-issue-24-smart-routing-manifest
REPORT_PATH: docs/plans/2026-06-09-issue-24-smart-routing-manifest/reports/aad-implementer-b1-smart-routing.md
PROGRESS_PATH: docs/plans/2026-06-09-issue-24-smart-routing-manifest/progress/aad-implementer-b1.md
COMMITS:
- not committed yet: slice owner will decide commit/integration boundary
FILES_CHANGED:
- `config/sing-box/config.json.template`: added local adblock/dev-direct rule sets and policy rules while preserving redirect DNS hijack/sniff order, RU direct, and final selected native.
- `config/sing-box/config.tun.json.template`: added the same policy for TUN/full-tunnel template while preserving DNS hijack/sniff order, RU direct, and final selected native.
- `config/sing-box/rule-sets/vpnkit-adblock.json`: added narrow public-safe ad sample source rule set.
- `config/sing-box/rule-sets/vpnkit-dev-direct.json`: added conservative developer/package infrastructure source rule set.
- `scripts/vpnkit-render-local-configs.sh`: renders/copies rule sets into `rendered/sing-box/rule-sets/` and applies private permissions.
- `test/sing-box-smart-routing-proof.py`: deterministic local proof for policy order, sample route decisions, remote RU metadata, and OpenVPN invariants.
- `docs/plans/2026-06-09-issue-24-smart-routing-manifest/verification/slice-b.md`: verification evidence.
- `docs/plans/2026-06-09-issue-24-smart-routing-manifest/progress/aad-implementer-b1.md`: progress notes.
AC_VERIFICATION:
- AC5: `python3 test/sing-box-smart-routing-proof.py` and temp render probe passed; templates contain adblock/dev-direct local rule sets, preserve full-tunnel final `selected-native-out`, RU direct, DNS hijack/sniff order, and OpenVPN redirect/MTU/MSS invariants — passed.
- AC6: `python3 test/sing-box-smart-routing-proof.py` proves ad samples -> `block-out`, dev/package samples -> `direct-out`, RU sample -> `direct-out`, ordinary foreign sample -> `selected-native-out`; remote RU rule-set entries are HTTPS binary with `download_detour: direct-out` — passed for repo-local config/proof scope.
TESTS_RUN:
- `python3 test/sing-box-smart-routing-proof.py`: passed (`PASS sing-box smart routing proof: adblock/dev-direct/RU/default decisions and template invariants`).
- `bash -n scripts/*.sh test/*.sh`: passed (no output).
- Temp dummy render with `VPNKIT_SECRETS_DIR=<tmp> VPNKIT_ROUTING_MODE=tun scripts/vpnkit-render-local-configs.sh` plus rendered JSON assertions: passed; expected missing-subscription warning only.
QUALITY_CHECKS:
- JSON/template parsing: passed through proof harness and rendered-config probe.
- Shell syntax: passed via `bash -n scripts/*.sh test/*.sh`.
QUALITY_NOTES:
- Readability/reuse: followed existing sing-box `rule_set` structure and kept domain lists in dedicated source rule-set files rather than inline policy lists.
- Error handling/logging: renderer remains `set -euo pipefail`; rule-set copy failure would fail render, which is safer than silently rendering broken policy.
- Backend/API/data: not relevant.
- Frontend/UI: not relevant.
- DevOps/runtime: rendered rule sets land under `/etc/sing-box/rule-sets/` via existing Docker read-only mount of `rendered/sing-box`.
- Security: no secrets/private endpoints read; no profile/log/private data committed.
- Concurrency/idempotency: renderer copy is deterministic/idempotent for tracked rule-set JSON files.
- Compatibility/performance: lists are intentionally narrow; existing RU remote sets remain remote and downloaded via `direct-out`.
SIDE_FINDINGS:
- Blocking: none.
- Non-blocking follow-up candidates: none.
PARENT_ACTION_REQUIRED:
- Action: none for repo-local Slice B scope.
- Reason: live Deck/prod/sing-box runtime acceptance is out of scope.
- Expected evidence: root may run broader final repo checks after integrating Slice A/B.
- Safety bounds: do not read private endpoints or mutate live hosts for this slice.
NOTES: Nested `aad-implementer` delegation was blocked by pi-subagent max depth, so the slice owner performed the bounded implementation directly and recorded implementer-style evidence.
