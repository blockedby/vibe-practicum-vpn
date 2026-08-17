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
if [[ "${1:-}" == container || "${1:-}" == network || "${1:-}" == volume ]]; then exit 0; fi
if [[ " $* " == *" compose "* && " $* " == *" ps -q vpnkit "* ]]; then exit 0; fi
exit 99
EOF
chmod +x "$tmp/bin/docker"

export PATH="$tmp/bin:$PATH"
export MOCK_DOCKER_LOG="$tmp/docker.log"
export VPNKIT_LOCAL_SECRETS_DIR="$tmp/secrets"
export VPNKIT_LOCAL_COMPOSE_PROJECT=vpnkit-local-test
export VPNKIT_LOCAL_MANAGE_NETWORKMANAGER=false
export MOCK_WORKDIR="$repo_root"
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
[[ -n "$bootstrap_line" && -n "$singbox_line" && -n "$barrier_line" && -n "$openvpn_line" && -n "$routing_line" && "$singbox_line" -lt "$bootstrap_line" && "$barrier_line" -lt "$openvpn_line" && "$openvpn_line" -lt "$routing_line" ]]
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

# REV-001 reproducer: renderer input/output descendants are validated before
# mkdir/chmod/write/cp. A symlinked rendered or vibe-vpn child must not let a
# rejected render touch an external directory.
renderer_link_base="$tmp/renderer-link-root"
renderer_link_target="$tmp/external-render-target"
renderer_input_target="$tmp/external-vibe-target"
mkdir -p "$renderer_link_base/rendered" "$renderer_link_target" "$renderer_input_target"
chmod 755 "$renderer_link_target" "$renderer_input_target"
ln -s "$renderer_link_target" "$renderer_link_base/rendered/vibe-vpn"
ln -s "$renderer_input_target" "$renderer_link_base/vibe-vpn"
link_render_mode=$(stat -c '%a %F' "$renderer_link_target")
link_input_mode=$(stat -c '%a %F' "$renderer_input_target")
if VPNKIT_LOCAL_TEST_FIXTURE=1 VPNKIT_LOCAL_SECRETS_DIR="$renderer_link_base" \
    VPNKIT_LOCAL_ALLOW_MISSING_SUBSCRIPTION=true VPNKIT_RULESET_SOURCE_MODE=local-fixture \
    "$renderer" >"$tmp/renderer-link.out" 2>&1; then
  echo 'renderer accepted a symlinked rendered/vibe-vpn child' >&2
  exit 1
fi
[[ "$(stat -c '%a %F' "$renderer_link_target")" == "$link_render_mode" ]]
[[ "$(stat -c '%a %F' "$renderer_input_target")" == "$link_input_mode" ]]
[[ ! -e "$renderer_link_target/config.yaml" ]]
[[ ! -e "$renderer_input_target/config.yaml" ]]

# The same preflight must reject hard-linked output/input files before a
# renderer operation can truncate or chmod their external inode.
renderer_hardlink_base="$tmp/renderer-hardlink-root"
renderer_hardlink_target="$tmp/external-render-config"
renderer_hardlink_input_target="$tmp/external-vibe-input"
mkdir -p "$renderer_hardlink_base/rendered/vibe-vpn" "$renderer_hardlink_base/vibe-vpn"
printf 'external-render-sentinel\n' >"$renderer_hardlink_target"
printf 'external-input-sentinel\n' >"$renderer_hardlink_input_target"
chmod 644 "$renderer_hardlink_target" "$renderer_hardlink_input_target"
ln "$renderer_hardlink_target" "$renderer_hardlink_base/rendered/vibe-vpn/config.yaml"
ln "$renderer_hardlink_input_target" "$renderer_hardlink_base/vibe-vpn/extra-nodes.json"
link_render_hash=$(sha256sum "$renderer_hardlink_target" | awk '{print $1}')
link_input_hash=$(sha256sum "$renderer_hardlink_input_target" | awk '{print $1}')
link_render_mode=$(stat -c '%a' "$renderer_hardlink_target")
link_input_mode=$(stat -c '%a' "$renderer_hardlink_input_target")
if VPNKIT_LOCAL_TEST_FIXTURE=1 VPNKIT_LOCAL_SECRETS_DIR="$renderer_hardlink_base" \
    VPNKIT_LOCAL_ALLOW_MISSING_SUBSCRIPTION=true VPNKIT_RULESET_SOURCE_MODE=local-fixture \
    "$renderer" >"$tmp/renderer-hardlink.out" 2>&1; then
  echo 'renderer accepted a hard-linked rendered/vibe-vpn child' >&2
  exit 1
fi
[[ "$(sha256sum "$renderer_hardlink_target" | awk '{print $1}')" == "$link_render_hash" ]]
[[ "$(sha256sum "$renderer_hardlink_input_target" | awk '{print $1}')" == "$link_input_hash" ]]
[[ "$(stat -c '%a' "$renderer_hardlink_target")" == "$link_render_mode" ]]
[[ "$(stat -c '%a' "$renderer_hardlink_input_target")" == "$link_input_mode" ]]
[[ ! -e "$renderer_hardlink_base/rendered/sing-box" ]]

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

# A syntactically allowed project name is still bounded by resource ownership.
# Foreign, missing-owner, and project-label collisions must stop before the
# destructive stop call; an exact owned container/network/volume set succeeds.
cat >"$tmp/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'docker %s\n' "$*" >>"$MOCK_DOCKER_LOG"
project=${MOCK_PROJECT:-vpnkit-local-boundary}
mode=${MOCK_RESOURCE_MODE:-owned}
if [[ "${1:-}" == container || "${1:-}" == network || "${1:-}" == volume ]]; then
  kind=$1
  joined="$*"
  if [[ "$joined" == *'name='* ]]; then
    if [[ "$mode" == project-collision && "$kind" == network ]]; then
      printf 'collision-network\n'
    fi
    exit 0
  fi
  case "$mode:$kind" in
    owned:container|same-label-wrong-name:container) printf '%s-container\n' "$mode" ;;
    owned:network) printf 'owned-network\n' ;;
    owned:volume) printf 'owned-volume\n' ;;
    foreign:container|missing:container) printf '%s-container\n' "$mode" ;;
    *) ;;
  esac
  exit 0
fi
if [[ " $* " == *'compose'*'ps -q vpnkit'* ]]; then
  if [[ -n "${MOCK_STOPPED_FILE:-}" && -e "$MOCK_STOPPED_FILE" ]]; then
    exit 0
  fi
  [[ "$mode" == owned || "$mode" == same-label-wrong-name ]] && printf '%s-container\n' "$mode"
  exit 0
