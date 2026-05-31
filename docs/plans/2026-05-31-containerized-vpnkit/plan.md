# Plan: containerized vpnkit OpenVPN -> sing-box lab

## Intake
- Goal: add safe repo scaffolding for a Dockerized `vpnkit` gateway running OpenVPN server plus one sing-box TPROXY/VLESS config, with a separate `ovpn-client-test` container for validation.
- In scope: Dockerfiles, compose, entrypoints/routing/test scripts, sanitized templates, docs/runbook, operator-bound secret copy/render/profile generation workflow.
- Out of scope: committing real secrets, xray runtime paths for this lab, broad permanent NAT bypass for `10.89.0.0/24`, mutating VPS or running production SSH/SCP automatically, unrelated Go behavior changes.
- Done state: repo contains executable scaffolding and runbook; safe local syntax/compose checks pass; live VLESS ACs are either evidenced or explicitly pending operator-provided secrets/live run.
- Blocking unknowns: real copied VPS config/secrets are unavailable in this worktree; live privileged Docker run may be unsafe/unavailable, so runtime acceptance may remain pending with exact commands.

## Repo orientation and reuse
- Repo is Go CLI/tooling plus operational docs/scripts. Existing shell scripts use `#!/usr/bin/env bash` and `set -euo pipefail`.
- `.gitignore` already ignores `secrets/`, `*.key`, `*.conf`; sanitized templates should avoid `.conf` suffix if they need tracking or be force-added only if safe.
- Existing relevant docs: `docs/OPENVPN_ASUS_TPROXY_CANARY.md`, `docs/TPROXY_CANARY.md`, `configs/sing-box/tproxy-canary.json` (tracked sample; inspect before reuse to avoid secrets).
- Verification defaults: `bash -n`, `docker compose config` if available, `grep` for forbidden NAT/secret patterns, optional `go test ./...` because Go should not change.

## Missing pieces
- `docker/vpnkit` image, entrypoint, routing setup, render/helper scripts.
- `docker/ovpn-client-test` image, entrypoint, validation runner.
- Compose file linking gateway and test client via Docker networking.
- Sanitized config templates for OpenVPN server/client and sing-box lab shape.
- Operator runbook/scripts for copying from documented VPS paths into gitignored `secrets/vps/...`, rendering local configs, generating client profile, running and collecting validation evidence.

## Plan tasks

### Task 1: Container lab scaffolding and safe operator workflow
Goal:
- Make the Dockerized gateway/test-client lab runnable by an operator with local secrets while keeping committed files sanitized.
Boundary:
- System area: Docker/runtime wiring and shell scripts/docs.
- Primary verification: shell syntax, compose config validation, static inspection for forbidden NAT and secrets.
Existing pattern / reuse:
- Follow existing script style in `scripts/*.sh`; reuse plan's OpenVPN/TPROXY commands; avoid xray paths.
Missing change:
- Add Dockerfiles, entrypoints, routing/test/render/copy scripts, templates, compose, and runbook/report evidence mapping.
Scope / likely files:
- `docker/vpnkit/**`, `docker/ovpn-client-test/**`, `config/**` or `templates/**`, `scripts/*vpnkit*`, `docker-compose.yml`, `docs/*VPNKIT*`.
Acceptance criteria:
- AC 1-11 are mapped to implemented artifact or pending live/operator action.
- No committed real secrets or full profiles; real inputs stay under `secrets/`.
- No permanent broad NAT bypass for `10.89.0.0/24`.
- Test client uses `remote vpnkit 1194 udp` and runs in separate container.
- sing-box config path uses native VLESS outbound from local rendered secrets, one process, inbound/tproxy `:2082`, DNS rules.
Test plan:
- Positive: `bash -n` on new scripts; `docker compose config` when available; template/static grep checks.
- Negative: grep for forbidden broad NAT and committed secret-looking UUID/private key markers; grep for xray in lab runtime files.
- Manual: live Docker/VLESS validation after operator copies secrets.
Dependencies:
- Depends on: none.
- Blocks: final report.
- Can run parallel with: none (single coherent runtime scaffold).
Executor:
- `aad-implementer`.
Report path:
- `docs/plans/2026-05-31-containerized-vpnkit/reports/aad-implementer-task-1.md`
Progress path:
- `docs/plans/2026-05-31-containerized-vpnkit/progress/aad-implementer-task-1.md`

## Dependency graph
- Task 1 -> final owner verification/report.

## Execution ledger
- 2026-06-01: Plan created; Task 1 ready for `aad-implementer`.
- 2026-06-01: Task 1 implemented directly by slice owner because nested implementer dispatch was unavailable at max subagent depth. Local syntax/compose/static checks passed. Live acceptance remains pending operator secrets/runtime.
