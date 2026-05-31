# Local verification: Google DoT DNS

Commands run from worktree `.worktrees/containerized-vpnkit-openvpn-singbox` on branch `pi/containerized-vpnkit-openvpn-singbox`.

## RED check

- `python3` template assertion for Google DoT primary/fallback before production edit: failed as expected with missing `remote-dns` `tls://8.8.8.8` and `remote-dns-fallback` `tls://8.8.4.4`.

## GREEN / validation checks

- `python3` template assertion after edit: passed; confirmed:
  - `remote-dns` address `tls://8.8.8.8`, detour `selected-native-out`
  - `remote-dns-fallback` address `tls://8.8.4.4`, detour `selected-native-out`
  - DNS `final` remains `remote-dns`
- `./scripts/vpnkit-render-local-configs.sh`: passed; rendered only gitignored local files under `secrets/` and printed file paths only.
- `jq -e` on rendered `secrets/vps/rendered/sing-box/config.json`: passed for both Google DoT entries.
- `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true sing-box check -c secrets/vps/rendered/sing-box/config.json`: passed with existing sing-box deprecation warnings; no config contents or secrets printed.
- `python3 ... | jq -e .` on `config/sing-box/config.json.template` with placeholder replaced: passed.
- `jq -e . secrets/vps/rendered/sing-box/config.json`: passed.
- `bash -n scripts/vpnkit-render-local-configs.sh`: passed.
- `git diff --check`: passed.
- `grep -R "tls://1\.1\.1\.1" config docker scripts docs/CONTAINERIZED_VPNKIT_RUNBOOK.md`: no matches.
- `grep -R "1\.1\.1\.1:853" docs/CONTAINERIZED_VPNKIT_RUNBOOK.md docs/plans/2026-05-31-containerized-vpnkit docs/plans/2026-06-01-google-dot-dns`: remaining matches are explicitly historical prior-run evidence or this task's plan/progress notes; literal-IP HTTPS `1.1.1.1:443` checks were not changed.

## Notes

- `secrets/` remains gitignored; rendered files were validated but not staged.
- A first local `sing-box check` without `ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true` failed on a pre-existing sing-box 1.13 deprecation gate. Re-running with both compatibility env vars passed.
