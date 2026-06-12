## Task
- Mission: Audit the sing-box DNS schema migration and production deployment for readiness.
- Target: `config/sing-box/*.template`, `docker-compose.yml`, `scripts/vpnkit/vpnkit-prod-singbox-dns-migration.sh`, `scripts/deck/vpnkit-steamdeck-podman.sh`, and the task package evidence under `docs/plans/2026-06-09-sing-box-dns-schema-migration/`.
- Boundaries: read-only audit; no implementation changes; no secret/private-endpoint disclosure.
- Done when: the migration is either accepted, or the exact gap/limitation is explicit and traceable to evidence.
- Expected evidence: local tests, production runtime verify, profile smoke, public-safety review, rollback refs, and any stated limitation around VPN-over-VPN nested diagnostics.

## Context
- Thread: delegated acceptance audit for the sing-box DNS schema migration.
- Slice: production-safe config/runtime migration plus deployment verification.
- Task name: sing-box DNS schema migration.
- Task package: `docs/plans/2026-06-09-sing-box-dns-schema-migration`.
- Report path: `docs/plans/2026-06-09-sing-box-dns-schema-migration/reports/acceptance-auditor.md`.
- Acceptance plan path: `docs/plans/2026-06-09-sing-box-dns-schema-migration/verification/acceptance-plan.md`.
- Worktree: `.worktrees/sing-box-dns-schema-migration`.
- Branch: `aad/sing-box-dns-schema-migration`.
- Verify scope: template schema migration, runtime env cleanup, local tests, production endpoint verify, profile smoke, public-safety, and nested VPN-over-VPN caveat.
- Review target: acceptance-readiness, not implementation correctness in isolation.

## Spec compliance
- Requirement / AC: new DNS schema in tracked sing-box templates.
  - Status: done
  - Evidence: `config/sing-box/config.json.template` and `config/sing-box/config.tun.json.template` now use `type`/`server` DNS entries instead of legacy `address: tls://...`; verified by `test/sing-box-dns-schema-test.sh` and rendered-config checks.
  - Gap if any: none.
- Requirement / AC: explicit default domain resolver.
  - Status: done
  - Evidence: both templates include `route.default_domain_resolver`; final production state uses `direct-dns` bootstrap resolver.
  - Gap if any: none.
- Requirement / AC: no deprecated DNS compatibility env reliance in tracked runtime wiring.
  - Status: done
  - Evidence: `docker-compose.yml` no longer sets the deprecated DNS envs; `scripts/deck/vpnkit-steamdeck-podman.sh` removed them; production verify reports `deprecated_env=absent` on both endpoints.
  - Gap if any: none.
- Requirement / AC: local tests prove the config without deprecated DNS compatibility flags.
  - Status: done
  - Evidence: `verification/local-final.md` shows `test/sing-box-dns-schema-test.sh`, `test/vpnkit-production-routing-wiring-test.sh`, `bash -n`, `go test ./...`, and `docker build` all passed; temp rendered-config checks also passed without deprecated DNS env.
  - Gap if any: none.
- Requirement / AC: production runtime smoke on both failover endpoints.
  - Status: done
  - Evidence: `verification/production-runtime-final-verify.md` shows both `vibe-practicum` and `moscow-tiger` with `singbox_check=ok`, `routing_mode=tun`, `openvpn=up`, `tun0=present`, `sb_tun0=present`, `policy_rule=ok`, `route_table=ok`, `udp_1194=mapped`, `deprecated_env=absent`.
  - Gap if any: none.
- Requirement / AC: OpenVPN failover profile smoke for domain, endpoint 1, endpoint 2.
  - Status: done
  - Evidence: `verification/profile-smoke-final.md` shows all three variants passing OpenVPN readiness, `tun0`, DNS, HTTPS by hostname, literal-IP HTTPS, and `ping 1.1.1.1` / `ping 8.8.8.8`.
  - Gap if any: none.
- Requirement / AC: public-safety review.
  - Status: done
  - Evidence: `verification/public-safety-final.md` has no secret/value matches; only redaction regex literals were found in helper scripts.
  - Gap if any: none.
- Requirement / AC: VPN-over-VPN nested diagnostic limitation called out explicitly.
  - Status: done
  - Evidence: `verification/vpn-over-vpn-inner-route-final.md` shows outer OpenVPN + sing-box startup passed without deprecated DNS env, but the inner client-container test only partially succeeded: inner `sb-tun0` route capture was not achieved and DNS / hostname HTTPS failed while ping and literal-IP HTTPS passed.
  - Gap if any: this remains a follow-up diagnostic, not a production blocker.

