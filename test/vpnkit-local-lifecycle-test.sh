#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/vpnkit-local-lifecycle.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/secrets/vibe-vpn"
: >"$tmp/docker.log"
cat >"$tmp/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >>"$MOCK_DOCKER_LOG"
if [[ " $* " == *" compose "* && " $* " == *" ps -q vpnkit "* ]]; then exit 0; fi
exit 99
EOF
chmod +x "$tmp/bin/docker"

export PATH="$tmp/bin:$PATH"
export MOCK_DOCKER_LOG="$tmp/docker.log"
export VPNKIT_LOCAL_SECRETS_DIR="$tmp/secrets"
export VPNKIT_LOCAL_COMPOSE_PROJECT=vpnkit-local-test
export VPNKIT_LOCAL_MANAGE_NETWORKMANAGER=false
lifecycle="$repo_root/scripts/vpnkit/vpnkit-local.sh"
renderer="$repo_root/scripts/vpnkit/vpnkit-render-local-kde-configs.sh"
assets="$repo_root/scripts/vpnkit/vpnkit-local-assets.sh"

bash -n "$lifecycle" "$renderer" "$assets" "$repo_root/docker/vpnkit/entrypoint.sh" "$repo_root/docker/vpnkit/setup-routing.sh" "$repo_root/docker/vpnkit/vpnkit-healthcheck.sh"
grep -Fq 'vibe-vpn --config "$VIBE_VPN_CONFIG" pick --max "$VPNKIT_BOOTSTRAP_MAX_NODES"' "$repo_root/docker/vpnkit/entrypoint.sh" || \
grep -Fq 'vibe-vpn --config "$VIBE_VPN_CONFIG" pick --restart-async --max "$VPNKIT_BOOTSTRAP_MAX_NODES"' "$repo_root/docker/vpnkit/entrypoint.sh"
grep -Fq 'wait_for_retest_runtime' "$lifecycle"
grep -Fq 'SINGBOX_GENERATION_FILE' "$lifecycle"
grep -Fq 'prior policy/runtime was restored' "$lifecycle"
grep -Fq 'verify_other_active_vpn_set' "$lifecycle"
grep -Fq 'rollback_start_transaction' "$lifecycle"
grep -Fq 'VPNKIT_LOCAL_SMOKE_DEVICE="$NM_DEVICE" bash "$HOST_SMOKE"' "$lifecycle"
! grep -Eq 'nmcli .*connection (up|down|import|delete|modify)' "$lifecycle"
active_capture_line=$(grep -n 'capture_active_vpn_identities "$snapshot"' "$lifecycle" | head -1 | cut -d: -f1)
compose_up_line=$(grep -n 'stack_attempted=true' "$lifecycle" | head -1 | cut -d: -f1)
[[ -n "$active_capture_line" && -n "$compose_up_line" && "$active_capture_line" -lt "$compose_up_line" ]]
bootstrap_line=$(grep -n 'vibe-vpn --config "$VIBE_VPN_CONFIG" pick' "$repo_root/docker/vpnkit/entrypoint.sh" | cut -d: -f1)
singbox_line=$(grep -n '^start_singbox$' "$repo_root/docker/vpnkit/entrypoint.sh" | head -1 | cut -d: -f1)
barrier_line=$(grep -n -- '--install-fail-closed-barrier' "$repo_root/docker/vpnkit/entrypoint.sh" | tail -1 | cut -d: -f1)
openvpn_line=$(grep -n '^openvpn --config "$OPENVPN_CONFIG"' "$repo_root/docker/vpnkit/entrypoint.sh" | cut -d: -f1)
routing_line=$(grep -n '^/usr/local/bin/setup-routing.sh$' "$repo_root/docker/vpnkit/entrypoint.sh" | tail -1 | cut -d: -f1)
[[ -n "$bootstrap_line" && -n "$singbox_line" && -n "$barrier_line" && -n "$openvpn_line" && -n "$routing_line" && "$bootstrap_line" -lt "$singbox_line" && "$barrier_line" -lt "$openvpn_line" && "$openvpn_line" -lt "$routing_line" ]]
grep -Fq 'OPENVPN_FAIL_CLOSED_CHAIN' "$repo_root/docker/vpnkit/setup-routing.sh"
grep -Fq 'fail_closed_barrier_absent' "$repo_root/docker/vpnkit/vpnkit-healthcheck.sh"