fi
if [[ "${1:-}" == inspect ]]; then
  joined="$*"
  case "$joined" in
    *'State.Running'*) printf 'healthy\n' ;;
    *'{{.Name}}'*)
      case "${4:-}" in
        collision-network|owned-network) printf '%s\n' "${project}_vpnkit-local" ;;
        owned-volume) printf '%s\n' "${project}_vpnkit-local-vibe-vpn-state" ;;
        *)
          if [[ "$mode" == same-label-wrong-name ]]; then
            printf '/vpnkit-local-boundary-not-vpnkit\n'
          else
            printf '/vpnkit-local-boundary-vpnkit-1\n'
          fi
          ;;
      esac
      ;;
    *'Config.Labels'*'com.docker.compose.project.working_dir'*) printf '%s\n' "$MOCK_WORKDIR" ;;
    *'Config.Labels'*'com.vpnkit.local.owner'*)
      case "$mode" in foreign) printf 'foreign-owner\n' ;; missing) printf '\n' ;; *) printf 'local-lifecycle\n' ;; esac
      ;;
    *'Config.Labels'*'com.docker.compose.project'*)
      printf '%s\n' "$project"
      ;;
    *'.Labels'*'com.vpnkit.local.owner'*)
      case "$mode" in foreign) printf 'foreign-owner\n' ;; missing) printf '\n' ;; *) printf 'local-lifecycle\n' ;; esac
      ;;
    *'.Labels'*'com.docker.compose.project'*)
      if [[ "$mode" == project-collision ]]; then printf 'foreign-project\n'; else printf '%s\n' "$project"; fi
      ;;
    *'.Labels'*'com.docker.compose.network'*) printf 'vpnkit-local\n' ;;
    *'.Labels'*'com.docker.compose.volume'*) printf 'vpnkit-local-vibe-vpn-state\n' ;;
    *'{{.Name}}'*)
      case "${4:-}" in
        collision-network|owned-network) printf '%s\n' "${project}_vpnkit-local" ;;
        owned-volume) printf '%s\n' "${project}_vpnkit-local-vibe-vpn-state" ;;
      esac
      ;;
  esac
  exit 0
fi
if [[ " $* " == *'compose'*'down --remove-orphans'* ]]; then
  printf 'COMPOSE_DOWN\n' >>"$MOCK_DOCKER_LOG"
  [[ -z "${MOCK_STOPPED_FILE:-}" ]] || : >"$MOCK_STOPPED_FILE"
  exit 0
fi
if [[ " $* " == *'compose'*'up '* ]]; then
  printf 'COMPOSE_UP\n' >>"$MOCK_DOCKER_LOG"
  exit 0
fi
exit 99
EOF
chmod +x "$tmp/bin/docker"
for mode in foreign missing project-collision; do
  : >"$tmp/docker.log"
  if VPNKIT_LOCAL_COMPOSE_PROJECT=vpnkit-local-boundary MOCK_PROJECT=vpnkit-local-boundary \
      MOCK_RESOURCE_MODE="$mode" MOCK_WORKDIR="$repo_root" "$lifecycle" stop >"$tmp/$mode.out" 2>&1; then
    echo "unsafe resource mode was accepted: $mode" >&2
    exit 1
  fi
  ! grep -Fq 'COMPOSE_DOWN' "$tmp/docker.log"
done

# REV-003: labels and working_dir are not enough. A same-project, same-owner,
# same-workdir container with the wrong Docker name must block every local
# Compose mutation, including start and policy recreate.
for operation in stop start toggle; do
  : >"$tmp/docker.log"
  if [[ "$operation" == toggle ]]; then
    wrong_name_command=("$lifecycle" toggle mode)
  else
    wrong_name_command=("$lifecycle" "$operation")
  fi
  if VPNKIT_LOCAL_COMPOSE_PROJECT=vpnkit-local-boundary MOCK_PROJECT=vpnkit-local-boundary \
      MOCK_RESOURCE_MODE=same-label-wrong-name MOCK_WORKDIR="$repo_root" \
      "${wrong_name_command[@]}" >"$tmp/wrong-name-$operation.out" 2>&1; then
    echo "wrong-name container was accepted by $operation" >&2
    exit 1
  fi
  ! grep -Eq 'COMPOSE_(DOWN|UP)' "$tmp/docker.log"
done
: >"$tmp/docker.log"
VPNKIT_LOCAL_COMPOSE_PROJECT=vpnkit-local-boundary MOCK_PROJECT=vpnkit-local-boundary \
  MOCK_RESOURCE_MODE=owned MOCK_STOPPED_FILE="$tmp/owned-stopped" MOCK_WORKDIR="$repo_root" "$lifecycle" stop >"$tmp/owned-stop.out"
grep -Fq 'vpnkit_local_stop=ok' "$tmp/owned-stop.out"
grep -Fq 'COMPOSE_DOWN' "$tmp/docker.log"

# REV-001: an external NetworkManager disconnect interval can introduce a
# same-project/same-owner/same-workdir container with an unexpected name. The
# post-disconnect preflight must reject it before Compose down.
cat >"$tmp/secrets/test-nm-disconnect-helper.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
  status)
    if [[ -e "$MOCK_NM_DISCONNECTED" ]]; then
      printf 'configured=no\nactive=no\nownership=missing\ndevice=none\n'
    else
      printf 'configured=no\nactive=no\nownership=missing\ndevice=none\n'
    fi
    ;;
  disconnect)
    printf '%s\n' "$*" >>"$MOCK_NM_DISCONNECT_LOG"
    : >"$MOCK_NM_DISCONNECTED"
    ;;
  *) exit 91 ;;
esac
EOF
cat >"$tmp/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'docker %s\n' "$*" >>"$MOCK_DOCKER_LOG"
project=${MOCK_PROJECT:?}
wrong_name=0
[[ -e "$MOCK_NM_DISCONNECTED" ]] && wrong_name=1
if [[ "${1:-}" == container || "${1:-}" == network || "${1:-}" == volume ]]; then
  kind=$1
  joined="$*"
  if [[ "$kind" == container && "$joined" == *"label=com.docker.compose.project=$project"* ]]; then
    if (( wrong_name )); then printf 'unexpected-container\n'; else printf 'owned-container\n'; fi
  fi
  exit 0
fi
if [[ " $* " == *' compose '*' ps -q vpnkit '* ]]; then
  if (( wrong_name )); then printf 'unexpected-container\n'; else printf 'owned-container\n'; fi
  exit 0
