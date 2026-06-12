#!/usr/bin/env bash
# Unified public-safe vpnkit container test harness.
#
# Usage:
#   test/containers-test.sh [-h|--help] [--scenario steamdeck-host] [--action up|test|down|cycle]
#
# Actions for --scenario steamdeck-host:
#   up     prepare isolated lab config and deploy isolated Deck Podman container
#   test   run server/container/client/policy smoke checks against isolated lab
#   down   remove only isolated lab container and optional isolated remote state
#   cycle  down + up + test
#
# Log output is redacted and written to both console and a log file immediately.
# Default log: logs/vpnkit-containers-test-<timestamp>.log
# Override:    VPNKIT_CONTAINERS_TEST_LOG=/path/to/log
#
# Public-safety: do not print profile contents, private endpoints, subscription
# URLs, auth values, node values, or raw config dumps. This harness redacts IPs
# and sensitive URL/token-shaped values from all emitted output.
#
# Environment/defaults:
#   VPNKIT_TEST_SSH_TARGET=${VPNKIT_TEST_SSH_TARGET:-${VPNKIT_STEAMDECK_SSH_TARGET:-${VPNKIT_STEAMDECK_SSH_HOST:-deck}}}
#   VPNKIT_TEST_RUNTIME=${VPNKIT_TEST_RUNTIME:-podman}
#   VPNKIT_TEST_SERVER_CONTAINER=${VPNKIT_TEST_SERVER_CONTAINER:-vpnkit}
#   VPNKIT_TEST_ENDPOINT=${VPNKIT_TEST_ENDPOINT:-${VPNKIT_STEAMDECK_LAN_ENDPOINT:-}}
#   VPNKIT_TEST_PROFILE=${VPNKIT_TEST_PROFILE:-secrets/vps/openvpn/client/test-client.ovpn}
#   VPNKIT_TEST_ROUTING_MODE=${VPNKIT_TEST_ROUTING_MODE:-tun}
#   VPNKIT_TEST_MANIFEST=config/vpnkit-manifest.example.yaml
#   VPNKIT_TEST_MANIFEST_SERVER=steamdeck
#   VPNKIT_TEST_MANIFEST_CLIENT=host-machine
#   VPNKIT_TEST_MANIFEST_RENDER_MODE=fixture|real (default: fixture)
#   VPNKIT_TEST_MANIFEST_PROFILE_INTENT=test|production (default: test; production must be explicit)
#   VPNKIT_TEST_SSH_TIMEOUT=12        SSH probe timeout seconds
#   VPNKIT_TEST_REMOTE_CMD_TIMEOUT=120 Remote inspect/exec timeout seconds
#   VPNKIT_TEST_DEPLOY_TIMEOUT=900    Steam Deck deploy timeout seconds
#   VPNKIT_TEST_CLIENT_TIMEOUT=180    Client smoke timeout seconds

set -u -o pipefail

usage() { sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; }
SCENARIO=${VPNKIT_TEST_SCENARIO:-}
ACTION=${VPNKIT_TEST_ACTION:-test}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario) SCENARIO=${2:?missing value}; shift 2 ;;
    --action) ACTION=${2:?missing value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$ACTION" in up|test|down|cycle) ;; *) echo "unknown action: $ACTION" >&2; usage >&2; exit 2 ;; esac
if [[ -n "$SCENARIO" && "$SCENARIO" != "steamdeck-host" ]]; then
  echo "unknown scenario: $SCENARIO (supported: steamdeck-host)" >&2; exit 2
fi
TS=$(date -u +%Y%m%dT%H%M%SZ)
LOG_FILE=${VPNKIT_CONTAINERS_TEST_LOG:-"logs/vpnkit-containers-test-$TS.log"}
LOG_NOTE=""
if ! mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || ! : >"$LOG_FILE" 2>/dev/null; then
  if [[ -n "${VPNKIT_CONTAINERS_TEST_LOG:-}" ]]; then
    printf 'cannot write VPNKIT_CONTAINERS_TEST_LOG: %s\n' "$LOG_FILE" >&2
    exit 2
  fi
  LOG_FILE="/tmp/vpnkit-containers-test-$TS.log"
  : >"$LOG_FILE"
  LOG_NOTE="default logs/ path was not writable; using $LOG_FILE"
fi

redact_stream() {
  sed -E \
    -e 's#vless://[^[:space:]]+#vless://[redacted]#ig' \
    -e 's#(https?://)[^[:space:]]*(token|sub|subscription|api[_-]?key|apikey|key|auth|password|passwd|secret)[^[:space:]]*#\1[redacted-url]#ig' \
    -e 's#(ss|trojan|vmess)://[^[:space:]]+#\1://[redacted]#ig' \
    -e 's/([0-9a-f]{8}-[0-9a-f-]{27,})/[redacted-uuid]/ig' \
    -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' \
    -e 's/\b([0-9a-f]{1,4}:){2,}[0-9a-f]{1,4}\b/<IPv6>/ig' \
    -e "s/((private[_-]?key|password|passwd|auth|token|secret|node|sub_url|subscription)[\"':= ]+)[^,\"' ]+/\\1[redacted]/ig"
}
exec > >(redact_stream | tee "$LOG_FILE") 2>&1

