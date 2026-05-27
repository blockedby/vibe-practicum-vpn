# Plan: Stack PR7 into PR6 and README usage update

## Task intake
- Goal: update branch `docs/failover-service-plan` / PR #6 so it contains PR #7 (`feature/fastest-rotation-mode`) changes plus a concise, command-heavy README.
- In scope: safe git integration of PR7 into PR6 branch; README rewrite focused on exact commands, config paths, file locations, install/validate/run service, and `failover-only` / `fastest-rotation` modes; local static/build/test checks; push branch and update PRs.
- Out of scope: merging PR #6 into `main`; deployment; running systemd/VPS/xray live commands.
- Done state: PR #6 branch pushed with PR7 commits/content and README update; PR #7 handled/closed if appropriate after branch contains its changes; report includes PR URLs, commits, checks, limitations.
- Blocking unknowns: none currently; conflicts/check failures will be handled in scope if local.

## Repo orientation
- Go CLI: `cmd/vibe-vpn`, `internal/...`; service assets under `systemd/`; docs under `docs/`; examples under `examples/`.
- Current PRs: #6 `docs/failover-service-plan` -> `main`; #7 `feature/fastest-rotation-mode` -> `docs/failover-service-plan`.
- Local constraints: no systemd/VPS/xray runtime operations; local `go test`, `go vet`, `go build` OK.
- Relevant checks: `go test ./...`, `go vet ./...`, `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`.

## Reuse discovery
- Existing README already lists CLI and service docs but is long/duplicated; use existing command names rather than inventing new flows.
- Service runbook: `docs/FAILOVER_SERVICE_RUNBOOK.md`.
- PR7 likely adds fastest rotation mode code/docs; preserve its command/config semantics.

## Missing pieces
- Merge PR7 head into PR6 branch without touching `main`.
- Rewrite README into concise command-heavy usage docs.
- Verify changed branch with Go checks/build.
- Push PR6 branch and close/update PR7 if redundant.

## Plan tasks

### Task 1: Integrate stacked PR changes and rewrite README
Goal:
- PR6 branch contains PR7 changes and README is concise usage documentation.
Boundary:
- System area: git/docs with preservation of existing Go/service changes.
- Primary verification: clean merge, README content inspection, Go tests/vet/build.
Existing pattern / reuse:
- Follow actual CLI/service flags and files from code, `systemd/`, `docs/FAILOVER_SERVICE_RUNBOOK.md`.
Missing change:
- Merge `origin/feature/fastest-rotation-mode`; edit `README.md` to prioritize commands/paths/modes.
Scope / likely files:
- `README.md`; merged PR7 files as-is.
Acceptance criteria:
- Branch `docs/failover-service-plan` includes PR7 commits/content.
- README contains exact local build/test commands, VPS install/validation/run commands, config/state/systemd paths, and documents `failover-only` and `fastest-rotation` modes.
- README avoids long architecture prose and duplicate stale sections.
- No live VPS/systemd/xray commands are executed locally; remote commands may appear as docs only.
Test plan:
- Positive: `git log`/`git branch --contains` confirms PR7 head in PR6; `go test ./...`; `go vet ./...`; `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`.
- Manual: inspect README for command-heavy content and path accuracy.
Dependencies:
- Depends on: none.
- Blocks: final push/PR update.
Executor:
- aad-implementer.
Report path: `docs/plans/2026-05-27-stack-pr7-readme-update/reports/aad-implementer-readme.md`.

## Dependency graph
- Single execution task; stays whole under slice owner with one `aad-implementer` task.

## Execution ledger
- 2026-05-27: Task package and plan created.
