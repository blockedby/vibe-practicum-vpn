## Task
- Mission: Finish Docker lab DNS/HTTPS regression for the RU-direct sing-box branch by diagnosing the local OpenVPN tunnel DNS timeout, applying a minimal repo fix if confirmed, and rerunning fresh local acceptance.
- Target: Docker vpnkit runtime startup/routing path, especially `docker/vpnkit/entrypoint.sh` and the AGENTS Docker compose OpenVPN client regression.
- Boundaries: no VPS/SSH/SCP/systemctl; no committed secrets/logs/generated artifacts; preserve RU direct routing/template invariant behavior.
- Done when: local Docker lab OpenVPN client connects, DNS returns NOERROR, HTTPS and literal-IP HTTPS return HTTP 200, Go tests/diff check pass, and task-package evidence is updated.
- Expected evidence: root cause classification, changed files, commands and excerpts, final readiness.

## Context
- Thread: Root task requested continuation of Docker lab DNS/HTTPS regression for RU-direct sing-box change.
- Slice: stayed whole; implementation/debugging completed directly by slice owner because nested implementer dispatch was blocked by subagent depth.
- Task name: RU direct sing-box routing
- Task package: `docs/plans/2026-06-02-ru-direct-singbox`
- Report path: `docs/plans/2026-06-02-ru-direct-singbox/reports/slice-owner-docker-lab-debug.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/ru-direct-singbox`
- Branch: `ru-direct-singbox`
- Verify scope: local Docker lab OpenVPN DNS/HTTPS acceptance, RU direct invariant tests, `go test ./...`, `git diff --check`.

## Spec compliance
- OpenVPN client connects and receives `10.89.0.2/24`: done.
  - Evidence: final compose client test showed `inet 10.89.0.2/24 scope global tun0`.
- DNS through OpenVPN succeeds with NOERROR: done.
  - Evidence: final `dig @8.8.8.8 example.com` returned `status: NOERROR`, two A records, query time 82 ms.
- HTTPS and literal-IP HTTPS through tunnel return HTTP 200: done.
  - Evidence: final client test printed `https-test http_code=200 remote_ip=104.20.23.154` and `literal-ip-test http_code=200 remote_ip=1.1.1.1`.
- RU direct route implementation remains intact: done.
  - Evidence: `go test ./...` passed including `internal/singbox`; vpnkit logs during lab showed `rule_set=geosite-category-ru => route(direct-out)` for `ya.ru`.
- No VPS touched / no secrets or generated artifacts committed: done.
  - Evidence: only local Docker commands were run; `secrets/` was copied only for local rendering/lab and removed before finish.

## Acceptance verification
- AC1: OpenVPN client connects in local Docker lab and gets `10.89.0.2/24`.
  - Covered by: `docker compose --profile test run --rm ovpn-client-test` with AGENTS flags and alternate host port `VPNKIT_OPENVPN_PORT=1196` because UDP 1194 is occupied by `vpnkit-compat-bypass-vpnkit-1`.
  - Result: passed.
  - Evidence: `inet 10.89.0.2/24 scope global tun0`.
- AC2: DNS through tunnel succeeds with NOERROR.
  - Covered by: same client test, `dig +time=10 +tries=1 @8.8.8.8 example.com`.
  - Result: passed.
  - Evidence: `status: NOERROR`, `example.com A 104.20.23.154`, `example.com A 172.66.147.243`.
- AC3: HTTPS and literal-IP HTTPS return HTTP 200.
  - Covered by: same client test curls.
  - Result: passed.
  - Evidence: `https-test http_code=200`; `literal-ip-test http_code=200`.
- AC4: RU direct route implementation remains present and covered.
  - Covered by: `go test ./...` and Docker log evidence.
  - Result: passed.
  - Evidence: Go tests passed; log excerpt `router: match[3] rule_set=geosite-category-ru => route(direct-out)`.
- AC5: `go test ./...` and `git diff --check` pass after edits.
  - Covered by: fresh local commands.
  - Result: passed.
  - Evidence: all Go packages passed/cached; `git diff --check` produced no output.
