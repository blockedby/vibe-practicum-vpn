# Verification: vpnkit vibe-vpn daemon + lil-sweden Hysteria2

Date: 2026-06-01
Branch: `pi/vpnkit-vibe-daemon-hy2`

## Local static checks

Passed:

```bash
go test ./...
go build ./cmd/vibe-vpn
docker compose config
docker compose --profile test config
bash -n docker/vpnkit/entrypoint.sh scripts/vpnkit-render-local-configs.sh
git diff --check
```

## Docker image/build checks

Passed:

```bash
docker build -t vpnkit:vibe-daemon-hy2 -f docker/vpnkit/Dockerfile .
```

Container sing-box template check with placeholder `selected-native-out` replaced by a direct outbound:

```bash
docker run --rm --entrypoint sing-box \
  -e ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true \
  -e ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true \
  -v "$PWD/.tmp/verify/sing-box-config.json:/tmp/config.json:ro" \
  vpnkit:vibe-daemon-hy2 check -c /tmp/config.json
```

Result: passed with the known sing-box deprecation warnings only.

## Local Hysteria2 extra-node environment check

A local `vibe-vpn test` using the new Hysteria2 extra-node support reached the new code path but failed from this host:

```text
WARN subscription unavailable: ... contains no subscription URLs; testing extra nodes only
Fetched 0 subscription nodes + 1 extra nodes, 1 after filters.
[001/001] FAIL socks connect reply [5 1 0 1]
Error: no working non-excluded node
```

Classification: expected/environmental. Earlier direct official Hysteria client tests from this local network to `lil-sweden` timed out, while the same server works from `vibe-practicum`.

## Remote Hysteria2 extra-node test from vibe-practicum

Copied the branch-built `vibe-vpn` binary and a temporary gitignored auth file to `/tmp` on `vibe-practicum`. The temporary files were removed after verification.

Dry-run benchmark using only `lil-sweden` as an extra node:

```text
WARN subscription unavailable: /tmp/vibe-vpn-hy2-test/sub_url contains no subscription URLs; testing extra nodes only
Fetched 0 subscription nodes + 1 extra nodes, 1 after filters.
Testing isolated on 127.0.0.1:18080; production stays untouched.
Benchmark mode: download up to 1024 KiB per node.
[001/001]   29.15 Mbps  0.29s #001 lil-sweden hy2 remote-check

Done: 1 ok, 0 failed. Results saved to last-results.json.

Top 1 by speed:
  #001    29.15 Mbps  lil-sweden hy2 remote-check                 84.22.149.216:443 hysteria2/tls

BEST:
  #001 lil-sweden hy2 remote-check
  29.15 Mbps
Dry run only. Use 'vibe-vpn pick' to apply winner.
```

Apply safety test against a temporary sing-box config and request-file restart adapter:

```text
Applying #001 29.15 Mbps lil-sweden hy2 remote-check (84.22.149.216:443 hysteria2/tls)
Applied to production singbox. Backup: /tmp/vibe-vpn-hy2-test/state/backups/sing-box-20260601-065403.567862663.json
apply-check-ok
```

The apply test did not modify the live VPS `vpnkit` container or production sing-box config; it used only `/tmp/vibe-vpn-hy2-test/production-sing-box.json` and `/tmp/vibe-vpn-hy2-test/restart-sing-box`.

Daemon smoke from `vibe-practicum`:

```text
timeout 4 /tmp/vibe-vpn-hy2-test-bin daemon --config /tmp/vibe-vpn-hy2-test/config.yaml
rc=124
```

Classification: passed smoke. The daemon stayed running until the test timeout killed it.

## Security cleanup

Removed temporary remote/local auth and test artifacts:

```text
vibe-practicum:/tmp/lil-sweden-hy2-auth
vibe-practicum:/tmp/vibe-vpn-hy2-test-bin
vibe-practicum:/tmp/vibe-vpn-hy2-test
.local .tmp/hy2-vibe-test
```
