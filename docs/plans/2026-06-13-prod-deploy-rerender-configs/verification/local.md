# Local verification: prod deploy rerender configs

Date: 2026-06-13
Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/fix-adblock-routes`
Scope: mocked deploy helper behavior and shell syntax only; no live host mutation.

## RED evidence

Command:

```bash
test/prod-deploy-helper-test.sh
```

Result before production change: failed as expected after adding rerender assertions. Key missing/failing expectations:

- `render-local-configs:tun` absent from plan output.
- `local_config_render=start mode=tun`, `render_invoked_routing_mode=tun token=<redacted>`, and `local_config_render=ok` absent from deploy output.
- Order assertions failed for `source_update=git resolved_ref=...` before render and render before `compose_build=vpnkit`.
- Mocked render failure did not fail before compose build/up because no render step existed yet.

## GREEN / targeted behavior evidence

Command:

```bash
test/prod-deploy-helper-test.sh
```

Result after implementation: passed (exit 0, no harness output on success).

Coverage in the harness includes:

- Positive deploy logs `local_config_render=start mode=tun`, invokes the mocked renderer with `VPNKIT_ROUTING_MODE=tun`, logs `local_config_render=ok`, then continues through existing build/activation/smoke success.
- Ordering assertions require `source_update=git resolved_ref=abc123resolved` before `local_config_render=start mode=tun`, and `local_config_render=ok` before `compose_build=vpnkit`.
- Negative deploy with `VPNKIT_MOCK_RENDER_FAIL=1` requires `local_config_render=failed` and `deploy_render=failed`, and asserts no `compose_build`, `compose_up`, `activation=no_build`, or rollback activation occurs.
- Redaction edge asserts mock renderer output `token=mock-render-secret` is only visible as `token=<redacted>` and raw token text is absent.

## Syntax evidence

Command:

```bash
bash -n scripts/vpnkit/vpnkit-prod-deploy.sh scripts/vpnkit/vpnkit-render-local-configs.sh test/prod-deploy-helper-test.sh
```

Result: passed (exit 0, no output).

## Outcome boundary

These checks prove local mocked deploy-helper ordering, failure behavior, redaction, tun-mode renderer invocation, and shell syntax. They intentionally do not mutate or verify live production hosts.