SSH_TARGET=${VPNKIT_TEST_SSH_TARGET:-${VPNKIT_STEAMDECK_SSH_TARGET:-${VPNKIT_STEAMDECK_SSH_HOST:-deck}}}
REMOTE_RUNTIME=${VPNKIT_TEST_RUNTIME:-podman}
SERVER_CONTAINER=${VPNKIT_TEST_SERVER_CONTAINER:-vpnkit}
TEST_ENDPOINT=${VPNKIT_TEST_ENDPOINT:-${VPNKIT_STEAMDECK_LAN_ENDPOINT:-}}
TEST_PROFILE=${VPNKIT_TEST_PROFILE:-secrets/vps/openvpn/client/test-client.ovpn}
TEST_ROUTING_MODE=${VPNKIT_TEST_ROUTING_MODE:-tun}
TEST_MANIFEST=${VPNKIT_TEST_MANIFEST:-}
TEST_MANIFEST_SERVER=${VPNKIT_TEST_MANIFEST_SERVER:-}
TEST_MANIFEST_CLIENT=${VPNKIT_TEST_MANIFEST_CLIENT:-}
TEST_MANIFEST_RENDER_MODE=${VPNKIT_TEST_MANIFEST_RENDER_MODE:-fixture}
TEST_MANIFEST_PROFILE_INTENT=${VPNKIT_TEST_MANIFEST_PROFILE_INTENT:-test}
TEST_MANIFEST_OUT_DIR=${VPNKIT_TEST_MANIFEST_OUT_DIR:-generated/openvpn-profiles}
SSH_TIMEOUT=${VPNKIT_TEST_SSH_TIMEOUT:-12}
REMOTE_CMD_TIMEOUT=${VPNKIT_TEST_REMOTE_CMD_TIMEOUT:-120}
DEPLOY_TIMEOUT=${VPNKIT_TEST_DEPLOY_TIMEOUT:-900}
CLIENT_TIMEOUT=${VPNKIT_TEST_CLIENT_TIMEOUT:-180}

is_placeholder_value() {
  local v=${1:-}
  [[ -z "$v" ]] && return 1
  case "$v" in
    your-*|*.invalid|192.0.2.*|203.0.113.*) return 0 ;;
    *) return 1 ;;
  esac
}

selected_ssh_source=default-deck
if [[ -n "${VPNKIT_TEST_SSH_TARGET:-}" ]]; then selected_ssh_source=VPNKIT_TEST_SSH_TARGET
elif [[ -n "${VPNKIT_STEAMDECK_SSH_TARGET:-}" ]]; then selected_ssh_source=VPNKIT_STEAMDECK_SSH_TARGET
elif [[ -n "${VPNKIT_STEAMDECK_SSH_HOST:-}" ]]; then selected_ssh_source=VPNKIT_STEAMDECK_SSH_HOST
fi
selected_endpoint_source=none
if [[ -n "${VPNKIT_TEST_ENDPOINT:-}" ]]; then selected_endpoint_source=VPNKIT_TEST_ENDPOINT
elif [[ -n "${VPNKIT_STEAMDECK_LAN_ENDPOINT:-}" ]]; then selected_endpoint_source=VPNKIT_STEAMDECK_LAN_ENDPOINT
fi

