## Task
- Mission: Fix post-deploy RU-direct behavior for `2ip.ru` by adding sing-box 1.13 route-action sniffing before RU geosite/rule-set routing, then verify and deploy if safe.
- Target: `config/sing-box/config.json.template`, `internal/singbox/singbox_test.go`, local Docker vpnkit lab, VPS Docker `vpnkit` runtime.
- Boundaries: no Steam Deck, no native service changes, no committed secrets/logs/generated artifacts, no broad routing refactor.
- Done when: source/test fix is on main, local evidence proves sniffed `2ip.ru` routes direct, and VPS deploy/live smoke passes or a real external blocker is recorded.
- Expected evidence: Go tests, sing-box check, Docker lab baseline, `2ip.ru` route logs, deploy/live smoke or blocker evidence.

## Context
- Thread: delegated post-deploy RU-direct sniff fix.
- Slice: single slice; kept whole. Implementation was a tiny owner-level edit in the user-specified main worktree; no sub-slices or implementer delegation used.
- Task package: `docs/plans/2026-06-02-ru-direct-sniff`
- Report path: `docs/plans/2026-06-02-ru-direct-sniff/reports/aad-slice-owner.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn`
- Branch: `main`
- Commit/push: `0e4cbfb Add vpnkit RU domain sniff routing`, pushed to `origin/main`.

## Spec compliance
- Requirement / AC: Add valid sing-box 1.13 route sniff action before RU geosite/domain routing, not deprecated inbound sniff.
  - Status: done.
  - Evidence: `config/sing-box/config.json.template` now has `{ "inbound": ["vpnkit-redirect-in", "vpnkit-socks-in"], "action": "sniff", "timeout": "1s" }` after DNS hijack rules and before RU rule sets; `sing-box check` passed.
  - Gap if any: none.
- Requirement / AC: Preserve DNS hijack, RU direct, and default proxy behavior.
  - Status: done locally.
  - Evidence: `TestDockerTemplateRoutingInvariants`, Docker lab baseline `10.89.0.2/24`, DNS `NOERROR`, HTTPS `200`, literal-IP HTTPS `200`.
  - Gap if any: live VPS not updated due SSH timeout.
- Requirement / AC: Prove `2ip.ru` catches domain/SNI and routes direct.
  - Status: done locally.
  - Evidence: Docker lab logs show `sniffed protocol: tls, domain: 2ip.ru`, then `match[4] rule_set=geosite-category-ru => route(direct-out)`, then `outbound/direct[direct-out]: outbound connection to 188.40.167.82:443`.
  - Gap if any: live VPS smoke not run due SSH timeout.
- Requirement / AC: Deploy VPS Docker runtime after local verification.
  - Status: blocked before mutation.
  - Evidence: SSH to `vibe-practicum` timed out; see `verification/vps-deploy.md`.
  - Gap if any: remote deploy and live smoke remain pending.

## Acceptance verification
- AC1: Template has route-action sniff after DNS hijack and before RU geosite/rule-set rules.
  - Covered by: source diff, `TestDockerTemplateRoutingInvariants`, `sing-box check`.
  - Result: passed locally.
  - Evidence: `go test ./internal/singbox -run TestDockerTemplateRoutingInvariants`; `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true sing-box check -c secrets/vps/rendered/sing-box/config.json`.
- AC2: DNS hijack/RU/final behavior preserved.
  - Covered by: regression test and Docker client baseline.
  - Result: passed locally.
  - Evidence: `go test ./...`; Docker client got `10.89.0.2/24`, DNS `NOERROR`, HTTPS `200`, literal-IP `200`.
- AC3: `2ip.ru` hosted on non-RU IP routes direct via sniffed domain/SNI.
  - Covered by: local Docker OpenVPN client curl and sing-box logs.
  - Result: passed locally.
  - Evidence: `2ip code=200 remote_ip=188.40.167.82`; logs show sniffed `2ip.ru` matched `geosite-category-ru` and routed `direct-out`.