fi
if [[ "${1:-}" == inspect ]]; then
  joined="$*"
  id=${!#}
  if [[ "$joined" == *'State.Running'* ]]; then
    printf 'healthy\n'
  elif [[ "$joined" == *'{{.Name}}'* ]]; then
    if [[ "$id" == unexpected-container ]]; then printf '/%s-not-vpnkit\n' "$project"; else printf '/%s-vpnkit-1\n' "$project"; fi
  elif [[ "$joined" == *'Config.Labels'*'com.docker.compose.project.working_dir'* ]]; then
    printf '%s\n' "$MOCK_WORKDIR"
  elif [[ "$joined" == *'Config.Labels'*'com.vpnkit.local.owner'* ]]; then
    printf 'local-lifecycle\n'
  elif [[ "$joined" == *'Config.Labels'*'com.docker.compose.project'* ]]; then
    printf '%s\n' "$project"
  fi
  exit 0
fi
if [[ " $* " == *' compose '*' down --remove-orphans '* ]]; then
  printf 'COMPOSE_DOWN\n' >>"$MOCK_DOCKER_LOG"
  exit 0
fi
exit 99
EOF
chmod +x "$tmp/secrets/test-nm-disconnect-helper.sh" "$tmp/bin/docker"
: >"$tmp/nm-disconnect.log"
: >"$tmp/docker.log"
rm -f -- "$tmp/nm-disconnected"
if VPNKIT_LOCAL_MANAGE_NETWORKMANAGER=true VPNKIT_LOCAL_TEST_FIXTURE=1 \
    VPNKIT_LOCAL_TEST_NM_HELPER="$tmp/secrets/test-nm-disconnect-helper.sh" \
    MOCK_NM_DISCONNECT_LOG="$tmp/nm-disconnect.log" MOCK_NM_DISCONNECTED="$tmp/nm-disconnected" \
    MOCK_ACTIVE_VPNS="$tmp/active-vpns" MOCK_PROJECT=vpnkit-local-nm-race MOCK_WORKDIR="$repo_root" \
    VPNKIT_LOCAL_COMPOSE_PROJECT=vpnkit-local-nm-race "$lifecycle" stop >"$tmp/nm-disconnect.out" 2>&1; then
  echo 'post-disconnect ownership collision was accepted' >&2
  exit 1
fi
grep -Fxq 'disconnect --yes' "$tmp/nm-disconnect.log"
! grep -Fq 'COMPOSE_DOWN' "$tmp/docker.log"
# The failed cross-layer recovery is intentionally retained. Do not let the
# later independent mock scenarios cross that fail-closed boundary.
[[ -f "$tmp/secrets/state/lifecycle.journal" ]]
rm -f -- "$tmp/secrets/state/lifecycle.journal"
rm -rf -- "$tmp/secrets/state/lifecycle-transactions"

# Unrelated project resources are outside this adapter's scope and must not
# veto a bounded stop of an otherwise owned local project. Use a fresh local
# secret root so an intentionally retained journal from the prior collision
# case cannot be crossed by a different Compose project identity.
unrelated_secrets="$tmp/unrelated-secrets"
mkdir -p "$unrelated_secrets"
cat >"$tmp/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'docker %s\n' "$*" >>"$MOCK_DOCKER_LOG"
if [[ "$*" == *'label=com.vpnkit.local.owner'* ]]; then
  printf 'GLOBAL_OWNER_SCAN\n' >>"$MOCK_DOCKER_LOG"
  printf 'unrelated-resource\n'
  exit 0
fi
if [[ "${1:-}" == container || "${1:-}" == network || "${1:-}" == volume ]]; then exit 0; fi
if [[ " $* " == *' compose '*' ps -q vpnkit '* ]]; then
  [[ -e "${MOCK_STOPPED_FILE:-/dev/null}" ]] && exit 0
  printf 'owned-container\n'
  exit 0
fi
if [[ "${1:-}" == inspect ]]; then
  joined="$*"
  if [[ "$joined" == *'State.Running'* ]]; then printf 'healthy\n'
  elif [[ "$joined" == *'{{.Name}}'* ]]; then printf '/vpnkit-local-unrelated-check-vpnkit-1\n'
  elif [[ "$joined" == *'Config.Labels'*'com.docker.compose.project.working_dir'* ]]; then printf '%s\n' "$MOCK_WORKDIR"
  elif [[ "$joined" == *'Config.Labels'*'com.vpnkit.local.owner'* ]]; then printf 'local-lifecycle\n'
  elif [[ "$joined" == *'Config.Labels'*'com.docker.compose.project'* ]]; then printf '%s\n' "$MOCK_PROJECT"
  fi
  exit 0
fi
if [[ " $* " == *' compose '*' down --remove-orphans '* ]]; then
  printf 'COMPOSE_DOWN\n' >>"$MOCK_DOCKER_LOG"
  [[ -z "${MOCK_STOPPED_FILE:-}" ]] || : >"$MOCK_STOPPED_FILE"
  exit 0
fi
exit 99
EOF
chmod +x "$tmp/bin/docker"
: >"$tmp/docker.log"
VPNKIT_LOCAL_MANAGE_NETWORKMANAGER=false VPNKIT_LOCAL_SECRETS_DIR="$unrelated_secrets" \
  MOCK_PROJECT=vpnkit-local-unrelated-check MOCK_WORKDIR="$repo_root" \
  VPNKIT_LOCAL_COMPOSE_PROJECT=vpnkit-local-unrelated-check MOCK_STOPPED_FILE="$tmp/unrelated-stopped" \
  "$lifecycle" stop >"$tmp/unrelated-stop.out"
grep -Fq 'vpnkit_local_stop=ok' "$tmp/unrelated-stop.out"
grep -Fq 'COMPOSE_DOWN' "$tmp/docker.log"
! grep -Fq 'GLOBAL_OWNER_SCAN' "$tmp/docker.log"

# Repeated start failures must preserve a pre-existing healthy local stack.
# The mock fails each candidate Compose up while leaving the pre-call healthy
# container in place; rollback must preserve it without a down or retry.
# No real Docker, NetworkManager, or profile is used.
cat >"$tmp/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'docker %s\n' "$*" >>"$MOCK_DOCKER_LOG"
if [[ "${1:-}" == container || "${1:-}" == network || "${1:-}" == volume ]]; then
  # Empty networks/volumes are valid; the selected container is validated by
  # the separate Compose-ps ownership check below.
  exit 0
fi
if [[ " $* " == *" compose "* && " $* " == *" ps -q vpnkit "* ]]; then
  [[ -e "$MOCK_STACK_PRESENT" ]] && printf 'local-cid\n'
  exit 0
fi
if [[ "${1:-}" == inspect ]]; then
  joined="$*"
  if [[ "$joined" == *'State.Running'* ]]; then
    [[ -e "$MOCK_STACK_PRESENT" ]] && printf 'healthy\n' || printf 'absent\n'
  elif [[ "$joined" == *'{{.Name}}'* ]]; then
    printf '/vpnkit-local-test-vpnkit-1\n'
  elif [[ "$joined" == *'Config.Labels'*'com.docker.compose.project.working_dir'* ]]; then
    printf '%s\n' "${MOCK_WORKDIR:-$PWD}"
  elif [[ "$joined" == *'Config.Labels'*'com.vpnkit.local.owner'* ]]; then
    printf '%s\n' "${MOCK_OWNER:-local-lifecycle}"
  elif [[ "$joined" == *'Config.Labels'*'com.docker.compose.project'* ]]; then
    printf '%s\n' "${MOCK_PROJECT:-vpnkit-local-test}"
  fi
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
printf 'configured=yes\nactive=yes\nownership=owned\ndevice=tun7\n' >"$tmp/nm-status"
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
fields=
joined="$*"
while [[ $# -gt 0 ]]; do
  if [[ "$1" == -f ]]; then fields=${2:-}; shift 2; else shift; fi
done
if [[ "$joined" == *'connection show --active'* && "$fields" == UUID,TYPE ]]; then
  # The source state intentionally contains display-name-shaped rows with
  # colons. The lifecycle must request and consume only UUID,TYPE rows.
  sed -E 's/^[^:]*:([0-9A-Fa-f-]+):(.*)$/\1:\2/' "$MOCK_ACTIVE_VPNS"
else
  cat "$MOCK_ACTIVE_VPNS"
fi
EOF
cat >"$tmp/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'docker %s\n' "$*" >>"$MOCK_DOCKER_LOG"
if [[ "${1:-}" == container || "${1:-}" == network || "${1:-}" == volume ]]; then
  exit 0
fi
if [[ " $* " == *" compose "* && " $* " == *" ps -q vpnkit "* ]]; then
  printf 'local-cid\n'
  exit 0
fi
if [[ "${1:-}" == inspect ]]; then
  joined="$*"
  if [[ "$joined" == *'State.Running'* ]]; then
    printf 'healthy\n'
  elif [[ "$joined" == *'{{.Name}}'* ]]; then
    printf '/vpnkit-local-test-vpnkit-1\n'
  elif [[ "$joined" == *'Config.Labels'*'com.docker.compose.project.working_dir'* ]]; then
    printf '%s\n' "${MOCK_WORKDIR:-$PWD}"
  elif [[ "$joined" == *'Config.Labels'*'com.vpnkit.local.owner'* ]]; then
    printf 'local-lifecycle\n'
  elif [[ "$joined" == *'Config.Labels'*'com.docker.compose.project'* ]]; then
    printf 'vpnkit-local-test\n'
  fi
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

# A failed activation can leave an owned NM UUID active while its tunnel/IP
# mapping is temporarily unprovable. Rollback must still use exact-UUID
# disconnect/remove rather than waiting on or guessing a device.
rm -f -- "$tmp/secrets/state/networkmanager-state" "$tmp/secrets/state/networkmanager-uuid" \
  "$tmp/secrets/state/networkmanager-profile-fingerprint" "$tmp/secrets/openvpn/client/vpnkit-local.ovpn"
cat >"$tmp/secrets/test-nm-rollback-helper.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
state="$VPNKIT_LOCAL_SECRETS_DIR/state"
uuid=33333333-3333-4333-8333-333333333333
fingerprint=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
printf '%s\n' "$*" >>"$MOCK_NM_ROLLBACK_LOG"
case "${1:-}" in
  status)
    [[ ! -e "$MOCK_NM_UNSAFE" ]] || exit 42
    if [[ -e "$MOCK_NM_CONFIGURED" ]]; then
      printf 'configured=yes\nactive=yes\nownership=owned\ndevice=tun0\n'
    else
      printf 'configured=no\nactive=no\nownership=missing\ndevice=none\n'
    fi
    ;;
  import)
    mkdir -p "$state"
    printf '%s %s\n' "$uuid" "$fingerprint" >"$state/networkmanager-state"
    printf '%s\n' "$uuid" >"$state/networkmanager-uuid"
    printf '%s\n' "$fingerprint" >"$state/networkmanager-profile-fingerprint"
    : >"$MOCK_NM_CONFIGURED"
    ;;
  connect)
    : >"$MOCK_NM_CONFIGURED"
    : >"$MOCK_NM_UNSAFE"
    ;;
  disconnect)
    rm -f -- "$MOCK_NM_ACTIVE"
    ;;
  remove)
    rm -f -- "$MOCK_NM_CONFIGURED" "$MOCK_NM_UNSAFE" "$MOCK_NM_ACTIVE" \
      "$state/networkmanager-state" "$state/networkmanager-uuid" "$state/networkmanager-profile-fingerprint"
    ;;
  *) exit 91 ;;
