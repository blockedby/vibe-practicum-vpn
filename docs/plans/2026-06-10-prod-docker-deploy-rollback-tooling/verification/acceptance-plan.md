# Acceptance plan: production Docker deploy/rollback tooling

## Audit scope
- Evaluate AC1-AC9 from `plan.md` for repo-safe tooling readiness only.
- Do not treat live production deploy/rollback readiness as accepted; no production mutation or private endpoint probing.
- Re-audit focus: confirm whether prior AC3 and AC8 partials are now closed by the audit-gap fixes, using fresh local evidence only.

## Evidence sources to inspect
- `scripts/vpnkit/vpnkit-prod-deploy.sh`
- `test/prod-deploy-helper-test.sh`
- `README.md`
- `config/private-endpoints.example.env`
- `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/reports/slice-owner-deploy-tooling.md`
- `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/verification/local.md`
- branch/push status from git metadata

## Verification route
1. Map each AC to concrete code/doc/test/report evidence.
2. Check freshness of targeted local checks already recorded.
3. Flag any AC where evidence is only descriptive, stale, or missing mocked/behavioral coverage.
4. Separate tooling readiness from live production readiness.

## Acceptance decision rules
- Mark AC as pass only if there is direct evidence that the tracked tooling/docs/tests support the criterion.
- Mark AC as partial if the code is present but evidence is descriptive only, incomplete, or missing feasible mocked coverage.
- Mark AC as fail if the criterion is contradicted by code/docs/tests or if the report overclaims beyond the evidence.

## Planned report output
- Write findings to `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/reports/acceptance-auditor.md`.
