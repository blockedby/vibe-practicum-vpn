## Task
- Mission: Implement mode-aware vpnkit readiness, Compose `OVPN_CIDR` wiring, public docs, and practical tests for Slice 1.
- Target: `docker/vpnkit/entrypoint.sh`, `docker-compose.yml`, `docs/DOCKER_SETUP.md`, `tests/vpnkit-production-routing-wiring-test.sh`.
- Boundaries: Repository-only work; no production SSH/deploy; no secrets/private endpoint output.
- Done when: AC1-AC5 are locally verified and changes are ready for PR/merge.
- Expected evidence: Fresh local commands and verification artifact.

## Context
- Thread: production-only vpnkit wiring follow-up.
- Slice: repository implementation, PR, and merge.
- Task package: `docs/plans/2026-06-08-production-routing-wiring-followup`.
- Report path: `docs/plans/2026-06-08-production-routing-wiring-followup/reports/aad-implementer-repo-wiring.md`.
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/prod-routing-wiring-followup`.
- Branch: `prod-routing-wiring-followup`.
- Verify scope: local repo implementation/tests only.

## Spec compliance
- AC1 branch/worktree isolation: done.
  - Evidence: work performed in delegated worktree on `prod-routing-wiring-followup`.
- AC2 mode-aware readiness: done.
  - Evidence: `wait_for_singbox_inbounds` dispatches `tun` to `ip link show ${SINGBOX_TUN_IFACE:-sb-tun0}`, `tproxy` to TCP 2082, and `redirect|*` to TCP 2082 plus UDP 5353.
- AC3 Compose `OVPN_CIDR`: done.
  - Evidence: `docker-compose.yml` passes `OVPN_CIDR: "${OVPN_CIDR:-10.89.0.0/24}"`.
- AC4 public docs/config examples: done.
  - Evidence: `docs/DOCKER_SETUP.md` documents redirect-mode consistency and `OVPN_CIDR` override behavior without private values.
- AC5 practical tests/checks: done.
  - Evidence: syntax, targeted wiring, compose config, and existing routing compatibility checks passed.
- AC6 PR/merge: not applicable to implementer-local work; pending slice-owner finalization.

## Acceptance verification
- AC1: Covered by branch/worktree status. Result: passed.
- AC2: Covered by `./tests/vpnkit-production-routing-wiring-test.sh`. Result: passed.
- AC3: Covered by targeted test and `docker compose config --format json` assertion. Result: passed.
- AC4: Covered by targeted docs assertions. Result: passed.
- AC5: Covered by commands in `verification/repo-local.md`. Result: passed.
- AC6: Result: not run in implementer phase; owner handles commit/push/PR/merge.

## System readiness
- Runtime / deployment wiring: repo wiring ready for local Docker-lab/deploy continuation after merge.
- Config / env / secrets: public-safe defaults only; production override remains via local `.env`.
- Services / APIs / database / frontend: not relevant.

## Verification run
- Local / targeted checks:
  - `bash -n docker/vpnkit/entrypoint.sh docker/vpnkit/setup-routing.sh scripts/*.sh tests/*.sh`: passed.
  - `./tests/vpnkit-production-routing-wiring-test.sh`: passed.
  - `./scripts/vpnkit-routing-compat-bypass-test.sh`: passed.
  - `docker compose config --format json` sanitized `OVPN_CIDR` assertion: passed.
- Remote checks / CI: not available before push/PR.

## Issues
- No R/F/U issues beyond the resolved requested implementation work.

## Side findings
- Blocking findings folded into active work: none.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: success for local implementation.
- Goal state: AC1-AC5 achieved locally; AC6 remains with slice owner.
- Final readiness: ready for commit/push/PR/merge finalization.
