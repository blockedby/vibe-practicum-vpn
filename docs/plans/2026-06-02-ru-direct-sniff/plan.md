# Plan: RU direct sniff post-deploy fix

## Task intake
- Goal: fix live Docker/vpnkit RU direct behavior for domains such as `2ip.ru` whose resolved CDN IPs are not RU geoip by adding sing-box 1.13 route `sniff` action before RU geosite/rule-set routing.
- In scope: `config/sing-box/config.json.template`, regression tests, task package evidence, local Docker lab, VPS Docker runtime deploy after local verification.
- Out of scope: Steam Deck, native VPS services, secrets/generated profiles/logs, broad routing refactors.
- Done-state: main has a coherent committed/pushed fix; local and live checks prove DNS hijack/default proxy remain green and `2ip.ru` routes direct / sees VPS IP.
- Blocking unknowns: local Docker/VPS connectivity and exact `2ip.ru` response format may vary; use logs and IP evidence if page content is hard to parse.

## Repo orientation
- Root guidance: Docker local lab required before VPS mutation for vpnkit routing; refresh persisted live sing-box config intentionally; no secrets/logs/generated artifacts committed; Steam Deck is Podman only and out of scope.
- Existing template: `config/sing-box/config.json.template` route rules start with DNS hijack, then `geoip-ru` and `geosite-category-ru`, final `selected-native-out`.
- Existing tests: `internal/singbox/singbox_test.go::TestDockerTemplateRoutingInvariants` parses template with placeholder substitution and asserts DNS/RU/final invariants.
- Existing sing-box examples: `configs/sing-box/tproxy-canary.json` uses route rule `{ "inbound": [...], "action": "sniff", "timeout": "1s" }` before domain rules.

## Reuse discovery
- Reuse route action sniff syntax already tracked in `configs/sing-box/tproxy-canary.json` and `configs/sing-box/local/kcnc-pc-safe-tun.json`.
- Reuse existing `direct-out`, `selected-native-out`, remote RU rule sets, and template test helpers.
- Reuse AGENTS local Docker lab commands and live client-test helper.

## Missing pieces
- Add sniff rule scoped to `vpnkit-redirect-in` and `vpnkit-socks-in` after DNS hijack rules and before RU rules.
- Update regression test to assert sniff ordering and absence of deprecated inbound sniff config.
- Verify config with sing-box 1.13 and Docker lab before live deploy.
- Refresh live persisted config and verify `2ip.ru` direct behavior.

## Plan tasks

### Task 1: Add sniff route action and regression coverage
- Goal: add minimal sing-box 1.13 route sniff action and tests.
- Acceptance criteria: DNS hijack rules first; sniff rule for redirect/socks inbounds comes before `geosite-category-ru`; RU rules/final preserved; no deprecated inbound sniff fields; `go test ./...` passes; `sing-box check` passes on rendered candidate.
- Test plan: targeted `go test ./internal/singbox -run TestDockerTemplateRoutingInvariants`; `go test ./...`; render/check config.
- Dependencies: none.
- Executor: owner-level tiny edit (delegation overhead not justified for two-file config/test change in user-specified main worktree).
- Status: done. Evidence: `verification/local.md`.

### Task 2: Local Docker lab acceptance
- Goal: prove local vpnkit runtime still starts and client baseline remains green.
- Acceptance criteria: render local configs; clean compose state; vpnkit starts with OpenVPN/sing-box/vibe-vpn; client test gets `10.89.0.2/24`, DNS `NOERROR`, HTTPS `200`, literal-IP HTTPS `200`.
- Test plan: AGENTS Docker lab commands; use alternate host port only if default port conflict occurs and record it.
- Dependencies: Task 1.
- Executor: owner.
- Status: done. Evidence: `verification/local.md`; default host UDP 1194 was occupied, so local compose used `VPNKIT_OPENVPN_PORT=1196`.

### Task 3: VPS Docker deploy and live verification
- Goal: deploy only after local success, refresh persisted live config, verify `2ip.ru` direct behavior and baseline smoke.
- Acceptance criteria: live container uses refreshed config with sniff + RU rules; baseline OpenVPN smoke green; `2ip.ru` through VPN sees `45.12.74.211` or logs prove direct-out; no Steam Deck/native changes; commit pushed to main.
- Test plan: sync/build/recreate existing Docker topology; grep mounted config; live client smoke with baseline and 2ip curl; inspect sanitized logs.
- Dependencies: Task 1, Task 2.
- Executor: owner.
- Status: blocked. Evidence: `verification/vps-deploy.md`; SSH/network access to `vibe-practicum` timed out before any remote mutation.

## Dependency graph
- Task 1 -> Task 2 -> Task 3 -> final report.

## Execution ledger
- 2026-06-02: Task package and executable plan created. Pre-dispatch/implementation gate satisfied; slice kept whole, with tiny owner-level source/test edit to avoid unnecessary delegation in a user-specified main worktree.
- 2026-06-02: Added route-action sniff rule after DNS hijack and before RU rules; updated template invariant regression.
- 2026-06-02: Local verification passed: targeted Go test, `go test ./...`, rendered sing-box config check with compatibility env, Docker lab baseline client, and local 2ip.ru route logs showing sniffed SNI `2ip.ru` matched `geosite-category-ru` and routed `direct-out`.
- 2026-06-02: Committed and pushed source/test/task-package fix to main at `0e4cbfb`.
- 2026-06-02: VPS deploy blocked before mutation because SSH/network access to `vibe-practicum` timed out. See `verification/vps-deploy.md` and `reports/aad-slice-owner.md`.

## Current done-state
- Source fix: done and pushed (`0e4cbfb`).
- Local acceptance: done.
- Live deploy: blocked before mutation by VPS reachability timeout.
- Open issue: U-01 in `reports/aad-slice-owner.md`.