esac
EOF
chmod +x "$tmp/secrets/test-nm-rollback-helper.sh"
: >"$tmp/nm-rollback.log"
rm -f -- "$tmp/nm-rollback-configured" "$tmp/nm-rollback-unsafe" "$tmp/nm-rollback-active"
if VPNKIT_LOCAL_MANAGE_NETWORKMANAGER=true VPNKIT_LOCAL_TEST_FIXTURE=1 \
    VPNKIT_LOCAL_TEST_NM_HELPER="$tmp/secrets/test-nm-rollback-helper.sh" \
    VPNKIT_LOCAL_TEST_UNDERLAY_HELPER="$tmp/secrets/test-underlay-helper.sh" \
    VPNKIT_LOCAL_HOST_SMOKE_SCRIPT="$tmp/secrets/test-host-smoke.sh" \
    MOCK_NM_ROLLBACK_LOG="$tmp/nm-rollback.log" MOCK_NM_CONFIGURED="$tmp/nm-rollback-configured" \
    MOCK_NM_UNSAFE="$tmp/nm-rollback-unsafe" MOCK_NM_ACTIVE="$tmp/nm-rollback-active" \
    MOCK_ACTIVE_VPNS="$tmp/active-vpns" VPNKIT_LOCAL_BOOT_TIMEOUT_SECONDS=2 \
    "$lifecycle" start >"$tmp/nm-rollback.out" 2>&1; then
  echo 'unsafe-mapping NM rollback unexpectedly succeeded' >&2
  exit 1
fi
grep -Fq 'local stack was rolled back' "$tmp/nm-rollback.out"
! grep -Fq 'rollback incomplete' "$tmp/nm-rollback.out"
grep -Fxq 'disconnect --yes' "$tmp/nm-rollback.log"
grep -Fxq 'remove --yes' "$tmp/nm-rollback.log"
[[ ! -e "$tmp/secrets/state/networkmanager-state" && ! -e "$tmp/secrets/state/networkmanager-uuid" ]]

# REV-001 lifecycle-level stateful NM mock. The legacy-shaped inventory has a
# colon in the work display name (`work:vpn`) and a foreign profile named
# `vpnkit-local`; the lifecycle must never request NAME or filter by name.
stateful_root="$tmp/stateful-lifecycle"
mkdir -p "$stateful_root/bin" "$stateful_root/secrets/vibe-vpn"
printf 'https://subscription.example.invalid/stateful-test\n' >"$stateful_root/secrets/vibe-vpn/sub_url"
chmod 600 "$stateful_root/secrets/vibe-vpn/sub_url"
cat >"$stateful_root/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
project=${MOCK_STATEFUL_PROJECT:?}
stack=${MOCK_STATEFUL_STACK:?}
log=${MOCK_STATEFUL_DOCKER_LOG:?}
joined="$*"
printf '%s\n' "$joined" >>"$log"
if [[ "${1:-}" == container || "${1:-}" == network || "${1:-}" == volume ]]; then
  if [[ "${1:-}" == container && "${2:-}" == ls && -e "$stack" && "$joined" == *"label=com.docker.compose.project=$project"* ]]; then
    printf 'stateful-cid\n'
  fi
  exit 0
fi
if [[ "${1:-}" == compose && "$joined" == *'ps -q vpnkit'* ]]; then
  [[ -e "$stack" ]] && printf 'stateful-cid\n'
  exit 0
fi
if [[ "${1:-}" == inspect ]]; then
  if [[ "$joined" == *'State.Running'* ]]; then
    printf 'healthy\n'
  elif [[ "$joined" == *'{{.Name}}'* ]]; then
    printf '/%s-vpnkit-1\n' "$project"
  elif [[ "$joined" == *'Config.Labels'*'com.docker.compose.project.working_dir'* ]]; then
    printf '%s\n' "$MOCK_WORKDIR"
  elif [[ "$joined" == *'Config.Labels'*'com.vpnkit.local.owner'* ]]; then
    printf 'local-lifecycle\n'
  elif [[ "$joined" == *'Config.Labels'*'com.docker.compose.project'* ]]; then
    printf '%s\n' "$project"
  fi
  exit 0
fi
if [[ "$joined" == *'compose'*'up -d --build vpnkit'* ]]; then
  : >"$stack"
  printf 'COMPOSE_UP\n' >>"$log"
  exit 0
fi
if [[ "$joined" == *'compose'*'down --remove-orphans'* ]]; then
  rm -f -- "$stack"
  printf 'COMPOSE_DOWN\n' >>"$log"
  exit 0
