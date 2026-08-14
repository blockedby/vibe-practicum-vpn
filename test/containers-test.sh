#!/usr/bin/env bash
# Unified public-safe vpnkit container test harness.
#
# Usage:
#   test/containers-test.sh [-h|--help] [--scenario steamdeck-host|local-docker] [--action up|test|down|cycle]
#
# Actions for lifecycle scenarios:
#   up     prepare isolated lab config and deploy the isolated server container
#   test   run server/container/client/policy smoke checks against the isolated lab
#   down   remove only isolated scenario resources
#   cycle  down + up + test
#
# `local-docker` is non-production and never uses SSH, sudo, NetworkManager, or
# the default Compose project. It defaults to project `vpnkit-local-lab` and
# secrets under `secrets/vpnkit-labs/local-docker/`.
#
# Log output is redacted and written to both console and a log file immediately.
# Default log: logs/vpnkit-containers-test-<timestamp>.log (local-docker uses
# /tmp/vpnkit-containers-test/<project>/ instead).
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
#   VPNKIT_LOCAL_TEST_LOG_ROOT=/tmp/vpnkit-containers-test/<project>
#   VPNKIT_LOCAL_TEST_PROJECT=vpnkit-local-lab

set -u -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd -P)
cd -- "$REPO_ROOT"

usage() { sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; }

canonical_path() {
  realpath -m -- "$1"
}

reject_protected_path() {
  local label=$1 path=$2 strict_logs=${3:-0} canonical
  canonical=$(canonical_path "$path") || {
    printf 'cannot canonicalize %s path: %s\n' "$label" "$path" >&2
    exit 2
  }
  case "$canonical" in
    "$REPO_ROOT/secrets"|"$REPO_ROOT/secrets/vps"|"$REPO_ROOT/secrets/vps/"*|\
    "$REPO_ROOT/secrets/vpnkit-local"|"$REPO_ROOT/secrets/vpnkit-local/"*)
      printf 'refusing protected real secrets path for %s: %s\n' "$label" "$canonical" >&2
      exit 2
      ;;
  esac
  if (( strict_logs )); then
    case "$canonical" in
      "$REPO_ROOT/logs"|"$REPO_ROOT/logs/"*)
        printf 'refusing protected real logs path for %s: %s\n' "$label" "$canonical" >&2
        exit 2
        ;;
    esac
  else
    case "$canonical" in
      "$REPO_ROOT/logs/vpnkit"|"$REPO_ROOT/logs/vpnkit/"*|\
      "$REPO_ROOT/logs/vpnkit-local"|"$REPO_ROOT/logs/vpnkit-local/"*|\
      "$REPO_ROOT/logs/vps"|"$REPO_ROOT/logs/vps/"*)
        printf 'refusing protected real logs path for %s: %s\n' "$label" "$canonical" >&2
        exit 2
        ;;
    esac
  fi
}

assert_user_owned_path() {
  local label=$1 path=$2 canonical
  canonical=$(canonical_path "$path") || return 1
  if [[ -e "$canonical" && ! -O "$canonical" ]]; then
    printf 'refusing root-owned host path for %s: %s\n' "$label" "$canonical" >&2
    return 1
  fi
}

