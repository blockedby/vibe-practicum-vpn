# Root final live verification: Steam Deck lab lifecycle green

Date: 2026-06-10
Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`
Branch: `feat/issue-24-smart-routing-manifest`

## Private/public-safety handling

- Private endpoint file was sourced only if present; this worktree did not rely on committing any private bindings.
- When no usable endpoint env was present, the Deck endpoint was discovered through SSH alias `deck` using `ip -4 -o addr show scope global` and stored only in process-local environment.
- Endpoint values were not printed in this report; harness output redacted IPs as `<IP>`.
- All live operations targeted isolated `vpnkit-test-steamdeck-host` with Podman and the isolated lab state/port defaults, not default/prod `vpnkit`.
- Final cleanup `down` was run after green `cycle`; final isolated lab container state is cleaned up.

## Live matrix

Environment summary (public-safe):

- `VPNKIT_TEST_SSH_TARGET=deck`
- `VPNKIT_TEST_RUNTIME=podman`
- `VPNKIT_TEST_ROUTING_MODE=tun`
- `VPNKIT_TEST_SERVER_CONTAINER=vpnkit-test-steamdeck-host` (defaulted by scenario)
- `VPNKIT_STEAMDECK_LOGS_TIMEOUT=20`
- `VPNKIT_STEAMDECK_VERIFY_TIMEOUT=60`
- `VPNKIT_TEST_CLIENT_TIMEOUT=180`
- `VPNKIT_TEST_DEPLOY_TIMEOUT=900`

Commands/results:

- `test/containers-test.sh --scenario steamdeck-host --action down`: PASS. Log: `logs/root-live2-down-20260610T080522Z.log`.
- `test/containers-test.sh --scenario steamdeck-host --action up`: PASS. Log: `logs/root-live2-up-20260610T080522Z.log`.
  - Lab generated local RU fixtures and direct selected-outbound fixture.
  - Runtime `sing-box` started; no GitHub RU `.srs` downloads.
  - `openvpn`, `tun0`, `sb-tun0`, and runtime `sing-box check` passed.
- `test/containers-test.sh --scenario steamdeck-host --action test`: PASS with honest non-required SKIPs. Log: `logs/root-live2-test-20260610T080606Z.log`.
  - PASS: SSH, container running, OpenVPN process, sing-box process, `tun0`, `sb-tun0`, runtime `sing-box check`, SOCKS inbound, config shape, OpenVPN client smoke.
  - Client smoke proved TLS/cert validation, pushed DNS query, HTTPS by hostname, and HTTPS by literal IP.
  - SKIP: `server:route-decision-proof` scaffold and `client:policy-visible-extension` TODO; these are not counted as required lifecycle acceptance. Repo-local smart-routing proof covers route policy semantics separately.
- `test/containers-test.sh --scenario steamdeck-host --action cycle`: PASS with honest non-required SKIPs. Log: `logs/root-live2-cycle-20260610T080613Z.log`.
  - Summary: PASS=13 FAIL=0 SKIP=2.
- Final cleanup `test/containers-test.sh --scenario steamdeck-host --action down`: PASS. Log: `logs/root-live2-down-20260610T080631Z.log`.

Note: the ad-hoc root wrapper printed `ROOT_LIVE_MATRIX ... cycle=99` because the wrapper initialized `rc_cycle=99` and did not reset it after a successful `run_phase cycle`. The actual harness phase line and log show `=== phase:cycle rc=0 ... ===`, and the cycle harness summary is PASS=13 FAIL=0 SKIP=2.

## Fresh local checks after final live run

- `bash -n scripts/vpnkit-render-local-configs.sh scripts/vpnkit-test-lab-setup.sh scripts/vpnkit-steamdeck-podman.sh scripts/vpnkit-steamdeck-client-test.sh test/containers-test.sh`: PASS.
- `python3 test/sing-box-smart-routing-proof.py`: PASS.
- `go test ./...`: PASS.
- `go vet ./...`: PASS.
- `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: PASS.
- `python3 -m py_compile $(find scripts test -name '*.py' -print)`: PASS.
- Sensitive tracked artifact check with `git ls-files | grep -Ei '(\.ovpn$|\.pem$|\.key$|\.crt$|secrets/|rendered/|logs/)'`: PASS/no matches.

## Acceptance mapping

- RU remote `.srs` startup blocker: PASS. Lab defaults local RU source fixtures; live `up` no longer downloads GitHub RU rule sets at startup.
- Persisted sing-box drift: PASS. Isolated run path refreshes persisted sing-box config before start.
- Direct selected-outbound fixture: PASS. Lab direct fixture avoids impossible dummy VLESS egress and `server:socks-inbound` passed.
- DNS path: PASS. Lab pushes DNS into sing-box TUN path and client smoke DNS probe passed.
- Lifecycle: PASS. `down`, `up`, `test`, `cycle`, and final cleanup all completed boundedly against the isolated lab.
- Public safety: PASS. No private endpoints, profiles, cert/key material, rendered configs, logs, or secrets are tracked or included here.