fi
exit 99
EOF
cat >"$stateful_root/secrets/stateful-nm-helper.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
state="$VPNKIT_LOCAL_SECRETS_DIR/state"
state_file="$state/networkmanager-state"
uuid=22222222-2222-4222-8222-222222222222
fingerprint=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
mkdir -p -- "$state"
case "${1:-}" in
  status)
    if [[ -s "$state_file" ]]; then
      if [[ -e "$state/active" ]]; then
        printf 'configured=yes\nactive=yes\nownership=owned\ndevice=tun7\n'
      else
        printf 'configured=yes\nactive=no\nownership=owned\ndevice=none\n'
      fi
      case "${MOCK_STATEFUL_CASE:-}" in
        owned-status-malformed) printf 'owned_uuid=not-a-canonical-uuid\n' ;;
        owned-status-ambiguous) printf 'owned_uuid=22222222-2222-4222-8222-222222222222\nowned_uuid=33333333-3333-4333-8333-333333333333\n' ;;
      esac
    else
      printf 'configured=no\nactive=no\nownership=missing\ndevice=none\n'
    fi
    ;;
  import)
    printf '%s %s\n' "$uuid" "$fingerprint" >"$state_file"
    printf '%s\n' "$uuid" >"$state/networkmanager-uuid"
    printf '%s\n' "$fingerprint" >"$state/networkmanager-profile-fingerprint"
    ;;
  connect) : >"$state/active" ;;
  disconnect) rm -f -- "$state/active" ;;
  remove) rm -f -- "$state/active" "$state_file" "$state/networkmanager-uuid" "$state/networkmanager-profile-fingerprint" ;;
  *) exit 91 ;;
esac
EOF
cat >"$stateful_root/secrets/stateful-underlay.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == verify ]]
EOF
cat >"$stateful_root/secrets/stateful-smoke.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'host_smoke=pass\n'
EOF
cat >"$stateful_root/bin/nmcli" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
fields=
joined="$*"
printf '%s\n' "$joined" >>"${MOCK_STATEFUL_NM_LOG:?}"
while [[ $# -gt 0 ]]; do
  if [[ "$1" == -f ]]; then fields=${2:-}; shift 2; else shift; fi
done
[[ "$joined" == *'connection show --active'* ]] || exit 0
if [[ "$fields" == NAME,UUID,TYPE ]]; then
  # This is intentionally unsafe legacy output. A compliant lifecycle never
  # reaches this branch.
  printf 'work:vpn:11111111-1111-4111-8111-111111111111:vpn\n'
  printf 'vpnkit-local:33333333-3333-4333-8333-333333333333:vpn\n'
  exit 0
fi
[[ "$fields" == UUID,TYPE ]] || exit 2
count_file=${MOCK_STATEFUL_NM_COUNT:?}
count=0
[[ -s "$count_file" ]] && count=$(<"$count_file")
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
work=11111111-1111-4111-8111-111111111111
foreign=33333333-3333-4333-8333-333333333333
owned=22222222-2222-4222-8222-222222222222
addition=44444444-4444-4444-8444-444444444444
rows_before() {
  printf '%s:vpn\n' "$work" "$foreign"
  if [[ "${MOCK_STATEFUL_CASE:-}" == owned ]]; then
    printf '%s:vpn\n' "$owned"
  fi
}
rows_after() {
  case "${MOCK_STATEFUL_CASE:-}" in
    work-disappears|foreign-same-name-disappears) printf '%s:vpn\n' "$foreign" "$owned" ;;
    work-addition|foreign-same-name-addition) printf '%s:vpn\n' "$work" "$foreign" "$addition" "$owned" ;;
    rollback-phase-change)
      if (( count >= 3 )); then printf '%s:vpn\n' "$foreign"; else printf '%s:vpn\n' "$work" "$foreign" "$addition" "$owned"; fi
      ;;
    stop-work-disappears) printf '%s:vpn\n' "$foreign" "$owned" ;;
    *) printf '%s:vpn\n' "$work" "$foreign" "$owned" ;;
  esac
}
if (( count == 1 )); then rows_before; else rows_after; fi
EOF
chmod +x "$stateful_root/bin/docker" "$stateful_root/bin/nmcli" \
  "$stateful_root/secrets/stateful-nm-helper.sh" "$stateful_root/secrets/stateful-underlay.sh" "$stateful_root/secrets/stateful-smoke.sh"
run_stateful_lifecycle_case() {
  local case_name=$1 expected=$2 action=$3 output="$stateful_root/$1.out" rc
  rm -rf -- "$stateful_root/secrets/state"
  mkdir -p -- "$stateful_root/secrets/state"
  rm -f -- "$stateful_root/stack" "$stateful_root/nm-count" "$stateful_root/docker.log" "$stateful_root/nmcli.log"
  : >"$stateful_root/nmcli.log"
  if [[ "$case_name" == owned || "$case_name" == owned-status-malformed || "$case_name" == owned-status-ambiguous || "$action" == stop ]]; then
    printf '%s %s\n' '22222222-2222-4222-8222-222222222222' 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' >"$stateful_root/secrets/state/networkmanager-state"
    printf '%s\n' '22222222-2222-4222-8222-222222222222' >"$stateful_root/secrets/state/networkmanager-uuid"
    printf '%s\n' 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' >"$stateful_root/secrets/state/networkmanager-profile-fingerprint"
    [[ "$action" == stop ]] && : >"$stateful_root/secrets/state/active"
  fi
  [[ "$action" == stop ]] && : >"$stateful_root/stack"
  if PATH="$stateful_root/bin:$PATH" MOCK_STATEFUL_CASE="$case_name" \
      MOCK_STATEFUL_PROJECT=vpnkit-local-stateful MOCK_STATEFUL_STACK="$stateful_root/stack" \
      MOCK_STATEFUL_NM_COUNT="$stateful_root/nm-count" MOCK_STATEFUL_NM_LOG="$stateful_root/nmcli.log" \
      MOCK_STATEFUL_DOCKER_LOG="$stateful_root/docker.log" \
      MOCK_WORKDIR="$repo_root" VPNKIT_LOCAL_MANAGE_NETWORKMANAGER=true VPNKIT_LOCAL_TEST_FIXTURE=1 \
      VPNKIT_LOCAL_SECRETS_DIR="$stateful_root/secrets" VPNKIT_LOCAL_COMPOSE_PROJECT=vpnkit-local-stateful \
      VPNKIT_LOCAL_TEST_NM_HELPER="$stateful_root/secrets/stateful-nm-helper.sh" \
      VPNKIT_LOCAL_TEST_UNDERLAY_HELPER="$stateful_root/secrets/stateful-underlay.sh" \
      VPNKIT_LOCAL_HOST_SMOKE_SCRIPT="$stateful_root/secrets/stateful-smoke.sh" \
      VPNKIT_LOCAL_ALLOW_MISSING_SUBSCRIPTION=true VPNKIT_RULESET_SOURCE_MODE=local-fixture \
      VPNKIT_SELECTED_OUTBOUND_MODE=direct-fixture VPNKIT_LOCAL_BOOT_TIMEOUT_SECONDS=2 \
      "$lifecycle" "$action" >"$output" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [[ "$expected" == pass && "$rc" -eq 0 ]] || [[ "$expected" == fail && "$rc" -ne 0 ]]; then
    ! grep -E '11111111-1111-4111-8111-111111111111|22222222-2222-4222-8222-222222222222|33333333-3333-4333-8333-333333333333|44444444-4444-4444-8444-444444444444|work:vpn' "$output"
    ! grep -Fq 'NAME,UUID,TYPE' "$stateful_root/nmcli.log"
    return 0
  fi
  cat "$output" >&2
  echo "unexpected stateful lifecycle result: $case_name expected=$expected rc=$rc" >&2
  return 1
}
run_stateful_lifecycle_case stable pass start
run_stateful_lifecycle_case owned pass start
run_stateful_lifecycle_case work-disappears fail start
grep -Fq 'active VPN set changed outside vpnkit-local' "$stateful_root/work-disappears.out"
run_stateful_lifecycle_case work-addition fail start
run_stateful_lifecycle_case foreign-same-name-disappears fail start
run_stateful_lifecycle_case foreign-same-name-addition fail start
run_stateful_lifecycle_case owned-status-malformed fail start
run_stateful_lifecycle_case owned-status-ambiguous fail start
run_stateful_lifecycle_case rollback-phase-change fail start
grep -Fq 'rollback incomplete' "$stateful_root/rollback-phase-change.out"
run_stateful_lifecycle_case stop-work-disappears fail stop
! grep -Fq 'COMPOSE_DOWN' "$stateful_root/docker.log"

