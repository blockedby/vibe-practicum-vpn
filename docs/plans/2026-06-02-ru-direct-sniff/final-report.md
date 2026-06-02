# Final root report: RU direct sniff post-deploy fix

## Task
- Mission: Fix post-deploy RU-direct issue where `2ip.ru` still showed Germany because transparent redirect routed CDN IPs through `selected-native-out` without domain context.
- Target: Docker/vpnkit sing-box template, regression coverage, local Docker runtime evidence, and VPS Docker runtime deploy readiness.
- Boundaries: no Steam Deck work, no native VPS service changes, no secrets/logs/generated artifacts committed.
- Done when: sniff fix is implemented, tested, pushed, deployed to VPS Docker runtime, persisted config refreshed, and live baseline + `2ip.ru` smoke pass.

## Context
- Task package: `docs/plans/2026-06-02-ru-direct-sniff`
- Worktree / branch: `/home/kcnc/code/tools/vibe-practicum-vpn` / `main`
- Current pushed branch state: `b695369` on `origin/main`; source fix commit is `0e4cbfb Add vpnkit RU domain sniff routing`.
- Slice structure: one slice, because the change has one config/runtime ownership boundary and one acceptance story. Slice report: `reports/aad-slice-owner.md`.

## Spec compliance
- Requirement / AC: Add sing-box 1.13 route action sniffing before RU geosite/rule-set routing and avoid deprecated inbound sniff.
  - Status: done.
  - Evidence: `config/sing-box/config.json.template` adds `{ "inbound": ["vpnkit-redirect-in", "vpnkit-socks-in"], "action": "sniff", "timeout": "1s" }` after DNS hijack rules and before RU rule-set routes; `sing-box check` passed in slice verification.
  - Gap if any: none in source/local runtime.
- Requirement / AC: Preserve DNS hijack, RU direct rule sets, and default selected proxy final.
  - Status: done locally.
  - Evidence: `internal/singbox/singbox_test.go::TestDockerTemplateRoutingInvariants`, `go test ./...`, and local Docker OpenVPN baseline passed.
  - Gap if any: live VPS runtime not updated.
- Requirement / AC: Prove `2ip.ru` uses domain/SNI-based RU direct routing despite non-RU CDN IP.
  - Status: done locally.
  - Evidence: local Docker logs show `sniffed protocol: tls, domain: 2ip.ru`, `rule_set=geosite-category-ru => route(direct-out)`, and direct outbound to `188.40.167.82:443`.
  - Gap if any: live VPS `2ip.ru` smoke not run due SSH reachability blocker.
- Requirement / AC: Deploy to VPS Docker runtime after local verification and verify live.
  - Status: blocked before mutation.
  - Evidence: fresh root retry of `ssh -o BatchMode=yes -o ConnectTimeout=8 vibe-practicum 'echo ok'` timed out.
  - Gap if any: VPS persisted config refresh, container recreate, and live baseline/2ip smoke remain pending.

## Acceptance verification
- AC1: Sniff route action precedes RU geosite/rule-set routing and DNS hijack remains first.
  - Covered by: targeted template invariant test and source inspection.
  - Result: passed.
  - Evidence: `go test ./internal/singbox -run TestDockerTemplateRoutingInvariants` passed in slice and root re-run.
- AC2: Full Go suite remains green.
  - Covered by: `go test ./...`.
  - Result: passed.
  - Evidence: fresh root run on 2026-06-02 passed all packages.
- AC3: Rendered config is valid for sing-box and local Docker lab stays healthy.
  - Covered by: slice `scripts/vpnkit-render-local-configs.sh`, `sing-box check`, Docker lab baseline.
  - Result: passed locally.
  - Evidence: `verification/local.md`.
- AC4: Local `2ip.ru` route proof catches sniffed domain and routes direct.
  - Covered by: OpenVPN client curl plus sing-box route logs.
  - Result: passed locally.
  - Evidence: `verification/local.md` excerpts listed above.
- AC5: VPS Docker deploy and live smoke.
  - Covered by: SSH preflight attempts only.
  - Result: blocked / not run.
  - Evidence: `verification/vps-deploy.md` and fresh root SSH retry timed out.
- AC6: Commit and push.
  - Covered by: git branch state.
  - Result: passed.
  - Evidence: `origin/main` contains source fix `0e4cbfb` and blocker evidence `b695369`; root `git status --branch --short` showed `## main...origin/main`.

## System readiness
- Routes / registration: source route rules ready; live route registration not updated.
- Services / APIs: local Docker `openvpn`, `sing-box`, and `vibe-vpn daemon` verified alive; live services not reachable for this deployment.
- Config / env / secrets: local gitignored secrets used for verification only; no secret values committed.
- Permissions / access: blocked; SSH to `vibe-practicum` times out from this host.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: local Docker ready; VPS Docker wiring pending access restoration.

## Verification run
- Local / targeted checks:
  - `go test ./internal/singbox -run TestDockerTemplateRoutingInvariants`: passed.
  - `git diff --check`: passed.
- Local / full checks:
  - `go test ./...`: passed.
- Remote checks / live runtime:
  - `ssh -o BatchMode=yes -o ConnectTimeout=8 vibe-practicum 'echo ok'`: failed with connection timeout; no VPS mutation attempted by root.
- Remote checks / CI:
  - Status: not checked separately; branch push to `origin/main` succeeded.

## Issues
### Issue R-01: Transparent redirect lacked domain context for 2ip.ru CDN IPs
- Description: current live behavior routes `2ip.ru` by resolved German CDN IP, missing RU geosite and selecting `selected-native-out`.
- Evidence: user diagnosis plus local fixed-path proof.
- Resolution: added route-action sniff for redirect/socks inbounds before RU rule-set routing and regression tests.
- Depends on: none.

### Issue U-01: VPS unreachable over SSH, blocking live deploy
- Description: deployment cannot be completed safely because the target VPS is not reachable from this host over SSH.
- Evidence: slice and fresh root SSH attempts timed out; slice also recorded ping/TCP timeout evidence.
- Why unresolved: external network/host access boundary.
- Needed next: restore SSH/reachability to `vibe-practicum`, deploy current `origin/main`, refresh `/opt/vpnkit/state/sing-box/config.json`, recreate Docker `vpnkit`, verify mounted config, baseline OpenVPN smoke, and `2ip.ru` smoke/logs.
- Depends on: none.

## Side findings
- Blocking findings folded into active work: U-01.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: partial / blocked.
- Goal state: source fix fully achieved and locally verified; live fix not achieved because VPS deployment is blocked by reachability.
- Final readiness: ready for deployment once SSH access is restored; not live-ready yet.
- Summary: The minimal sing-box 1.13 sniff fix is implemented, tested locally, committed, and pushed. The live VPS runtime remains unchanged until SSH access is available for the required Docker deploy and smoke checks.

## Next-agent brief
- Objective: finish VPS Docker deployment of current `origin/main`.
- Target: `vibe-practicum` `/opt/vpnkit` Docker runtime and persisted `/opt/vpnkit/state/sing-box/config.json`.
- Settled already: source/test fix and local Docker route proof are complete.
- Boundaries: no Steam Deck, no native service changes, no secrets/logs committed.
- Verification target: live mounted config contains sniff + RU rules; baseline OpenVPN smoke passes; `curl https://2ip.ru/` through OpenVPN reports `45.12.74.211` or logs prove `2ip.ru` geosite direct-out.
- Expected output: update `verification/vps-deploy.md` and return final live readiness report.