## Acceptance verification
- AC1: new DNS schema in templates
  - Covered by: `test/sing-box-dns-schema-test.sh`, `test/vpnkit-production-routing-wiring-test.sh`, template file inspection.
  - Result: passed
  - Evidence: local-final and template contents.
- AC2: default domain resolver present
  - Covered by: template inspection + runtime verify.
  - Result: passed
  - Evidence: `route.default_domain_resolver` exists; production verify passes.
- AC3: deprecated DNS env removed from runtime wiring
  - Covered by: `docker-compose.yml`, `scripts/deck/vpnkit-steamdeck-podman.sh`, production verify.
  - Result: passed
  - Evidence: both runtime checks report `deprecated_env=absent`.
- AC4: local tests
  - Covered by: `verification/local-final.md`.
  - Result: passed
  - Evidence: all requested checks passed.
- AC5: both production endpoints
  - Covered by: `verification/production-runtime-final-verify.md` and recovery artifacts.
  - Result: passed
  - Evidence: both endpoints verified green.
- AC6: failover profile smoke
  - Covered by: `verification/profile-smoke-final.md`.
  - Result: passed
  - Evidence: domain + endpoint1 + endpoint2 all passed.
- AC7: public safety
  - Covered by: `verification/public-safety-final.md`.
  - Result: passed
  - Evidence: no secret/private-endpoint leakage found.

## System readiness
- Routes / registration: done
- Services / APIs: done
- Config / env / secrets: done
- Permissions / access: done
- Database / migrations: not relevant
- Frontend-backend integration: not relevant
- Runtime / deployment wiring: done

## Verification run
- Local / targeted checks:
  - `test/sing-box-dns-schema-test.sh`: passed
  - `test/vpnkit-production-routing-wiring-test.sh`: passed
  - `bash -n scripts/*.sh docker/vpnkit/*.sh test/*.sh`: passed
  - `go test ./...`: passed
  - `docker build -q -t vpnkit-singbox-dns-migration:local -f docker/vpnkit/Dockerfile .`: passed
- Local / full checks:
  - Full repo tests above are sufficient for this scope; no extra CI-only gate was available locally.
- Remote checks / CI:
  - Status: not available before push / no status checks shown on PR
  - Evidence: `gh pr view 25` showed an open draft PR with empty `statusCheckRollup`.

## Issues
### Issue U-01: VPN-over-VPN nested diagnostic is only partially proven
- Description: The disposable nested client-container test did not achieve a clean inner `sb-tun0` data-path success. Evidence shows outer OpenVPN and sing-box startup passed without deprecated DNS env, but inner DNS / hostname HTTPS failed while ping and literal-IP HTTPS passed.
- Evidence: `verification/vpn-over-vpn-inner-route-final.md`.
- Why unresolved: this is a real follow-up diagnostic boundary, not part of the production runtime acceptance path, and it would require more targeted nested routing/bootstrap work to finish.
- Needed next: if the owner wants a full nested VPN-over-VPN acceptance, rerun the disposable client-container test with a purpose-built inner-TUN bootstrap path and rule-set strategy.
- Depends on: none.

## Side findings
- Blocking findings folded into active work: none.
- Non-blocking findings tracked separately: the nested VPN-over-VPN limitation above.

## Verdict
- Status: accepted with limitations
- Goal state: fully achieved for the production DNS schema migration and deployment; nested VPN-over-VPN diagnostic only partially achieved.
- Final readiness: ready except explicit limitation
- Summary: The DNS schema migration, runtime cleanup, production deploy to both endpoints, and user profile smoke are acceptable; the only remaining gap is the separate nested VPN-over-VPN diagnostic, which does not block acceptance of the production migration.

## Next-agent brief
- Objective: only if needed, finish the nested VPN-over-VPN client-container diagnostic.
- Target: disposable local client-container path and inner `sb-tun0` bootstrap/routing.
- Settled already: production templates, env wiring, deploy helper, production endpoint verify, and failover profile smoke are green.
- Boundaries: do not re-open production mutation or secret disclosure.
- Verification target: inner `sb-tun0` route capture plus DNS/hostname HTTPS success under the nested container path.
- Expected output: a short follow-up diagnostic report, not a production rollback/change request.