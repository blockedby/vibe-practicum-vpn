# Production routing wiring follow-up plan

## Intake

Goal: commit the production-only vpnkit routing wiring follow-up from a clean branch based on `origin/main`, merge it to `main`, redeploy/update all known vpnkit production servers, and return the primary checkout at `/home/kcnc/code/tools/vibe-practicum-vpn` to branch `main`.

Public-safety constraints:
- Do not commit or print secrets, private endpoints, generated OpenVPN profiles, rendered configs, raw logs, private CIDR values, or private endpoint values.
- Live mutation is explicitly approved for the vpnkit Compose service on the known production servers only.
- Preserve untracked user files in the primary checkout.

## Acceptance criteria

AC1. Repository changes are made on a clean branch from `origin/main`, not the dirty primary checkout.
AC2. `docker/vpnkit/entrypoint.sh` readiness is mode-aware: `tun` waits for the TUN link, `tproxy` waits for TCP 2082, and `redirect`/default waits for TCP 2082 plus UDP 5353.
AC3. `docker-compose.yml` passes `OVPN_CIDR` with a public-safe default matching repo routing defaults and allows production `.env` override.
AC4. Public docs/config examples document redirect-mode consistency without secrets.
AC5. Practical tests/checks cover mode-aware readiness and compose env, plus `bash -n` and existing routing tests where available.
AC6. Branch is committed, pushed, PR-first path used if possible, and merged into `main`.
AC7. Updated `main` is deployed to all known vpnkit production servers with backup/rollback awareness and without mutating unrelated production containers.
AC8. Each server is verified after deploy: vpnkit running, deployed entrypoint has mode-aware wait and setup-routing after sing-box restart, internal sing-box restart works, routing rules present, and safe smoke tests pass.
AC9. Primary repository folder is on branch `main` with user untracked files preserved.
AC10. Final report records files changed, PR/merge commit, servers updated in sanitized form, verification evidence, rollback tags, and checkout state.

## Slice structure

One implementation slice followed by one deployment slice preserves ownership clarity:

### Slice 1: repository implementation, PR, and merge
- Owner: `aad-slice-owner`
- Worktree: `.worktrees/prod-routing-wiring-followup`
- Branch: `prod-routing-wiring-followup`
- Report path: `docs/plans/2026-06-08-production-routing-wiring-followup/reports/repo-implementation-slice.md`
- Goal: implement public-safe repo changes, tests/docs, commit, push, open PR, and merge to `main`.
- Depends on: none.
- Blocks: Slice 2.
- Acceptance: AC1-AC6, plus safe evidence for AC10 repo fields.

### Slice 2: production deploy and verification
- Owner: `aad-slice-owner`
- Worktree: primary checkout or a clean main checkout after Slice 1 merge.
- Report path: `docs/plans/2026-06-08-production-routing-wiring-followup/reports/production-deploy-slice.md`
- Goal: deploy merged `main` to known vpnkit production servers and verify runtime health.
- Depends on: Slice 1 merged `main`.
- Blocks: final root report.
- Acceptance: AC7-AC8 and deploy evidence for AC10.

### Root checkout/finalization
- Owner: `aad-root-owner`
- Goal: put `/home/kcnc/code/tools/vibe-practicum-vpn` on branch `main`, preserving untracked user files; integrate reports and produce final done-state.
- Acceptance: AC9-AC10.

## Verification ledger

- Pending Slice 1 report.
- Pending Slice 2 report.
- Pending root final verification and checkout state.
