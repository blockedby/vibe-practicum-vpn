# VPS deploy verification: RU direct sing-box routing

Date: 2026-06-02 UTC
Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/ru-direct-singbox`
Branch/head: `ru-direct-singbox` @ `d342683`
Target: `vibe-practicum` Docker container `vpnkit`, image tag `vpnkit:vps`, OpenVPN `45.12.74.211:1194/udp`.

## Predeploy

```text
$ git status --porcelain=v1 && git branch --show-current && git log --oneline origin/main..HEAD
ru-direct-singbox
d342683 Add RU direct acceptance audit
7531869 Finalize RU direct Docker lab evidence
3d6d344 Fix vpnkit startup readiness for Docker lab
...
```

Worktree was clean. Local acceptance evidence in `final-report.md` was fresh from 2026-06-02; targeted predeploy check also passed:

```text
$ go test ./...
ok github.com/kcnc/vibe-practicum-vpn/internal/singbox (cached)
... all packages passed/cached ...
```

Initial live state before mutation:

```text
$ ssh vibe-practicum 'sudo docker ps --filter name=^/vpnkit$ --format ...'
vpnkit vpnkit:vps 0.0.0.0:1194->1194/udp, [::]:1194->1194/udp Up 3 hours
```

## Deploy actions

- Synced current branch source to `/opt/vpnkit/src` without copying local `secrets/`, `logs/`, `.git/`, generated configs, or profiles.
- Wrote deployed source marker `/opt/vpnkit/src/.deployed-git-rev` = `d342683`.
- Preserved live Docker runtime convention from the already-running container: host bind mounts under `/opt/vpnkit/secrets`, `/opt/vpnkit/state`, and `/opt/vpnkit/logs`; did not touch Steam Deck or native services.
- Deliberately regenerated the rendered sing-box config from the new template and the existing live rendered `selected-native-out`, then installed it to both:
  - `/opt/vpnkit/secrets/vps/rendered/sing-box/config.json`
  - `/opt/vpnkit/state/sing-box/config.json` (the persisted live file mounted at `/var/lib/vpnkit/sing-box/config.json`)
- Built `vpnkit:vps` from `/opt/vpnkit/src`.
- Recreated `vpnkit` with the existing Docker runtime env/mounts/ports and `VPNKIT_ENABLE_VIBE_VPN_DAEMON=true`.

Config proof before restart:

```text
57:    { "type": "direct", "tag": "direct-out" },
64:      { "rule_set": "geoip-ru", "outbound": "direct-out" },
65:      { "rule_set": "geosite-category-ru", "outbound": "direct-out" }
70:        "tag": "geoip-ru",
73:        "download_detour": "direct-out"
77:        "tag": "geosite-category-ru",
80:        "download_detour": "direct-out"
```

`sing-box check` against the persisted config exited 0 with only the known deprecation warnings when the existing compatibility env vars were set.

## Postdeploy runtime evidence

```text
$ ssh vibe-practicum 'sudo docker ps --filter name=^/vpnkit$ --format ...'
vpnkit vpnkit:vps 0.0.0.0:1194->1194/udp, [::]:1194->1194/udp Up 36 seconds

$ ssh vibe-practicum 'sudo docker exec vpnkit ps auxww | grep -E "[o]penvpn|[s]ing-box|[v]ibe-vpn daemon"'
root 14 ... sing-box run -c /var/lib/vpnkit/sing-box/config.json
root 34 ... openvpn --config /etc/openvpn/server.conf
root 94 ... vibe-vpn daemon --config /etc/vibe-vpn/config.yaml