if [[ "$SCENARIO" == "steamdeck-host" ]]; then
  export VPNKIT_RULESET_SOURCE_MODE=${VPNKIT_RULESET_SOURCE_MODE:-local-fixture}
  LAB_SCENARIO_DIR=${VPNKIT_TEST_LAB_SECRETS_DIR:-secrets/vpnkit-labs/steamdeck-host}
  LAB_CONTAINER=${VPNKIT_TEST_SERVER_CONTAINER:-vpnkit-test-steamdeck-host}
  LAB_IMAGE=${VPNKIT_STEAMDECK_IMAGE:-localhost/vpnkit:test-steamdeck-host}
  LAB_PORT=${VPNKIT_OPENVPN_PORT:-21194}
  LAB_REMOTE_DIR=${VPNKIT_STEAMDECK_REMOTE_DIR:-'~/.local/state/vpnkit-labs/steamdeck-host'}
  LAB_ROUTING_MODE=${VPNKIT_TEST_ROUTING_MODE:-${VPNKIT_ROUTING_MODE:-tun}}
  SERVER_CONTAINER=$LAB_CONTAINER
  TEST_PROFILE=${VPNKIT_TEST_PROFILE:-$LAB_SCENARIO_DIR/openvpn/client/test-client.ovpn}
  LAB_NESTED_PROFILE=${VPNKIT_STEAMDECK_NESTED_CLIENT_PROFILE:-$LAB_SCENARIO_DIR/nested/openvpn/client/test-client.ovpn}
  TEST_ROUTING_MODE=$LAB_ROUTING_MODE
  export VPNKIT_TEST_SERVER_CONTAINER=$LAB_CONTAINER VPNKIT_TEST_PROFILE=$TEST_PROFILE VPNKIT_TEST_ROUTING_MODE=$TEST_ROUTING_MODE
  export VPNKIT_STEAMDECK_NESTED_CLIENT_PROFILE=$LAB_NESTED_PROFILE
  export VPNKIT_STEAMDECK_CONTAINER=$LAB_CONTAINER VPNKIT_STEAMDECK_IMAGE=$LAB_IMAGE VPNKIT_OPENVPN_PORT=$LAB_PORT VPNKIT_STEAMDECK_REMOTE_DIR=$LAB_REMOTE_DIR VPNKIT_ROUTING_MODE=$LAB_ROUTING_MODE
  export VPNKIT_STEAMDECK_SSH_TARGET=$SSH_TARGET
  export VPNKIT_STEAMDECK_CONFIG_SOURCE="$LAB_SCENARIO_DIR/rendered"
  TEST_ENDPOINT=${VPNKIT_TEST_ENDPOINT:-${VPNKIT_STEAMDECK_LAN_ENDPOINT:-}}
fi

PASS=0; FAIL=0; SKIP=0
RESULTS=()

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
record() {
  local status=$1 name=$2 reason=${3:-}
  case "$status" in PASS) PASS=$((PASS+1));; FAIL) FAIL=$((FAIL+1));; SKIP) SKIP=$((SKIP+1));; *) status=FAIL; FAIL=$((FAIL+1)); reason="internal bad status: $1 $reason";; esac
  RESULTS+=("$status|$name|$reason")
  log "$status $name${reason:+ - $reason}"
}

run_capture() { local out rc; out=$("$@" 2>&1); rc=$?; printf '%s' "$out"; return "$rc"; }
run_capture_timeout() { local seconds=$1; shift; local out rc; out=$(timeout -k 5s "$seconds" "$@" 2>&1); rc=$?; printf '%s' "$out"; return "$rc"; }
ssh_run() { timeout --preserve-status "$REMOTE_CMD_TIMEOUT" ssh -o BatchMode=yes -o ConnectTimeout="$SSH_TIMEOUT" "$SSH_TARGET" "$@"; }
container_exec() { ssh_run "$REMOTE_RUNTIME exec $SERVER_CONTAINER sh -lc $(printf '%q' "$1")"; }

log "vpnkit unified container test harness starting"
log "log_file=$LOG_FILE"
[[ -n "$LOG_NOTE" ]] && log "$LOG_NOTE"
ssh_target_state=usable
endpoint_state=$([[ -n "$TEST_ENDPOINT" ]] && echo yes || echo no)
if [[ "$SCENARIO" == "steamdeck-host" ]]; then
  is_placeholder_value "$SSH_TARGET" && ssh_target_state=placeholder
  if [[ -n "$TEST_ENDPOINT" ]] && is_placeholder_value "$TEST_ENDPOINT"; then endpoint_state=placeholder; fi
fi
log "ssh_target_source=$selected_ssh_source ssh_target_state=$ssh_target_state remote_runtime=$REMOTE_RUNTIME server_container=$SERVER_CONTAINER"
log "client_profile_path=$TEST_PROFILE endpoint_state=$endpoint_state endpoint_source=$selected_endpoint_source"

