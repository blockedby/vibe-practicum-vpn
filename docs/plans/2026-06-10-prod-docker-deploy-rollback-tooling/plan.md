# Plan: Production Docker deploy/rollback tooling

## Goal

Implement repo-safe, repeatable, one-button production Docker/Compose deploy and rollback tooling for `vpnkit` before any real production mutation occurs.

## Scope

In scope:
- Add a public-safe deploy helper (preferred `scripts/vpnkit-prod-deploy.sh`) with `plan`/`dry-run`, `deploy --yes --target-ref <ref> <host...>`, `rollback --yes <host...>`, and `verify <host...>` style flows.
- Default-safe behavior: dry-run/plan by default, refusal for mutating actions without `--yes`, bounded remote command timeouts, redaction, no private endpoints/secrets/log payloads printed or committed.
- Host inputs from CLI/env/gitignored `config/private-endpoints.local.env`; update tracked example keys only with placeholders if useful.
- Remote discovery of repo/Compose workdir, Compose project/service/container from Docker Compose labels or approved env overrides; avoid hard-coded production paths.
- Deploy flow: backup rollback bundle, fetch/checkout target ref, refresh/check persisted sing-box config, rebuild/recreate only vpnkit service/container, run partial smoke, auto-rollback on failed smoke, post-rollback smoke, nonzero on failed deploy/rollback smoke.
- Rollback flow using latest or explicit rollback bundle.
- Multi-host sequential behavior with stop-on-first-failed-host after rollback.
- README/runbook docs and feasible tests/static checks.

Out of scope:
- No production deploy, rollback, restart, compose up/down, remote mutation, endpoint probing, or reading/printing private endpoint values in this task.
- No unrelated runtime/routing behavior changes.
- No secrets, real hostnames/IPs, rendered configs, profiles, logs, snapshots, or image exports in tracked files.

## Acceptance criteria

AC1. A tracked deploy helper exists with safe subcommands for planning/dry-run, deploy, rollback, and verify, with mutating commands refusing unless `--yes` is passed.
AC2. Deploy design implements backup -> fetch/checkout target ref -> config refresh/check -> rebuild/recreate vpnkit service -> smoke -> automatic rollback on failed smoke -> post-rollback smoke.
AC3. Rollback bundles are created under a remote `.rollback/vpnkit/<timestamp>/`-style location and include current git ref, image metadata/tag/id where available, compose/env references, current runtime sing-box config, container inspect metadata, and an executable rollback payload without printing secret config contents.
AC4. Remote repo/Compose service discovery uses Docker/Compose labels and/or approved env overrides; no hard-coded production workdir/endpoint values.
AC5. Smoke checks cover at minimum container running, UDP 1194 published/listening, OpenVPN process and `tun0`, sing-box process and `sb-tun0` for tun mode, policy rule/table, and `sing-box check` when available; optional network checks are bounded and safe.
AC6. Multi-host deploy is sequential and stops on first host failure after rollback; there is no partial silent success.
AC7. Tracked docs explain setup, plan/dry-run, deploy, rollback, verify, env placeholders, production approval boundary, and public-safety rules.
AC8. Tests/checks cover shell syntax and safe argument/redaction/refusal behavior; mocked SSH/Docker/Compose tests are added where feasible.
AC9. Changes are committed and pushed to `feat/issue-24-smart-routing-manifest` if verification passes.

## Ownership model

Single slice: deployment tooling and runbook. The work has one system boundary (operator tooling/docs/tests) and one verification story (static/unit-style checks plus no live production mutation). A single `aad-slice-owner` should own implementation and may delegate internally.

## Delegated slice

### Slice: deploy-tooling

Goal:
- Make the repo contain a safe, documented, test-backed deploy/rollback helper meeting AC1-AC9 without mutating production.

Boundary:
- Likely files: `scripts/vpnkit-prod-deploy.sh`, `README.md`, `docs/*` runbook if appropriate, `config/private-endpoints.example.env`, `test/*` or existing shell test harness.
- Reuse patterns: `scripts/vpnkit-prod-singbox-dns-migration.sh`, public-safety/redaction patterns in existing scripts/tests, AGENTS production checklist.
- Do not touch production endpoints, private local env values, generated profiles/configs, or unrelated runtime logic.

Verification plan:
- `bash -n scripts/*.sh` or narrower syntax checks as appropriate.
- Targeted shell tests for argument parsing/refusal/redaction/host list and mocked SSH/remote commands if feasible.
- Static grep/manual checks proving no real endpoints/secrets are added and no hard-coded production paths.
- Optional existing local checks only if directly relevant and cheap.

Report path:
- `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/reports/slice-owner-deploy-tooling.md`

Status:
- pending delegation

## Execution ledger

2026-06-10 deploy-tooling slice owner update:
- Implemented `scripts/vpnkit-prod-deploy.sh` with `plan`/`dry-run`, `deploy --yes --target-ref`, `rollback --yes`, and `verify` flows.
- Added `test/prod-deploy-helper-test.sh` for local refusal/redaction/host-list coverage.
- Updated `README.md` and `config/private-endpoints.example.env` with public-safe usage and placeholder env knobs.
- Verification evidence recorded in `verification/local.md`.
- No production deploy/rollback/verify/probe was run.
