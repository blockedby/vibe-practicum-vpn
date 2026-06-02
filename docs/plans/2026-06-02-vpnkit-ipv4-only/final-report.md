## Task
- Mission: Implement Phase 1 vpnkit IPv4-only / IPv6-block policy.
- Target: containerized vpnkit runtime, sing-box template, routing setup, compat bypass test, docs.
- Boundaries: no live deploy/SSH/remote mutation; no secrets/generated profiles/logs.
- Done when: branch/PR has committed implementation, verification evidence, and operator deploy instructions.

## Spec compliance
- `VPNKIT_IPV6_POLICY=block` default: done; `docker-compose.yml` propagates default and `docker/vpnkit/setup-routing.sh` defaults/validates it.
- sing-box DNS `strategy=ipv4_only`: done; `config/sing-box/config.json.template` sets DNS strategy.
- Explicit IPv6 block: done; setup script installs managed `ip6tables` DROP chain for `tun0` IPv6 traffic under block policy.
- Docs: done; README and containerized runbook document IPv4-only behavior, override, verification, and deploy/recreate notes.
- Preserve compat bypass/no secrets: done; dry-run compat assertions preserved and no secret/log/generated-profile paths committed.

## Acceptance verification
- AC1 default env + DNS strategy: passed via `docker compose config` grep and sing-box template grep/check.
- AC2 IPv6 block rules: passed via `scripts/vpnkit-routing-compat-bypass-test.sh` dry-run assertions.
- AC3 compat bypass preserved: passed via existing assertions in same test.
- AC4 docs/deploy instructions: passed by README/runbook updates and `verification/local.md` deploy-time commands.
- AC5 no secrets: passed by committed changed-file set review.

## Verification run
- `bash -n docker/vpnkit/entrypoint.sh docker/vpnkit/setup-routing.sh scripts/vpnkit-render-local-configs.sh scripts/vpnkit-routing-compat-bypass-test.sh`: passed.
- `scripts/vpnkit-routing-compat-bypass-test.sh`: passed.
- `docker compose config >/tmp/vpnkit-compose-config-owner.out && grep -n "VPNKIT_IPV6_POLICY" /tmp/vpnkit-compose-config-owner.out`: passed.
- `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true sing-box check -c <temp rendered config>`: passed with existing deprecation warnings.
- `git diff --check`: passed.

## Issues
- R-01: IPv6/AAAA blackhole prevention for Phase 1 resolved by default IPv4-only DNS and IPv6 block policy.
- U-*: none.
- F-*: none created. Existing sing-box legacy DNS deprecation warning remains outside this Phase 1 scope and is noted in verification/operator docs.

## System readiness
- Config/env/secrets: ready; no new secrets required; env default is documented.
- Runtime/deployment wiring: ready for branch/PR update; existing persisted `vpnkit-sing-box-state` volumes need intentional rerender/recreate to pick up `ipv4_only`.
- Live deploy: not performed.

## Verdict
- Status: success.
- Goal state: achieved locally and ready for PR review/deploy by operator.
