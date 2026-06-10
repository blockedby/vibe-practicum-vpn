# RU ruleset fixture verification

Date: 2026-06-10
Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`
Branch: `feat/issue-24-smart-routing-manifest`

## Local checks

- `bash -n scripts/*.sh test/*.sh`: PASS.
- `python3 test/sing-box-smart-routing-proof.py`: PASS — remote/default and local-fixture template invariants covered.
- Disposable local lab render with default lab mode: PASS — rendered `geoip-ru` and `geosite-category-ru` as local/source JSON fixtures under `rendered/sing-box/rule-sets/`.
- Disposable local lab render with `VPNKIT_RULESET_SOURCE_MODE=remote`: PASS — rendered remote binary RU `.srs` URLs.
- Local `sing-box check` on disposable fixture config with `/etc/sing-box` paths rewritten to the disposable rendered directory: PASS.
- `go test ./...`: PASS.
- `go vet ./...`: PASS.
- `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: PASS.
- Sensitive tracked artifact check: PASS — `git ls-files | grep -Ei '(\.ovpn$|\.key$|\.crt$|secrets/|rendered/|logs/)'` returned no tracked sensitive artifacts.

## Live isolated Deck matrix

Private endpoint file was absent in this worktree. The Deck endpoint was discovered through SSH alias `deck` without printing the value.

- `down`: PASS (`ru-ruleset-fixture-final-cleanup.log`; isolated `vpnkit-test-steamdeck-host` cleanup only).
- `up`: PASS (`ru-ruleset-fixture-up4.log`). Lab rendered local RU fixtures, refreshed persisted sing-box state before container run, and remote container started with no GitHub RU `.srs` downloads. Runtime `sing-box check` passed and `sb-tun0` was ready.
- `test`: BOUNDED FAIL (`ru-ruleset-fixture-test6.log`). Server-level readiness mostly passed: SSH reachable, container running, OpenVPN process, sing-box process, `tun0`, `sb-tun0`, runtime `sing-box check`, and config shape. Remaining failures:
  - `server:socks-inbound`: curl through SOCKS failed with `SSL_ERROR_SYSCALL`.
  - `client:steamdeck-profile-smoke`: OpenVPN client connected and completed TLS/profile setup after cert key-usage fix, but DNS probe failed (`connection refused` to pushed VPN DNS), so client smoke failed.
- `cycle`: not rerun after `test` failed; running it would reproduce the same client/DNS failure after the already-green `down`/`up` phases.

## Root cause/resolution for current blocker

Resolved: the previous startup blocker was stale/persisted remote RU rule-set config plus default remote RU rule-set rendering for the lab. The lab now defaults local fixture mode, generates local source JSON RU fixtures, and the Steam Deck deploy path removes persisted sing-box config before isolated lab container start so refreshed rendered config is used.

## Remaining blocker

U-01: Isolated Deck lab is not fully green. The next blocker is no longer remote RU `.srs` download; it is runtime data-path/DNS/SOCKS behavior after the server is up. Evidence: `ru-ruleset-fixture-test6.log` shows OpenVPN TLS succeeds, but pushed VPN DNS is refused and SOCKS HTTPS returns `SSL_ERROR_SYSCALL`.

## Commit and public updates

- Commit pushed: current branch head (`fix(lab): use local RU rule fixtures for Steam Deck`).
- Issue #27 update: https://github.com/blockedby/vibe-practicum-vpn/issues/27#issuecomment-4667856262
- PR #26 update: https://github.com/blockedby/vibe-practicum-vpn/pull/26#issuecomment-4667856378