- AC6: no VPS/secrets/logs/generated artifacts committed.
  - Covered by: command boundary and final cleanup/status.
  - Result: passed.
  - Evidence: no VPS commands used; copied `secrets/` removed; logs/generated files remain untracked/gitignored and not committed.

## System readiness
- Routes / registration: done; `setup-routing.sh` NAT redirect rules stayed unchanged and counters incremented in the passing non-compat repro.
- Services / APIs: not relevant.
- Config / env / secrets: done for local lab; gitignored secrets were copied from the existing local worktree per AGENTS workflow and removed before finish.
- Permissions / access: done; Docker privileged/TUN path worked locally.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: done for Docker lab. Minimal fix waits for sing-box redirect/DNS inbounds before starting OpenVPN, removing the startup race exposed by compat bypass/RU remote rule-set startup latency.

## Verification run
- Local / targeted checks:
  - Reproduction with AGENTS flags + `VPNKIT_OPENVPN_PORT=1196` before fix: failed.
    - Evidence: OpenVPN connected, then `dig @8.8.8.8 example.com` timed out; vpnkit logs showed sing-box inbounds/rule-set update completed only after the OpenVPN client had already connected and queried DNS.
  - Control run with compat bypass disabled before fix: passed.
    - Evidence: OpenVPN got `10.89.0.2/24`; DNS NOERROR; HTTPS/literal-IP HTTPS 200. This narrowed the timeout to a startup timing issue exposed by slower compat/RU startup rather than broken RU routing or NAT.
  - Final AGENTS-equivalent run with compat bypass enabled and alternate host port 1196: passed.
    - Command: `VPNKIT_OPENVPN_PORT=1196 VPNKIT_ENABLE_VIBE_VPN_DAEMON=true VPNKIT_ROUTING_MODE=redirect VPNKIT_IPV6_POLICY=block VPNKIT_COMPAT_BYPASS_ENABLED=true VPNKIT_COMPAT_BYPASS_ENDPOINTS='vpn.proofix.tv:1194/udp,vpn.proofix.tv:1194/tcp' docker compose --profile test run --rm ovpn-client-test`
    - Evidence: `status: NOERROR`; `https-test http_code=200`; `literal-ip-test http_code=200`.
- Local / full checks:
  - `go test ./...`: passed.
  - `git diff --check`: passed.
- Remote checks / CI:
  - Status: not available before push; no push requested/performed.

## Issues
### Issue R-01: Docker lab DNS timeout was a vpnkit startup race
- Description: With AGENTS compat bypass enabled and RU remote rule-set downloads, `sing-box run` took long enough to update rule sets and bind inbounds that the compose client could connect to OpenVPN before sing-box DNS/redirect inbounds were ready. The client's first `dig @8.8.8.8` then timed out.
- Evidence: failing run showed OpenVPN connected and `dig` timed out; vpnkit log ordering showed OpenVPN client activity before `inbound/direct[vpnkit-dns-in]: udp server started at 0.0.0.0:5353` / `sing-box started`. A control run with compat bypass disabled passed, and the final fixed run with compat bypass enabled passed.
- Resolution: updated `docker/vpnkit/entrypoint.sh` to wait until sing-box TCP redirect port 2082 and UDP DNS port 5353 are listening before starting OpenVPN. This prevents clients from entering the tunnel before the local sing-box packet handlers are ready.
- Depends on: none.

## Side findings
- Blocking findings folded into active work: R-01.
- Non-blocking findings tracked separately: none created. Existing sing-box 1.13 legacy DNS/default-domain-resolver deprecation warnings remain pre-existing and covered by existing compose env vars.

## Verdict
- Status: success.
- Goal state: fully achieved for local Docker lab acceptance.
- Final readiness: ready for root owner integration/review; not pushed.
- Summary: RU direct branch now passes fresh local Docker lab DNS/HTTPS acceptance on alternate host UDP port 1196, with a minimal vpnkit startup readiness fix and no VPS/secrets committed.