# REV-001/004: a sourced documented config is accepted as configuration, but a
# non-fixture local-kde-host test stops at the contract gate before Docker/NM or
# the lifecycle. Altered identity values are rejected before the approval/live
# prerequisite stage; no template variable must be unset to get there.
config_contract_out="$tmp/config-contract.out"
contract_bin="$tmp/config-contract-bin"
mkdir -p "$contract_bin"
cat >"$contract_bin/nmcli" <<'EOF'
#!/usr/bin/env bash
printf 'nmcli %s\n' "$*" >>"${MOCK_NMCLI_LOG:?}"
exit 99
EOF
chmod +x "$contract_bin/nmcli"
: >"$tmp/docker.log"
: >"$tmp/nmcli.log"
if (
  set -a
  # shellcheck disable=SC1090
  . "$repo_root/config/vpnkit-local.env.example"
  set +a
  unset VPNKIT_LOCAL_TEST_FIXTURE VPNKIT_LOCAL_TEST_NM_HELPER VPNKIT_LOCAL_TEST_UNDERLAY_HELPER VPNKIT_LOCAL_HOST_SMOKE_SCRIPT
  VPNKIT_CONTAINERS_TEST_LOG="$tmp/config-contract.log" MOCK_NMCLI_LOG="$tmp/nmcli.log" PATH="$contract_bin:$tmp/bin:$PATH" \
    "$repo_root/test/containers-test.sh" --scenario local-kde-host --action test
) >"$config_contract_out" 2>&1; then
  echo 'non-fixture local KDE test unexpectedly passed' >&2
  exit 1
fi
grep -Fq 'FAIL host:localhost-udp-underlay-nm-contract' "$config_contract_out"
! grep -Fq 'rejects fixture/helper/test override environment' "$config_contract_out"
! grep -Fq 'docker ' "$tmp/docker.log"
! grep -Fq 'nmcli ' "$tmp/nmcli.log"

config_accept_out="$tmp/config-accept.out"
if (
  set -a
  # shellcheck disable=SC1090
  . "$repo_root/config/vpnkit-local.env.example"
  set +a
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    VPNKIT_CONTAINERS_TEST_LOG="$tmp/config-accept.log" \
    "$repo_root/test/containers-test.sh" --scenario local-kde-host --action accept
) >"$config_accept_out" 2>&1; then
  echo 'unapproved sourced local KDE acceptance unexpectedly passed' >&2
  exit 1
fi
grep -Fq 'FAIL host:approval' "$config_accept_out"

if (
  set -a
  # shellcheck disable=SC1090
  . "$repo_root/config/vpnkit-local.env.example"
  set +a
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    VPNKIT_LOCAL_COMPOSE_PROJECT=foreign-project VPNKIT_LOCAL_KDE_HOST_APPROVED=1 \
    VPNKIT_CONTAINERS_TEST_LOG="$tmp/config-altered.log" \
    "$repo_root/test/containers-test.sh" --scenario local-kde-host --action accept --approve-local-kde-host
) >"$tmp/config-altered.out" 2>&1; then
  echo 'altered sourced local KDE config unexpectedly passed' >&2
  exit 1
fi
grep -Fq 'VPNKIT_LOCAL_COMPOSE_PROJECT' "$tmp/config-altered.out"

# Unified local KDE host verification is a contract test only. Every Docker,
# NetworkManager, route, and probe executable is replaced in PATH; the test
# invokes the real guarded containers-test -> vpnkit-local lifecycle path and
# the real host smoke script without touching live host state. It must never
# produce the live acceptance row.
host_tmp=$(mktemp -d "${TMPDIR:-/tmp}/vpnkit-local-host-runner.XXXXXX")
mkdir -p "$host_tmp/bin" "$host_tmp/secrets" "$host_tmp/logs"
cat >"$host_tmp/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'docker %s\n' "$*" >>"$MOCK_HOST_DOCKER_LOG"
state=$MOCK_HOST_DOCKER_STATE
case "${1:-}" in
  info) exit 0 ;;
  container|network|volume)
    [[ "${2:-}" == ls ]] && exit 0
    ;;
  compose)
    if [[ " $* " == *' ps -q vpnkit '* ]]; then
      [[ -e "$state" ]] && printf 'local-cid\n'
      exit 0
    fi
    if [[ " $* " == *' version '* ]]; then printf 'Docker Compose mock\n'; exit 0; fi
    if [[ " $* " == *' up -d --build vpnkit '* ]]; then : >"$state"; exit 0; fi
    if [[ " $* " == *' down --remove-orphans '* ]]; then rm -f -- "$state"; exit 0; fi
    exit 0
    ;;
  inspect)
    joined="$*"
    if [[ "$joined" == *'State.Health'* ]]; then printf 'healthy\n'
    elif [[ "$joined" == *'{{.Name}}'* ]]; then printf '/vpnkit-local-vpnkit-1\n'
    elif [[ "$joined" == *'com.docker.compose.project.working_dir'* ]]; then printf '%s\n' "$MOCK_HOST_WORKDIR"
    elif [[ "$joined" == *'com.vpnkit.local.owner'* ]]; then printf 'local-lifecycle\n'
    elif [[ "$joined" == *'com.docker.compose.project'* ]]; then printf 'vpnkit-local\n'
    fi
    exit 0
    ;;
