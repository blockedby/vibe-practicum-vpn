# Runtime smoke verification

## 2026-06-02 pre-live safety gate

Claim checked: whether this owner can safely inspect/mutate the live `moscow-tiger` Docker runtime and run a fresh host Docker OpenVPN client smoke.

Command:

```bash
test -r config/private-endpoints.local.env && { echo present; sed -n '1,120p' config/private-endpoints.local.env | sed -E 's/(=.*/=<redacted>/' ; } || echo absent
```

Safe output excerpt:

```text
absent
```

Result: blocked before live/runtime commands. The repo requires loading gitignored private endpoint values before commands requiring real private endpoints; with `config/private-endpoints.local.env` absent, live target inspection, mutation, and host-to-target client smoke were not run.

No real endpoints, SSH aliases, subscription URLs, profiles, rendered configs, auth values, or raw logs were written to this artifact.

## 2026-06-02 continuation pre-live safety gate

Claim checked: whether the newly copied `config/private-endpoints.local.env` contains usable live endpoint values for `moscow-tiger` access without exposing them.

Commands:

```bash
sed -n '1,120p' config/private-endpoints.local.env | sed -E 's/(=).*/=REDACTED/'
set -a; . config/private-endpoints.local.env; set +a
: "${VPNKIT_VPS_SSH_HOST:?missing}"
ssh -o BatchMode=yes "$VPNKIT_VPS_SSH_HOST" 'set -e; hostname | sed "s/.*/[redacted-host]/"; pwd; docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | sed -E "s/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[redacted-ip]/g"'
```

Safe output excerpt:

```text
config/private-endpoints.local.env: present; all values redacted for safety.
SSH failed before live runtime inspection: Could not resolve hostname your-vps-ssh-alias: Name or service not known.
```

Result: blocked before live/runtime commands. The copied local endpoint file is present, but `VPNKIT_VPS_SSH_HOST` is still the example placeholder, not a resolvable operator-local SSH target. Because the target cannot be reached, no live Docker logs/config/processes/listeners/routes/iptables/nftables evidence, targeted in-container checks, runtime mutation, or fresh host Docker OpenVPN client smoke could be run.

Public-safety check:

```bash
git status --short
```

Safe output excerpt:

```text
?? docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix/
```

No private endpoint values, generated profiles, rendered configs, raw logs, snapshots, subscription URLs, auth values, or secrets were staged or committed.

## 2026-06-02 source MTU/MSS durability and local render guard

Claim checked: the tracked OpenVPN render source on branch `aad/moscow-tiger-runtime-smoke-fix` persists the live MTU/MSS fix and a render from this checkout includes both directives.

Commands:

```bash
go test ./internal/config
bash -n scripts/*.sh
grep -nE '^(tun-mtu 1400|mssfix 1360)$' config/openvpn/server.tpl
# Render with throwaway fake local inputs; no private values or rendered files committed.
VPNKIT_SECRETS_DIR="$tmp" scripts/vpnkit-render-local-configs.sh
grep -nE '^(tun-mtu 1400|mssfix 1360)$' "$tmp/rendered/openvpn/server.conf"
cat "$tmp/rendered/vibe-vpn/extra-nodes.json"
go test ./...
```

Safe output excerpt:

```text
ok   github.com/kcnc/vibe-practicum-vpn/internal/config 0.002s
8:tun-mtu 1400
9:mssfix 1360
8:tun-mtu 1400
9:mssfix 1360
extra-nodes=[]
go test ./...: passed
```

Result: source durability guard passed locally. The tracked template contains `tun-mtu 1400` and `mssfix 1360`, a render from this branch includes both directives, and the render path writes an empty extra-nodes list when no gitignored extra-nodes input exists.

## 2026-06-02 source-based live deploy/smoke gate

Claim checked: whether this environment can deploy the source-rendered config to `moscow-tiger` and rerun fresh host Docker client baseline plus explicit 2ip smoke.

Commands:

```bash
set -a; . config/private-endpoints.local.env; set +a
: "${VPNKIT_VPS_SSH_HOST:?missing}"
ssh -o BatchMode=yes "$VPNKIT_VPS_SSH_HOST" 'true'
```

Safe output excerpt:

```text
config/private-endpoints.local.env is present but still uses the example SSH placeholder.
SSH failed before live access: Could not resolve hostname your-vps-ssh-alias: Name or service not known.
```

Result: live deploy and fresh smoke remain blocked from this worktree by the same operator-local endpoint boundary. No SSH, remote render/deploy/recreate, Docker client baseline, or 2ip smoke commands were run. No private endpoint values, rendered configs, generated profiles, raw logs, subscription URLs, auth files, or secrets were printed, staged, or committed.
