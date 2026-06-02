## Task
- Mission: Add Docker/vpnkit sing-box routing so RU IP and RU geosite traffic goes direct, not through proxy.
- Target: `config/sing-box/config.json.template` and regression coverage.
- Boundaries: no VPS mutation; no committed secrets/generated artifacts.

## Context
- Slice stayed whole under one slice owner; implementation delegated to one `aad-implementer` task.
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/ru-direct-singbox`
- Branch: `ru-direct-singbox`
- Task package: `docs/plans/2026-06-02-ru-direct-singbox`

## Spec compliance
- RU IP traffic routes direct: done via `geoip-ru` remote binary rule set and route to `direct-out`.
- RU geosite traffic routes direct: done via `geosite-category-ru` remote binary rule set and route to `direct-out`.
- Existing DNS/default behavior preserved: done; DNS hijack rules remain first and route final remains `selected-native-out`.
- VPS untouched/secrets uncommitted: done.

## Acceptance verification
- Template parses after placeholder substitution: passed (`TestDockerTemplateRoutingInvariants`, temp `sing-box check` with existing deprecation env vars).
- RU direct rules present: passed (`go test ./internal/singbox -run TestDockerTemplateRoutingInvariants -count=1`).
- Broader regression: passed (`go test ./...`, `git diff --check`).
- Local Docker lab: partial. Render passed; `vpnkit` built/started and OpenVPN client connected on retry, but client DNS regression failed (`dig @8.8.8.8` timed out). No VPS deploy attempted.

## System readiness
- Runtime/deployment wiring: code branch is review-ready, but live deployment should wait for a green Docker lab DNS/HTTPS regression or resolution of the local lab/runtime issue.

## Verification run
- `go test ./internal/singbox -run TestDockerTemplateRoutingInvariants -count=1`: passed.
- `go test ./...`: passed.
- `git diff --check`: passed.
- `scripts/vpnkit-render-local-configs.sh`: passed using copied gitignored local secrets, then secrets removed.
- Docker compose client test: failed at DNS timeout after OpenVPN connection; see `verification/local.md`.

## Issues
### Issue U-01: Docker lab DNS/HTTPS regression not green
- Description: Local Docker acceptance did not fully pass. First run hit host port 1194 conflict; retry on port 1195 started vpnkit and connected OpenVPN, but DNS query through the tunnel timed out.
- Evidence: `dig @8.8.8.8 example.com` returned `no servers could be reached` in the OpenVPN client test.
- Why unresolved: resolving the broader local vpnkit DNS/proxy runtime issue would exceed the minimal RU routing slice; VPS deploy is explicitly forbidden.
- Needed next: debug local Docker lab runtime/proxy/DNS path, then rerun AGENTS full client regression before deployment.

## Side findings
- Existing sing-box config still relies on legacy DNS server format/default domain resolver compatibility env vars for sing-box 1.13.x. This was not changed.

## Verdict
- Status: partial-success.
- Goal state: code/config behavior implemented and locally unit-verified; full runtime acceptance remains blocked by U-01.
- Final readiness: ready for review, not ready for deployment.