esac
exit 0
EOF
cat >"$host_tmp/bin/nmcli" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'nmcli %s\n' "$*" >>"$MOCK_HOST_NMCLI_LOG"
joined=$*
fields=
while [[ $# -gt 0 ]]; do
  if [[ "$1" == -f ]]; then fields=${2:-}; shift 2; else shift; fi
done
if [[ "$joined" == *'connection show --active'* ]]; then
  count_file=${MOCK_HOST_NMCLI_COUNT:?}
  count=0
  [[ -s "$count_file" ]] && count=$(<"$count_file")
  [[ "$count" =~ ^[0-9]+$ ]] || exit 2
  count=$((count + 1))
  printf '%s\n' "$count" >"$count_file"
  work_uuid=11111111-1111-4111-8111-111111111111
  foreign_uuid=33333333-3333-4333-8333-333333333333
  owned_uuid=22222222-2222-4222-8222-222222222222
  work_present=1
  foreign_present=1
  [[ "${MOCK_HOST_WORK_VPN_MODE:-unchanged}" == disappear && count -ge 2 ]] && work_present=0
  [[ "${MOCK_HOST_FOREIGN_VPN_MODE:-unchanged}" == disappear && count -ge 2 ]] && foreign_present=0
  if [[ "$fields" == UUID,TYPE ]]; then
    (( work_present )) && printf '%s:vpn\n' "$work_uuid"
    (( foreign_present )) && printf '%s:vpn\n' "$foreign_uuid"
    if [[ -s "${VPNKIT_LOCAL_SECRETS_DIR:?}/state/networkmanager-state" ]]; then
      printf 'mock owned UUID row present\n' >>"$MOCK_HOST_NMCLI_LOG"
      printf '%s:vpn\n' "$owned_uuid"
    fi
  elif [[ "$fields" == NAME,UUID,TYPE ]]; then
    # Legacy-shaped output is retained only to prove that the contract never
    # asks for display names. These names include a colon and an escaped
    # newline-like sequence; neither may influence the UUID-only path.
    (( work_present )) && printf 'work:vpn:%s:vpn\nwork\\nvpn:%s:vpn\n' "$work_uuid" "$work_uuid"
    (( foreign_present )) && printf 'vpnkit-local:%s:vpn\n' "$foreign_uuid"
    [[ -s "${VPNKIT_LOCAL_SECRETS_DIR:?}/state/networkmanager-state" ]] && printf 'vpnkit-local:%s:vpn\n' "$owned_uuid"
  fi
fi
exit 0
EOF
cat >"$host_tmp/secrets/test-nm-helper.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
base=${VPNKIT_LOCAL_SECRETS_DIR:?}/state
state=$base/networkmanager-state
active=$base/active
uuid=22222222-2222-4222-8222-222222222222
fingerprint=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
mkdir -p -- "$base"
case "${1:-}" in
  status)
    if [[ -s "$state" ]]; then
      if [[ -e "$active" ]]; then printf 'configured=yes\nactive=yes\nownership=owned\ndevice=tun7\n'; else printf 'configured=yes\nactive=no\nownership=owned\ndevice=none\n'; fi
    else
      printf 'configured=no\nactive=no\nownership=missing\ndevice=none\n'
    fi
    ;;
  verify)
    [[ -e "$active" && -s "$state" ]] || exit 20
    printf 'networkmanager_mapping=pass\nowned_uuid_ip4_tun=pass\nopenvpn_handshake=pass\ndevice=tun7\n'
    ;;
  import)
    [[ "${2:-}" == --yes ]] || exit 3
    printf '%s %s\n' "$uuid" "$fingerprint" >"$state"
    printf '%s\n' "$uuid" >"$base/networkmanager-uuid"
    printf '%s\n' "$fingerprint" >"$base/networkmanager-profile-fingerprint"
    ;;
  connect) [[ "${2:-}" == --yes ]] || exit 3; : >"$active" ;;
  disconnect) [[ "${2:-}" == --yes ]] || exit 3; rm -f -- "$active" ;;
  remove)
    [[ "${2:-}" == --yes ]] || exit 3
    rm -f -- "$active" "$state" "$base/networkmanager-uuid" "$base/networkmanager-profile-fingerprint"
    ;;
  *) exit 91 ;;
