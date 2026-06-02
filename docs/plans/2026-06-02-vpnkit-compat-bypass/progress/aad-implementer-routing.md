# aad-implementer progress: routing

- 2026-06-02: Started implementation. Read AGENTS.md, plan, setup-routing.sh, docker-compose.yml, and runbook. CLAUDE.md not present. `git status --short` clean on branch `vpnkit-compat-bypass`.
- 2026-06-02: No existing test harness for setup-routing parsing found; proceeding with a narrow dry-run/render test for compatibility bypass rules before production routing changes.
- 2026-06-02: RED check run: `bash scripts/vpnkit-routing-compat-bypass-test.sh` failed as expected before implementation; script tried live iptables because dry-run/compat bypass rendering was not implemented.
- 2026-06-02: Implemented scoped compatibility bypass parsing/rule installation, compose env wiring, and runbook docs. GREEN check: `bash scripts/vpnkit-routing-compat-bypass-test.sh` passed.
- 2026-06-02: Refactored parser to reject conflicting explicit proto declarations and made DNS resolution failures use the explicit unresolved-host error path. Re-ran `bash -n docker/vpnkit/setup-routing.sh scripts/vpnkit-routing-compat-bypass-test.sh && bash scripts/vpnkit-routing-compat-bypass-test.sh`: passed.
- 2026-06-02: Final targeted verification passed: bash syntax, render test, `docker compose config`, source grep for no broad MASQUERADE. `shellcheck` not available. Wrote verification evidence to `verification/local.md`.
- 2026-06-02: Committed implementation: `c4d0cc7cbcfe3824e4a339d1338c273028bf57bd Add scoped vpnkit compatibility bypass`.
- 2026-06-02: Wrote final implementation report to `reports/aad-implementer-routing.md`; preparing report artifact commit and push.