# Production and arbitrary project identities are rejected before even a
# mocked Docker probe.
: >"$tmp/docker.log"
for project in vpnkit not-local arbitrary-project vpnkit-local-prod vpnkit-local-prod-blue vpnkit-local-production-test vpnkit-local-live-test; do
  if VPNKIT_LOCAL_COMPOSE_PROJECT=$project "$lifecycle" status --json >/dev/null 2>&1; then
    echo "unsafe project identity was accepted: $project" >&2
    exit 1
  fi
  [[ ! -s "$tmp/docker.log" ]]
done
status=$($lifecycle status --json)
python3 - "$status" <<'PY'
import json,sys
value=json.loads(sys.argv[1])
assert value == {"container":"absent","networkmanager":{"active":"not-managed","configured":"not-managed"},"routing_policy":"strict","schema":1,"subscription":"missing"}
PY

$lifecycle toggle mode >"$tmp/toggle.out"
grep -q '^routing_policy=smart$' "$tmp/toggle.out"
[[ $(<"$tmp/secrets/state/routing-policy") == smart ]]
[[ $(stat -c '%a' "$tmp/secrets/state/routing-policy") == 600 ]]

# An unrelated secret root and a symlinked root are rejected before any asset,
# Compose, or NetworkManager operation.
: >"$tmp/docker.log"
if VPNKIT_LOCAL_SECRETS_DIR="$repo_root/secrets/vps" "$lifecycle" status --json >/dev/null 2>&1; then
  echo 'external secret root was accepted' >&2
  exit 1
fi
[[ ! -s "$tmp/docker.log" ]]
ln -s "$tmp/secrets" "$tmp/vpnkit-local-secret-link"
if VPNKIT_LOCAL_SECRETS_DIR="$tmp/vpnkit-local-secret-link" "$lifecycle" status --json >/dev/null 2>&1; then
  echo 'symlinked secret root was accepted' >&2
  exit 1
fi
[[ ! -s "$tmp/docker.log" ]]

# The toggle test above is stopped-stack policy state; the implementation also
# carries an explicit runtime/NM rollback path for the healthy-stack case.
grep -Fq 'restore_networkmanager_state' "$lifecycle"
grep -Fq -- '--force-recreate' "$lifecycle"
grep -Fq 'VPNKIT_LOCAL_SECRETS_DIR must stay' "$lifecycle"
grep -Fq 'vpnkit-local(-[a-z0-9]' "$lifecycle"
grep -Fq 'sync_local_path' "$lifecycle"

printf 'https://subscription.example.invalid/test-only\n' >"$tmp/secrets/vibe-vpn/sub_url"
chmod 600 "$tmp/secrets/vibe-vpn/sub_url"
VPNKIT_LOCAL_ALLOW_MISSING_SUBSCRIPTION=false VPNKIT_RULESET_SOURCE_MODE=local-fixture "$assets" --secrets-dir "$tmp/secrets" >/dev/null
for policy in strict smart; do
  VPNKIT_LOCAL_POLICY=$policy VPNKIT_RULESET_SOURCE_MODE=local-fixture "$renderer" >"$tmp/render.out"
  python3 - "$tmp/secrets/rendered/sing-box/config.json" "$policy" <<'PY'
import json,sys
cfg=json.load(open(sys.argv[1], encoding='utf-8')); policy=sys.argv[2]
assert cfg['route']['final']=='selected-native-out'
dns={server['tag']:server for server in cfg['dns']['servers']}
assert dns['remote-dns']['type']=='https' and dns['remote-dns']['server']=='1.1.1.1' and dns['remote-dns']['detour']=='selected-native-out'
assert dns['remote-dns']['tls']['server_name']=='cloudflare-dns.com'
assert dns['remote-dns-fallback']['type']=='https' and dns['remote-dns-fallback']['server']=='8.8.8.8'
assert dns['remote-dns-fallback']['tls']['server_name']=='dns.google'
rules=cfg['route']['rules']
if policy=='strict':
    assert not any('rule_set' in rule for rule in rules)
    assert cfg['route']['rule_set']==[]
else:
    assert any(rule.get('outbound')=='block-out' for rule in rules)
    assert any(rule.get('outbound')=='direct-out' for rule in rules)
PY
done
if VPNKIT_LOCAL_POLICY=strict VPNKIT_RULESET_SOURCE_MODE=local-fixture VPNKIT_SELECTED_OUTBOUND_MODE=direct-fixture "$renderer" >/dev/null 2>&1; then
  echo 'direct fixture outbound was accepted without explicit test-fixture capability' >&2
  exit 1
