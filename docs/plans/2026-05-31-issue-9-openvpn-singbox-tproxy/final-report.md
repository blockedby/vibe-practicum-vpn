## Task
- Mission: Own and run the AAD flow for GitHub issue #9 through discovery, acceptance refinement, slicing, repo-side preparation, and readiness decision for live implementation.
- Target: OpenVPN dynamic-pool clients (`ignat`, observed `10.89.0.23`) routed via `tun-asus -> TPROXY :2082 -> sing-box native VLESS`, with DNS under sing-box rules and no broad NAT final success.
- Boundaries: No xray-based solution; no broad VPS NAT as success; no live VPS mutation after discovery because no active dynamic client traffic was present; no secrets in repo/report.
- Done when: Current evidence is integrated, repo-side runbook/docs are ready, and the next live action is explicit.
- Expected evidence: Task package, agent reports, verification artifacts, PR, and acceptance audit.

## Context
- Thread: User-requested AAD flow for https://github.com/blockedby/vibe-practicum-vpn/issues/9.
- Task name: Issue #9 OpenVPN dynamic clients through sing-box TPROXY/VLESS.
- Task package: `docs/plans/2026-05-31-issue-9-openvpn-singbox-tproxy`.
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-9-openvpn-singbox-tproxy`.
- Branch: `issue-9-openvpn-singbox-tproxy`.
- PR: https://github.com/blockedby/vibe-practicum-vpn/pull/10 (draft).

## Slice structure used
- Slice A: `aad-explorer` read-only live discovery first. Reason: live state was uncertain and VPS mutation before current evidence would be unsafe.
- Slice B: `aad-slice-owner` repo-side plan/docs/runbook. Reason: after discovery, a single ownership boundary covered acceptance refinement and safe reproducibility changes; live mutation remained gated.
- Acceptance audit: `aad-acceptance-auditor`. Reason: independent readiness check was useful before reporting root done-state.
- Root integration: root owner integrated reports, ran fresh verification, pushed draft PR, and decided final state.

## Spec compliance
- AC1 dynamic client lease: partial. Evidence: `reports/live-discovery.md` found `ignat -> 10.89.0.23`; no active client session at capture time.
- AC2 TPROXY/INPUT local delivery: partial/passed for wiring. Evidence: live discovery found dynamic-pool PREROUTING, INPUT accept for mark `0x1`, table 100, and sing-box `:2082`; no live packet counter proof.
- AC3 DNS under sing-box rules: partial. Evidence: repo docs/runbook now require sing-box `hijack-dns`/DNS rules; live config still had direct elements and no DNS packet proof.
- AC4 UDP-over-VLESS/DNS transport: partial. Evidence: live outbound is native VLESS and runbook defines proof/fallback; no active-client UDP/DNS proof yet.
- AC5 TCP/HTTPS after DNS: not proven. Evidence: Slice A tcpdump saw `0 packets` because client was inactive.
- AC6 no broad NAT final success: partial. Evidence: broad NAT fallback was detected and explicitly excluded from acceptance; final path still needs live proof.
- AC7 intended sing-box service: mostly passed. Evidence: `sing-box-vibe-router` active, package `sing-box.service` masked/inactive, one sing-box process; legacy `xray.service` remains a side finding.
- AC8 docs/reproducibility: passed for repo-side readiness. Evidence: PR #10 updates docs/config example/runbook and task package.

## Acceptance verification
- Accepted now: Slice B repo-side preparation and gated live Slice C readiness.
- Not accepted now: full root issue closure.
- Independent audit: `reports/acceptance-auditor.md` verdict was “accepted with limitations”; root issue #9 is not fixed yet because AC3-AC6 lack fresh active-client proof.

## System readiness
- Routes / registration: live wiring observed; dynamic-pool INPUT delivery documented.
- Services / APIs: `sing-box-vibe-router` is intended service; `sing-box.service` masked; xray remains legacy side service, not route success.
- Config / env / secrets: no secrets committed; config example validates locally with `sing-box check`; live DNS final decision pending.
- Runtime / deployment wiring: live Slice C runbook includes backup, `sing-box check`, rollback, DNS/HTTPS captures, and no-NAT success gate.

## Verification run
- Fresh root checks passed:
  - `go test ./...`
  - `go vet ./...`
  - `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`
  - `jq . configs/sing-box/tproxy-canary.json >/dev/null`
  - `sing-box check -c configs/sing-box/tproxy-canary.json` with local sing-box 1.13.12
  - `bash -n scripts/openvpn-asus-tproxy-canary-rules.sh`
- Remote checks / CI: PR #10 has no status checks reported yet (`statusCheckRollup: []`).

## Issues
### U-01: Active dynamic-client proof is missing
- Description: No active `ignat` traffic was present during discovery.
- Evidence: Slice A tcpdump on `tun-asus` captured `0 packets`; OpenVPN status had no current rows.
- Why unresolved: final DNS/TCP path cannot be proven without active client traffic.
- Needed next: connect `ignat`/dynamic client and run live Slice C AC3-AC6 proof.

### U-02: Live DNS final state still needs decision/proof
- Description: live config had sing-box `hijack-dns` plus direct `yandex-basic`/pushed public DNS elements.
- Evidence: `reports/live-discovery.md`.
- Why unresolved: no live mutation was made without active client/proof window.
- Needed next: under Slice C, backup config, adjust DNS to sing-box-governed final path if needed, validate/reload/restart minimally, and prove DNS reply on `tun-asus OUT`.

## Side findings
- Broad `10.89.0.0/24 -> eth0 MASQUERADE`/FORWARD fallback exists; it is emergency/diagnostic only and not success evidence.
- Legacy `xray.service` remains active on `10808`; non-blocking for this prepared state, but not part of issue #9 success path.

## Verdict
- Status: partial.
- Goal state: repo-side AAD flow and live Slice C readiness achieved; root issue #9 not fully achieved.
- Final readiness: ready for gated live Slice C when a dynamic client is actively connected.
- Summary: We created the AAD task package, refined AC1-AC8, performed read-only live discovery, updated repo docs/config/runbook in PR #10, verified locally, audited acceptance, and stopped before live mutation because active-client evidence was unavailable.

## Next-agent brief
- Objective: Live Slice C — prove/fix DNS and TCP/HTTPS for active dynamic OpenVPN client.
- Target: `vibe-practicum`, `tun-asus`, `/etc/sing-box-vibe/tproxy-canary.json`, `sing-box-vibe-router`, dynamic client `ignat`/current pool IP.
- Settled already: xray is deprecated/not success path; DNS final policy belongs to sing-box rules; dynamic-pool INPUT accept is required; broad NAT is not final success.
- Boundaries: backup before config edits; redact secrets; validate with `sing-box check`; rollback ready; do not count NAT-only connectivity.
- Verification target: `verification/slice-b-local.md` AC1-AC8 proof map.
- Expected output: live evidence report with exact commands, changes, backup/rollback path, DNS query/reply on `tun-asus`, HTTPS response return, and final done-state.
