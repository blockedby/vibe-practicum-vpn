# Runtime data-path / DNS / SOCKS verification

Date: 2026-06-10
Worktree: `.worktrees/issue-24-smart-routing-manifest`
Branch: `feat/issue-24-smart-routing-manifest`

## Root cause evidence

- Prior live log `verification/logs/ru-ruleset-fixture-test6.log` showed server startup/checks passed, but `server:socks-inbound` failed with `SSL_ERROR_SYSCALL` while connecting through SOCKS to `example.com:443`.
- The isolated lab rendered `selected-native-out` from a dummy VLESS node pointing at `127.0.0.1:443`. There is no lab fixture proxy listening there, so any default/SOCKS egress that selects `selected-native-out` cannot complete. Fix: explicit `VPNKIT_SELECTED_OUTBOUND_MODE=proxy|direct-fixture`; renderer default remains `proxy`, lab setup defaults `direct-fixture`.
- Prior live log `verification/logs/ru-ruleset-fixture-test6.log` showed OpenVPN TLS/profile setup succeeded, but the client DNS probe to pushed VPN DNS was refused. The common server template pushed `10.89.0.1`, the OpenVPN server `tun0` address. In `tun` routing mode packets to that local address terminate in container INPUT and do not enter sing-box TUN. Fix: renderable `VPNKIT_OPENVPN_PUSH_DNS`; default remains `10.89.0.1`, lab setup defaults `172.19.0.1` so DNS packets traverse the pushed full-tunnel route into sing-box TUN.

## Fresh local checks

- `bash -n scripts/vpnkit-render-local-configs.sh scripts/vpnkit-test-lab-setup.sh test/containers-test.sh scripts/vpnkit-steamdeck-podman.sh`: PASS.
- `python3 test/sing-box-smart-routing-proof.py`: PASS — remote/local-fixture routing invariants preserved.
- Disposable lab setup/render: PASS — lab defaults render `selected-native-out` as direct with final/tag preserved, local RU fixtures, and OpenVPN pushes DNS `172.19.0.1`.
- Disposable explicit/default render: PASS — `VPNKIT_RULESET_SOURCE_MODE=remote VPNKIT_SELECTED_OUTBOUND_MODE=proxy` renders VLESS `selected-native-out` and OpenVPN DNS `10.89.0.1`.
- `go test ./...`: PASS.
- `go vet ./...`: PASS.
- `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: PASS.
- `python3 -m py_compile $(find scripts test -name '*.py' -print)`: PASS.
- Sensitive tracked artifact check: PASS — no tracked `.ovpn`, key, cert, PEM, secrets, rendered configs, or log paths found.

## Live isolated Deck sequence

Not run in this worktree: `config/private-endpoints.local.env` is absent, so no authorized non-placeholder Deck endpoint binding is available without printing/discovering private data. Attempted live runner gate returned `NO_PRIVATE_ENV` before mutation. No remote container state was changed by this slice.

Required live sequence when private bindings are available:

```bash
test -r config/private-endpoints.local.env && set -a && . config/private-endpoints.local.env && set +a
VPNKIT_TEST_ROUTING_MODE=tun test/containers-test.sh --scenario steamdeck-host --action down
VPNKIT_TEST_ROUTING_MODE=tun test/containers-test.sh --scenario steamdeck-host --action up
VPNKIT_TEST_ROUTING_MODE=tun test/containers-test.sh --scenario steamdeck-host --action test
VPNKIT_TEST_ROUTING_MODE=tun test/containers-test.sh --scenario steamdeck-host --action cycle
```

## Acceptance mapping

- AC root cause documented: PASS from code inspection plus prior live log symptoms.
- AC lab selected outbound fixture explicit, lab-only default, prod default proxy/VLESS: PASS from renderer modes and disposable render checks.
- AC DNS wiring changed safely: PASS locally for rendered config semantics; live pushed-DNS behavior still requires Deck run.
- AC live `down/up/test/cycle`: NOT RUN/BLOCKED by absent private env in this worktree.
- AC repo checks: PASS locally.
