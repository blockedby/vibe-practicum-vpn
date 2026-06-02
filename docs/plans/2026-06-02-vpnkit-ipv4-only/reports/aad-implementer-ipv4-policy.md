PI_RESULT: PASS
TASK: Phase 1 vpnkit IPv4-only / IPv6-block policy — Task 1
TASK_PACKAGE: docs/plans/2026-06-02-vpnkit-ipv4-only
REPORT_PATH: docs/plans/2026-06-02-vpnkit-ipv4-only/reports/aad-implementer-ipv4-policy.md
PROGRESS_PATH: docs/plans/2026-06-02-vpnkit-ipv4-only/progress/aad-implementer-ipv4-policy.md
COMMITS:
- 184fe34: Add vpnkit IPv4-only runtime policy
FILES_CHANGED:
- docker-compose.yml: exposes default `VPNKIT_IPV6_POLICY=block` to the vpnkit container.
- docker/vpnkit/setup-routing.sh: validates `VPNKIT_IPV6_POLICY`, defaults to `block`, installs managed `ip6tables` DROP rules for OpenVPN `tun0` IPv6 traffic, and supports diagnostic `allow` cleanup.
- config/sing-box/config.json.template: sets DNS `strategy` to `ipv4_only`.
- scripts/vpnkit-routing-compat-bypass-test.sh: extends dry-run coverage for IPv6 block rules and invalid IPv6 policy while preserving compat bypass assertions.
- docs/CONTAINERIZED_VPNKIT_RUNBOOK.md: documents IPv4-only policy, diagnostic override, safe verification, and deploy/recreate checks.
- README.md: adds top-level IPv4-only vpnkit note and runbook pointer.
- docs/plans/2026-06-02-vpnkit-ipv4-only/verification/local.md: records local verification evidence and deploy-time checks.
- docs/plans/2026-06-02-vpnkit-ipv4-only/progress/aad-implementer-ipv4-policy.md: records progress and RED/GREEN evidence.
AC_VERIFICATION:
- Default config exposes `VPNKIT_IPV6_POLICY=block` and sing-box DNS defaults to IPv4-only: `docker compose config` showed `VPNKIT_IPV6_POLICY: block`; `grep -n '"strategy": "ipv4_only"' config/sing-box/config.json.template` found the DNS strategy — passed.
- IPv6 client traffic is explicitly blocked/dropped where applicable: `scripts/vpnkit-routing-compat-bypass-test.sh` dry-run asserts `ip6tables` INPUT/FORWARD/OUTPUT `tun0` jumps to `OVPN_IPV6_BLOCK` and DROP rule — passed.
- Existing compat bypass dry-run behavior remains covered: same routing test still asserts scoped bypass RETURN/MASQUERADE/FORWARD/ICMP behavior and no broad `POSTROUTING -s 10.89.0.0/24 -j MASQUERADE` — passed.
- Docs state current vpnkit is IPv4-only and give safe verification/deploy steps: README and containerized runbook updated; verification commands are also in `verification/local.md` — passed.
- No secrets/generated profiles/logs are committed: `git status --short` only showed scoped source/docs/task-package changes before commit; committed paths contain no secrets/logs/generated profiles — passed.
TESTS_RUN:
- `scripts/vpnkit-routing-compat-bypass-test.sh` before production changes after RED test edit: failed as expected with missing `ip6tables ... OVPN_IPV6_BLOCK` rule.
- `bash -n docker/vpnkit/entrypoint.sh docker/vpnkit/setup-routing.sh scripts/vpnkit-render-local-configs.sh scripts/vpnkit-routing-compat-bypass-test.sh`: passed.
- `scripts/vpnkit-routing-compat-bypass-test.sh`: passed.
- `docker compose config >/tmp/vpnkit-compose-config.out && grep -n "VPNKIT_IPV6_POLICY" /tmp/vpnkit-compose-config.out`: passed; output included `VPNKIT_IPV6_POLICY: block`.
- `grep -n '"strategy": "ipv4_only"' config/sing-box/config.json.template`: passed.
- `sing-box check` on temp-rendered safe config without compose env flags: failed on existing sing-box legacy-DNS compatibility gate requiring deprecated-feature env.
- `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true sing-box check -c <temp-rendered-config>`: passed with deprecation warnings only.
QUALITY_CHECKS:
- `git diff --check`: passed.
- Shell syntax: `bash -n docker/vpnkit/entrypoint.sh docker/vpnkit/setup-routing.sh scripts/vpnkit-render-local-configs.sh scripts/vpnkit-routing-compat-bypass-test.sh` — passed.
- Compose render: `docker compose config` — passed.
- sing-box config validation: passed on temp-rendered config with compose's existing deprecated-feature env flags; local binary available at `/usr/bin/sing-box`.
QUALITY_NOTES:
- Readability/reuse: reused existing `setup-routing.sh` dry-run/run and idempotent rule patterns; added small local helpers mirroring existing iptables behavior rather than adding new abstractions or dependencies.
- Error handling/logging: invalid `VPNKIT_IPV6_POLICY` fails with a clear stderr message; no sensitive env values are printed; ip6tables absence fails under block policy when IPv6 appears available and skips only when kernel IPv6 support is absent.
- Backend/API/data: not relevant; no API/storage/schema/persisted data changes.
- Frontend/UI: not relevant.
- DevOps/runtime: compose env, sing-box template, runtime routing, and operator docs were updated together; no live deploy was performed. Existing persisted `vpnkit-sing-box-state` configs should be verified/recreated intentionally so live `/var/lib/vpnkit/sing-box/config.json` includes `"strategy": "ipv4_only"`.
- Security: no secrets, generated profiles, keys, tokens, or logs touched/committed; change blocks IPv6 leak/blackhole paths rather than widening network access.
- Concurrency/idempotency: managed `ip6tables` jumps are installed idempotently; diagnostic `allow` removes managed jumps/chains for reruns.
- Compatibility/performance: compat bypass assertions preserved; default redirect/tun/tproxy routing path behavior otherwise unchanged; added rules are bounded to `tun0` IPv6 filter traffic.
SIDE_FINDINGS:
- Blocking: none.
- Non-blocking follow-up candidates: migrate sing-box DNS config away from deprecated legacy DNS server format before sing-box 1.14 removes the compatibility env path.
NOTES: No live deployment, SSH, remote mutation, secrets rendering, or generated profile/log commits were performed. Operator deploy-time checks are recorded in `docs/plans/2026-06-02-vpnkit-ipv4-only/verification/local.md`.
