# Acceptance plan: sing-box DNS schema migration

Audit the migration and deployment against these acceptance criteria:

1. Tracked sing-box templates use the new DNS schema (`type`/`server`) instead of legacy `address: tls://...`.
2. `route.default_domain_resolver` is present so deprecated missing-domain-resolver compatibility is not required.
3. Tracked runtime wiring no longer relies on `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS` or `ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER`.
4. Local tests prove both templates render/check without deprecated DNS compatibility flags.
5. Production `vpnkit` on both failover endpoints is backed up, recreated/restarted, and passes runtime smoke.
6. OpenVPN failover profile smoke passes for domain, endpoint 1, and endpoint 2 variants.
7. Public-safety review finds no secret/private-endpoint leakage in tracked changes or reports.
8. Any VPN-over-VPN nested diagnostic limitation is called out explicitly and does not masquerade as a production pass.

Fresh evidence files to inspect:
- `verification/local-final.md`
- `verification/production-runtime-final-verify.md`
- `verification/profile-smoke-final.md`
- `verification/vpn-over-vpn-inner-route-final.md`
- `verification/public-safety-final.md`
- `verification/production-runtime-moscow-recovery.md`
- `verification/production-runtime-vibe-final-localdns.md`

Decision rule:
- Accept if criteria 1-7 are passed and 8 is documented as a limitation/follow-up rather than a blocker.
- Reject if any production endpoint fails verify, if deprecated DNS env is still required, or if secrets/private endpoints leak into the task package.