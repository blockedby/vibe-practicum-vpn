# Apply adapter verification

## Summary
- Result: **partial**. Container-safe request-file adapter and supervisor-owned sing-box restart are implemented and verified through apply request/restart evidence. Full post-switch OpenVPN client network acceptance did not pass with the available real subscription node because the selected node's hostname caused sing-box DNS lookup loop/timeouts after switching.
- Secrets: real node names/hosts are omitted here; detailed local logs are under ignored `logs/` and contain runner redaction.

## Fresh local checks
- `go test ./...` — passed.
- `go vet ./...` — passed.
- `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn` — passed.
- `bash -n scripts/vpnkit-vibe-vpn-e2e.sh docker/vpnkit/entrypoint.sh scripts/vpnkit-render-local-configs.sh` — passed.
- `docker compose config >/tmp/vpnkit-compose-config.txt` — passed.

## Real vpnkit e2e switching attempt
Command:
```bash
scripts/vpnkit-vibe-vpn-e2e.sh --run-id apply-adapter-rerun-20260601T031905Z --switching --cleanup-on-failure --no-cleanup-images
```

Evidence:
- Build and startup passed.
- `vibe-vpn doctor --config /etc/vibe-vpn/config.yaml` passed.
- `vibe-vpn test --limit-kib 64 --max 2` fetched 9 subscription nodes, 8 after filters, tested 2, yielded 1 OK / 1 failed.
- Baseline pre-switch OpenVPN client passed: client received `10.89.0.2`, DNS query succeeded, HTTPS domain check returned 200, literal-IP HTTPS check returned 200.
- `vibe-vpn apply --config /etc/vibe-vpn/config.yaml best` succeeded and wrote a backup under `/var/lib/vibe-vpn/backups/`.
- `vibe-vpn current` showed the selected node/state updated (node details redacted here).
- `sing-box check -c /var/lib/vpnkit/sing-box/config.json` passed after apply.
- Post-switch OpenVPN client reconnected but DNS query timed out; command exited 9. The runner cleaned containers/volumes because `--cleanup-on-failure` was set.
- Earlier preserved-artifact run logs showed the supervisor saw `restart requested for sing-box` and started a new sing-box process from `/var/lib/vpnkit/sing-box/config.json`; a race where the parent monitor exited on the old PID was fixed before the rerun.

Classification:
- R-1: request-file restart adapter works well enough for `apply` to write validated config and request supervisor restart without `systemctl`.
- R-2: entrypoint remains the sole long-lived sing-box owner after the race fix; no second long-lived `sing-box run` is started by `vibe-vpn`.
- U-1: full switched data path is not accepted. Available real winner uses a domain-form upstream; after apply, sing-box logs (from the preserved first attempt) reported DNS lookup loop for the selected server hostname and client DNS timed out. This needs a follow-up design/fix for resolving selected outbound server hostnames without looping through the outbound whose hostname is being resolved.

## Secret / forbidden-pattern checks
- Changed tracked files contain no real subscription URL, private key, or credential. Grep hits for `vless://` are only existing tests/docs/redaction patterns outside changed implementation files.
- Static grep for broad runtime `10.89.0.0/24` MASQUERADE in changed runtime areas: no new broad MASQUERADE rule added.
