## Task
- Mission: Finish the RU-direct sing-box change and close the Docker lab DNS/HTTPS regression.
- Target: `config/sing-box/config.json.template`, `internal/singbox/singbox_test.go`, Docker vpnkit startup wiring, and local Docker lab acceptance.
- Boundaries: no VPS mutation; no committed secrets/logs/generated artifacts; preserve RU direct routing behavior.
- Done when: RU IP/geosite traffic routes direct, existing DNS/default proxy behavior is preserved, and the local Docker OpenVPN client lab passes DNS/HTTPS acceptance.

## Context
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/ru-direct-singbox`
- Branch: `ru-direct-singbox`
- Task package: `docs/plans/2026-06-02-ru-direct-singbox`
- Slice structure: one implementation/debugging slice, because the remaining work had one runtime ownership boundary and one acceptance story.

## Spec compliance
- RU IP traffic routes direct: done via `geoip-ru` remote rule set routed to `direct-out`.
- RU geosite traffic routes direct: done via `geosite-category-ru` remote rule set routed to `direct-out`.
- Existing DNS/default behavior preserved: done; DNS hijack rules remain first and route final remains `selected-native-out`.
- Docker lab DNS/HTTPS regression fixed: done; root cause was a vpnkit startup race, fixed by waiting for sing-box redirect/DNS inbounds before starting OpenVPN.
- VPS untouched/secrets uncommitted: done.

## Acceptance verification
- Template parses and RU direct invariants hold:
  - Covered by: `go test ./internal/singbox -run TestDockerTemplateRoutingInvariants -count=1` and `go test ./...`.
  - Result: passed.
- OpenVPN client connects and gets `10.89.0.2/24`:
  - Covered by: fresh Docker compose client test with AGENTS flags and `VPNKIT_OPENVPN_PORT=1196` because host UDP 1194 is occupied locally.
  - Result: passed; output included `inet 10.89.0.2/24 scope global tun0`.
- DNS through tunnel returns NOERROR:
  - Covered by: same client test, `dig @8.8.8.8 example.com`.
  - Result: passed; `status: NOERROR`, A records returned.
- HTTPS and literal-IP HTTPS return HTTP 200:
  - Covered by: same client test.
  - Result: passed; `https-test http_code=200`, `literal-ip-test http_code=200`.
- Runtime processes alive:
  - Covered by: root process check after start.
  - Result: passed; `sing-box`, `openvpn`, and `vibe-vpn daemon` were all running.
- No secrets/logs/generated artifacts committed:
  - Covered by: copied gitignored `secrets/` removed after local lab; `git status --short --branch` clean.
  - Result: passed.

## Verification run
- `go test ./...`: passed.
- `git diff --check`: passed.
- `scripts/vpnkit-render-local-configs.sh`: passed using copied gitignored local secrets, then secrets removed.
- `docker compose up -d --build vpnkit` with AGENTS flags and `VPNKIT_OPENVPN_PORT=1196`: passed.
- `docker compose exec vpnkit ps auxww | grep -E '[o]penvpn|[s]ing-box|[v]ibe-vpn daemon'`: passed.
- `docker compose --profile test run --rm ovpn-client-test` with same flags: passed DNS/HTTPS/literal-IP checks.
- Remote/VPS checks: not run by constraint.

## Issues
### Issue R-01: Docker lab DNS timeout was a vpnkit startup race
- Description: With compat bypass enabled and RU remote rule-set startup work, OpenVPN could accept a client before sing-box DNS/redirect inbounds were listening; the client's first DNS query then timed out.
- Evidence: failing slice reproduction showed OpenVPN connected before sing-box logged `vpnkit-dns-in` readiness; control without compat bypass passed; fixed run with compat bypass passed.
- Resolution: `docker/vpnkit/entrypoint.sh` waits for TCP redirect port `2082` and UDP DNS port `5353` before starting OpenVPN.

## System readiness
- Local Docker lab: ready; DNS/HTTPS regression is green.
- VPS/deploy: not touched; deploy remains a separate explicit action after review.
- Known non-blocking note: existing sing-box legacy DNS/default-domain-resolver deprecation compatibility env vars remain pre-existing.

## Verdict
- Status: success.
- Goal state: fully achieved.
- Final readiness: ready for review / next explicit deploy step; not pushed.
