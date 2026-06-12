# Acceptance plan: production Docker deploy/rollback tooling

## Audit scope
- Re-audit current HEAD for tooling-only acceptance of the production deploy helper redesign.
- Specifically confirm whether the prior partials are closed:
  - rollback release-pointer restoration
  - explicit TUN mode restore/enforcement
- No live production mutation, no private endpoint reads/prints, no secrets.

## Evidence route used
1. Inspect `scripts/vpnkit/vpnkit-prod-deploy.sh` for rollback pointer handling and TUN override enforcement.
2. Inspect `test/prod-deploy-helper-test.sh` for direct behavioral assertions.
3. Run fresh local checks on current HEAD:
   - `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh`
   - `test/prod-deploy-helper-test.sh`
   - `git diff --check`
4. Record pass/partial/fail mapping in `reports/acceptance-auditor-prod-deploy-redesign.md`.

## Decision rule
- Mark a prior partial as closed only when both code and a fresh local test assert the behavior.
- Keep live production readiness out of scope for this audit.

## Result
- Fresh local checks passed.
- The two prior partials are closed in current HEAD.
- Report updated at `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/reports/acceptance-auditor-prod-deploy-redesign.md`.