fi
VPNKIT_LOCAL_POLICY=strict VPNKIT_RULESET_SOURCE_MODE=local-fixture VPNKIT_SELECTED_OUTBOUND_MODE=direct-fixture VPNKIT_LOCAL_TEST_FIXTURE=1 "$renderer" >/dev/null
python3 - "$tmp/secrets/rendered/sing-box/config.json" <<'PY'
import json,sys
cfg=json.load(open(sys.argv[1], encoding='utf-8'))
selected=next(out for out in cfg['outbounds'] if out['tag']=='selected-native-out')
assert selected['type']=='direct'
for server in cfg['dns']['servers']:
    if server.get('tag') in {'remote-dns','remote-dns-fallback'}:
        assert 'detour' not in server
PY
grep -Fqx 'sing_box_restart_ack_generation_file: /run/vpnkit/sing-box-generation' "$tmp/secrets/rendered/vibe-vpn/config.yaml"
grep -Fqx 'sing_box_restart_ack_timeout: 60s' "$tmp/secrets/rendered/vibe-vpn/config.yaml"
! grep -R -F 'test-only' "$tmp"/*.out

# Repeated start failures must preserve a pre-existing healthy local stack.
# The mock fails each candidate Compose up while leaving the pre-call healthy
# container in place; rollback must preserve it without a down or retry.
# No real Docker, NetworkManager, or profile is used.
cat >"$tmp/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'docker %s\n' "$*" >>"$MOCK_DOCKER_LOG"
if [[ " $* " == *" compose "* && " $* " == *" ps -q vpnkit "* ]]; then
  [[ -e "$MOCK_STACK_PRESENT" ]] && printf 'local-cid\n'
  exit 0
fi
if [[ "${1:-}" == inspect ]]; then
  [[ -e "$MOCK_STACK_PRESENT" ]] && printf 'healthy\n' || printf 'absent\n'
  exit 0
fi
if [[ " $* " == *" compose "* && " $* " == *" up -d --build vpnkit "* ]]; then
  count=$(<"$MOCK_UP_COUNT")
  count=$((count + 1))
  printf '%s\n' "$count" >"$MOCK_UP_COUNT"
  # Every candidate call fails, while the pre-existing healthy marker remains.
  exit 42
fi
if [[ " $* " == *" compose "* && " $* " == *" down --remove-orphans "* ]]; then
  printf 'down\n' >>"$MOCK_DOCKER_LOG"
  exit 0
fi
exit 99
EOF
chmod +x "$tmp/bin/docker"
: >"$tmp/up-count"
: >"$tmp/docker.log"
touch "$tmp/stack-present"
for attempt in 1 2; do
  if VPNKIT_LOCAL_BOOT_TIMEOUT_SECONDS=2 MOCK_STACK_PRESENT="$tmp/stack-present" MOCK_UP_COUNT="$tmp/up-count" \
      "$lifecycle" start >"$tmp/start-$attempt.out" 2>&1; then
    echo "start failure unexpectedly succeeded on attempt $attempt" >&2
    exit 1
  fi
  grep -Fq 'local stack was rolled back' "$tmp/start-$attempt.out"
  [[ -e "$tmp/stack-present" ]]
  ! grep -Fq 'down --remove-orphans' "$tmp/docker.log"
done
[[ $(<"$tmp/up-count") == 2 ]]

# With a pre-existing owned NM capability, repeated late start failures must
# preserve the exact UUID, helper state, source profile bytes, active device,
# and unrelated active VPN identity.  All helpers here are test fixtures under
# the isolated root; no real NM or host routing is touched.
uuid=11111111-1111-4111-8111-111111111111
fingerprint=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
mkdir -p "$tmp/secrets/state" "$tmp/secrets/openvpn/client"
printf '%s %s\n' "$uuid" "$fingerprint" >"$tmp/secrets/state/networkmanager-state"
printf '%s\n' "$uuid" >"$tmp/secrets/state/networkmanager-uuid"
printf '%s\n' "$fingerprint" >"$tmp/secrets/state/networkmanager-profile-fingerprint"
printf 'pre-existing-profile-bytes\n' >"$tmp/secrets/openvpn/client/vpnkit-local.ovpn"
chmod 600 "$tmp/secrets/state/networkmanager-state" "$tmp/secrets/state/networkmanager-uuid" \
  "$tmp/secrets/state/networkmanager-profile-fingerprint" "$tmp/secrets/openvpn/client/vpnkit-local.ovpn"
cp -- "$tmp/secrets/openvpn/client/vpnkit-local.ovpn" "$tmp/pre-existing-profile"
cp -- "$tmp/secrets/state/networkmanager-state" "$tmp/pre-existing-state"
cp -- "$tmp/secrets/state/networkmanager-uuid" "$tmp/pre-existing-uuid"
cp -- "$tmp/secrets/state/networkmanager-profile-fingerprint" "$tmp/pre-existing-fingerprint"
printf 'configured=yes\nactive=yes\ndevice=tun7\n' >"$tmp/nm-status"
cat >"$tmp/secrets/test-nm-helper.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$MOCK_NM_LOG"
case "${1:-}" in
  status) cat "$MOCK_NM_STATUS" ;;
  *) exit 91 ;;
esac
EOF
cat >"$tmp/secrets/test-underlay-helper.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == verify ]]
EOF
cat >"$tmp/secrets/test-host-smoke.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$tmp/secrets/test-nm-helper.sh" "$tmp/secrets/test-underlay-helper.sh" "$tmp/secrets/test-host-smoke.sh"
cat >"$tmp/bin/nmcli" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
cat "$MOCK_ACTIVE_VPNS"
EOF
cat >"$tmp/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'docker %s\n' "$*" >>"$MOCK_DOCKER_LOG"
if [[ " $* " == *" compose "* && " $* " == *" ps -q vpnkit "* ]]; then
  printf 'local-cid\n'
  exit 0
fi
if [[ "${1:-}" == inspect ]]; then
  printf 'healthy\n'
  exit 0
fi
if [[ " $* " == *" compose "* && " $* " == *" up -d --build vpnkit "* ]]; then
  exit 0
fi
exit 99
EOF
chmod +x "$tmp/bin/nmcli" "$tmp/bin/docker"
printf 'local-vpn:99999999-9999-4999-8999-999999999999:vpn\nother-vpn:22222222-2222-4222-8222-222222222222:wireguard\n' >"$tmp/active-vpns"
: >"$tmp/nm.log"
: >"$tmp/docker.log"
for attempt in 1 2; do
  if VPNKIT_LOCAL_MANAGE_NETWORKMANAGER=true VPNKIT_LOCAL_TEST_FIXTURE=1 \
      VPNKIT_LOCAL_TEST_NM_HELPER="$tmp/secrets/test-nm-helper.sh" \
      VPNKIT_LOCAL_TEST_UNDERLAY_HELPER="$tmp/secrets/test-underlay-helper.sh" \
      VPNKIT_LOCAL_HOST_SMOKE_SCRIPT="$tmp/secrets/test-host-smoke.sh" \
      MOCK_NM_LOG="$tmp/nm.log" MOCK_NM_STATUS="$tmp/nm-status" MOCK_ACTIVE_VPNS="$tmp/active-vpns" \
      VPNKIT_LOCAL_BOOT_TIMEOUT_SECONDS=2 "$lifecycle" start >"$tmp/nm-start-$attempt.out" 2>&1; then
    echo "NM start failure unexpectedly succeeded on attempt $attempt" >&2
    exit 1
  fi
  cmp -- "$tmp/secrets/state/networkmanager-state" "$tmp/pre-existing-state"
  cmp -- "$tmp/secrets/state/networkmanager-uuid" "$tmp/pre-existing-uuid"
  cmp -- "$tmp/secrets/state/networkmanager-profile-fingerprint" "$tmp/pre-existing-fingerprint"
  cmp -- "$tmp/secrets/openvpn/client/vpnkit-local.ovpn" "$tmp/pre-existing-profile"
  grep -Fq 'configured=yes' "$tmp/nm-status"
  grep -Fq 'active=yes' "$tmp/nm-status"
  grep -Fq 'device=tun7' "$tmp/nm-status"
  ! grep -Eq '^(import|connect|disconnect|remove)( |$)' "$tmp/nm.log"
  ! grep -Fq 'down --remove-orphans' "$tmp/docker.log"
done

$repo_root/scripts/vpnkit/vpnkit_local_kde_tui.py --status-json --test | python3 -c 'import json,sys; assert json.load(sys.stdin)["routing_mode"]=="strict"'
printf 'vpnkit local lifecycle tests passed\n'
