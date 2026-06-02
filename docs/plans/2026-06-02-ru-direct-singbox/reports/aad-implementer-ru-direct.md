PI_RESULT: PASS
TASK: RU direct sing-box routing
TASK_PACKAGE: docs/plans/2026-06-02-ru-direct-singbox
REPORT_PATH: docs/plans/2026-06-02-ru-direct-singbox/reports/aad-implementer-ru-direct.md
PROGRESS_PATH: docs/plans/2026-06-02-ru-direct-singbox/progress/aad-implementer-ru-direct.md
COMMITS:
- 3d4534d: Route RU sing-box traffic direct
FILES_CHANGED:
- config/sing-box/config.json.template: added RU IP and RU geosite-compatible remote rule-set routes to `direct-out`, preserving DNS hijack first and final `selected-native-out`.
- internal/singbox/singbox_test.go: added regression coverage for template placeholder JSON parsing, route ordering, RU direct rules, remote rule-set declarations, and final route.
- docs/plans/2026-06-02-ru-direct-singbox/plan.md: updated execution ledger.
- docs/plans/2026-06-02-ru-direct-singbox/progress/aad-implementer-ru-direct.md: recorded TDD progress and verification decisions.
- docs/plans/2026-06-02-ru-direct-singbox/verification/local.md: recorded local verification evidence and Docker/secrets waiver.
AC_VERIFICATION:
- Template parses after placeholder substitution: Go regression unmarshals temp-substituted template JSON; temp `sing-box check` passed with compatibility env vars for pre-existing deprecation gates — passed.
- Explicit RU IP and RU geosite route to `direct-out`: `geoip-ru` and `geosite-category-ru` route-set rules point to `direct-out`; remote binary rule sets are declared with direct download detour — passed.
- DNS hijack rules remain before normal routing: regression asserts first two route rules remain `vpnkit-dns-in`/`protocol=dns` hijack rules before RU direct routes — passed.
- Final remains `selected-native-out`: regression asserts `route.final == selected-native-out` — passed.
- No secrets/generated artifacts committed: did not touch `secrets/`; temp render used `mktemp` and was removed; `git status --short` before docs commit showed only intended tracked changes plus task package — passed.
TESTS_RUN:
- `go test ./internal/singbox -run TestDockerTemplateRoutingInvariants`: failed before production change as expected (`route.rules length = 2`) — red passed.
- `go test ./internal/singbox -run TestDockerTemplateRoutingInvariants -count=1`: passed.
- `go test ./...`: passed.
- `sing-box check -c <temp-rendered-config>`: not passed without env due pre-existing sing-box 1.13.12 legacy DNS deprecation gate.
- `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true sing-box check -c <temp-rendered-config>`: not passed due second pre-existing missing domain resolver deprecation gate.
- `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true sing-box check -c <temp-rendered-config>`: passed with warnings.
- Docker compose OpenVPN client lab: not run; `secrets/` absent and delegated boundary says not to touch secrets.
QUALITY_CHECKS:
- `gofmt -w internal/singbox/singbox_test.go`: passed.
- `git diff --check`: passed.
- `go test ./...`: passed.
QUALITY_NOTES:
- Readability/reuse: reused existing `direct-out`, route ordering, and sing-box `rule_set` pattern already present in canary configs; no new production abstraction added.
- Error handling/logging: not relevant; no runtime logging/error handling changed.
- Backend/API/data: not relevant; no API/storage/persisted data changes.
- Frontend/UI: not relevant.
- DevOps/runtime: touched Docker/vpnkit sing-box template only; used modern remote binary rule sets because Docker image installs sing-box 1.13.x where legacy `geoip`/`geosite` route items are removed/deprecated. Docker lab requires gitignored secrets and was waived without VPS mutation.
- Security: no secrets, tokens, certificates, keys, rendered configs, or logs committed; no sensitive values printed.
- Concurrency/idempotency: not relevant for static route template; remote rule-set downloads use direct detour.
- Compatibility/performance: preserved default proxy final and DNS hijack ordering; added two route checks before final routing with bounded rule-set lookups.
SIDE_FINDINGS:
- Blocking: none.
- Non-blocking follow-up candidates: existing template uses sing-box legacy DNS server format and lacks `route.default_domain_resolver`, which local sing-box 1.13.12 now gates unless compatibility env vars are set.
NOTES: Used `geosite-category-ru` as the available sing-box SRS equivalent for broad RU geosite/category routing from the same runetfreedom source family as `geoip-ru`. No VPS commands were run.
