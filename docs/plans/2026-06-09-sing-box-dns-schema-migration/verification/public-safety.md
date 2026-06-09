$ changed tracked/untracked files
config/sing-box/config.json.template
config/sing-box/config.tun.json.template
docker-compose.yml
docs/plans/2026-06-09-sing-box-dns-schema-migration/plan.md
docs/plans/2026-06-09-sing-box-dns-schema-migration/README.md
docs/plans/2026-06-09-sing-box-dns-schema-migration/verification/local.md
docs/plans/2026-06-09-sing-box-dns-schema-migration/verification/public-safety.md
scripts/vpnkit-prod-singbox-dns-migration.sh
scripts/vpnkit-steamdeck-podman.sh
tests/sing-box-dns-schema-test.sh
tests/vpnkit-production-routing-wiring-test.sh
$ public-safety grep over changed tracked/untracked files
scripts/vpnkit-prod-singbox-dns-migration.sh:59:    -e 's#vless://[^[:space:]]+#vless://[redacted]#g' \
scripts/vpnkit-steamdeck-podman.sh:82:    -e 's#vless://[^[:space:]]+#vless://[redacted]#g' \
note: vless:// matches in changed files are redaction/test pattern literals only, not secret values.
