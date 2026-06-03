## Task
- Mission: implement and document chosen OpenVPN subnets in `vpnkit-tproxy-udp-nested`.
- Outer/default subnet: `10.231.89.0/24`; gateway/DNS: `10.231.89.1`.
- Future nested/inner guidance subnet: `10.232.90.0/24`.
- Boundaries: source/docs/tests only; no production hosts, generated profiles, secrets, logs, rendered configs, or private endpoint values touched.

## Changed files
- `config/openvpn/server.tpl` — default server subnet/DNS now render `10.231.89.0 255.255.255.0` and `10.231.89.1`.
- `docker/vpnkit/setup-routing.sh` — default `OVPN_CIDR` now `10.231.89.0/24`.
- `scripts/openvpn-asus-install.sh` — active OpenVPN defaults updated to `10.231.89.0/24`, gateway `10.231.89.1`, ASUS/static IP `10.231.89.2`, pool `10.231.89.20-10.231.89.254`.
- `scripts/openvpn-asus-rollback.sh`, `scripts/openvpn-asus-status.sh` — default VPN CIDR updated.
- `scripts/openvpn-asus-pool-tproxy-profile.sh`, `scripts/openvpn-asus-tproxy-canary-rules.sh` — current guidance/default IP ranges updated.
- `scripts/vpnkit-routing-compat-bypass-test.sh`, `tests/vpnkit-setup-routing-test.sh` — routing expectations updated to new default CIDR.
- `tests/openvpn-server-template-test.sh` — added focused template default check.
- Task package docs/reports/verification — added current guidance notes for outer `10.231.89.0/24` and future nested `10.232.90.0/24` while preserving historical evidence.

## Historical references intentionally left
- Prior validation evidence under `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/`, prior reports, and progress files still mention `10.89.0.0/24`, `10.89.0.1`, `10.89.0.2`, and temporary nested `10.90.0.0/24` because those are facts from earlier runs.
- Notes were added where useful to clarify that future guidance is outer `10.231.89.0/24` and nested/inner `10.232.90.0/24`; the previous `10.90.0.0/24` was temporary validation evidence.
- `internal/ikev2/registry_test.go` keeps `10.89.0.2` as an unrelated negative/sample value, not an OpenVPN default.

## Verification run
- `bash tests/openvpn-server-template-test.sh` — passed.
- `bash tests/vpnkit-setup-routing-test.sh` — passed.
- `bash tests/vpnkit-singbox-template-test.sh` — passed.
- `bash scripts/vpnkit-routing-compat-bypass-test.sh` — passed.
- `go test ./...` — passed.
- `git diff --check` — passed.

## Commit / push
- Implementation commit: `a428a0c` (`Set vpnkit OpenVPN subnet defaults`).
- Report commit: `fcc3321` (`Report OpenVPN subnet default update`).
- Branch pushed: `origin/vpnkit-tproxy-udp-nested`.

## Verdict
- Status: success.
- Goal state: achieved for source/docs/tests.
- System readiness: source default change is ready based on focused checks; no live/runtime mutation was performed or needed for this source/docs/test-only task.
