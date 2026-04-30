# Production test plan for `vibe-vpn`

This plan is for testing the VPS-hosted `vibe-vpn` CLI on the live
`vibe-practicum` gateway without unnecessary disruption.

## 0. Preconditions

From the workstation:

```bash
cd ~/code/tools/vibe-practicum-vpn
git pull
GOOS=linux GOARCH=amd64 go build -o /tmp/vibe-vpn ./cmd/vibe-vpn
gzip -c /tmp/vibe-vpn > /tmp/vibe-vpn.gz
scp -C /tmp/vibe-vpn.gz vibe-practicum:/tmp/vibe-vpn.gz
ssh vibe-practicum 'gunzip -c /tmp/vibe-vpn.gz > /tmp/vibe-vpn.new && chmod +x /tmp/vibe-vpn.new && sudo install -o root -g root -m 755 /tmp/vibe-vpn.new /usr/local/bin/vibe-vpn'
```

On the VPS:

```bash
ssh vibe-practicum 'sudo test -s /etc/vibe-vpn/sub_url && echo sub_url:OK'
ssh vibe-practicum 'systemctl is-active xray && sudo ss -lntup | grep :10808'
```

Expected:

- subscription file exists;
- production `xray` is active;
- production SOCKS `:10808` is listening.

## 1. Baseline status test

```bash
ssh vibe-practicum 'sudo vibe-vpn status'
```

Expected output includes:

```text
xray: active
production_socks: 127.0.0.1:10808
current:
  name: ...
  server: host:port
  transport: ws|grpc|tcp / none|tls|reality
  last_speed: ... Mbps
live_check:
  socks: OK
  egress_ip: ...
  latency: ... ms
```

Pass criteria:

- `xray: active`;
- `live_check.socks: OK`;
- `egress_ip` is not the VPS public IP `45.12.74.211` when proxying is expected;
- current node is shown, or explicitly `unknown` with a reason.

## 2. Isolated smoke benchmark, no production change

```bash
ssh vibe-practicum 'sudo sha256sum /usr/local/etc/xray/config.json; sudo vibe-vpn test --limit-kib 64 --max 2; sudo sha256sum /usr/local/etc/xray/config.json'
```

Pass criteria:

- command finishes;
- at least one node is tested;
- output shows `BEST`;
- before/after sha256 of production xray config is identical;
- `ssh vibe-practicum 'sudo vibe-vpn status'` still works.

## 3. Full dry-run benchmark

```bash
ssh vibe-practicum 'sudo vibe-vpn test --limit-kib 256'
```

Pass criteria:

- production VPN stays usable during the test;
- output lists node speeds and a final `BEST`;
- `/var/lib/vibe-vpn/last-results.json` is written;
- production xray config is unchanged.

Useful inspection:

```bash
ssh vibe-practicum 'sudo python3 - <<"PY"
import json
r=json.load(open("/var/lib/vibe-vpn/last-results.json"))
ok=sorted([x for x in r if x.get("ok")], key=lambda x:x.get("mbps",0), reverse=True)
for x in ok[:10]: print(x.get("mbps"), x.get("name"), x.get("host"), x.get("port"), x.get("network"), x.get("security"))
PY'
```

## 4. Controlled production pick

Run when a short disruption is acceptable. The benchmark phase should not touch
production; only final apply restarts production `xray` once.

```bash
ssh vibe-practicum 'sudo vibe-vpn pick --limit-kib 256'
```

Pass criteria:

- output shows benchmark results and `BEST`;
- output says production was applied;
- `/var/lib/vibe-vpn/backups/` contains a new backup;
- `sudo vibe-vpn status` shows the chosen node;
- `live_check.socks: OK` and egress IP is through the selected upstream.

Post-pick checks:

```bash
ssh vibe-practicum 'sudo vibe-vpn status'
ssh vibe-practicum 'systemctl is-active xray'
```

Client checks from phone/PC using Tailscale exit-node:

- browser opens normal sites;
- YouTube starts playback;
- Telegram connects;
- external IP matches the proxy upstream, not the local ISP.

## 5. Rollback test

Only run after confirming there is a backup.

```bash
ssh vibe-practicum 'sudo ls -lt /var/lib/vibe-vpn/backups | head'
ssh vibe-practicum 'sudo vibe-vpn rollback'
ssh vibe-practicum 'sudo vibe-vpn status'
```

Pass criteria:

- rollback restores latest backup;
- `xray` is active;
- production SOCKS smoke check succeeds.

Known caveat for MVP:

- rollback restores xray config, but current-node metadata may be stale unless a
  matching metadata backup exists. Treat `status` current metadata after rollback
  as informational; `live_check` is authoritative.

## 6. Failure tests

### Missing subscription

```bash
ssh vibe-practicum 'sudo mv /etc/vibe-vpn/sub_url /etc/vibe-vpn/sub_url.tmp; sudo vibe-vpn test --max 1; sudo mv /etc/vibe-vpn/sub_url.tmp /etc/vibe-vpn/sub_url'
```

Expected: clear error, no production change.

### Occupied test port

```bash
ssh vibe-practicum 'python3 -m http.server 18080 >/tmp/vibe-port.log 2>&1 & echo $! >/tmp/vibe-port.pid; sudo vibe-vpn test --max 1; kill $(cat /tmp/vibe-port.pid)'
```

Expected: `test SOCKS address 127.0.0.1:18080 is already in use`, no production change.

## 7. After-test cleanup

```bash
ssh vibe-practicum 'sudo vibe-vpn status'
ssh vibe-practicum 'sudo find /tmp -maxdepth 1 -name "vibe-vpn-xray-*.json" -ls'
```

Expected:

- final status is healthy;
- no stale temporary xray config files are left.

## 8. Go/no-go checklist

Go if:

- `status` shows live SOCKS OK and egress IP;
- isolated `test` leaves production config unchanged;
- `pick` creates backup and applies winner;
- client devices work through Tailscale exit-node;
- rollback restores a working xray config.

No-go if:

- `status` cannot show live egress IP;
- `test` modifies production config;
- `pick` leaves `xray` inactive;
- client traffic stops after pick and rollback does not recover it.