validate_local_project() {
  [[ "$LOCAL_PROJECT" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || {
    printf 'VPNKIT_LOCAL_TEST_PROJECT has an unsafe Compose project name: %s\n' "$LOCAL_PROJECT" >&2
    exit 2
  }
  case "$LOCAL_PROJECT" in
    vpnkit|vpnkit-local)
      printf 'refusing protected Compose project for local test runner: %s\n' "$LOCAL_PROJECT" >&2
      exit 2
      ;;
  esac
}

validate_isolated_artifact_tree() {
  local label=$1 path=$2 canonical
  canonical=$(canonical_path "$path") || exit 2
  reject_protected_path "$label" "$canonical"
  case "$canonical" in
    "$REPO_ROOT/secrets/vpnkit-labs/"*|/tmp/*|/var/tmp/*) ;;
    *)
      printf '%s must stay under the isolated lab root or a temporary directory\n' "$label" >&2
      exit 2
      ;;
  esac
  [[ "$canonical" != /tmp && "$canonical" != /var/tmp && "$canonical" != "$REPO_ROOT/secrets/vpnkit-labs" ]] || {
    printf 'refusing broad isolated artifact directory for %s\n' "$label" >&2
    exit 2
  }
  assert_user_owned_path "$label" "$canonical" || exit 2
}

validate_isolated_profile_path() {
  local label=$1 path=$2 root=$3 canonical
  canonical=$(canonical_path "$path") || exit 2
  reject_protected_path "$label" "$canonical" 1
  case "$canonical" in
    "$root/"*|"$REPO_ROOT/generated/openvpn-profiles/"*|/tmp/*|/var/tmp/*) ;;
    *)
      printf '%s must stay in the isolated lab, fixture, or temporary tree\n' "$label" >&2
      exit 2
      ;;
  esac
}

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
if [[ -n "$SCENARIO" && "$SCENARIO" != "steamdeck-host" && "$SCENARIO" != "local-docker" ]]; then
  echo "unknown scenario: $SCENARIO (supported: steamdeck-host, local-docker)" >&2; exit 2
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
# compose.local defaults to the ordinary lifecycle owner.  This runner opts in
# to a separate immutable marker so it cannot adopt or remove lifecycle-owned
# resources, even when a different Compose project is present.
LOCAL_TEST_OWNER_LABEL=containers-test

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

if [[ "$SCENARIO" == "local-docker" ]]; then
  LOCAL_PROJECT=${VPNKIT_LOCAL_TEST_PROJECT:-vpnkit-local-lab}
  validate_local_project
  LOCAL_SCENARIO_DIR=${VPNKIT_TEST_LAB_SECRETS_DIR:-secrets/vpnkit-labs/local-docker}
  case "$LOCAL_SCENARIO_DIR" in /*) ;; *) LOCAL_SCENARIO_DIR="$REPO_ROOT/$LOCAL_SCENARIO_DIR" ;; esac
  LOCAL_SCENARIO_DIR=$(canonical_path "$LOCAL_SCENARIO_DIR")
  validate_isolated_artifact_tree VPNKIT_TEST_LAB_SECRETS_DIR "$LOCAL_SCENARIO_DIR"
  # Keep the disposable lab able to run beside the real local instance.
  LOCAL_PORT=${VPNKIT_LOCAL_TEST_OPENVPN_PORT:-21195}
  if ! [[ "$LOCAL_PORT" =~ ^[0-9]+$ ]] || (( 10#$LOCAL_PORT < 1 || 10#$LOCAL_PORT > 65535 )); then
    printf 'VPNKIT_LOCAL_TEST_OPENVPN_PORT must be a UDP port in the range 1-65535\n' >&2
    exit 2
  fi
  LOCAL_SERVER_SUBNET=${VPNKIT_LOCAL_TEST_SERVER_SUBNET:-172.30.91.0/24}
  LOCAL_SERVER_ADDRESS=${VPNKIT_LOCAL_TEST_SERVER_ADDRESS:-172.30.91.2}
  LOCAL_LOG_ROOT=${VPNKIT_LOCAL_TEST_LOG_ROOT:-/tmp/vpnkit-containers-test/$LOCAL_PROJECT}
  LOCAL_LOG_ROOT=$(canonical_path "$LOCAL_LOG_ROOT")
  reject_protected_path VPNKIT_LOCAL_TEST_LOG_ROOT "$LOCAL_LOG_ROOT" 1
  case "$LOCAL_LOG_ROOT" in
    /tmp/*|/var/tmp/*) ;;
    *)
      printf 'local test logs must stay under a temporary per-project root\n' >&2
      exit 2
      ;;
  esac
  assert_user_owned_path VPNKIT_LOCAL_TEST_LOG_ROOT "$LOCAL_LOG_ROOT" || exit 2
  # The override intentionally defaults to local-lifecycle for the KDE
  # lifecycle adapter.  Only this test runner exports the test-only owner.
  export VPNKIT_LOCAL_RESOURCE_OWNER="$LOCAL_TEST_OWNER_LABEL"
  LOCAL_COMPOSE=(docker compose -p "$LOCAL_PROJECT" -f "$REPO_ROOT/docker-compose.yml" -f "$REPO_ROOT/compose.local.yaml")
  TEST_ROUTING_MODE=tun
  TEST_PROFILE=${VPNKIT_TEST_PROFILE:-$LOCAL_SCENARIO_DIR/openvpn/client/test-client.ovpn}
  SERVER_CONTAINER=""
  REMOTE_RUNTIME=docker
  TEST_ENDPOINT=vpnkit
  selected_ssh_source=not-used-local-docker
  selected_endpoint_source=compose-service
  export VPNKIT_TEST_PROFILE=$TEST_PROFILE VPNKIT_TEST_ROUTING_MODE=tun
  export VPNKIT_LOCAL_SECRETS_DIR="$LOCAL_SCENARIO_DIR"
  export VPNKIT_OPENVPN_BIND_ADDRESS=127.0.0.1 VPNKIT_OPENVPN_PORT=$LOCAL_PORT VPNKIT_LOCAL_OPENVPN_PORT=$LOCAL_PORT
  export VPNKIT_LOCAL_DOCKER_SUBNET=$LOCAL_SERVER_SUBNET VPNKIT_LOCAL_CONTAINER_ADDRESS=$LOCAL_SERVER_ADDRESS
  export VPNKIT_ROUTING_MODE=tun VPNKIT_RULESET_SOURCE_MODE=local-fixture VPNKIT_SELECTED_OUTBOUND_MODE=direct-fixture
  export VPNKIT_BOOTSTRAP_PICK_ON_START=false
  for protected_var in VPNKIT_RENDERED_ROOT VPNKIT_LOG_ROOT VPNKIT_CLIENT_PROFILE_ROOT; do
    protected_value=${!protected_var:-}
    [[ -n "$protected_value" ]] && reject_protected_path "$protected_var" "$protected_value" 1
  done
fi

if [[ "$SCENARIO" == "steamdeck-host" ]]; then
  export VPNKIT_RULESET_SOURCE_MODE=${VPNKIT_RULESET_SOURCE_MODE:-local-fixture}
  LAB_SCENARIO_DIR=${VPNKIT_TEST_LAB_SECRETS_DIR:-secrets/vpnkit-labs/steamdeck-host}
  case "$LAB_SCENARIO_DIR" in /*) ;; *) LAB_SCENARIO_DIR="$REPO_ROOT/$LAB_SCENARIO_DIR" ;; esac
  LAB_SCENARIO_DIR=$(canonical_path "$LAB_SCENARIO_DIR")
  validate_isolated_artifact_tree VPNKIT_TEST_LAB_SECRETS_DIR "$LAB_SCENARIO_DIR"
  LAB_CONTAINER=${VPNKIT_TEST_SERVER_CONTAINER:-vpnkit-test-steamdeck-host}
  [[ "$LAB_CONTAINER" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || {
    printf 'refusing unsafe Steam Deck lab container name\n' >&2
    exit 2
  }
  case "$LAB_CONTAINER" in
    vpnkit|vpnkit-local)
      printf 'refusing protected Steam Deck lab container name: %s\n' "$LAB_CONTAINER" >&2
      exit 2
      ;;
  esac
  LAB_IMAGE=${VPNKIT_STEAMDECK_IMAGE:-localhost/vpnkit:test-steamdeck-host}
  [[ "$LAB_IMAGE" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.:/-]*$ ]] || {
    printf 'refusing unsafe Steam Deck lab image reference\n' >&2
    exit 2
  }
  LAB_PORT=${VPNKIT_OPENVPN_PORT:-21194}
  if ! [[ "$LAB_PORT" =~ ^[0-9]+$ ]] || (( 10#$LAB_PORT < 1 || 10#$LAB_PORT > 65535 )); then
    printf 'VPNKIT_OPENVPN_PORT must be a UDP port in the range 1-65535\n' >&2
    exit 2
  fi
  LAB_REMOTE_DIR=${VPNKIT_STEAMDECK_REMOTE_DIR:-'~/.local/state/vpnkit-labs/steamdeck-host'}
  case "$LAB_REMOTE_DIR" in
    '~/.local/state/vpnkit-labs/steamdeck-host') ;;
    *)
      printf 'refusing unsafe remote lab state path; use the isolated ~/.local/state/vpnkit-labs/steamdeck-host path\n' >&2
      exit 2
      ;;
  esac
  LAB_ROUTING_MODE=${VPNKIT_TEST_ROUTING_MODE:-${VPNKIT_ROUTING_MODE:-tun}}
  SERVER_CONTAINER=$LAB_CONTAINER
  TEST_PROFILE=${VPNKIT_TEST_PROFILE:-$LAB_SCENARIO_DIR/openvpn/client/test-client.ovpn}
  LAB_NESTED_PROFILE=${VPNKIT_STEAMDECK_NESTED_CLIENT_PROFILE:-$LAB_SCENARIO_DIR/nested/openvpn/client/test-client.ovpn}
  validate_isolated_profile_path VPNKIT_TEST_PROFILE "$TEST_PROFILE" "$LAB_SCENARIO_DIR"
  validate_isolated_profile_path VPNKIT_STEAMDECK_NESTED_CLIENT_PROFILE "$LAB_NESTED_PROFILE" "$LAB_SCENARIO_DIR"
  TEST_ROUTING_MODE=$LAB_ROUTING_MODE
  export VPNKIT_TEST_SERVER_CONTAINER=$LAB_CONTAINER VPNKIT_TEST_PROFILE=$TEST_PROFILE VPNKIT_TEST_ROUTING_MODE=$TEST_ROUTING_MODE
  export VPNKIT_STEAMDECK_NESTED_CLIENT_PROFILE=$LAB_NESTED_PROFILE
  export VPNKIT_STEAMDECK_CONTAINER=$LAB_CONTAINER VPNKIT_STEAMDECK_IMAGE=$LAB_IMAGE VPNKIT_OPENVPN_PORT=$LAB_PORT VPNKIT_STEAMDECK_REMOTE_DIR=$LAB_REMOTE_DIR VPNKIT_ROUTING_MODE=$LAB_ROUTING_MODE
  export VPNKIT_STEAMDECK_SSH_TARGET=$SSH_TARGET
  export VPNKIT_STEAMDECK_CONFIG_SOURCE="$LAB_SCENARIO_DIR/rendered"
  TEST_ENDPOINT=${VPNKIT_TEST_ENDPOINT:-${VPNKIT_STEAMDECK_LAN_ENDPOINT:-}}
fi

if [[ "$SCENARIO" == "local-docker" ]]; then
  validate_isolated_profile_path VPNKIT_TEST_PROFILE "$TEST_PROFILE" "$LOCAL_SCENARIO_DIR"
  reject_protected_path VPNKIT_CONTAINERS_TEST_LOG "${VPNKIT_CONTAINERS_TEST_LOG:-$LOCAL_LOG_ROOT/vpnkit-containers-test-$(date -u +%Y%m%dT%H%M%SZ).log}" 1
elif [[ -n "${VPNKIT_CONTAINERS_TEST_LOG:-}" ]]; then
  reject_protected_path VPNKIT_CONTAINERS_TEST_LOG "$VPNKIT_CONTAINERS_TEST_LOG"
fi
if [[ -n "$TEST_MANIFEST" || -n "$TEST_MANIFEST_SERVER" || -n "$TEST_MANIFEST_CLIENT" || -n "${VPNKIT_TEST_MANIFEST_OUT_DIR:-}" ]]; then
  manifest_out_canonical=$(canonical_path "$TEST_MANIFEST_OUT_DIR")
  reject_protected_path VPNKIT_TEST_MANIFEST_OUT_DIR "$manifest_out_canonical" 1
  case "$manifest_out_canonical" in
    "$REPO_ROOT/generated/openvpn-profiles"|"$REPO_ROOT/generated/openvpn-profiles/"*|/tmp/*|/var/tmp/*) ;;
    *)
      printf 'manifest profile output must stay in the fixture or temporary tree\n' >&2
      exit 2
      ;;
  esac
fi

TS=$(date -u +%Y%m%dT%H%M%SZ)
if [[ "$SCENARIO" == "local-docker" ]]; then
  LOG_FILE=${VPNKIT_CONTAINERS_TEST_LOG:-"$LOCAL_LOG_ROOT/vpnkit-containers-test-$TS.log"}
  LOG_FALLBACK="/tmp/vpnkit-containers-test/$LOCAL_PROJECT/vpnkit-containers-test-$TS.log"
else
  LOG_FILE=${VPNKIT_CONTAINERS_TEST_LOG:-"logs/vpnkit-containers-test-$TS.log"}
  LOG_FALLBACK="/tmp/vpnkit-containers-test-$TS.log"
fi
LOG_NOTE=""
log_dir=$(dirname -- "$LOG_FILE")
if [[ -e "$log_dir" && ! -O "$log_dir" ]]; then
  if [[ -n "${VPNKIT_CONTAINERS_TEST_LOG:-}" ]]; then
    printf 'refusing non-user-owned VPNKIT_CONTAINERS_TEST_LOG directory: %s\n' "$log_dir" >&2
    exit 2
  fi
  LOG_NOTE="default log directory was not user-owned; using $LOG_FALLBACK"
  LOG_FILE=$LOG_FALLBACK
  log_dir=$(dirname -- "$LOG_FILE")
fi
if ! mkdir -p -- "$log_dir" 2>/dev/null || ! [[ -O "$log_dir" ]] || ! : >"$LOG_FILE" 2>/dev/null; then
  if [[ -n "${VPNKIT_CONTAINERS_TEST_LOG:-}" ]]; then
    printf 'cannot write VPNKIT_CONTAINERS_TEST_LOG: %s\n' "$LOG_FILE" >&2
    exit 2
  fi
  LOG_FILE=$LOG_FALLBACK
  log_dir=$(dirname -- "$LOG_FILE")
  mkdir -p -- "$log_dir" 2>/dev/null && [[ -O "$log_dir" ]] && : >"$LOG_FILE" 2>/dev/null || {
    printf 'cannot create a user-owned test log path: %s\n' "$LOG_FILE" >&2
    exit 2
  }
  [[ -n "$LOG_NOTE" ]] || LOG_NOTE="default log path was not writable; using $LOG_FILE"
fi

exec > >(redact_stream | tee "$LOG_FILE") 2>&1

PASS=0; FAIL=0; SKIP=0
RESULTS=()

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
record() {
  local status=$1 name=$2 reason=${3:-}
  case "$status" in PASS) PASS=$((PASS+1));; FAIL) FAIL=$((FAIL+1));; SKIP) SKIP=$((SKIP+1));; *) status=FAIL; FAIL=$((FAIL+1)); reason="internal bad status: $1 $reason";; esac
  RESULTS+=("$status|$name|$reason")
  log "$status $name${reason:+ - $reason}"
}

local_safety_error=""
resource_label() {
  local kind=$1 id=$2 label=$3
  case "$kind" in
    container) docker inspect --format "{{ index .Config.Labels \"$label\" }}" "$id" 2>/dev/null ;;
    network|volume) docker inspect --format "{{ index .Labels \"$label\" }}" "$id" 2>/dev/null ;;
    *) return 2 ;;
  esac
}

resource_name() {
  local kind=$1 id=$2
  case "$kind" in
    network|volume) docker inspect --format '{{.Name}}' "$id" 2>/dev/null ;;
    *) return 2 ;;
  esac
}

# Compose puts working_dir on container Config.Labels only. Networks and
# volumes instead have their type-specific Compose resource label and the
# project-prefixed resource name; requiring a container label on those kinds
# makes a normal post-up `down` look foreign.
local_resource_owned() {
  local kind=$1 id=$2 project owner workdir compose_resource actual_name expected_name
  [[ -n "$id" ]] || { local_safety_error="$kind id is empty"; return 1; }
  project=$(resource_label "$kind" "$id" com.docker.compose.project || true)
  owner=$(resource_label "$kind" "$id" com.vpnkit.local.owner || true)
  case "$kind" in
    container)
      workdir=$(resource_label container "$id" com.docker.compose.project.working_dir || true)
      if [[ "$project" != "$LOCAL_PROJECT" || "$owner" != "$LOCAL_TEST_OWNER_LABEL" || "$workdir" != "$REPO_ROOT" ]]; then
        local_safety_error="container $id is not owned by project=$LOCAL_PROJECT owner=$LOCAL_TEST_OWNER_LABEL working_dir=$REPO_ROOT"
        return 1
      fi
      ;;
    network)
      compose_resource=$(resource_label network "$id" com.docker.compose.network || true)
      actual_name=$(resource_name network "$id" || true)
      case "$compose_resource" in
        vpnkit-local) expected_name="${LOCAL_PROJECT}_vpnkit-local" ;;
        *)
          local_safety_error="network $id has unexpected Compose network label: ${compose_resource:-missing}"
          return 1
          ;;
      esac
      if [[ "$project" != "$LOCAL_PROJECT" || "$owner" != "$LOCAL_TEST_OWNER_LABEL" || "$actual_name" != "$expected_name" ]]; then
        local_safety_error="network $id is not the owned Compose resource ${expected_name:-unknown} (project=$LOCAL_PROJECT owner=$LOCAL_TEST_OWNER_LABEL)"
        return 1
      fi
      ;;
    volume)
      compose_resource=$(resource_label volume "$id" com.docker.compose.volume || true)
      actual_name=$(resource_name volume "$id" || true)
      case "$compose_resource" in
        vpnkit-local-vibe-vpn-state|vpnkit-local-sing-box-state|vpnkit-local-vpnkit-logs|vpnkit-local-vibe-vpn-logs)
          expected_name="${LOCAL_PROJECT}_${compose_resource}"
          ;;
        *)
          local_safety_error="volume $id has unexpected Compose volume label: ${compose_resource:-missing}"
          return 1
          ;;
      esac
      if [[ "$project" != "$LOCAL_PROJECT" || "$owner" != "$LOCAL_TEST_OWNER_LABEL" || "$actual_name" != "$expected_name" ]]; then
        local_safety_error="volume $id is not the owned Compose resource ${expected_name:-unknown} (project=$LOCAL_PROJECT owner=$LOCAL_TEST_OWNER_LABEL)"
        return 1
      fi
      ;;
    *)
      local_safety_error="unsupported resource kind: $kind"
      return 1
      ;;
  esac
}

local_client_network_owned() {
  local id=$1 expected_name=$2 project owner marker actual_name
  project=$(resource_label network "$id" com.docker.compose.project || true)
  owner=$(resource_label network "$id" com.vpnkit.local.owner || true)
  marker=$(resource_label network "$id" com.vpnkit.local.resource || true)
  actual_name=$(resource_name network "$id" || true)
  if [[ "$project" != "$LOCAL_PROJECT" || "$owner" != "$LOCAL_TEST_OWNER_LABEL" || "$marker" != client-smoke || "$actual_name" != "$expected_name" ]]; then
    local_safety_error="client network $id is not the owned client-smoke resource $expected_name"
    return 1
  fi
}

local_compose_resource_ids() {
  local kind=$1 project_ids owner_ids
  case "$kind" in
    container)
      project_ids=$(docker container ls -aq --filter "label=com.docker.compose.project=$LOCAL_PROJECT" 2>/dev/null) || { local_safety_error="cannot list Compose containers"; return 1; }
      owner_ids=$(docker container ls -aq --filter label=com.vpnkit.local.owner 2>/dev/null) || { local_safety_error="cannot list owner-labeled containers"; return 1; }
      ;;
    network)
      project_ids=$(docker network ls -q --filter "label=com.docker.compose.project=$LOCAL_PROJECT" 2>/dev/null) || { local_safety_error="cannot list Compose networks"; return 1; }
      owner_ids=$(docker network ls -q --filter label=com.vpnkit.local.owner 2>/dev/null) || { local_safety_error="cannot list owner-labeled networks"; return 1; }
      ;;
    volume)
      project_ids=$(docker volume ls -q --filter "label=com.docker.compose.project=$LOCAL_PROJECT" 2>/dev/null) || { local_safety_error="cannot list Compose volumes"; return 1; }
      owner_ids=$(docker volume ls -q --filter label=com.vpnkit.local.owner 2>/dev/null) || { local_safety_error="cannot list owner-labeled volumes"; return 1; }
      ;;
    *) local_safety_error="unsupported Compose resource kind: $kind"; return 1 ;;
  esac
  printf '%s\n%s\n' "$project_ids" "$owner_ids" | awk 'NF && !seen[$0]++'
}

local_compose_project_collisions() {
  local kind ids id project
  for kind in container network volume; do
    ids=$(local_compose_resource_ids "$kind") || return 1
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      project=$(resource_label "$kind" "$id" com.docker.compose.project || true)
      if [[ -n "$project" && "$project" != "$LOCAL_PROJECT" ]]; then
        local_safety_error="$kind $id belongs to alternate Compose project $project; refusing cleanup before down -v --remove-orphans"
        return 1
      fi
    done <<<"$ids"
  done
}

local_compose_resources_owned() {
  local kind ids id
  command -v docker >/dev/null 2>&1 || { local_safety_error="docker is unavailable"; return 1; }
  # Check every local marker first, not only the requested project.  A
  # lifecycle stack under another project must block this destructive Compose
  # call rather than being silently treated as out of scope.
  local_compose_project_collisions || return 1
  for kind in container network volume; do
    ids=$(local_compose_resource_ids "$kind") || return 1
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      local_resource_owned "$kind" "$id" || return 1
    done <<<"$ids"
  done
}

local_client_cleanup_scope_owned() {
  local client_name=$1 client_network=$2 server_id=$3 smoke_dir=$4 id
  [[ "$client_name" == "$LOCAL_PROJECT-"* ]] || { local_safety_error="client container name is outside the local project namespace"; return 1; }
  [[ "$client_network" == "$LOCAL_PROJECT-"* ]] || { local_safety_error="client network name is outside the local project namespace"; return 1; }
  assert_user_owned_path local-client-smoke-dir "$smoke_dir" || { local_safety_error="local client smoke directory is not user-owned"; return 1; }
  if id=$(docker container inspect -f '{{.Id}}' "$client_name" 2>/dev/null); then
    local_resource_owned container "$id" || return 1
  fi
  if id=$(docker network inspect -f '{{.Id}}' "$client_network" 2>/dev/null); then
    local_client_network_owned "$id" "$client_network" || return 1
  fi
  if [[ -n "$server_id" ]]; then
    local_resource_owned container "$server_id" || return 1
  fi
}

run_capture() { local out rc; out=$("$@" 2>&1); rc=$?; printf '%s' "$out"; return "$rc"; }
run_capture_timeout() { local seconds=$1; shift; local out rc; out=$(timeout -k 5s "$seconds" "$@" 2>&1); rc=$?; printf '%s' "$out"; return "$rc"; }
ssh_run() { timeout --preserve-status "$REMOTE_CMD_TIMEOUT" ssh -o BatchMode=yes -o ConnectTimeout="$SSH_TIMEOUT" "$SSH_TARGET" "$@"; }
container_exec() {
  if [[ "$SCENARIO" == "local-docker" ]]; then
    docker exec "$SERVER_CONTAINER" sh -lc "$1"
  else
    ssh_run "$REMOTE_RUNTIME exec $SERVER_CONTAINER sh -lc $(printf '%q' "$1")"
  fi
}

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

set_local_container() {
  [[ "$SCENARIO" == "local-docker" ]] || return 0
  SERVER_CONTAINER=$(${LOCAL_COMPOSE[@]} ps -q vpnkit 2>/dev/null || true)
}

run_lifecycle_down() {
  if [[ "$SCENARIO" == "local-docker" ]]; then
    if ! local_compose_resources_owned; then
      record FAIL "lifecycle:down-safety" "refusing local Docker cleanup: $local_safety_error"
      return 1
    fi
    if out=$(run_capture_timeout "$REMOTE_CMD_TIMEOUT" "${LOCAL_COMPOSE[@]}" down -v --remove-orphans); then
      record PASS "lifecycle:down" "isolated local Docker project removed"
      return 0
    fi
    record FAIL "lifecycle:down" "isolated local Docker cleanup failed: $out"
    return 1
  fi
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
    if out=$(run_capture ssh -o BatchMode=yes -o ConnectTimeout=8 "$SSH_TARGET" 'rm -rf -- "$HOME/.local/state/vpnkit-labs/steamdeck-host"'); then
      record PASS "lifecycle:remote-state-down" "optional isolated remote state removed"
    else
      record FAIL "lifecycle:remote-state-down" "optional remote state cleanup failed: $out"
    fi
  fi
}

run_lifecycle_up() {
  if [[ "$SCENARIO" == "local-docker" ]]; then
    if ! local_compose_resources_owned; then
      record FAIL "lifecycle:up-safety" "refusing local Docker start: $local_safety_error"
      return 1
    fi
    if out=$(run_capture env VPNKIT_TEST_LAB_SECRETS_DIR="$LOCAL_SCENARIO_DIR" VPNKIT_TEST_LAB_ENDPOINT=vpnkit VPNKIT_TEST_LAB_PORT=1194 VPNKIT_ROUTING_MODE=tun VPNKIT_RULESET_SOURCE_MODE=local-fixture VPNKIT_SELECTED_OUTBOUND_MODE=direct-fixture VPNKIT_OPENVPN_PUSH_DNS=8.8.8.8 "$REPO_ROOT/scripts/vpnkit/vpnkit-test-lab-setup.sh") \
      && render_out=$(run_capture env VPNKIT_LOCAL_SECRETS_DIR="$LOCAL_SCENARIO_DIR" VPNKIT_LOCAL_TEST_FIXTURE=1 VPNKIT_LOCAL_ALLOW_MISSING_SUBSCRIPTION=true VPNKIT_LOCAL_POLICY=strict VPNKIT_RULESET_SOURCE_MODE=local-fixture VPNKIT_SELECTED_OUTBOUND_MODE=direct-fixture "$REPO_ROOT/scripts/vpnkit/vpnkit-render-local-kde-configs.sh"); then
      printf '%s\n' "$out"
      printf '%s\n' "$render_out"
      record PASS "lifecycle:prepare" "generated isolated local Docker fixture artifacts with local DNS policy"
    else
      printf '%s\n' "${out:-}"
      printf '%s\n' "${render_out:-}"
      record FAIL "lifecycle:prepare" "local Docker fixture setup or local policy render failed"
      return 1
    fi
    if out=$(run_capture_timeout "$DEPLOY_TIMEOUT" "${LOCAL_COMPOSE[@]}" up -d --build vpnkit); then
      printf '%s\n' "$out"
      set_local_container
      if [[ -n "$SERVER_CONTAINER" ]]; then
        health_deadline=$((SECONDS + 90))
        while (( SECONDS < health_deadline )); do
          health_state=$(docker inspect "$SERVER_CONTAINER" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' 2>/dev/null || true)
          [[ "$health_state" == healthy ]] && break
          [[ "$health_state" == unhealthy ]] && break
          sleep 1
        done
        if [[ "${health_state:-missing}" != healthy ]]; then
          record FAIL "lifecycle:readiness" "isolated local vpnkit health=${health_state:-missing}"
          return 1
        fi
        record PASS "lifecycle:deploy" "isolated local Docker vpnkit deployed and healthy"
        return 0
      fi
      record FAIL "lifecycle:deploy" "Compose did not return an isolated vpnkit container id"
      return 1
    fi
    printf '%s\n' "$out"
    record FAIL "lifecycle:deploy" "isolated local Docker deploy failed or timed out"
    return 1
  fi
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

if [[ "$SCENARIO" == "steamdeck-host" || "$SCENARIO" == "local-docker" ]]; then
  case "$ACTION" in
    down) run_lifecycle_down; printf '\nTotals: PASS=%d FAIL=%d SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"; [[ $FAIL -eq 0 ]]; exit $? ;;
    up) run_lifecycle_up; printf '\nTotals: PASS=%d FAIL=%d SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"; [[ $FAIL -eq 0 ]]; exit $? ;;
    cycle)
      if ! run_lifecycle_down; then
        printf '\nTotals: PASS=%d FAIL=%d SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"
        exit 1
      fi
      run_lifecycle_up || true
      if [[ $FAIL -gt 0 ]]; then printf '\nTotals: PASS=%d FAIL=%d SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"; exit 1; fi
      ;;
    test) ;;
  esac
fi

if [[ "$SCENARIO" == "local-docker" ]]; then
  set_local_container
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
if [[ "$SCENARIO" == "local-docker" ]]; then
  if out=$(run_capture_timeout "$SSH_TIMEOUT" docker info); then
    record PASS "server:local-docker-reachable" "local Docker daemon reachable"
    server_ready=1
  else
    record SKIP "server:local-docker-reachable" "local Docker daemon unavailable: $out"
  fi
elif [[ "$SCENARIO" == "steamdeck-host" && ( "$ssh_target_state" == "placeholder" || -z "$SSH_TARGET" ) ]]; then
  record FAIL "server:ssh-reachable" "placeholder/missing SSH target rejected before probe (source=$selected_ssh_source)"
elif out=$(run_capture_timeout "$SSH_TIMEOUT" ssh -o BatchMode=yes -o ConnectTimeout="$SSH_TIMEOUT" "$SSH_TARGET" true); then
  record PASS "server:ssh-reachable" "target reachable"
  server_ready=1
else
  record SKIP "server:ssh-reachable" "cannot reach SSH target '$SSH_TARGET': $out"
fi

container_ready=0
if [[ $server_ready -eq 1 ]]; then
  if [[ "$SCENARIO" == "local-docker" ]]; then
    if [[ -z "$SERVER_CONTAINER" ]]; then
      record FAIL "server:container-running" "isolated local Docker vpnkit container not found"
    elif out=$(run_capture docker inspect -f '{{.State.Running}}' "$SERVER_CONTAINER"); then
      if [[ "$out" == *true* ]]; then record PASS "server:container-running" "isolated local vpnkit running"; container_ready=1
      else record FAIL "server:container-running" "isolated local vpnkit exists but is not running: $out"; fi
    else
      record FAIL "server:container-running" "cannot inspect isolated local vpnkit: $out"
    fi
  elif out=$(run_capture ssh_run "$REMOTE_RUNTIME container inspect $SERVER_CONTAINER >/dev/null && $REMOTE_RUNTIME inspect -f '{{.State.Running}}' $SERVER_CONTAINER"); then
    if [[ "$out" == *true* ]]; then record PASS "server:container-running" "$SERVER_CONTAINER running"; container_ready=1
    else record FAIL "server:container-running" "$SERVER_CONTAINER exists but is not running: $out"; fi
  else
    record SKIP "server:container-running" "cannot inspect container/runtime: $out"
  fi
else
  record SKIP "server:container-running" "server runtime unavailable"
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

check_exec_contains "server:openvpn-process" "pgrep -a openvpn 2>/dev/null || ps auxww 2>/dev/null || ps" "openvpn" FAIL
check_exec_contains "server:sing-box-process" "pgrep -a sing-box 2>/dev/null || ps auxww 2>/dev/null || ps" "sing-box" FAIL
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

  cfg_cmd='for c in /var/lib/vpnkit/sing-box/config.json /etc/sing-box/config.json /run/sing-box/config.json; do [ -r "$c" ] && { grep -E "selected-native-out|direct-out|block-out|tun|socks|remote-dns" "$c" | sort -u; exit 0; }; done; echo no-readable-config; exit 77'
  if out=$(run_capture container_exec "$cfg_cmd"); then
    miss=(); for n in selected-native-out direct-out block-out tun socks remote-dns remote-dns-fallback; do [[ "$out" == *"$n"* ]] || miss+=("$n"); done
    if [[ ${#miss[@]} -eq 0 ]]; then record PASS "server:config-shape" "required tags/inbounds present"; else record FAIL "server:config-shape" "missing: ${miss[*]}"; fi
  else
    rc=$?; [[ $rc -eq 77 ]] && record SKIP "server:config-shape" "$out" || record FAIL "server:config-shape" "$out"
  fi
  if [[ "$SCENARIO" == "local-docker" ]]; then
    # The watchdog may legitimately switch the mutable runtime to Google.
    # Validate the immutable source policy separately from the active runtime
    # so a real fallback is not misreported as a missing Cloudflare primary.
    dns_source_shape_cmd='c=/etc/sing-box/config.json; [ -r "$c" ] || exit 77; grep -E "server|tag|final" "$c"'
    dns_runtime_shape_cmd='c=/var/lib/vpnkit/sing-box/config.json; [ -r "$c" ] || exit 77; grep -E "server|tag|final" "$c"'
    source_out= runtime_out=
    if source_out=$(run_capture container_exec "$dns_source_shape_cmd") \
      && runtime_out=$(run_capture container_exec "$dns_runtime_shape_cmd"); then
      if [[ "$source_out" == *'1.1.1.1'* && "$source_out" == *'8.8.8.8'* \
        && "$source_out" == *'remote-dns'* && "$source_out" == *'remote-dns-fallback'* \
        && "$runtime_out" == *'remote-dns'* && "$runtime_out" == *'remote-dns-fallback'* \
        && ( "$runtime_out" == *'1.1.1.1'* || "$runtime_out" == *'8.8.8.8'* ) ]]; then
        record PASS "server:dns-failover-shape" "Cloudflare/Google source policy and valid active runtime are rendered"
      else
        record FAIL "server:dns-failover-shape" "source policy or active DNS runtime shape is invalid"
      fi
    else
      rc=$?; [[ $rc -eq 77 ]] && record SKIP "server:dns-failover-shape" "source or runtime config is unavailable" || record FAIL "server:dns-failover-shape" "source/runtime shape query failed"
    fi
  fi
else
  record SKIP "server:sing-box-check" "server container unavailable"
  record SKIP "server:socks-inbound" "server container unavailable"
  record SKIP "server:config-shape" "server container unavailable"
  [[ "$SCENARIO" == "local-docker" ]] && record SKIP "server:dns-failover-shape" "server container unavailable"
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
if [[ "$SCENARIO" == "local-docker" && $container_ready -ne 1 ]]; then
  record SKIP "client:local-docker-profile-smoke" "isolated local server container unavailable"
elif [[ "$SCENARIO" == "local-docker" && -r "$TEST_PROFILE" ]]; then
  reject_protected_path VPNKIT_TEST_PROFILE "$TEST_PROFILE" 1
  client_network=${VPNKIT_LOCAL_TEST_CLIENT_NETWORK:-${LOCAL_PROJECT}-client-smoke}
  client_subnet=${VPNKIT_LOCAL_TEST_CLIENT_SUBNET:-172.30.90.0/24}
  client_name=${VPNKIT_LOCAL_TEST_CLIENT_CONTAINER:-${LOCAL_PROJECT}-client-smoke}
  client_alias=vpnkit-test-server
  smoke_dir="$LOCAL_SCENARIO_DIR/client-smoke"
  smoke_profile="$smoke_dir/test-client.ovpn"
  local_client_cleanup() {
    local id
    local_client_cleanup_scope_owned "$client_name" "$client_network" "$SERVER_CONTAINER" "$smoke_dir" || return 1
    if id=$(docker container inspect -f '{{.Id}}' "$client_name" 2>/dev/null); then
      docker rm -f "$id" >/dev/null 2>&1 || return 1
    fi
    if id=$(docker network inspect -f '{{.Id}}' "$client_network" 2>/dev/null); then
      docker network disconnect -f "$id" "$SERVER_CONTAINER" >/dev/null 2>&1 || true
      docker network rm "$id" >/dev/null 2>&1 || return 1
    fi
    rm -rf -- "$smoke_dir"
  }
  if [[ "$client_name" != "$LOCAL_PROJECT-"* || "$client_network" != "$LOCAL_PROJECT-"* || ! "$client_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ || ! "$client_network" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
    record FAIL "client:local-docker-cleanup-safety" "client container/network names must stay within project namespace"
  elif ! local_client_cleanup; then
    record FAIL "client:local-docker-cleanup-safety" "refusing unowned local client cleanup: $local_safety_error"
  elif ! mkdir -p -- "$smoke_dir" || ! assert_user_owned_path local-client-smoke-dir "$smoke_dir"; then
    record FAIL "client:local-docker-cleanup-safety" "local client smoke directory is not user-owned"
  else
    chmod 700 "$smoke_dir"
    awk -v target="$client_alias" 'BEGIN{done=0} /^remote[[:space:]]+/ && !done {print "remote " target " 1194"; done=1; next} {print}' "$TEST_PROFILE" >"$smoke_profile"
    chmod 600 "$smoke_profile"
    if ! out=$(run_capture docker network create --label "com.docker.compose.project=$LOCAL_PROJECT" --label "com.vpnkit.local.owner=$LOCAL_TEST_OWNER_LABEL" --label com.vpnkit.local.resource=client-smoke --subnet "$client_subnet" "$client_network"); then
      record FAIL "client:local-docker-profile-smoke" "isolated client network creation failed: $out"
    elif ! out=$(run_capture docker network connect --alias "$client_alias" "$client_network" "$SERVER_CONTAINER"); then
      record FAIL "client:local-docker-profile-smoke" "isolated server/client network attachment failed: $out"
    else
      client_image=$("${LOCAL_COMPOSE[@]}" --profile test config --images | grep -- '-ovpn-client-test$' | head -1 || true)
      if [[ -z "$client_image" ]]; then
        record FAIL "client:local-docker-profile-smoke" "OpenVPN client test image name was not resolved"
      # Always ask Compose to build: layer caching keeps this cheap while
      # guaranteeing that required evidence rows come from the current source,
      # not a stale same-tag client image left by an earlier acceptance run.
      elif ! out=$(run_capture_timeout "$DEPLOY_TIMEOUT" "${LOCAL_COMPOSE[@]}" --profile test build ovpn-client-test); then
        record FAIL "client:local-docker-profile-smoke" "OpenVPN client test image build failed: $out"
      elif ! docker image inspect "$client_image" >/dev/null 2>&1; then
        record FAIL "client:local-docker-profile-smoke" "OpenVPN client test image was not resolved after build"
      elif out=$(run_capture_timeout "$CLIENT_TIMEOUT" docker run --rm --name "$client_name" --label "com.docker.compose.project=$LOCAL_PROJECT" --label "com.vpnkit.local.owner=$LOCAL_TEST_OWNER_LABEL" --label "com.docker.compose.project.working_dir=$REPO_ROOT" --network "$client_network" --cap-add NET_ADMIN --cap-add NET_RAW --device /dev/net/tun -e VPNKIT_NESTED_VPN_ENABLED=0 -v "$smoke_dir:/etc/openvpn/client:ro" "$client_image" /etc/openvpn/client/test-client.ovpn); then
        printf '%s\n' "$out"
        required_rows=(
          'PASS openvpn:tun0'
          'PASS route:via-tun0'
          'PASS udp:google-dns'
          'PASS https:hostname'
          'PASS https:literal-ip'
          'PASS icmp:1.1.1.1'
          'PASS icmp:8.8.8.8'
          'PASS ipv6:no-default-route'
          'PASS ipv6:connectivity-fail-closed'
          'PASS ipv6:icmp-fail-closed'
        )
        missing_rows=()
        for marker in "${required_rows[@]}"; do
          [[ "$out" == *"$marker"* ]] || missing_rows+=("$marker")
        done
        if [[ ${#missing_rows[@]} -eq 0 ]]; then
          record PASS "client:local-docker-profile-smoke" "isolated separate-subnet OpenVPN full-tunnel smoke passed with ICMP, UDP DNS, and IPv6 fail-closed evidence"
        else
          record FAIL "client:local-docker-profile-smoke" "client smoke exited successfully but omitted required evidence: ${missing_rows[*]}"
        fi
      else
        printf '%s\n' "$out"
        record FAIL "client:local-docker-profile-smoke" "isolated separate-subnet OpenVPN client smoke failed or timed out"
      fi
    fi
    if ! local_client_cleanup; then
      record FAIL "client:local-docker-cleanup" "refusing unowned local client cleanup: $local_safety_error"
    fi
  fi
elif [[ "$SCENARIO" == "local-docker" ]]; then
  record FAIL "client:local-docker-profile-smoke" "isolated local client profile missing/unreadable"
elif [[ "$SCENARIO" == "steamdeck-host" && $container_ready -ne 1 ]]; then
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
