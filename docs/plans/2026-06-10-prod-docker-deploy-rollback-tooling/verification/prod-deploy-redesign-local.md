# Production deploy redesign local verification

Updated: 2026-06-13 strict audit follow-up pass.

Scope: local/static/mocked checks only. No live production mutation, no real SSH endpoints, no private endpoint values, no generated profiles/configs/logs/images.

## Fresh required checks

- `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh`
  - Result: PASS
- `test/prod-deploy-helper-test.sh`
  - Result: PASS
  - Evidence: mocked ssh/timeout/docker/git paths cover plan/refusal/redaction, verify TUN smoke, deploy release/image override activation, rollback no-build activation, rollback-smoke manual recovery, TUN-pair deploy failure auto-rollback, strict current/previous symlink behavior, and override content with `VPNKIT_ROUTING_MODE: tun`.
- `git diff --check`
  - Result: PASS
- source-transfer grep
  - Command: `! grep -RInE 'source_update=archive|source-before\.tar|git archive|scp ' scripts/vpnkit/vpnkit-prod-deploy.sh README.md`
  - Result: PASS
  - Note: tests/task-package docs may contain intentional negative assertions/history for removed source-mode/archive/scp behavior.
- public-safety grep
  - Command: `git diff -- scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh README.md docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling | grep '^+' | grep -Ev '^\+\+\+|assert_|grep|public-safety|source-transfer|token=mock-secret-output|secret\|token' | (! grep -E 'BEGIN (RSA|OPENSSH|PRIVATE)|PRIVATE KEY|client\.ovpn|vless://|trojan://|ss://|vmess://|password=[^<]|token=[^<]|([0-9]{1,3}\.){3}[0-9]{1,3}')`
  - Result: PASS
  - Note: excludes documented grep command lines and intentional test redaction sentinels; no private material was found in added content.

## Strict audit partial closure evidence

- Release-pointer rollback:
  - Code: `write_metadata()` writes `previous-release-target.txt` before activation; `activate_image()` sets `previous` to the pre-deploy `current` target and `current` to `/opt/vpnkit/releases/<deploy-id>`; `rollback_to()` restores `current` from `previous-release-target.txt` and sets `previous` to the failed release dir.
  - Test: `test/prod-deploy-helper-test.sh` creates a mocked prior release/current symlink, asserts metadata records it, asserts deploy `current`/`previous` values, runs rollback, then asserts rollback `current` is restored to the prior release and `previous` points at the failed release.
  - Result: PASS; prior AC4 release-pointer limitation closed for mocked/local evidence.
- Explicit TUN mode restore/enforcement:
  - Code: generated Compose image override now includes `environment: VPNKIT_ROUTING_MODE: tun` for both deploy activation and rollback activation.
  - Test: `test/prod-deploy-helper-test.sh` inspects both deploy and rollback override files for selected image and `VPNKIT_ROUTING_MODE: tun`.
  - Result: PASS; prior AC5 explicit mode-restore limitation closed for mocked/local evidence.

## Remaining limitation

- Live production deploy/rollback/verify and CI/push evidence remain outside this bounded follow-up unless separately authorized/requested.