- AC4: VPS Docker runtime deployed/refreshed and live smoke green.
  - Covered by: attempted SSH preflight.
  - Result: blocked / not run.
  - Evidence: SSH/network timeout before mutation; no live deploy attempted.
- AC5: Main commit and push.
  - Covered by: git commit/push.
  - Result: passed.
  - Evidence: `0e4cbfb` pushed `d816ffe..0e4cbfb main -> main`.

## System readiness
- Routes / registration: source ready; live runtime not updated.
- Services / APIs: local Docker `openvpn`, `sing-box`, and `vibe-vpn daemon` ran successfully; live not checked after source change.
- Config / env / secrets: source template ready; gitignored local secrets used only for rendering/test; no secret values committed.
- Permissions / access: blocked for VPS SSH (`45.12.74.211:22` timed out).
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: local Docker ready; live Docker deploy pending access restoration.

## Verification run
- Local / targeted checks:
  - `go test ./internal/singbox -run TestDockerTemplateRoutingInvariants`: passed.
  - `scripts/vpnkit-render-local-configs.sh`: passed after restoring gitignored local secrets.
  - `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true sing-box check -c secrets/vps/rendered/sing-box/config.json`: passed with only known deprecation warnings.
- Local / full checks:
  - `go test ./...`: passed.
  - Docker lab with `VPNKIT_OPENVPN_PORT=1196`: passed baseline and local `2ip.ru` route proof.
- Remote checks / live runtime:
  - SSH preflight to `vibe-practicum`: failed / timed out; deploy not attempted.
- Remote checks / CI:
  - Status: not checked separately; main push succeeded.

## Issues
### Issue R-01: Transparent redirect lacked domain context for non-RU CDN IPs
- Description: `2ip.ru` resolved to IPs such as `188.40.167.82`; without sniffing, transparent redirect matched only IP and missed RU geosite routing.
- Evidence: user diagnosis plus local reproduction after fix showing the same IP can be routed direct once SNI is sniffed.
- Resolution: added sing-box route-action `sniff` for `vpnkit-redirect-in` and `vpnkit-socks-in` before RU rule-set routing.
- Depends on: none.

### Issue U-01: VPS SSH/network access unavailable, blocking live deploy
- Description: live deployment and live `2ip.ru` smoke could not be run because the VPS was not reachable over SSH from this host.
- Evidence: `ssh -o ConnectTimeout=10 vibe-practicum 'echo ok'` timed out; ping to `45.12.74.211` had 100% loss; TCP probes to 22/1194 timed out.
- Why unresolved: external network/host access blocker; continuing would require reachable SSH or alternate deployment access.
- Needed next: restore/confirm VPS SSH reachability, then deploy commit `0e4cbfb`, refresh persisted `/opt/vpnkit/state/sing-box/config.json`, recreate Docker `vpnkit`, and run live baseline + `2ip.ru` OpenVPN smoke.
- Depends on: none.

## Side findings
- Blocking findings folded into active work: U-01.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: partial / blocked.
- Goal state: source fix fully achieved and pushed; live deploy not achieved due external VPS access timeout.
- Final readiness: ready for deployment once VPS SSH is reachable; not live-ready until deployed and smoked.
- Summary: The minimal sing-box 1.13 sniff fix is implemented, tested locally, and pushed to main at `0e4cbfb`; VPS deployment was safely skipped because the target host was unreachable.

## Next-agent brief
- Objective: finish live deployment of `0e4cbfb` to VPS Docker `vpnkit`.
- Target: `vibe-practicum` `/opt/vpnkit` Docker runtime and persisted `/opt/vpnkit/state/sing-box/config.json`.
- Settled already: source/test fix is correct locally; local Docker proves `2ip.ru` SNI is sniffed and routes `direct-out`.
- Boundaries: no Steam Deck, no native services, no secrets/logs committed.
- Verification target: mounted live config contains sniff + RU rules; baseline OpenVPN client smoke green; `curl https://2ip.ru/` through OpenVPN reports `45.12.74.211` or logs prove `2ip.ru` geosite direct-out.
- Expected output: update `verification/vps-deploy.md` and report final live readiness.