run_lifecycle_down() {
  [[ "$SCENARIO" == "steamdeck-host" ]] || return 0
  if [[ "$SERVER_CONTAINER" == "vpnkit" ]]; then
    record FAIL "lifecycle:down-safety" "refusing to operate on default/prod container name vpnkit"
    return 1
  fi
  if [[ -z "$SSH_TARGET" || "$ssh_target_state" == "placeholder" ]]; then
    record FAIL "lifecycle:prereq-ssh" "steamdeck-host requires non-placeholder SSH target before isolated cleanup (source=$selected_ssh_source)"
    return 1
  fi
  if ! out=$(run_capture_timeout "$REMOTE_CMD_TIMEOUT" scripts/deck/vpnkit-steamdeck-podman.sh cleanup); then
    record FAIL "lifecycle:down" "isolated container cleanup failed: $out"
    return 1
  fi
  record PASS "lifecycle:down" "isolated lab container cleanup completed for $SERVER_CONTAINER"
  if [[ "${VPNKIT_TEST_LAB_REMOVE_REMOTE_STATE:-0}" == "1" ]]; then
    if out=$(run_capture ssh -o BatchMode=yes -o ConnectTimeout=8 "$SSH_TARGET" "case '$VPNKIT_STEAMDECK_REMOTE_DIR' in '~/'*|/*) rm -rf '$VPNKIT_STEAMDECK_REMOTE_DIR' ;; *) exit 2 ;; esac"); then
      record PASS "lifecycle:remote-state-down" "optional isolated remote state removed"
    else
      record FAIL "lifecycle:remote-state-down" "optional remote state cleanup failed: $out"
    fi
  fi
}

run_lifecycle_up() {
  [[ "$SCENARIO" == "steamdeck-host" ]] || return 0
  if [[ "$SERVER_CONTAINER" == "vpnkit" ]]; then
    record FAIL "lifecycle:up-safety" "refusing to operate on default/prod container name vpnkit"
    return 1
  fi
  if [[ -z "$TEST_ENDPOINT" || "$endpoint_state" == "placeholder" ]]; then
    record FAIL "lifecycle:prereq-endpoint" "steamdeck-host requires non-placeholder VPNKIT_TEST_ENDPOINT or VPNKIT_STEAMDECK_LAN_ENDPOINT (source=$selected_endpoint_source)"
  fi
  if [[ -z "$SSH_TARGET" || "$ssh_target_state" == "placeholder" ]]; then
    record FAIL "lifecycle:prereq-ssh" "steamdeck-host requires non-placeholder SSH target from VPNKIT_TEST_SSH_TARGET, VPNKIT_STEAMDECK_SSH_TARGET, VPNKIT_STEAMDECK_SSH_HOST, or deck (source=$selected_ssh_source)"
  fi
  if [[ $FAIL -gt 0 ]]; then return 1; fi
  if out=$(run_capture env VPNKIT_TEST_LAB_SECRETS_DIR="$LAB_SCENARIO_DIR" VPNKIT_TEST_LAB_ENDPOINT="$TEST_ENDPOINT" VPNKIT_TEST_LAB_PORT="$LAB_PORT" VPNKIT_ROUTING_MODE="$TEST_ROUTING_MODE" scripts/vpnkit/vpnkit-test-lab-setup.sh); then
    printf '%s\n' "$out"
    record PASS "lifecycle:prepare" "generated isolated lab artifacts under $LAB_SCENARIO_DIR (contents not printed)"
  else
    printf '%s\n' "$out"
    record FAIL "lifecycle:prepare" "lab setup failed"
    return 1
  fi
  if out=$(run_capture_timeout "$DEPLOY_TIMEOUT" scripts/deck/vpnkit-steamdeck-podman.sh deploy); then
    printf '%s\n' "$out"
    record PASS "lifecycle:deploy" "isolated Podman lab deployed"
  else
    printf '%s\n' "$out"
    record FAIL "lifecycle:deploy" "isolated Podman lab deploy failed or timed out after ${DEPLOY_TIMEOUT}s"
    return 1
  fi
}