$ ssh vibe-practicum 'sudo docker exec vpnkit grep -n "geoip-ru\|geosite-category-ru\|direct-out" /var/lib/vpnkit/sing-box/config.json | head -20'
57:    { "type": "direct", "tag": "direct-out" },
64:      { "rule_set": "geoip-ru", "outbound": "direct-out" },
65:      { "rule_set": "geosite-category-ru", "outbound": "direct-out" }
70:        "tag": "geoip-ru",
73:        "download_detour": "direct-out"
77:        "tag": "geosite-category-ru",
80:        "download_detour": "direct-out"
```

Healthy startup/log excerpts:

```text
router: updated rule-set geoip-ru
router: updated rule-set geosite-category-ru
inbound/redirect[vpnkit-redirect-in]: tcp server started at 0.0.0.0:2082
inbound/direct[vpnkit-dns-in]: udp server started at 0.0.0.0:5353
sing-box inbounds ready
OpenVPN ... Initialization Sequence Completed
started vibe-vpn daemon pid=94 config=/etc/vibe-vpn/config.yaml
router: match[3] rule_set=geosite-category-ru => route(direct-out)
outbound/direct[direct-out]: outbound connection to ya.ru:443
```

## Live OpenVPN client regression

Command run from local host using a gitignored copied test profile, then the profile/log were removed from the worktree:

```bash
scripts/vpnkit-steamdeck-client-test.sh \
  --endpoint 45.12.74.211 \
  --port 1194 \
  --runtime docker \
  --profile secrets/vps/openvpn/client/test-client.ovpn \
  --log-file logs/vps-client-test-45.12.74.211.log
```

Result: passed. The script hit a local `tee: ... Permission denied` for the requested log path, so evidence was captured from command output instead of keeping a raw log artifact.

Key output:

```text
inet 10.89.0.2/24 scope global tun0
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 35176
example.com. 24 IN A 104.20.23.154
example.com. 24 IN A 172.66.147.243
https-test http_code=200 remote_ip=172.66.147.243
literal-ip-test http_code=200 remote_ip=1.1.1.1
```

## Acceptance matrix

- AC1 predeploy clean/fresh enough: passed (`git status` clean; `go test ./...` passed; local Docker lab final evidence was same-day green).
- AC2 VPS Docker runtime updated from this branch: passed (`/opt/vpnkit/src` synced to `d342683`; `vpnkit:vps` rebuilt; container recreated only on `vibe-practicum`).
- AC3 persisted live sing-box config replaced and verified: passed (`/opt/vpnkit/state/sing-box/config.json` / container `/var/lib/vpnkit/sing-box/config.json` include `geoip-ru`, `geosite-category-ru`, `direct-out`).
- AC4 container healthy after recreate: passed (`docker ps`, OpenVPN/sing-box/vibe-vpn processes, healthy logs).
- AC5 live OpenVPN client regression: passed (`10.89.0.2/24`, DNS `NOERROR`, HTTPS `200`, literal-IP HTTPS `200`).
- AC6 task package evidence/report: passed (this file plus `reports/aad-slice-owner-vps-deploy.md`).

## Root owner post-slice recheck

After integrating the deployment slice, the root owner reran live readiness checks.

```text
$ git status --short
 M docs/plans/2026-06-02-ru-direct-singbox/plan.md
?? docs/plans/2026-06-02-ru-direct-singbox/reports/aad-slice-owner-vps-deploy.md
?? docs/plans/2026-06-02-ru-direct-singbox/verification/vps-deploy.md
```

Only task-package evidence files were modified/untracked; `secrets/` was absent after cleanup.

```text
$ ssh vibe-practicum 'sudo docker ps ...; sudo docker exec vpnkit ps ...; sudo docker exec vpnkit grep ... /var/lib/vpnkit/sing-box/config.json'
vpnkit vpnkit:vps 0.0.0.0:1194->1194/udp, [::]:1194->1194/udp Up 3 minutes
root ... sing-box run -c /var/lib/vpnkit/sing-box/config.json
root ... openvpn --config /etc/openvpn/server.conf
root ... vibe-vpn daemon --config /etc/vibe-vpn/config.yaml
64:      { "rule_set": "geoip-ru", "outbound": "direct-out" },
65:      { "rule_set": "geosite-category-ru", "outbound": "direct-out" }
```

Root owner also reran the live client regression using a temporary copied gitignored profile and `/tmp/vps-client-test-ru-direct-root.log`, then removed the copied `secrets/` tree and temp log:

```text
$ scripts/vpnkit-steamdeck-client-test.sh --endpoint 45.12.74.211 --port 1194 --runtime docker --profile secrets/vps/openvpn/client/test-client.ovpn --log-file /tmp/vps-client-test-ru-direct-root.log
inet 10.89.0.2/24 scope global tun0
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 19430
https-test http_code=200 remote_ip=104.20.23.154
literal-ip-test http_code=200 remote_ip=1.1.1.1
```

Result: passed.