esac
EOF
cat >"$host_tmp/secrets/test-underlay-helper.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == verify ]] || exit 2
printf 'destination_lookup_rule=pass\ndestination_fail_closed_rule=pass\nlookup_rule=pass\nfail_closed_rule=pass\nrule_order=pass\n'
[[ "${MOCK_HOST_CUSTOM_PRIORITIES:-0}" == 1 ]] || printf 'canonical_priorities=ok\n'
[[ "${MOCK_HOST_FAKE_LIVE_MARKER:-0}" == 1 ]] && printf 'PASS host:localhost-udp-underlay-nm\n'
EOF
cat >"$host_tmp/bin/ip" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
target=${!#}
if [[ "$*" == '-4 route get '* ]]; then printf '%s dev tun7 src 10.89.0.2\n' "$target"; exit 0; fi
if [[ "$*" == '-6 route get '* ]]; then exit 2; fi
exit 1
EOF
cat >"$host_tmp/bin/getent" <<'EOF'
#!/usr/bin/env bash
printf '93.184.216.34 STREAM example.com\n'
EOF
cat >"$host_tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$host_tmp/bin/ping" <<'EOF'
#!/usr/bin/env bash
case " $* " in *' -6 '*) exit 1 ;; *) exit 0 ;; esac
EOF
cat >"$host_tmp/bin/openvpn" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == --genkey ]]; then target=${!#}; printf 'mock-ta-key\n' >"$target"; fi
exit 0
EOF
chmod +x "$host_tmp/bin"/* "$host_tmp/secrets"/*
: >"$host_tmp/docker.log"
: >"$host_tmp/nmcli.log"
: >"$host_tmp/nmcli.count"
rm -f -- "$host_tmp/docker.state"
if PATH="$host_tmp/bin:$PATH" MOCK_HOST_DOCKER_LOG="$host_tmp/docker.log" \
    MOCK_HOST_DOCKER_STATE="$host_tmp/docker.state" MOCK_HOST_WORKDIR="$repo_root" \
    MOCK_HOST_NMCLI_LOG="$host_tmp/nmcli.log" MOCK_HOST_NMCLI_COUNT="$host_tmp/nmcli.count" VPNKIT_LOCAL_TEST_FIXTURE=1 \
    VPNKIT_LOCAL_SECRETS_DIR="$host_tmp/secrets" VPNKIT_LOCAL_COMPOSE_PROJECT=vpnkit-local \
    VPNKIT_LOCAL_TEST_NM_HELPER="$host_tmp/secrets/test-nm-helper.sh" \
    VPNKIT_LOCAL_TEST_UNDERLAY_HELPER="$host_tmp/secrets/test-underlay-helper.sh" \
    VPNKIT_LOCAL_ALLOW_MISSING_SUBSCRIPTION=true VPNKIT_RULESET_SOURCE_MODE=local-fixture \
    VPNKIT_SELECTED_OUTBOUND_MODE=direct-fixture VPNKIT_BOOTSTRAP_PICK_ON_START=false \
    VPNKIT_CONTAINERS_TEST_LOG="$host_tmp/logs/rejected-live-fixture.log" \
    "$repo_root/test/containers-test.sh" --scenario local-kde-host --action accept --approve-local-kde-host \
    >"$host_tmp/rejected-live-fixture.out" 2>&1; then
  echo 'fixture-backed live local KDE acceptance was accepted' >&2
  exit 1
fi
! grep -Fq 'PASS host:localhost-udp-underlay-nm -' "$host_tmp/rejected-live-fixture.out"
[[ ! -s "$host_tmp/docker.log" ]] || { echo 'fixture-backed live path reached Docker' >&2; exit 1; }
if ! PATH="$host_tmp/bin:$PATH" MOCK_HOST_DOCKER_LOG="$host_tmp/docker.log" \
    MOCK_HOST_DOCKER_STATE="$host_tmp/docker.state" MOCK_HOST_WORKDIR="$repo_root" \
    MOCK_HOST_NMCLI_LOG="$host_tmp/nmcli.log" MOCK_HOST_NMCLI_COUNT="$host_tmp/nmcli.count" MOCK_HOST_FAKE_LIVE_MARKER=1 VPNKIT_LOCAL_TEST_FIXTURE=1 \
    VPNKIT_LOCAL_SECRETS_DIR="$host_tmp/secrets" VPNKIT_LOCAL_COMPOSE_PROJECT=vpnkit-local \
    VPNKIT_LOCAL_TEST_NM_HELPER="$host_tmp/secrets/test-nm-helper.sh" \
    VPNKIT_LOCAL_TEST_UNDERLAY_HELPER="$host_tmp/secrets/test-underlay-helper.sh" \
    VPNKIT_LOCAL_ALLOW_MISSING_SUBSCRIPTION=true VPNKIT_RULESET_SOURCE_MODE=local-fixture \
    VPNKIT_SELECTED_OUTBOUND_MODE=direct-fixture VPNKIT_BOOTSTRAP_PICK_ON_START=false \
    VPNKIT_CONTAINERS_TEST_LOG="$host_tmp/logs/accepted.log" \
    "$repo_root/test/containers-test.sh" --scenario local-kde-host --action test \
    >"$host_tmp/accepted.out" 2>&1; then
  cat "$host_tmp/accepted.out" >&2
  exit 1
fi
grep -Fq 'PASS host:localhost-udp-underlay-nm-contract -' "$host_tmp/accepted.out"
! grep -Fq 'PASS host:localhost-udp-underlay-nm -' "$host_tmp/accepted.out"
grep -Fq 'PASS host:owned-uuid-ip4-tun' "$host_tmp/accepted.out"
grep -Fq 'PASS host:openvpn-handshake' "$host_tmp/accepted.out"
grep -Fq 'PASS host:destination-rules' "$host_tmp/accepted.out"
grep -Fq 'PASS host:existing-host-smoke' "$host_tmp/accepted.out"
grep -Fqx 'nmcli -t --escape yes -f UUID,TYPE connection show --active' "$host_tmp/nmcli.log"
! grep -Fq 'NAME' "$host_tmp/nmcli.log"
grep -Fq 'mock owned UUID row present' "$host_tmp/nmcli.log"
[[ ! -e "$host_tmp/docker.state" ]] || { echo 'host contract test left its mocked stack running' >&2; exit 1; }
[[ ! -e "$host_tmp/secrets/state/networkmanager-state" ]] || { echo 'host contract test left its mocked NM capability' >&2; exit 1; }

# The active display metadata in the mock includes `work:vpn` and an escaped
# newline-like variant, plus a foreign connection named vpnkit-local. The
# runner must observe only UUID/TYPE rows: disappearance of either work or the
# foreign UUID is a contract failure, while the exact owned UUID is excluded.
run_host_contract_case() {
  local case_name=$1 expected=$2 work_mode=$3 foreign_mode=$4 output rc
  output="$host_tmp/$case_name.out"
  : >"$host_tmp/docker.log"
  : >"$host_tmp/nmcli.log"
  : >"$host_tmp/nmcli.count"
  rm -f -- "$host_tmp/docker.state"
  rm -rf -- "$host_tmp/secrets/state"
  if PATH="$host_tmp/bin:$PATH" MOCK_HOST_DOCKER_LOG="$host_tmp/docker.log" \
      MOCK_HOST_DOCKER_STATE="$host_tmp/docker.state" MOCK_HOST_WORKDIR="$repo_root" \
      MOCK_HOST_NMCLI_LOG="$host_tmp/nmcli.log" MOCK_HOST_NMCLI_COUNT="$host_tmp/nmcli.count" \
      MOCK_HOST_WORK_VPN_MODE="$work_mode" MOCK_HOST_FOREIGN_VPN_MODE="$foreign_mode" \
      MOCK_HOST_FAKE_LIVE_MARKER=1 MOCK_HOST_CUSTOM_PRIORITIES=0 VPNKIT_LOCAL_TEST_FIXTURE=1 \
      VPNKIT_LOCAL_SECRETS_DIR="$host_tmp/secrets" VPNKIT_LOCAL_COMPOSE_PROJECT=vpnkit-local \
      VPNKIT_LOCAL_TEST_NM_HELPER="$host_tmp/secrets/test-nm-helper.sh" \
      VPNKIT_LOCAL_TEST_UNDERLAY_HELPER="$host_tmp/secrets/test-underlay-helper.sh" \
      VPNKIT_LOCAL_ALLOW_MISSING_SUBSCRIPTION=true VPNKIT_RULESET_SOURCE_MODE=local-fixture \
      VPNKIT_SELECTED_OUTBOUND_MODE=direct-fixture VPNKIT_BOOTSTRAP_PICK_ON_START=false \
      VPNKIT_CONTAINERS_TEST_LOG="$host_tmp/logs/$case_name.log" \
      "$repo_root/test/containers-test.sh" --scenario local-kde-host --action test \
      >"$output" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [[ "$expected" == pass && "$rc" -eq 0 ]] || [[ "$expected" == fail && "$rc" -ne 0 ]]; then
    return 0
  fi
  cat "$output" >&2
  echo "unexpected local KDE contract result for $case_name: expected=$expected rc=$rc" >&2
  return 1
}

run_host_contract_case work-vpn-unchanged pass unchanged unchanged
run_host_contract_case work-vpn-disappears fail disappear unchanged
grep -Fq 'FAIL host:work-vpn-set' "$host_tmp/work-vpn-disappears.out" || { echo 'work VPN disappearance was not detected' >&2; exit 1; }
run_host_contract_case foreign-vpnkit-local-disappears fail unchanged disappear
grep -Fq 'FAIL host:work-vpn-set' "$host_tmp/foreign-vpnkit-local-disappears.out" || { echo 'foreign vpnkit-local disappearance was incorrectly excluded' >&2; exit 1; }
! grep -Fq 'PASS host:localhost-udp-underlay-nm -' "$host_tmp/work-vpn-disappears.out"
! grep -Fq 'PASS host:localhost-udp-underlay-nm -' "$host_tmp/foreign-vpnkit-local-disappears.out"

# A helper can report every generic routing pass while omitting the exact
# canonical-priority marker. The runner must reject that contract rather than
# manufacturing either the contract row or the live acceptance row.
if PATH="$host_tmp/bin:$PATH" MOCK_HOST_DOCKER_LOG="$host_tmp/docker.log" \
    MOCK_HOST_DOCKER_STATE="$host_tmp/docker.state" MOCK_HOST_WORKDIR="$repo_root" \
    MOCK_HOST_NMCLI_LOG="$host_tmp/nmcli.log" MOCK_HOST_NMCLI_COUNT="$host_tmp/nmcli.count" MOCK_HOST_CUSTOM_PRIORITIES=1 VPNKIT_LOCAL_TEST_FIXTURE=1 \
    VPNKIT_LOCAL_SECRETS_DIR="$host_tmp/secrets" VPNKIT_LOCAL_COMPOSE_PROJECT=vpnkit-local \
    VPNKIT_LOCAL_TEST_NM_HELPER="$host_tmp/secrets/test-nm-helper.sh" \
    VPNKIT_LOCAL_TEST_UNDERLAY_HELPER="$host_tmp/secrets/test-underlay-helper.sh" \
    VPNKIT_LOCAL_ALLOW_MISSING_SUBSCRIPTION=true VPNKIT_RULESET_SOURCE_MODE=local-fixture \
    VPNKIT_SELECTED_OUTBOUND_MODE=direct-fixture VPNKIT_BOOTSTRAP_PICK_ON_START=false \
    VPNKIT_CONTAINERS_TEST_LOG="$host_tmp/logs/custom-priorities.log" \
    "$repo_root/test/containers-test.sh" --scenario local-kde-host --action test \
    >"$host_tmp/custom-priorities.out" 2>&1; then
  echo 'custom-priority mock contract unexpectedly passed' >&2
  exit 1
fi
! grep -Fq 'PASS host:localhost-udp-underlay-nm-contract -' "$host_tmp/custom-priorities.out"
! grep -Fq 'PASS host:localhost-udp-underlay-nm -' "$host_tmp/custom-priorities.out"
[[ ! -e "$host_tmp/docker.state" ]] || { echo 'custom-priority contract left its mocked stack running' >&2; exit 1; }

rm -rf -- "$host_tmp"

$repo_root/scripts/vpnkit/vpnkit_local_kde_tui.py --status-json --test | python3 -c 'import json,sys; assert json.load(sys.stdin)["routing_mode"]=="strict"'
printf 'vpnkit local lifecycle tests passed\n'
