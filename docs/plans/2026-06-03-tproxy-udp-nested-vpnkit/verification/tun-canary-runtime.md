# TUN canary runtime verification

Date: 2026-06-03
Task: Task 5 opt-in vpnkit sing-box TUN-mode runtime path

## Automated checks

| Check | Result | Notes |
| --- | --- | --- |
| `bash tests/vpnkit-singbox-template-test.sh` | PASS | Covers redirect unchanged, tproxy unchanged, tun template inbound/interface/address/MTU/stack, tun route rules, entrypoint `config.tun.json` selection string, and render-script tun output string. |
| `bash tests/vpnkit-setup-routing-test.sh` | PASS | Covers existing tproxy private UDP bypass ordering, redirect mode absence of tproxy bypass chains, and tun dry-run policy route/rule with no redirect/tproxy capture rules. |
| `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh` | PASS | Shell syntax for touched scripts/tests. |
| `go test ./...` | PASS | Repo Go tests. |
| `git diff --check` | PASS | No whitespace errors. |
| Dummy rendered `sing-box check` for redirect/tproxy/tun templates | PASS | Used placeholder `{ "type": "direct", "tag": "selected-native-out" }`; local sing-box 1.13.12 required `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true` and `ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true`; warnings only. |

## RED/GREEN evidence

- RED: before production changes, `bash tests/vpnkit-singbox-template-test.sh` failed with `FileNotFoundError` for `config/sing-box/config.tun.json.template`.
- GREEN: after adding the tun template and wiring, `bash tests/vpnkit-singbox-template-test.sh` and `bash tests/vpnkit-setup-routing-test.sh` passed.

## Runtime behavior covered by source/tests

- Redirect/default mode still selects `/etc/sing-box/config.json`, still has `vpnkit-redirect-in` on TCP 2082 and DNS direct inbound on UDP 5353, and does not include `vpnkit-tun-in`.
- Tproxy mode still selects `/etc/sing-box/config.tproxy.json` and still expects TCP/UDP 2082, TCP 2083, and UDP 5353 readiness.
- Tun mode selects `/etc/sing-box/config.tun.json`, waits for `sb-tun0` with `172.19.0.1/30` plus UDP 5353, and does not wait for redirect/tproxy-only ports.
- Tun mode policy-routes `OVPN_CIDR` (`10.89.0.0/24` default) to routing table 101 via `sb-tun0`/`172.19.0.2` and does not install redirect/tproxy capture chains in the dry-run test.
- Tun template uses `auto_route=false` and the setup script installs only the source-CIDR policy route, so sing-box process egress is not globally re-routed into its own TUN interface.

## Production/live boundary

- No production containers or live hosts were mutated during Task 5 implementation checks.
- No secrets, rendered config contents, profiles, endpoint values, or logs are stored in this verification file.
