# Local verification: OpenVPN push DNS prod deploy support

Date: 2026-06-13
Scope: local helper tests only; no live hosts touched.

## Commands

- `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh` — PASS
- `test/prod-deploy-helper-test.sh` — PASS
- `git diff --check` — PASS

## Evidence notes

- Mocked deploy verifies render completes before `openvpn_push_dns=updated`, and DNS sync completes before `compose_build=vpnkit`.
- Default mocked deploy rewrites `secrets/vps/rendered/openvpn/server.conf` to `push "dhcp-option DNS 1.1.1.1"` while preserving unrelated lines.
- Override mocked deploy with `VPNKIT_OPENVPN_PUSH_DNS=8.8.4.4` rewrites the same config to the override value.
- Invalid override and missing `server.conf` fail before mocked compose build/up.
- Output assertions keep secrets redacted; DNS sync logs only summary status.