if [[ "$SCENARIO" == "steamdeck-host" ]]; then
  case "$ACTION" in
    down) run_lifecycle_down; printf '\nTotals: PASS=%d FAIL=%d SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"; [[ $FAIL -eq 0 ]]; exit $? ;;
    up) run_lifecycle_up; printf '\nTotals: PASS=%d FAIL=%d SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"; [[ $FAIL -eq 0 ]]; exit $? ;;
    cycle) run_lifecycle_down || true; run_lifecycle_up || true; if [[ $FAIL -gt 0 ]]; then printf '\nTotals: PASS=%d FAIL=%d SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"; exit 1; fi ;;
    test) ;;
  esac
fi

if [[ "$SCENARIO" == "steamdeck-host" && "$ACTION" == "test" ]]; then
  if [[ "$SERVER_CONTAINER" == "vpnkit" ]]; then
    record FAIL "lifecycle:test-safety" "refusing to test default/prod container name vpnkit for explicit steamdeck-host scenario"
  fi
  if [[ -z "$TEST_ENDPOINT" || "$endpoint_state" == "placeholder" ]]; then
    record FAIL "lifecycle:prereq-endpoint" "steamdeck-host requires non-placeholder VPNKIT_TEST_ENDPOINT or VPNKIT_STEAMDECK_LAN_ENDPOINT for live client smoke (source=$selected_endpoint_source)"
  fi
  if [[ -z "$SSH_TARGET" || "$ssh_target_state" == "placeholder" ]]; then
    record FAIL "lifecycle:prereq-ssh" "steamdeck-host requires non-placeholder SSH target (source=$selected_ssh_source)"
  fi
fi

# Server checks: best-effort remote read-only inspection.
server_ready=0
if [[ "$SCENARIO" == "steamdeck-host" && ( "$ssh_target_state" == "placeholder" || -z "$SSH_TARGET" ) ]]; then
  record FAIL "server:ssh-reachable" "placeholder/missing SSH target rejected before probe (source=$selected_ssh_source)"
elif out=$(run_capture_timeout "$SSH_TIMEOUT" ssh -o BatchMode=yes -o ConnectTimeout="$SSH_TIMEOUT" "$SSH_TARGET" true); then
  record PASS "server:ssh-reachable" "target reachable"
  server_ready=1
else
  record SKIP "server:ssh-reachable" "cannot reach SSH target '$SSH_TARGET': $out"
fi

container_ready=0
if [[ $server_ready -eq 1 ]]; then
  if out=$(run_capture ssh_run "$REMOTE_RUNTIME container inspect $SERVER_CONTAINER >/dev/null && $REMOTE_RUNTIME inspect -f '{{.State.Running}}' $SERVER_CONTAINER"); then
    if [[ "$out" == *true* ]]; then record PASS "server:container-running" "$SERVER_CONTAINER running"; container_ready=1
    else record FAIL "server:container-running" "$SERVER_CONTAINER exists but is not running: $out"; fi
  else
    record SKIP "server:container-running" "cannot inspect container/runtime: $out"
  fi
else
  record SKIP "server:container-running" "SSH unavailable"
fi

check_exec_contains() {
  local name=$1 cmd=$2 needle=$3 missing_status=${4:-FAIL} out
  if [[ $container_ready -ne 1 ]]; then record SKIP "$name" "server container unavailable"; return; fi
  if out=$(run_capture container_exec "$cmd"); then
    if [[ "$out" == *"$needle"* ]]; then record PASS "$name" "found $needle"; else record "$missing_status" "$name" "expected '$needle' not observed: $out"; fi
  else
    record SKIP "$name" "check command unavailable/failed: $out"
  fi
}

check_exec_contains "server:openvpn-process" "ps ww 2>/dev/null || ps" "openvpn" FAIL
check_exec_contains "server:sing-box-process" "ps ww 2>/dev/null || ps" "sing-box" FAIL
check_exec_contains "server:tun0-interface" "ip link show tun0 2>/dev/null || ifconfig tun0 2>/dev/null" "tun0" FAIL
if [[ "$TEST_ROUTING_MODE" == "tun" ]]; then
  check_exec_contains "server:sb-tun0-interface" "ip link show sb-tun0 2>/dev/null || ifconfig sb-tun0 2>/dev/null" "sb-tun0" FAIL
else
  record SKIP "server:sb-tun0-interface" "routing mode '$TEST_ROUTING_MODE' does not use sing-box TUN; set VPNKIT_TEST_ROUTING_MODE=tun for full-tunnel sb-tun0 acceptance"
fi

