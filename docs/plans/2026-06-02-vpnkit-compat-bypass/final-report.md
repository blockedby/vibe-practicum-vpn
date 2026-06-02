## Task
- Mission: Implement compatibility-mode support for vpnkit scoped direct bypass to nested OpenVPN endpoint `vpn.proofix.tv:1194` with optional ICMP while preserving redirect-mode sing-box TCP+DNS behavior.
- Target: `docker/vpnkit/setup-routing.sh`, docker compose env wiring, runbook docs, lightweight routing tests.
- Boundaries: No secrets/generated profiles/logs; no live VPS mutation; no broad direct OpenVPN-client NAT.

## Context
- Task package: `docs/plans/2026-06-02-vpnkit-compat-bypass`
- Worktree: `.worktrees/vpnkit-compat-bypass`
- Branch: `vpnkit-compat-bypass`
- PR: https://github.com/blockedby/vibe-practicum-vpn/pull/16 (draft)
- Implementation report: `reports/aad-implementer-routing.md`

## Spec compliance
- Scoped bypass for nested work OpenVPN endpoint: done.
  - Evidence: `VPNKIT_COMPAT_BYPASS_ENABLED`, `VPNKIT_COMPAT_BYPASS_ENDPOINTS`, endpoint parsing/resolution, and endpoint-specific `RETURN`/`FORWARD`/`MASQUERADE` rules in `docker/vpnkit/setup-routing.sh`.
- `vpn.proofix.tv:1194` default with UDP assumption and explicit proto config: done.
  - Evidence: compose default `VPNKIT_COMPAT_BYPASS_ENDPOINTS=vpn.proofix.tv:1194`; parser defaults proto to UDP and supports `/tcp`, `/udp`, and `tcp://...` forms.
- Optional direct ICMP: done.
  - Evidence: `VPNKIT_COMPAT_BYPASS_ALLOW_ICMP=false` default; true adds endpoint-IP-scoped ICMP rules only.
- Preserve TCP+DNS through sing-box in redirect mode: done.
  - Evidence: redirect-mode TCP and UDP/53 REDIRECT rules remain after compatibility `RETURN` rules.
- Avoid broad direct VPS NAT: done.
  - Evidence: no broad `POSTROUTING -s 10.89.0.0/24 -j MASQUERADE`; NAT happens only inside endpoint-specific compatibility chain rules.

## Acceptance verification
- `bash -n docker/vpnkit/setup-routing.sh scripts/vpnkit-routing-compat-bypass-test.sh`: passed.
- `bash scripts/vpnkit-routing-compat-bypass-test.sh`: passed.
- `docker compose config >/tmp/vpnkit-compose-config-owner.out`: passed.
- `git diff --check`: passed.
- Broad NAT grep over routing/compose source: passed/no matches.
- `shellcheck docker/vpnkit/setup-routing.sh scripts/vpnkit-routing-compat-bypass-test.sh`: not run; `shellcheck` unavailable in this environment.
- PR checks: none reported by `gh pr view`.

## Issues
- R-01: Compatibility bypass implemented and verified with static/dry-run tests.
- No unresolved current-goal issues.
- No non-blocking follow-up issue created; shellcheck absence is an environment limitation, while required `bash -n` coverage passed.

## Verdict
- Status: success.
- Goal state: achieved with local static/dry-run verification.
- System readiness: ready for PR review; no live runtime/VPS validation was performed or required by this slice.