if [[ $container_ready -eq 1 ]]; then
  if out=$(run_capture container_exec 'if command -v sing-box >/dev/null 2>&1; then for c in /var/lib/vpnkit/sing-box/config.json /etc/sing-box/config.json /run/sing-box/config.json; do [ -r "$c" ] && exec sing-box check -c "$c"; done; echo no-readable-config; exit 77; else echo no-sing-box-command; exit 78; fi'); then
    record PASS "server:sing-box-check" "runtime config validates"
  else
    rc=$?; if [[ $rc -eq 77 || $rc -eq 78 ]]; then record SKIP "server:sing-box-check" "$out"; else record FAIL "server:sing-box-check" "$out"; fi
  fi

  if out=$(run_capture container_exec 'if command -v curl >/dev/null 2>&1; then curl -fsS --max-time 5 --socks5-hostname 127.0.0.1:2080 https://example.com >/dev/null; elif command -v nc >/dev/null 2>&1; then nc -z -w 3 127.0.0.1 2080; else echo no-curl-or-nc; exit 77; fi'); then
    record PASS "server:socks-inbound" "127.0.0.1:2080 reachable"
  else
    rc=$?; [[ $rc -eq 77 ]] && record SKIP "server:socks-inbound" "$out" || record FAIL "server:socks-inbound" "$out"
  fi

  cfg_cmd='for c in /var/lib/vpnkit/sing-box/config.json /etc/sing-box/config.json /run/sing-box/config.json; do [ -r "$c" ] && { grep -E "selected-native-out|direct-out|block-out|tun|socks" "$c" | sort -u; exit 0; }; done; echo no-readable-config; exit 77'
  if out=$(run_capture container_exec "$cfg_cmd"); then
    miss=(); for n in selected-native-out direct-out block-out tun socks; do [[ "$out" == *"$n"* ]] || miss+=("$n"); done
    if [[ ${#miss[@]} -eq 0 ]]; then record PASS "server:config-shape" "required tags/inbounds present"; else record FAIL "server:config-shape" "missing: ${miss[*]}"; fi
  else
    rc=$?; [[ $rc -eq 77 ]] && record SKIP "server:config-shape" "$out" || record FAIL "server:config-shape" "$out"
  fi
else
  record SKIP "server:sing-box-check" "server container unavailable"
  record SKIP "server:socks-inbound" "server container unavailable"
  record SKIP "server:config-shape" "server container unavailable"
fi

route_cases=("ya.ru=direct" "npmjs.com=direct" "pypi.org=direct" "debian.org=direct" "doubleclick.net=block" "googleads.g.doubleclick.net=block" "example.com=selected")
if [[ $container_ready -eq 1 ]]; then
  if out=$(run_capture container_exec 'command -v curl >/dev/null 2>&1 && { test -r /var/log/sing-box.log || test -r /var/lib/vpnkit/sing-box/sing-box.log || test -r /tmp/sing-box.log; }'); then
    record SKIP "server:route-decision-proof" "scaffold cases: ${route_cases[*]}; bounded log/tag proof is not yet robust enough in this environment"
  else
    record SKIP "server:route-decision-proof" "scaffold cases: ${route_cases[*]}; missing curl/readable sing-box logs/tools for safe proof"
  fi
else
  record SKIP "server:route-decision-proof" "server container unavailable; scaffold cases: ${route_cases[*]}"
fi

# Optional manifest-pair preparation: explicit selection validates, resolves, renders,
# then hands the generated profile to the existing client smoke/profile path.
manifest_pair_selected=0
manifest_fixture_profile=0
rendered_profile=""
if [[ -n "$TEST_MANIFEST" || -n "$TEST_MANIFEST_SERVER" || -n "$TEST_MANIFEST_CLIENT" ]]; then
  manifest_pair_selected=1
  if [[ -z "$TEST_MANIFEST" ]]; then TEST_MANIFEST="config/vpnkit-manifest.example.yaml"; fi
  if [[ "$TEST_MANIFEST_PROFILE_INTENT" != "test" && "$TEST_MANIFEST_PROFILE_INTENT" != "production" ]]; then
    record FAIL "manifest:selection" "VPNKIT_TEST_MANIFEST_PROFILE_INTENT must be test or production"
  elif [[ -z "$TEST_MANIFEST_SERVER" || -z "$TEST_MANIFEST_CLIENT" ]]; then
    record FAIL "manifest:selection" "VPNKIT_TEST_MANIFEST_SERVER and VPNKIT_TEST_MANIFEST_CLIENT are required when manifest mode is selected"
  elif [[ ! -r "$TEST_MANIFEST" ]]; then
    record FAIL "manifest:validate" "manifest missing/unreadable: $TEST_MANIFEST"
  elif [[ ! -x scripts/vpnkit/vpnkit-manifest-validate.py ]]; then
    record FAIL "manifest:validate" "scripts/vpnkit/vpnkit-manifest-validate.py not executable"
  elif out=$(run_capture python3 scripts/vpnkit/vpnkit-manifest-validate.py --manifest "$TEST_MANIFEST"); then
    record PASS "manifest:validate" "manifest schema/semantics passed"
    if out=$(run_capture python3 scripts/vpnkit/vpnkit-manifest-validate.py --manifest "$TEST_MANIFEST" --server "$TEST_MANIFEST_SERVER" --client "$TEST_MANIFEST_CLIENT" --profile-intent "$TEST_MANIFEST_PROFILE_INTENT"); then
      record PASS "manifest:resolve-pair" "resolved $TEST_MANIFEST_SERVER/$TEST_MANIFEST_CLIENT intent=$TEST_MANIFEST_PROFILE_INTENT to sanitized JSON"
      if [[ ! -x scripts/vpnkit/vpnkit-render-profile-for-pair.sh ]]; then
        record FAIL "manifest:render-profile" "scripts/vpnkit/vpnkit-render-profile-for-pair.sh not executable"
      elif out=$(run_capture scripts/vpnkit/vpnkit-render-profile-for-pair.sh --manifest "$TEST_MANIFEST" --server "$TEST_MANIFEST_SERVER" --client "$TEST_MANIFEST_CLIENT" --profile-intent "$TEST_MANIFEST_PROFILE_INTENT" --out-dir "$TEST_MANIFEST_OUT_DIR" --"$TEST_MANIFEST_RENDER_MODE"); then
        printf '%s\n' "$out"
        rendered_profile=$(printf '%s\n' "$out" | awk -F= '/^profile_written=/{print $2; exit}')
        if [[ -n "$rendered_profile" && -r "$rendered_profile" ]]; then
          TEST_PROFILE="$rendered_profile"
          [[ "$TEST_MANIFEST_RENDER_MODE" == "fixture" ]] && manifest_fixture_profile=1
          record PASS "manifest:render-profile" "profile rendered for selected pair intent=$TEST_MANIFEST_PROFILE_INTENT"
        else
          record FAIL "manifest:render-profile" "renderer did not produce a readable profile path"
        fi
      else
        printf '%s\n' "$out"
        record FAIL "manifest:render-profile" "selected pair profile render failed"
      fi
    else
      printf '%s\n' "$out"
      record FAIL "manifest:resolve-pair" "selected pair resolution failed"
    fi
  else
    printf '%s\n' "$out"
    record FAIL "manifest:validate" "manifest validation failed"
  fi
  if [[ -z "$rendered_profile" || ! -r "$rendered_profile" ]]; then
    TEST_PROFILE="$TEST_MANIFEST_OUT_DIR/selected-manifest-pair-not-rendered.ovpn"
  fi
fi

# Client checks: reuse existing public-safe smoke scripts where inputs allow.
if [[ "$SCENARIO" == "steamdeck-host" && $container_ready -ne 1 ]]; then
  record SKIP "client:steamdeck-profile-smoke" "server container unavailable; skipping bounded client smoke"
elif [[ $manifest_fixture_profile -eq 1 && -r "$TEST_PROFILE" ]]; then
  perms=$(stat -c '%a' "$TEST_PROFILE" 2>/dev/null || stat -f '%Lp' "$TEST_PROFILE")
  if [[ "$perms" == "600" && -s "$TEST_PROFILE" ]]; then
    record PASS "client:manifest-fixture-profile-shape" "fixture profile exists with mode 600 for OpenVPN client smoke handoff; contents not printed"
  else
    record FAIL "client:manifest-fixture-profile-shape" "fixture profile failed safe existence/permission checks"
  fi
elif [[ -r "$TEST_PROFILE" ]]; then
  if [[ -n "$TEST_ENDPOINT" ]]; then
    if [[ -x scripts/deck/vpnkit-steamdeck-client-test.sh ]]; then
      nested_args=()
      if [[ "$SCENARIO" == "steamdeck-host" ]]; then
        if [[ "${VPNKIT_STEAMDECK_NESTED_VPN_ENABLED:-1}" == "0" ]]; then
          record FAIL "client:nested-vpn-required" "nested VPN acceptance explicitly disabled; not deploy-ready"
        else
          nested_args+=(--nested-profile "${VPNKIT_STEAMDECK_NESTED_CLIENT_PROFILE:-}")
        fi
      fi
      if out=$(run_capture_timeout "$CLIENT_TIMEOUT" env VPNKIT_STEAMDECK_CLIENT_ENDPOINT="$TEST_ENDPOINT" VPNKIT_STEAMDECK_CLIENT_PROFILE="$TEST_PROFILE" VPNKIT_STEAMDECK_CLIENT_LOG_FILE= VPNKIT_STEAMDECK_CLIENT_TIMEOUT="$CLIENT_TIMEOUT" VPNKIT_STEAMDECK_NESTED_VPN_ENABLED="${VPNKIT_STEAMDECK_NESTED_VPN_ENABLED:-1}" scripts/deck/vpnkit-steamdeck-client-test.sh --endpoint "$TEST_ENDPOINT" --profile "$TEST_PROFILE" --timeout "$CLIENT_TIMEOUT" "${nested_args[@]}"); then
        printf '%s\n' "$out"
        if [[ "$SCENARIO" == "steamdeck-host" && "${VPNKIT_STEAMDECK_NESTED_VPN_ENABLED:-1}" != "0" ]]; then
          for pair in "client:nested-route-via-tun0=nested_route_via_tun0=ok" "client:nested-handshake=nested_openvpn_handshake=ok" "client:nested-tun1=nested_tun1=ok" "client:nested-ping-peer=nested_ping_peer=ok"; do
            name=${pair%%=*}; needle=${pair#*=}
            if [[ "$out" == *"$needle"* ]]; then record PASS "$name" "$needle"; else record FAIL "$name" "missing nested evidence marker: $needle"; fi
          done
        fi
        record PASS "client:steamdeck-profile-smoke" "existing endpoint replacement smoke passed"
      else
        printf '%s\n' "$out"
        if [[ "$SCENARIO" == "steamdeck-host" && "${VPNKIT_STEAMDECK_NESTED_VPN_ENABLED:-1}" != "0" ]]; then
          for pair in "client:nested-route-via-tun0=nested_route_via_tun0=ok" "client:nested-handshake=nested_openvpn_handshake=ok" "client:nested-tun1=nested_tun1=ok" "client:nested-ping-peer=nested_ping_peer=ok"; do
            name=${pair%%=*}; needle=${pair#*=}
            [[ "$out" == *"$needle"* ]] && record PASS "$name" "$needle" || record FAIL "$name" "nested client smoke failed before marker: $needle"
          done
        fi
        record FAIL "client:steamdeck-profile-smoke" "existing client smoke failed or timed out after ${CLIENT_TIMEOUT}s"
      fi
    else
      record SKIP "client:steamdeck-profile-smoke" "scripts/deck/vpnkit-steamdeck-client-test.sh not executable"
    fi
  elif [[ -x scripts/vpnkit/vpnkit-profile-check.sh ]]; then
    if out=$(run_capture scripts/vpnkit/vpnkit-profile-check.sh "$TEST_PROFILE"); then
      printf '%s\n' "$out"
      record PASS "client:profile-check" "existing profile check passed"
    else
      printf '%s\n' "$out"
      record FAIL "client:profile-check" "existing profile check failed"
    fi
  else
    record SKIP "client:profile-check" "scripts/vpnkit/vpnkit-profile-check.sh not executable"
  fi
else
  if [[ $manifest_pair_selected -eq 1 ]]; then
    record FAIL "client:profile-check" "selected manifest pair did not produce/read a usable profile: $TEST_PROFILE"
  else
    record SKIP "client:profile-check" "profile missing/unreadable: $TEST_PROFILE"
  fi
fi
record SKIP "client:policy-visible-extension" "TODO: add cheap dev/adblock policy-visible checks after smart route proof exists"

printf '\nSummary:\n'
printf '%-6s | %-36s | %s\n' STATUS CHECK REASON
printf '%-6s-+-%-36s-+-%s\n' ------ ------------------------------------ ------
for row in "${RESULTS[@]}"; do IFS='|' read -r s n r <<<"$row"; printf '%-6s | %-36s | %s\n' "$s" "$n" "$r"; done
printf '\nTotals: PASS=%d FAIL=%d SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"
log "vpnkit unified container test harness finished"

if [[ $FAIL -gt 0 ]]; then exit 1; fi
exit 0
