#!/usr/bin/env bash
# Unified public-safe vpnkit container test harness.
#
# Usage:
#   test/containers-test.sh [-h|--help] [--scenario steamdeck-host|local-docker|local-kde-host] [--action up|test|down|cycle|accept] [--approve-local-kde-host|--yes]
#
# Actions for lifecycle scenarios:
#   up     prepare isolated lab config and deploy the isolated server container
#   test   run server/container/client/policy smoke checks against the isolated lab
#   down   remove only isolated scenario resources
#   cycle  down + up + test
#
# For local-kde-host, `--action test` is a non-live contract path. Without an
# explicit test fixture it refuses before command discovery; with a fixture it
# may exercise only temporary mock lifecycle/Docker/NM seams and emits the
# `host:localhost-udp-underlay-nm-contract` result. The opt-in `--action
# accept` path runs the guarded local lifecycle and NetworkManager path on this
# host. It requires VPNKIT_LOCAL_KDE_HOST_APPROVED=1 or --approve-local-kde-host.
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
# URLs, auth values, node values, or raw config dumps. This harness redacts IPs,
# configured SSH/private endpoint hostnames, and sensitive URL/token-shaped
# values from all emitted output.
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

absolute_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$PWD" "$1" ;;
  esac
}

# The local KDE acceptance path is the one deliberately live host path in this
# runner.  It must not inherit a fake PATH, even though the contract path below
# intentionally does.  Resolve commands through the shell's trusted default
# search path, canonicalize them, and then pass only those directories to child
# helpers.  This keeps a mocked PATH from manufacturing live acceptance rows.
HOST_LOCAL_LIVE_ACCEPT=0
HOST_ACCEPTANCE_RESULT_NAME=host:localhost-udp-underlay-nm-contract
HOST_TRUSTED_DEFAULT_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
HOST_TRUSTED_PATH=
declare -A HOST_TRUSTED_COMMAND_PATHS=()

trusted_command_location_allowed() {
  case "$1" in
    /bin/*|/sbin/*|/usr/bin/*|/usr/sbin/*|/usr/local/bin/*|/usr/local/sbin/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

host_acceptance_bind_trusted_commands() {
  local realpath_candidate realpath_path command_name command_path canonical
  local -a required_commands=(
    docker nmcli ip openvpn getent curl ping timeout python3 bash env
    awk grep sed mktemp chmod cp rm mkdir realpath stat date sort flock
    systemctl sleep dirname basename cat mv rmdir find cut tr head tail
    ln sha256sum
  )
  local -a trusted_dirs=()

  HOST_TRUSTED_COMMAND_PATHS=()
  HOST_TRUSTED_PATH=
  realpath_candidate=$(PATH="$HOST_TRUSTED_DEFAULT_PATH" command -p -v realpath 2>/dev/null) || return 1
  [[ "$realpath_candidate" == /* ]] || return 1
  trusted_command_location_allowed "$realpath_candidate" || return 1
  realpath_path=$("$realpath_candidate" -e -- "$realpath_candidate" 2>/dev/null) || return 1
  [[ -x "$realpath_path" && ! -L "$realpath_path" ]] || return 1
  trusted_command_location_allowed "$realpath_path" || return 1
  HOST_TRUSTED_COMMAND_PATHS[realpath]=$realpath_path
  trusted_dirs+=("${realpath_path%/*}")

  for command_name in "${required_commands[@]}"; do
    [[ "$command_name" == realpath ]] && continue
    command_path=$(PATH="$HOST_TRUSTED_DEFAULT_PATH" command -p -v "$command_name" 2>/dev/null) || return 1
    [[ "$command_path" == /* ]] || return 1
    trusted_command_location_allowed "$command_path" || return 1
    canonical=$("$realpath_path" -e -- "$command_path" 2>/dev/null) || return 1
    [[ -x "$canonical" && ! -L "$canonical" ]] || return 1
    trusted_command_location_allowed "$canonical" || return 1
    HOST_TRUSTED_COMMAND_PATHS["$command_name"]=$canonical
    trusted_dirs+=("${canonical%/*}")
  done

  local dir
  for dir in "${trusted_dirs[@]}"; do
    case ":$HOST_TRUSTED_PATH:" in
      *":$dir:"*) ;;
      *) HOST_TRUSTED_PATH=${HOST_TRUSTED_PATH:+$HOST_TRUSTED_PATH:}$dir ;;
    esac
  done
  [[ -n "$HOST_TRUSTED_PATH" ]]
}

host_acceptance_validate_current_path() {
  local name current canonical
  local realpath_path=${HOST_TRUSTED_COMMAND_PATHS[realpath]:-}
  local -a required_commands=(
    docker nmcli ip openvpn getent curl ping timeout python3 bash env
    awk grep sed mktemp chmod cp rm mkdir realpath stat date sort flock
    systemctl sleep dirname basename cat mv rmdir find cut tr head tail
    ln sha256sum
  )
  [[ -n "$realpath_path" ]] || return 1
  for name in "${required_commands[@]}"; do
    current=$(command -v "$name" 2>/dev/null) || return 1
    [[ "$current" == /* ]] || return 1
    canonical=$("$realpath_path" -e -- "$current" 2>/dev/null) || return 1
    [[ "$canonical" == "${HOST_TRUSTED_COMMAND_PATHS[$name]:-}" ]] || return 1
  done
}

host_acceptance_command_path() {
  local command_name=$1
  if (( HOST_LOCAL_LIVE_ACCEPT == 1 )); then
    [[ -n "${HOST_TRUSTED_COMMAND_PATHS[$command_name]:-}" ]] || return 1
    printf '%s\n' "${HOST_TRUSTED_COMMAND_PATHS[$command_name]}"
  else
    command -v "$command_name"
  fi
}

host_acceptance_validate_canonical_sources() {
  local path canonical
  local realpath_path=${HOST_TRUSTED_COMMAND_PATHS[realpath]:-}
  [[ -n "$realpath_path" ]] || return 1
  for path in \
    "$REPO_ROOT/scripts/vpnkit/vpnkit-local.sh" \
    "$REPO_ROOT/scripts/vpnkit/vpnkit-local-networkmanager.sh" \
    "$REPO_ROOT/scripts/vpnkit/vpnkit-local-underlay-routing.sh" \
    "$REPO_ROOT/scripts/vpnkit/vpnkit-local-host-smoke.sh"; do
    [[ -f "$path" && -x "$path" && ! -L "$path" ]] || return 1
    canonical=$("$realpath_path" -e -- "$path" 2>/dev/null) || return 1
    [[ "$canonical" == "$path" ]] || return 1
  done
}

# The live host path accepts the tracked local configuration contract, but it
# never accepts test seams or arbitrary routing/resource overrides.  Keep these
# values in one place so the runner, config example, and acceptance tests share
# the same public-safe identity.
HOST_CANONICAL_SECRETS_DIR="$REPO_ROOT/secrets/vpnkit-local"
HOST_CANONICAL_ENDPOINT=127.0.0.1
HOST_CANONICAL_PROJECT=vpnkit-local
HOST_CANONICAL_DOCKER_SUBNET=172.30.89.0/24
HOST_CANONICAL_CONTAINER_ADDRESS=172.30.89.2
HOST_CANONICAL_OVPN_CIDR=10.89.0.0/24
HOST_CANONICAL_IPV6_POLICY=block
HOST_CANONICAL_ROUTE_TABLE=51840
HOST_CANONICAL_DESTINATION_RULE_PRIORITY=998
HOST_CANONICAL_DESTINATION_FAIL_CLOSED_PRIORITY=999
HOST_CANONICAL_RULE_PRIORITY=1000
HOST_CANONICAL_FAIL_CLOSED_PRIORITY=1001
HOST_CANONICAL_POLICY=strict
HOST_CANONICAL_PUSH_DNS=8.8.8.8
HOST_CANONICAL_OPENVPN_PORT=21194
HOST_CANONICAL_BOOTSTRAP_PICK=true
HOST_CANONICAL_BOOTSTRAP_MAX_NODES=50
HOST_CANONICAL_BOOT_TIMEOUT_SECONDS=1200
HOST_CANONICAL_RETEST_TIMEOUT_SECONDS=180
HOST_CANONICAL_NM_CONNECT_TIMEOUT_SECONDS=30

# Test-only fixture roots, helper identities, projects, and underlay priority
# overrides are useful for the contract path but are never accepted by a live
# host run.  Check variable presence, not just truthiness, so an empty override
# cannot become an accidental bypass.  Safe values from
# config/vpnkit-local.local.env are validated separately below.
host_acceptance_reject_overrides() {
  local name
  local -a forbidden=(
    VPNKIT_LOCAL_TEST_FIXTURE
    VPNKIT_LOCAL_TEST_NM_HELPER
    VPNKIT_LOCAL_TEST_UNDERLAY_HELPER
    VPNKIT_LOCAL_HOST_SMOKE_SCRIPT
    VPNKIT_LOCAL_TEST_PROJECT
    VPNKIT_LOCAL_TEST_CLIENT_CONTAINER
    VPNKIT_LOCAL_TEST_CLIENT_NETWORK
    VPNKIT_LOCAL_TEST_CLIENT_SUBNET
    VPNKIT_LOCAL_TEST_OPENVPN_PORT
    VPNKIT_LOCAL_TEST_SERVER_SUBNET
    VPNKIT_LOCAL_TEST_SERVER_ADDRESS
    VPNKIT_LOCAL_TEST_LOG_ROOT
    VPNKIT_LOCAL_UNDERLAY_ROOT
    VPNKIT_LOCAL_UNDERLAY_LOCK_FILE
    VPNKIT_LOCAL_UNDERLAY_LOCK_WAIT_SECONDS
    VPNKIT_LOCAL_PATH_GUARD_BASE
    VPNKIT_LOCAL_PROFILE
    VPNKIT_LOCAL_NM_CONNECTION
    VPNKIT_LOCAL_HOST
    VPNKIT_LOCAL_PORT
    VPNKIT_LOCAL_CERT_DAYS
    VPNKIT_LOCAL_ALLOW_MISSING_SUBSCRIPTION
    VPNKIT_LOCAL_SMOKE_ROUTE_IP
    VPNKIT_LOCAL_SMOKE_PING_IPS
    VPNKIT_LOCAL_SMOKE_HOSTNAME
    VPNKIT_LOCAL_SMOKE_IPV6_ADDRESS
    VPNKIT_LOCAL_SMOKE_TIMEOUT_SECONDS
    VPNKIT_LOCAL_SINGBOX_RESTART_FILE
    VPNKIT_LOCAL_SINGBOX_GENERATION_FILE
    VPNKIT_LOCAL_RESOURCE_OWNER
    VPNKIT_LOCAL_ENV_FILE
    VPNKIT_OPENVPN_PUSH_DNS
    VPNKIT_OPENVPN_BIND_ADDRESS
    VPNKIT_OPENVPN_PORT
    VPNKIT_ROUTING_MODE
    OVPN_CIDR
    VPNKIT_IPV6_POLICY
    VPNKIT_COMPAT_BYPASS_ENABLED
    VPNKIT_COMPAT_BYPASS_ENDPOINTS
    VPNKIT_COMPAT_BYPASS_ALLOW_ICMP
    VPNKIT_ENABLE_VIBE_VPN_DAEMON
    VPNKIT_RULESET_SOURCE_MODE
    VPNKIT_SELECTED_OUTBOUND_MODE
    VPNKIT_LOCAL_RENDER_RACE_HOOK
    VPNKIT_LOCAL_UPLINK_IFACE
    VPNKIT_LOCAL_UPLINK_TABLE
    VPNKIT_LOCAL_UPLINK_GATEWAY
  )
  for name in "${forbidden[@]}"; do
    if [[ -v "$name" ]]; then
      printf 'live local KDE acceptance rejects fixture/helper/test override environment (%s)\n' "$name" >&2
      return 1
    fi
  done
  while IFS= read -r name; do
    case "$name" in
      VPNKIT_LOCAL_TEST_*|VPNKIT_LOCAL_UNDERLAY_*|VPNKIT_LOCAL_INSTALL_*)
        printf 'live local KDE acceptance rejects fixture/helper/test override environment (%s)\n' "$name" >&2
        return 1
        ;;
    esac
  done < <(compgen -v)
  return 0
}

host_acceptance_require_exact() {
  local name=$1 expected=$2
  if [[ -v "$name" && "${!name}" != "$expected" ]]; then
    printf 'live local KDE acceptance rejects unsafe config value (%s)\n' "$name" >&2
    return 1
  fi
}

host_acceptance_require_integer() {
  local name=$1 minimum=$2 maximum=$3 value
  [[ -v "$name" ]] || return 0
  value=${!name}
  [[ "$value" =~ ^[0-9]+$ ]] && (( 10#$value >= minimum && 10#$value <= maximum )) || {
    printf 'live local KDE acceptance rejects unbounded config value (%s)\n' "$name" >&2
    return 1
  }
}

# Validate the values which may arrive from a sourced
# config/vpnkit-local.local.env before any live command or lifecycle helper is
# selected.  Presence is allowed for the documented template variables when
# their value is the safe canonical value; callers do not have to unset them.
host_acceptance_validate_safe_config() {
  local value
  if [[ -v VPNKIT_LOCAL_SECRETS_DIR ]]; then
    value=${VPNKIT_LOCAL_SECRETS_DIR}
    case "$value" in
      secrets/vpnkit-local|./secrets/vpnkit-local|"$HOST_CANONICAL_SECRETS_DIR") ;;
      *)
        printf 'live local KDE acceptance rejects unsafe config value (VPNKIT_LOCAL_SECRETS_DIR)\n' >&2
        return 1
        ;;
    esac
  fi
  host_acceptance_require_exact VPNKIT_LOCAL_ENDPOINT "$HOST_CANONICAL_ENDPOINT" || return 1
  host_acceptance_require_exact VPNKIT_LOCAL_COMPOSE_PROJECT "$HOST_CANONICAL_PROJECT" || return 1
  host_acceptance_require_exact VPNKIT_LOCAL_DOCKER_SUBNET "$HOST_CANONICAL_DOCKER_SUBNET" || return 1
  host_acceptance_require_exact VPNKIT_LOCAL_CONTAINER_ADDRESS "$HOST_CANONICAL_CONTAINER_ADDRESS" || return 1
  host_acceptance_require_exact VPNKIT_LOCAL_OVPN_CIDR "$HOST_CANONICAL_OVPN_CIDR" || return 1
  host_acceptance_require_exact VPNKIT_LOCAL_IPV6_POLICY "$HOST_CANONICAL_IPV6_POLICY" || return 1
  host_acceptance_require_exact VPNKIT_LOCAL_ROUTE_TABLE "$HOST_CANONICAL_ROUTE_TABLE" || return 1
  host_acceptance_require_exact VPNKIT_LOCAL_DESTINATION_RULE_PRIORITY "$HOST_CANONICAL_DESTINATION_RULE_PRIORITY" || return 1
  host_acceptance_require_exact VPNKIT_LOCAL_DESTINATION_FAIL_CLOSED_PRIORITY "$HOST_CANONICAL_DESTINATION_FAIL_CLOSED_PRIORITY" || return 1
  host_acceptance_require_exact VPNKIT_LOCAL_RULE_PRIORITY "$HOST_CANONICAL_RULE_PRIORITY" || return 1
  host_acceptance_require_exact VPNKIT_LOCAL_FAIL_CLOSED_PRIORITY "$HOST_CANONICAL_FAIL_CLOSED_PRIORITY" || return 1
  host_acceptance_require_exact VPNKIT_LOCAL_POLICY "$HOST_CANONICAL_POLICY" || return 1
  host_acceptance_require_exact VPNKIT_LOCAL_MANAGE_NETWORKMANAGER true || return 1
  host_acceptance_require_exact VPNKIT_BOOTSTRAP_PICK_ON_START "$HOST_CANONICAL_BOOTSTRAP_PICK" || return 1
  host_acceptance_require_exact VPNKIT_BOOTSTRAP_MAX_NODES "$HOST_CANONICAL_BOOTSTRAP_MAX_NODES" || return 1
  host_acceptance_require_integer VPNKIT_LOCAL_OPENVPN_PORT 1024 65535 || return 1
  host_acceptance_require_integer VPNKIT_LOCAL_BOOT_TIMEOUT_SECONDS 1 7200 || return 1
  host_acceptance_require_integer VPNKIT_LOCAL_RETEST_TIMEOUT_SECONDS 1 3600 || return 1
  host_acceptance_require_integer VPNKIT_LOCAL_NM_CONNECT_TIMEOUT_SECONDS 1 120 || return 1
  if [[ -v VPNKIT_LOCAL_OPENVPN_PUSH_DNS ]]; then
    case "${VPNKIT_LOCAL_OPENVPN_PUSH_DNS}" in
      8.8.8.8|8.8.4.4) ;;
      *)
        printf 'live local KDE acceptance rejects unsafe config DNS (VPNKIT_LOCAL_OPENVPN_PUSH_DNS)\n' >&2
        return 1
        ;;
    esac
  fi
  return 0
}

# Check the caller's lexical path before realpath -m is allowed to resolve it.
# A canonical path alone cannot distinguish an allowed target reached through a
# symlink from an ordinary path in that target tree.
path_has_symlink_component() {
  local path=$1 current=/ part
  local -a parts=()
  [[ "$path" == /* ]] || return 2
  IFS=/ read -r -a parts <<<"${path#/}"
  for part in "${parts[@]}"; do
    case "$part" in
      ''|.) continue ;;
      ..)
        current=${current%/*}
        [[ -n "$current" ]] || current=/
        continue
        ;;
    esac
    if [[ "$current" == / ]]; then
      current="/$part"
    else
      current="$current/$part"
    fi
    [[ -L "$current" ]] && return 0
  done
  return 1
}

is_protected_canonical_path() {
  local canonical=$1 strict_logs=${2:-0}
  case "$canonical" in
    "$REPO_ROOT/secrets"|"$REPO_ROOT/secrets/vps"|"$REPO_ROOT/secrets/vps/"*|\
    "$REPO_ROOT/secrets/vpnkit-local"|"$REPO_ROOT/secrets/vpnkit-local/"*)
      return 0
      ;;
  esac
  if (( strict_logs )); then
    case "$canonical" in
      "$REPO_ROOT/logs"|"$REPO_ROOT/logs/"*) return 0 ;;
    esac
  else
    case "$canonical" in
      "$REPO_ROOT/logs/vpnkit"|"$REPO_ROOT/logs/vpnkit/"*|\
      "$REPO_ROOT/logs/vpnkit-local"|"$REPO_ROOT/logs/vpnkit-local/"*|\
      "$REPO_ROOT/logs/vps"|"$REPO_ROOT/logs/vps/"*)
        return 0
        ;;
    esac
  fi
  return 1
}

reject_protected_path() {
  local label=$1 path=$2 strict_logs=${3:-0} canonical
  canonical=$(canonical_path "$path") || {
    printf 'cannot canonicalize %s path: %s\n' "$label" "$path" >&2
    exit 2
  }
  if is_protected_canonical_path "$canonical" "$strict_logs"; then
    case "$canonical" in
      "$REPO_ROOT/secrets"|"$REPO_ROOT/secrets/vps"|"$REPO_ROOT/secrets/vps/"*|\
      "$REPO_ROOT/secrets/vpnkit-local"|"$REPO_ROOT/secrets/vpnkit-local/"*)
        printf 'refusing protected real secrets path for %s: %s\n' "$label" "$canonical" >&2
        ;;
      *)
        printf 'refusing protected real logs path for %s: %s\n' "$label" "$canonical" >&2
        ;;
    esac
    exit 2
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

log_path_is_anchor() {
  case "$1" in
    /|/tmp|/var/tmp) return 0 ;;
    *) return 1 ;;
  esac
}

log_path_is_broad() {
  case "$1" in
    /|/tmp|/var/tmp|"$REPO_ROOT"|"$REPO_ROOT/secrets"|"$REPO_ROOT/logs") return 0 ;;
    *) return 1 ;;
  esac
}

log_parent_is_broad() {
  case "$1" in
    /|/tmp|/var/tmp|"$REPO_ROOT") return 0 ;;
    *) return 1 ;;
  esac
}

# Validate every existing directory component without creating anything. The
# standard temporary roots are trusted anchors, but the actual log parent must
# be user-owned and not writable by another uid/group. Missing components are
# checked again after they are created.
log_parent_components_safe() {
  local parent=$1 current=/ part mode
  local -a parts=()
  IFS=/ read -r -a parts <<<"${parent#/}"
  for part in "${parts[@]}"; do
    case "$part" in
      ''|.) continue ;;
      ..)
        current=${current%/*}
        [[ -n "$current" ]] || current=/
        continue
        ;;
    esac
    if [[ "$current" == / ]]; then
      current="/$part"
    else
      current="$current/$part"
    fi
    if [[ -L "$current" ]]; then
      LOG_ERROR="log parent contains a symlink component: $current"
      return 1
    fi
    if [[ -e "$current" ]]; then
      [[ -d "$current" ]] || {
        LOG_ERROR="log parent component is not a directory: $current"
        return 1
      }
      if ! log_path_is_anchor "$current"; then
        if [[ "$current" == "$parent" && ! -O "$current" ]]; then
          LOG_ERROR="log parent is not user-owned: $current"
          return 1
        fi
        mode=$(stat -c '%a' -- "$current" 2>/dev/null) || {
          LOG_ERROR="cannot inspect log parent permissions: $current"
          return 1
        }
        if (( (8#$mode & 022) != 0 )); then
          LOG_ERROR="log parent is writable by another uid/group: $current"
          return 1
        fi
      fi
    fi
  done
}

log_parent_create_missing() {
  local parent=$1 current=/ part old_umask rc=0
  local -a parts=()
  old_umask=$(umask) || {
    LOG_ERROR='cannot read process umask for private log creation'
    return 1
  }
  umask 077
  IFS=/ read -r -a parts <<<"${parent#/}"
  for part in "${parts[@]}"; do
    case "$part" in
      ''|.) continue ;;
      ..)
        current=${current%/*}
        [[ -n "$current" ]] || current=/
        continue
        ;;
    esac
    if [[ "$current" == / ]]; then
      current="/$part"
    else
      current="$current/$part"
    fi
    if [[ -L "$current" ]]; then
      LOG_ERROR="log parent contains a symlink component: $current"
      rc=1
      break
    fi
    if [[ ! -e "$current" ]]; then
      if ! mkdir -- "$current" 2>/dev/null; then
        LOG_ERROR="cannot create log parent: $current"
        rc=1
        break
      fi
    fi
    if [[ -L "$current" || ! -d "$current" ]]; then
      LOG_ERROR="log parent changed to a non-directory: $current"
      rc=1
      break
    fi
    if [[ "$current" == "$parent" && ! -O "$current" ]]; then
      LOG_ERROR="log parent is not user-owned: $current"
      rc=1
      break
    fi
  done
  umask "$old_umask"
  return "$rc"
}

# Open a brand-new log inode while positioned in its already-validated
# directory. Bash noclobber maps this regular-file creation to an exclusive
# create, so a final symlink or a target installed after validation cannot be
# followed or overwritten. The descriptor is retained and tee later writes
# through /proc/self/fd rather than reopening the user-controlled pathname.
prepare_log_file() {
  local requested=$1 strict_logs=${2:-0}
  local absolute canonical parent base links mode file_info file_type file_uid file_links file_mode
  local old_umask open_rc noclobber_was_set=0

  LOG_ERROR=
  absolute=$(absolute_path "$requested") || {
    LOG_ERROR="cannot make log path absolute: $requested"
    return 1
  }
  if path_has_symlink_component "$absolute"; then
    LOG_ERROR="log path contains a symlink component: $requested"
    return 1
  fi
  canonical=$(canonical_path "$absolute") || {
    LOG_ERROR="cannot canonicalize log path: $requested"
    return 1
  }
  if path_has_symlink_component "$canonical"; then
    LOG_ERROR="log path resolves through a symlink: $requested"
    return 1
  fi
  if log_path_is_broad "$canonical"; then
    LOG_ERROR="log path is too broad: $canonical"
    return 1
  fi
  case "$canonical" in
    "$REPO_ROOT/secrets/"*)
      LOG_ERROR="log path is protected: $canonical"
      return 1
      ;;
  esac
  if is_protected_canonical_path "$canonical" "$strict_logs"; then
    LOG_ERROR="log path is protected: $canonical"
    return 1
  fi

  parent=$(dirname -- "$canonical")
  if log_parent_is_broad "$parent"; then
    LOG_ERROR="log parent is too broad: $parent"
    return 1
  fi
  base=$(basename -- "$canonical")
  [[ -n "$base" && "$base" != . && "$base" != .. ]] || {
    LOG_ERROR="log path has no regular-file basename: $canonical"
    return 1
  }
  log_parent_components_safe "$parent" || return 1

  if [[ -L "$canonical" ]]; then
    LOG_ERROR="log target is a symlink: $canonical"
    return 1
  fi
  if [[ -e "$canonical" ]]; then
    [[ -f "$canonical" ]] || {
      LOG_ERROR="log target is not a regular file: $canonical"
      return 1
    }
    [[ -O "$canonical" ]] || {
      LOG_ERROR="log target is not user-owned: $canonical"
      return 1
    }
    links=$(stat -c '%h' -- "$canonical" 2>/dev/null) || {
      LOG_ERROR="cannot inspect log target link count: $canonical"
      return 1
    }
    [[ "$links" == 1 ]] || {
      LOG_ERROR="log target is hard-linked: $canonical"
      return 1
    }
    LOG_ERROR="log target already exists; refusing overwrite: $canonical"
    return 1
  fi

  log_parent_create_missing "$parent" || return 1
  log_parent_components_safe "$parent" || return 1
  if path_has_symlink_component "$canonical" || [[ -e "$canonical" || -L "$canonical" ]]; then
    LOG_ERROR="log target appeared or changed during setup: $canonical"
    return 1
  fi

  if ! cd -- "$parent" 2>/dev/null; then
    LOG_ERROR="cannot enter validated log parent: $parent"
    return 1
  fi
  if [[ "$(pwd -P 2>/dev/null)" != "$parent" ]]; then
    cd -- "$REPO_ROOT" 2>/dev/null || true
    LOG_ERROR="log parent changed through a symlink before creation: $parent"
    return 1
  fi
  old_umask=$(umask) || old_umask=0022
  umask 077
  [[ "$-" == *C* ]] && noclobber_was_set=1
  set -C
  if exec {LOG_FD}>"$base" 2>/dev/null; then
    open_rc=0
  else
    open_rc=$?
  fi
  (( noclobber_was_set )) || set +C
  umask "$old_umask"
  if ! cd -- "$REPO_ROOT" 2>/dev/null; then
    [[ -n "${LOG_FD:-}" ]] && exec {LOG_FD}>&-
    LOG_FD=
    LOG_ERROR="cannot restore repository working directory after log creation"
    return 1
  fi
  if (( open_rc != 0 )); then
    LOG_ERROR="cannot exclusively create new log file: $canonical"
    return 1
  fi

  file_info=$(stat -Lc '%F|%u|%h|%a' -- "/proc/self/fd/$LOG_FD" 2>/dev/null) || {
    exec {LOG_FD}>&-
    LOG_FD=
    LOG_ERROR='cannot inspect newly-created log descriptor'
    return 1
  }
  IFS='|' read -r file_type file_uid file_links file_mode <<<"$file_info"
  if [[ "$file_type" != regular* || "$file_uid" != "$(id -u)" || "$file_links" != 1 || "$file_mode" != 600 ]]; then
    exec {LOG_FD}>&-
    LOG_FD=
    LOG_ERROR='new log is not a private, single-link regular file'
    return 1
  fi
  LOG_FILE=$canonical
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

APPROVE_LOCAL_KDE_HOST=0
SCENARIO=${VPNKIT_TEST_SCENARIO:-}
ACTION=${VPNKIT_TEST_ACTION:-test}
SCENARIO_FROM_CLI=0
ACTION_FROM_CLI=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario) SCENARIO=${2:?missing value}; SCENARIO_FROM_CLI=1; shift 2 ;;
    --action) ACTION=${2:?missing value}; ACTION_FROM_CLI=1; shift 2 ;;
    --approve-local-kde-host|--approve-local-host|--yes) APPROVE_LOCAL_KDE_HOST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$ACTION" in up|test|down|cycle|accept) ;; *) echo "unknown action: $ACTION" >&2; usage >&2; exit 2 ;; esac
if [[ -n "$SCENARIO" && "$SCENARIO" != "steamdeck-host" && "$SCENARIO" != "local-docker" && "$SCENARIO" != "local-kde-host" ]]; then
  echo "unknown scenario: $SCENARIO (supported: steamdeck-host, local-docker, local-kde-host)" >&2; exit 2
fi
if [[ "$SCENARIO" == "local-kde-host" && "$ACTION" != accept && "$ACTION" != test ]]; then
  echo "local-kde-host requires --action accept (or its contract-test alias)" >&2
  exit 2
fi
if [[ "$SCENARIO" == "local-kde-host" && "$ACTION" == accept && ( "$SCENARIO_FROM_CLI" != 1 || "$ACTION_FROM_CLI" != 1 ) ]]; then
  echo "live local KDE acceptance requires explicit --scenario local-kde-host --action accept" >&2
  exit 2
fi
if [[ "$SCENARIO" != "local-kde-host" && "$ACTION" == accept ]]; then
  echo "--action accept is only supported with --scenario local-kde-host" >&2
  exit 2
fi
if [[ "$SCENARIO" == "local-kde-host" && "$ACTION" == accept ]]; then
  HOST_LOCAL_LIVE_ACCEPT=1
  HOST_ACCEPTANCE_RESULT_NAME=host:localhost-udp-underlay-nm
fi
redact_stream() {
  # First apply shape-based redaction, then replace configured host values by
  # exact string. The allow-list is deliberately not a blanket hostname
  # filter: tracked public probes such as example.com, dns.google, and
  # cloudflare-dns.com remain visible and useful in test evidence.
  local line value
  local -a private_values=(
    "${VPNKIT_PRIVATE_HOSTNAME_SENTINEL:-}"
    private-hostname-sentinel
    private-endpoint-sentinel
  )
  # `local-docker` intentionally uses the public Compose service name
  # `vpnkit`; do not treat that internal fixture value as a private endpoint.
  # Explicitly configured SSH values are still included even when a caller is
  # running a different scenario, because child diagnostics may echo them.
  if [[ "$SCENARIO" == steamdeck-host ]]; then
    private_values+=("${SSH_TARGET:-}" "${SSH_TARGET##*@}" "${SSH_TARGET%%:*}" "${TEST_ENDPOINT:-}" "${TEST_ENDPOINT%%:*}" "${VPNKIT_TEST_ENDPOINT:-}" "${VPNKIT_STEAMDECK_LAN_ENDPOINT:-}")
  fi
  private_values+=(
    "${VPNKIT_TEST_SSH_TARGET:-}"
    "${VPNKIT_STEAMDECK_SSH_TARGET:-}"
    "${VPNKIT_STEAMDECK_SSH_HOST:-}"
    "${VPNKIT_VPS_SSH_HOST:-}"
    "${VPNKIT_VPS_PUBLIC_ENDPOINT:-}"
    "${VPNKIT_PRODUCTION_OPENVPN_ENDPOINT:-}"
    "${VPNKIT_EXTRA_NODE_HOST:-}"
    "${VPNKIT_EXTRA_NODE_SNI:-}"
    "${VPN_FAILOVER_DOMAIN:-}"
    "${VPNKIT_PRIVATE_ENDPOINT_HOSTNAME:-}"
    "${VPNKIT_PRIVATE_HOSTNAME:-}"
  )
  while IFS= read -r line || [[ -n "$line" ]]; do
    for value in "${private_values[@]}"; do
      [[ -n "$value" ]] || continue
      case "$value" in
        localhost|127.0.0.1|example.com|example.org|cloudflare-dns.com|dns.google|ya.ru|npmjs.com|pypi.org|debian.org|doubleclick.net|googleads.g.doubleclick.net)
          continue
          ;;
      esac
      line=${line//"$value"/<private-host>}
    done
    printf '%s\n' "$line"
  done < <(
    sed -E \
      -e 's#vless://[^[:space:]]+#vless://[redacted]#ig' \
      -e 's#(https?://)[^[:space:]]*(token|sub|subscription|api[_-]?key|apikey|key|auth|password|passwd|secret)[^[:space:]]*#\1[redacted-url]#ig' \
      -e 's#(ss|trojan|vmess)://[^[:space:]]+#\1://[redacted]#ig' \
      -e 's/([0-9a-f]{8}-[0-9a-f-]{27,})/[redacted-uuid]/ig' \
      -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' \
      -e 's/\b([0-9a-f]{1,4}:){2,}[0-9a-f]{1,4}\b/<IPv6>/ig' \
      -e "s/((private[_-]?key|password|passwd|auth|token|secret|node|sub_url|subscription)[\"':= ]+)[^,\"' ]+/\\1[redacted]/ig"
  )
}

SSH_TARGET=${VPNKIT_TEST_SSH_TARGET:-${VPNKIT_STEAMDECK_SSH_TARGET:-${VPNKIT_STEAMDECK_SSH_HOST:-deck}}}
REMOTE_RUNTIME=${VPNKIT_TEST_RUNTIME:-podman}
[[ "$REMOTE_RUNTIME" =~ ^[A-Za-z0-9_.-]+$ ]] || {
  printf 'VPNKIT_TEST_RUNTIME contains unsafe characters\n' >&2
  exit 2
}
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
# These are populated once the local client smoke scope is selected. Keeping
# them in the ownership capability lets full Compose preflights include the
# runner-created client resources after an external Docker interval.
LOCAL_CLIENT_CONTAINER_NAME=
LOCAL_CLIENT_NETWORK_NAME=

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
  # Include previously-created runner client resources in the initial full
  # capability check when their configured names are themselves safe. Invalid
  # names remain empty here and are rejected by the client safety row below.
  LOCAL_CLIENT_CONTAINER_NAME=${VPNKIT_LOCAL_TEST_CLIENT_CONTAINER:-${LOCAL_PROJECT}-client-smoke}
  LOCAL_CLIENT_NETWORK_NAME=${VPNKIT_LOCAL_TEST_CLIENT_NETWORK:-${LOCAL_PROJECT}-client-smoke}
  if [[ "$LOCAL_CLIENT_CONTAINER_NAME" != "$LOCAL_PROJECT-"* || "$LOCAL_CLIENT_NETWORK_NAME" != "$LOCAL_PROJECT-"* || ! "$LOCAL_CLIENT_CONTAINER_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ || ! "$LOCAL_CLIENT_NETWORK_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
    LOCAL_CLIENT_CONTAINER_NAME=
    LOCAL_CLIENT_NETWORK_NAME=
  fi
  LOCAL_SCENARIO_DIR=${VPNKIT_TEST_LAB_SECRETS_DIR:-secrets/vpnkit-labs/local-docker}
  case "$LOCAL_SCENARIO_DIR" in /*) ;; *) LOCAL_SCENARIO_DIR="$REPO_ROOT/$LOCAL_SCENARIO_DIR" ;; esac
  LOCAL_SCENARIO_DIR=$(canonical_path "$LOCAL_SCENARIO_DIR")
  validate_isolated_artifact_tree VPNKIT_TEST_LAB_SECRETS_DIR "$LOCAL_SCENARIO_DIR"
  # This private record is the only durable freshness authority for a
  # standalone local-docker test. It lives inside the isolated, gitignored lab
  # root and is never printed or included in the source digest.
  LOCAL_PROVENANCE_FILE="$LOCAL_SCENARIO_DIR/.containers-test-provenance"
  # Keep the disposable lab able to run beside the real local instance.
  LOCAL_PORT=${VPNKIT_LOCAL_TEST_OPENVPN_PORT:-21195}
  if ! [[ "$LOCAL_PORT" =~ ^[0-9]+$ ]] || (( 10#$LOCAL_PORT < 1 || 10#$LOCAL_PORT > 65535 )); then
    printf 'VPNKIT_LOCAL_TEST_OPENVPN_PORT must be a UDP port in the range 1-65535\n' >&2
    exit 2
  fi
  LOCAL_SERVER_SUBNET=${VPNKIT_LOCAL_TEST_SERVER_SUBNET:-172.30.91.0/24}
  LOCAL_SERVER_ADDRESS=${VPNKIT_LOCAL_TEST_SERVER_ADDRESS:-172.30.91.2}
  LOCAL_LOG_ROOT=${VPNKIT_LOCAL_TEST_LOG_ROOT:-/tmp/vpnkit-containers-test/$LOCAL_PROJECT}
  local_log_root_absolute=$(absolute_path "$LOCAL_LOG_ROOT")
  if path_has_symlink_component "$local_log_root_absolute"; then
    printf 'VPNKIT_LOCAL_TEST_LOG_ROOT must not contain symlink components: %s\n' "$LOCAL_LOG_ROOT" >&2
    exit 2
  fi
  LOCAL_LOG_ROOT=$(canonical_path "$local_log_root_absolute")
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

if [[ "$SCENARIO" == "local-kde-host" ]]; then
  if (( HOST_LOCAL_LIVE_ACCEPT == 1 )); then
    # Reject fixture/override capability before any live command is resolved or
    # any lifecycle/NM/Docker operation can begin. The contract alias below is
    # intentionally the only path that may use these seams.
    host_acceptance_reject_overrides || exit 2
    host_acceptance_bind_trusted_commands || {
      printf 'trusted host command binding is unavailable for live local KDE acceptance\n' >&2
      exit 2
    }
    host_acceptance_validate_current_path || {
      printf 'live local KDE acceptance refuses a mocked or untrusted command PATH\n' >&2
      exit 2
    }
    host_acceptance_validate_canonical_sources || {
      printf 'canonical local KDE lifecycle/helper sources are unavailable\n' >&2
      exit 2
    }
    export PATH="$HOST_TRUSTED_PATH"
    host_acceptance_validate_safe_config || exit 2
  elif [[ "$ACTION" == test && "${VPNKIT_LOCAL_TEST_FIXTURE:-0}" != 1 ]]; then
    # A non-fixture contract run is deliberately rejected before the
    # acceptance function can resolve Docker/NM or invoke the lifecycle. It is
    # still safe to validate a sourced local config here, so the documented
    # template reaches the non-mutating contract gate rather than being
    # mistaken for a forbidden override.
    host_acceptance_validate_safe_config || exit 2
  fi
  case "${VPNKIT_LOCAL_KDE_HOST_APPROVED:-${VPNKIT_LOCAL_HOST_ACCEPTANCE_APPROVED:-0}}" in
    1|true|yes|on) APPROVE_LOCAL_KDE_HOST=1 ;;
  esac
  HOST_LOCAL_SECRETS_DIR=${VPNKIT_LOCAL_SECRETS_DIR:-$REPO_ROOT/secrets/vpnkit-local}
  case "$HOST_LOCAL_SECRETS_DIR" in
    /*) host_local_secrets_request=$HOST_LOCAL_SECRETS_DIR ;;
    *) host_local_secrets_request="$REPO_ROOT/$HOST_LOCAL_SECRETS_DIR" ;;
  esac
  path_has_symlink_component "$host_local_secrets_request" && {
    printf 'local-kde-host secret root must not contain symlink components\n' >&2
    exit 2
  }
  HOST_LOCAL_SECRETS_DIR=$(canonical_path "$host_local_secrets_request")
  host_local_root="$REPO_ROOT/secrets/vpnkit-local"
  case "$HOST_LOCAL_SECRETS_DIR" in
    "$host_local_root"|"$host_local_root/"*) ;;
    /tmp/*|/var/tmp/*)
      [[ "${VPNKIT_LOCAL_TEST_FIXTURE:-0}" == 1 ]] || {
        printf 'temporary local-kde-host secret roots require VPNKIT_LOCAL_TEST_FIXTURE=1\n' >&2
        exit 2
      }
      ;;
    *)
      printf 'local-kde-host secret root must stay in secrets/vpnkit-local or an explicit temporary fixture\n' >&2
      exit 2
      ;;
  esac
  [[ "$HOST_LOCAL_SECRETS_DIR" != /tmp && "$HOST_LOCAL_SECRETS_DIR" != /var/tmp ]] || {
    printf 'local-kde-host secret root is too broad\n' >&2
    exit 2
  }
  assert_user_owned_path local-kde-host-secrets "$HOST_LOCAL_SECRETS_DIR" || exit 2
  HOST_LOCAL_PROJECT=${VPNKIT_LOCAL_COMPOSE_PROJECT:-vpnkit-local}
  [[ "$HOST_LOCAL_PROJECT" == vpnkit-local || ( "${VPNKIT_LOCAL_TEST_FIXTURE:-0}" == 1 && "$HOST_LOCAL_PROJECT" =~ ^vpnkit-local-[a-z0-9][a-z0-9_-]*$ ) ]] || {
    printf 'local-kde-host requires the guarded vpnkit-local Compose project identity\n' >&2
    exit 2
  }
  case "$HOST_LOCAL_PROJECT" in
    *-prod*|*-production*|*-live*)
      printf 'refusing production-like local-kde-host Compose project identity\n' >&2
      exit 2
      ;;
  esac
  # Do not inherit the Steam Deck/production-oriented generic
  # VPNKIT_OPENVPN_PORT into this local-host path; only the local override may
  # select the loopback publication.
  HOST_LOCAL_PORT=${VPNKIT_LOCAL_OPENVPN_PORT:-$HOST_CANONICAL_OPENVPN_PORT}
  if ! [[ "$HOST_LOCAL_PORT" =~ ^[0-9]+$ ]] || (( 10#$HOST_LOCAL_PORT < 1024 || 10#$HOST_LOCAL_PORT > 65535 )); then
    printf 'local-kde-host OpenVPN port must be in the range 1024-65535\n' >&2
    exit 2
  fi
  HOST_LOCAL_SUBNET=${VPNKIT_LOCAL_DOCKER_SUBNET:-$HOST_CANONICAL_DOCKER_SUBNET}
  HOST_LOCAL_CONTAINER_ADDRESS=${VPNKIT_LOCAL_CONTAINER_ADDRESS:-$HOST_CANONICAL_CONTAINER_ADDRESS}
  HOST_LOCAL_PUSH_DNS=${VPNKIT_LOCAL_OPENVPN_PUSH_DNS:-$HOST_CANONICAL_PUSH_DNS}
  HOST_LOCAL_BOOT_TIMEOUT=${VPNKIT_LOCAL_BOOT_TIMEOUT_SECONDS:-$HOST_CANONICAL_BOOT_TIMEOUT_SECONDS}
  HOST_LOCAL_RETEST_TIMEOUT=${VPNKIT_LOCAL_RETEST_TIMEOUT_SECONDS:-$HOST_CANONICAL_RETEST_TIMEOUT_SECONDS}
  HOST_LOCAL_NM_CONNECT_TIMEOUT=${VPNKIT_LOCAL_NM_CONNECT_TIMEOUT_SECONDS:-$HOST_CANONICAL_NM_CONNECT_TIMEOUT_SECONDS}
  HOST_LOCAL_LIFECYCLE="$REPO_ROOT/scripts/vpnkit/vpnkit-local.sh"
  HOST_LOCAL_SMOKE="$REPO_ROOT/scripts/vpnkit/vpnkit-local-host-smoke.sh"
  if (( HOST_LOCAL_LIVE_ACCEPT == 1 )); then
    # These are source-controlled, canonical identities for live acceptance;
    # test helper overrides are rejected above rather than selected here.
    HOST_LOCAL_NM_HELPER="$REPO_ROOT/scripts/vpnkit/vpnkit-local-networkmanager.sh"
    HOST_LOCAL_UNDERLAY_HELPER="$REPO_ROOT/scripts/vpnkit/vpnkit-local-underlay-routing.sh"
  else
    HOST_LOCAL_NM_HELPER=${VPNKIT_LOCAL_TEST_NM_HELPER:-$REPO_ROOT/scripts/vpnkit/vpnkit-local-networkmanager.sh}
    HOST_LOCAL_UNDERLAY_HELPER=${VPNKIT_LOCAL_TEST_UNDERLAY_HELPER:-$REPO_ROOT/scripts/vpnkit/vpnkit-local-underlay-routing.sh}
  fi
  TEST_PROFILE="$HOST_LOCAL_SECRETS_DIR/openvpn/client/vpnkit-local.ovpn"
  TEST_ENDPOINT=127.0.0.1
  SERVER_CONTAINER=vpnkit-local
  REMOTE_RUNTIME=docker
  selected_ssh_source=not-used-local-kde-host
  selected_endpoint_source=localhost-published-port
  export VPNKIT_LOCAL_SECRETS_DIR="$HOST_LOCAL_SECRETS_DIR"
  export VPNKIT_LOCAL_COMPOSE_PROJECT="$HOST_LOCAL_PROJECT"
  export VPNKIT_LOCAL_ENDPOINT="$HOST_CANONICAL_ENDPOINT" VPNKIT_LOCAL_OPENVPN_PORT="$HOST_LOCAL_PORT"
  export VPNKIT_LOCAL_DOCKER_SUBNET="$HOST_LOCAL_SUBNET" VPNKIT_LOCAL_CONTAINER_ADDRESS="$HOST_LOCAL_CONTAINER_ADDRESS"
  export VPNKIT_LOCAL_OPENVPN_PUSH_DNS="$HOST_LOCAL_PUSH_DNS"
  export VPNKIT_LOCAL_DESTINATION_RULE_PRIORITY="$HOST_CANONICAL_DESTINATION_RULE_PRIORITY"
  export VPNKIT_LOCAL_DESTINATION_FAIL_CLOSED_PRIORITY="$HOST_CANONICAL_DESTINATION_FAIL_CLOSED_PRIORITY"
  export VPNKIT_LOCAL_RULE_PRIORITY="$HOST_CANONICAL_RULE_PRIORITY"
  export VPNKIT_LOCAL_FAIL_CLOSED_PRIORITY="$HOST_CANONICAL_FAIL_CLOSED_PRIORITY"
  export VPNKIT_LOCAL_POLICY="$HOST_CANONICAL_POLICY"
  export VPNKIT_BOOTSTRAP_PICK_ON_START="$HOST_CANONICAL_BOOTSTRAP_PICK"
  export VPNKIT_BOOTSTRAP_MAX_NODES="$HOST_CANONICAL_BOOTSTRAP_MAX_NODES"
  export VPNKIT_LOCAL_BOOT_TIMEOUT_SECONDS="$HOST_LOCAL_BOOT_TIMEOUT"
  export VPNKIT_LOCAL_RETEST_TIMEOUT_SECONDS="$HOST_LOCAL_RETEST_TIMEOUT"
  export VPNKIT_LOCAL_NM_CONNECT_TIMEOUT_SECONDS="$HOST_LOCAL_NM_CONNECT_TIMEOUT"
  export VPNKIT_OPENVPN_BIND_ADDRESS="$HOST_CANONICAL_ENDPOINT" VPNKIT_OPENVPN_PORT="$HOST_LOCAL_PORT"
  export VPNKIT_LOCAL_MANAGE_NETWORKMANAGER=true
fi

if [[ "$SCENARIO" == "local-docker" ]]; then
  validate_isolated_profile_path VPNKIT_TEST_PROFILE "$TEST_PROFILE" "$LOCAL_SCENARIO_DIR"
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

# Include the shell pid so repeated safe-mock runs cannot collide on a new
# exclusive log path. Existing paths are never truncated or overwritten.
TS=$(date -u +%Y%m%dT%H%M%SZ)-$$
if [[ "$SCENARIO" == "local-docker" ]]; then
  DEFAULT_LOG_FILE="$LOCAL_LOG_ROOT/vpnkit-containers-test-$TS.log"
  LOG_FALLBACK="/tmp/vpnkit-containers-test/$LOCAL_PROJECT/vpnkit-containers-test-$TS.log"
  LOG_STRICT_LOGS=1
else
  DEFAULT_LOG_FILE="logs/vpnkit-containers-test-$TS.log"
  LOG_FALLBACK="/tmp/vpnkit-containers-test-$TS/vpnkit-containers-test.log"
  LOG_STRICT_LOGS=0
fi
LOG_NOTE=""
LOG_FD=
if [[ -n "${VPNKIT_CONTAINERS_TEST_LOG:-}" ]]; then
  if ! prepare_log_file "$VPNKIT_CONTAINERS_TEST_LOG" "$LOG_STRICT_LOGS"; then
    printf 'cannot create private VPNKIT_CONTAINERS_TEST_LOG: %s\n' "$LOG_ERROR" >&2
    exit 2
  fi
else
  if ! prepare_log_file "$DEFAULT_LOG_FILE" "$LOG_STRICT_LOGS"; then
    LOG_NOTE="default log path was not available; using private temporary fallback"
    if ! prepare_log_file "$LOG_FALLBACK" 1; then
      printf 'cannot create a private user-owned test log: %s\n' "$LOG_ERROR" >&2
      exit 2
    fi
  fi
fi

# The pathname is no longer reopened here. tee receives the already-open
# descriptor, while redact_stream ensures both console and file are redacted.
exec > >(redact_stream | tee -a -- "/proc/self/fd/$LOG_FD") 2>&1

PASS=0; FAIL=0; SKIP=0
RESULTS=()

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
record() {
  local status=$1 name=$2 reason=${3:-}
  case "$status" in PASS) PASS=$((PASS+1));; FAIL) FAIL=$((FAIL+1));; SKIP) SKIP=$((SKIP+1));; *) status=FAIL; FAIL=$((FAIL+1)); reason="internal bad status: $1 $reason";; esac
  RESULTS+=("$status|$name|$reason")
  log "$status $name${reason:+ - $reason}"
}

finish_runner_early() {
  local rc=$1
  printf '\nTotals: PASS=%d FAIL=%d SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"
  # The redaction tee is intentionally fed through an already-open log FD.
  # Close the parent copy before waiting; otherwise tee quite correctly waits
  # for EOF on /proc/self/fd/$LOG_FD and an early terminal path would hang.
  [[ -z "${LOG_FD:-}" ]] || exec {LOG_FD}>&-
  exec 1>&- 2>&-
  wait || true
  exit "$rc"
}

local_safety_error=""
LOCAL_DOCKER_PREREQ_CHECKED=0
LOCAL_DOCKER_PREREQ_READY=0
LOCAL_DOCKER_PREREQ_OUTPUT=

ensure_local_docker_prerequisite() {
  [[ "$SCENARIO" == local-docker ]] || return 0
  if (( LOCAL_DOCKER_PREREQ_CHECKED )); then
    (( LOCAL_DOCKER_PREREQ_READY == 1 ))
    return
  fi
  LOCAL_DOCKER_PREREQ_CHECKED=1
  if ! command -v docker >/dev/null 2>&1; then
    record FAIL "server:local-docker-reachable" "Docker command is unavailable"
    return 1
  fi
  if ! LOCAL_DOCKER_PREREQ_OUTPUT=$(run_capture_timeout "$SSH_TIMEOUT" docker info); then
    record FAIL "server:local-docker-reachable" "Docker daemon is unavailable"
    return 1
  fi
  if ! run_capture_timeout "$SSH_TIMEOUT" docker compose version >/dev/null; then
    record FAIL "server:local-docker-reachable" "Docker Compose plugin is unavailable"
    return 1
  fi
  LOCAL_DOCKER_PREREQ_READY=1
  record PASS "server:local-docker-reachable" "local Docker daemon and Compose are reachable"
  return 0
}

# Hash source by Git's tracked + nonignored-untracked view. Secret and log
# trees are excluded even if an operator accidentally makes one nonignored;
# generated lab material therefore cannot become provenance input. The digest
# binds both path and bytes, and the NUL-delimited list handles odd filenames.
local_docker_source_digest() {
  python3 - "$REPO_ROOT" <<'PY'
import hashlib
import os
import pathlib
import stat
import subprocess
import sys

root = pathlib.Path(sys.argv[1]).resolve()
try:
    raw = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        stderr=subprocess.DEVNULL,
    )
except (OSError, subprocess.CalledProcessError):
    raise SystemExit(1)

paths = sorted(raw.split(b"\0"))
hash_value = hashlib.sha256()
count = 0
for raw_name in paths:
    if not raw_name:
        continue
    try:
        relative = os.fsdecode(raw_name)
    except UnicodeDecodeError:
        continue
    normalized = relative.replace(os.sep, "/")
    if normalized == "secrets" or normalized.startswith("secrets/"):
        continue
    if normalized == "logs" or normalized.startswith("logs/"):
        continue
    path = root / pathlib.PurePosixPath(normalized)
    try:
        metadata = path.lstat()
    except OSError:
        continue
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        continue
    hash_value.update(b"path\0")
    hash_value.update(raw_name)
    hash_value.update(b"\0bytes\0")
    try:
        with path.open("rb") as source:
            while True:
                chunk = source.read(1024 * 1024)
                if not chunk:
                    break
                hash_value.update(chunk)
    except OSError:
        raise SystemExit(1)
    count += 1
if count == 0:
    raise SystemExit(1)
print(hash_value.hexdigest())
PY
}

local_docker_config_digest() {
  local config
  config=$("${LOCAL_COMPOSE[@]}" config --format json 2>/dev/null) || return 1
  [[ -n "$config" ]] || return 1
  python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())' <<<"$config"
}

local_docker_provenance_digest() {
  local source_digest=$1 config_digest=$2
  printf 'schema=1\nproject=%s\nsource=%s\nconfig=%s\n' \
    "$LOCAL_PROJECT" "$source_digest" "$config_digest" |
    python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
}

local_docker_invalidate_provenance() {
  [[ -n "${LOCAL_PROVENANCE_FILE:-}" ]] || return 0
  [[ ! -L "$LOCAL_PROVENANCE_FILE" ]] || {
    local_safety_error='local Docker provenance record is a symlink'
    return 1
  }
  if [[ -e "$LOCAL_PROVENANCE_FILE" ]]; then
    [[ -f "$LOCAL_PROVENANCE_FILE" && -O "$LOCAL_PROVENANCE_FILE" ]] || {
      local_safety_error='local Docker provenance record is not a user-owned regular file'
      return 1
    }
    [[ "$(stat -c '%h' -- "$LOCAL_PROVENANCE_FILE" 2>/dev/null)" == 1 ]] || {
      local_safety_error='local Docker provenance record is hard-linked'
      return 1
    }
    rm -f -- "$LOCAL_PROVENANCE_FILE" || {
      local_safety_error='local Docker provenance record could not be removed'
      return 1
    }
  fi
}

local_docker_read_provenance() {
  local key value
  LOCAL_PROVENANCE_SCHEMA=
  LOCAL_PROVENANCE_PROJECT=
  LOCAL_PROVENANCE_SOURCE_DIGEST=
  LOCAL_PROVENANCE_CONFIG_DIGEST=
  LOCAL_PROVENANCE_DIGEST=
  LOCAL_PROVENANCE_IMAGE_ID=
  LOCAL_PROVENANCE_CONTAINER_ID=
  [[ -f "$LOCAL_PROVENANCE_FILE" && ! -L "$LOCAL_PROVENANCE_FILE" && -O "$LOCAL_PROVENANCE_FILE" ]] || return 1
  [[ "$(stat -c '%a|%h' -- "$LOCAL_PROVENANCE_FILE" 2>/dev/null)" == 600\|1 ]] || return 1
  while IFS='=' read -r key value; do
    [[ -n "$key" && "$key" != *[!a-z_]* && -n "$value" && "$value" != *$'\n'* && "$value" != *$'\r'* ]] || return 1
    case "$key" in
      schema) [[ -z "$LOCAL_PROVENANCE_SCHEMA" ]] || return 1; LOCAL_PROVENANCE_SCHEMA=$value ;;
      project) [[ -z "$LOCAL_PROVENANCE_PROJECT" ]] || return 1; LOCAL_PROVENANCE_PROJECT=$value ;;
      source_digest) [[ -z "$LOCAL_PROVENANCE_SOURCE_DIGEST" ]] || return 1; LOCAL_PROVENANCE_SOURCE_DIGEST=$value ;;
      config_digest) [[ -z "$LOCAL_PROVENANCE_CONFIG_DIGEST" ]] || return 1; LOCAL_PROVENANCE_CONFIG_DIGEST=$value ;;
      provenance_digest) [[ -z "$LOCAL_PROVENANCE_DIGEST" ]] || return 1; LOCAL_PROVENANCE_DIGEST=$value ;;
      image_id) [[ -z "$LOCAL_PROVENANCE_IMAGE_ID" ]] || return 1; LOCAL_PROVENANCE_IMAGE_ID=$value ;;
      container_id) [[ -z "$LOCAL_PROVENANCE_CONTAINER_ID" ]] || return 1; LOCAL_PROVENANCE_CONTAINER_ID=$value ;;
      *) return 1 ;;
    esac
  done <"$LOCAL_PROVENANCE_FILE"
  [[ "$LOCAL_PROVENANCE_SCHEMA" == 1 && "$LOCAL_PROVENANCE_PROJECT" == "$LOCAL_PROJECT" ]] || return 1
  [[ "$LOCAL_PROVENANCE_SOURCE_DIGEST" =~ ^[0-9a-f]{64}$ && "$LOCAL_PROVENANCE_CONFIG_DIGEST" =~ ^[0-9a-f]{64}$ && "$LOCAL_PROVENANCE_DIGEST" =~ ^[0-9a-f]{64}$ ]] || return 1
  [[ -n "$LOCAL_PROVENANCE_IMAGE_ID" && -n "$LOCAL_PROVENANCE_CONTAINER_ID" ]] || return 1
  [[ "$LOCAL_PROVENANCE_IMAGE_ID" != *[[:space:]]* && "$LOCAL_PROVENANCE_CONTAINER_ID" != *[[:space:]]* ]] || return 1
}

local_docker_persist_provenance() {
  local container=$1 source_before config_before source_after config_after
  local current_container_id image_id expected_digest tmp
  source_before=$(local_docker_source_digest) || return 1
  config_before=$(local_docker_config_digest) || return 1
  current_container_id=$(docker inspect --format '{{.Id}}' "$container" 2>/dev/null) || return 1
  image_id=$(docker inspect --format '{{.Image}}' "$container" 2>/dev/null) || return 1
  [[ -n "$current_container_id" && -n "$image_id" ]] || return 1
  [[ "$current_container_id" != *[[:space:]]* && "$image_id" != *[[:space:]]* ]] || return 1
  docker image inspect "$image_id" >/dev/null 2>&1 || return 1
  # A source/config change during the build or health wait invalidates the
  # candidate. Never publish a record for a deployment whose inputs drifted.
  source_after=$(local_docker_source_digest) || return 1
  config_after=$(local_docker_config_digest) || return 1
  [[ "$source_before" == "$source_after" && "$config_before" == "$config_after" ]] || return 1
  expected_digest=$(local_docker_provenance_digest "$source_before" "$config_before") || return 1
  mkdir -p -- "$(dirname -- "$LOCAL_PROVENANCE_FILE")" || return 1
  assert_user_owned_path local-docker-provenance-dir "$(dirname -- "$LOCAL_PROVENANCE_FILE")" || return 1
  [[ ! -L "$LOCAL_PROVENANCE_FILE" && ! -e "$LOCAL_PROVENANCE_FILE" ]] || return 1
  tmp=$(mktemp "${LOCAL_PROVENANCE_FILE}.XXXXXX") || return 1
  if ! {
    printf 'schema=1\n'
    printf 'project=%s\n' "$LOCAL_PROJECT"
    printf 'source_digest=%s\n' "$source_before"
    printf 'config_digest=%s\n' "$config_before"
    printf 'provenance_digest=%s\n' "$expected_digest"
    printf 'image_id=%s\n' "$image_id"
    printf 'container_id=%s\n' "$current_container_id"
  } >"$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  chmod 600 "$tmp" || { rm -f -- "$tmp"; return 1; }
  mv -f -- "$tmp" "$LOCAL_PROVENANCE_FILE" || { rm -f -- "$tmp"; return 1; }
  [[ "$(stat -c '%a' -- "$LOCAL_PROVENANCE_FILE" 2>/dev/null)" == 600 ]]
}

local_docker_verify_freshness() {
  local source_digest config_digest provenance_digest current_container_id current_image_id
  local expected_container_id=$SERVER_CONTAINER
  local selected_container_id
  local_docker_read_provenance || {
    local_safety_error='fresh local-docker provenance is missing or malformed'
    return 1
  }
  [[ "$LOCAL_PROVENANCE_PROJECT" == "$LOCAL_PROJECT" ]] || {
    local_safety_error='local-docker provenance project does not match the selected project'
    return 1
  }
  source_digest=$(local_docker_source_digest) || {
    local_safety_error='current nonignored source digest could not be computed'
    return 1
  }
  config_digest=$(local_docker_config_digest) || {
    local_safety_error='current Compose config digest could not be computed'
    return 1
  }
  provenance_digest=$(local_docker_provenance_digest "$source_digest" "$config_digest") || return 1
  [[ "$source_digest" == "$LOCAL_PROVENANCE_SOURCE_DIGEST" && "$config_digest" == "$LOCAL_PROVENANCE_CONFIG_DIGEST" && "$provenance_digest" == "$LOCAL_PROVENANCE_DIGEST" ]] || {
    local_safety_error='source or Compose config changed since the recorded deployment'
    return 1
  }
  selected_container_id=$("${LOCAL_COMPOSE[@]}" ps -q vpnkit 2>/dev/null) || return 1
  [[ -n "$selected_container_id" && "$selected_container_id" == "$expected_container_id" ]] || {
    local_safety_error='Compose selected a different local-docker container than the recorded deployment'
    return 1
  }
  current_container_id=$(docker inspect --format '{{.Id}}' "$SERVER_CONTAINER" 2>/dev/null) || return 1
  current_image_id=$(docker inspect --format '{{.Image}}' "$SERVER_CONTAINER" 2>/dev/null) || return 1
  [[ "$current_container_id" == "$LOCAL_PROVENANCE_CONTAINER_ID" && "$current_image_id" == "$LOCAL_PROVENANCE_IMAGE_ID" ]] || {
    local_safety_error='deployed image or container identity is stale'
    return 1
  }
  docker image inspect "$current_image_id" >/dev/null 2>&1 || {
    local_safety_error='recorded deployed image is missing from Docker'
    return 1
  }
  return 0
}

STEAMDECK_PREREQ_CHECKED=0
STEAMDECK_PREREQ_READY=0

ensure_steamdeck_prerequisite() {
  [[ "$SCENARIO" == steamdeck-host ]] || return 0
  if (( STEAMDECK_PREREQ_CHECKED )); then
    (( STEAMDECK_PREREQ_READY == 1 ))
    return
  fi
  STEAMDECK_PREREQ_CHECKED=1
  if [[ -z "$SSH_TARGET" || "$ssh_target_state" == placeholder ]]; then
    record FAIL "server:ssh-reachable" "placeholder/missing SSH target rejected before probe (source=$selected_ssh_source)"
    record FAIL "server:runtime-reachable" "remote runtime prerequisite cannot be checked without SSH"
    return 1
  fi
  if ! run_capture_timeout "$SSH_TIMEOUT" ssh -o BatchMode=yes -o ConnectTimeout="$SSH_TIMEOUT" "$SSH_TARGET" true >/dev/null; then
    record FAIL "server:ssh-reachable" "configured SSH target is unreachable"
    record FAIL "server:runtime-reachable" "remote runtime prerequisite cannot be checked without SSH"
    return 1
  fi
  record PASS "server:ssh-reachable" "configured SSH target is reachable"
  if ! run_capture_timeout "$REMOTE_CMD_TIMEOUT" ssh -o BatchMode=yes -o ConnectTimeout="$SSH_TIMEOUT" "$SSH_TARGET" "command -v $REMOTE_RUNTIME" >/dev/null; then
    record FAIL "server:runtime-reachable" "configured remote runtime is unavailable"
    return 1
  fi
  record PASS "server:runtime-reachable" "configured remote runtime is available"
  STEAMDECK_PREREQ_READY=1
}

resource_label() {
  local kind=$1 id=$2 label=$3
  case "$kind" in
    container) docker inspect --format "{{ index .Config.Labels \"$label\" }}" "$id" 2>/dev/null ;;
    network|volume) docker inspect --format "{{ index .Labels \"$label\" }}" "$id" 2>/dev/null ;;
    *) return 2 ;;
  esac
}

resource_name() {
  local kind=$1 id=$2 name
  case "$kind" in
    container|network|volume) ;;
    *) return 2 ;;
  esac
  name=$(docker inspect --format '{{.Name}}' "$id" 2>/dev/null) || return 1
  # Docker's container `.Name` is slash-prefixed; ownership comparisons use
  # the normalized exact name rather than a namespace/prefix match.
  name=${name#/}
  [[ -n "$name" ]] || return 1
  printf '%s\n' "$name"
}

local_compose_expected_names() {
  local kind=$1
  case "$kind" in
    container)
      printf '%s\n' \
        "${LOCAL_PROJECT}-vpnkit-1" "${LOCAL_PROJECT}_vpnkit_1" \
        "${LOCAL_PROJECT}-ovpn-client-test-1" "${LOCAL_PROJECT}_ovpn-client-test_1"
      [[ -n "${LOCAL_CLIENT_CONTAINER_NAME:-}" ]] && printf '%s\n' "$LOCAL_CLIENT_CONTAINER_NAME"
      ;;
    network)
      printf '%s\n' "${LOCAL_PROJECT}_vpnkit-local"
      [[ -n "${LOCAL_CLIENT_NETWORK_NAME:-}" ]] && printf '%s\n' "$LOCAL_CLIENT_NETWORK_NAME"
      ;;
    volume)
      printf '%s\n' \
        "${LOCAL_PROJECT}_vpnkit-local-vibe-vpn-state" \
        "${LOCAL_PROJECT}_vpnkit-local-sing-box-state" \
        "${LOCAL_PROJECT}_vpnkit-local-vpnkit-logs" \
        "${LOCAL_PROJECT}_vpnkit-local-vibe-vpn-logs"
      ;;
    *) return 2 ;;
  esac
}

local_compose_container_name_allowed() {
  local actual_name=$1 explicit_name=${2:-} expected_name
  [[ -n "$actual_name" ]] || return 1
  if [[ -n "$explicit_name" ]]; then
    [[ "$actual_name" == "$explicit_name" ]]
    return
  fi
  while IFS= read -r expected_name; do
    [[ "$actual_name" == "$expected_name" ]] && return 0
  done < <(local_compose_expected_names container)
  return 1
}

# Compose puts working_dir on container Config.Labels only. Networks and
# volumes instead have their type-specific Compose resource label and the
# project-prefixed resource name; requiring a container label on those kinds
# makes a normal post-up `down` look foreign.
local_resource_owned() {
  local kind=$1 id=$2 explicit_container_name=${3:-} project owner workdir compose_resource marker actual_name expected_name
  [[ -n "$id" ]] || { local_safety_error="$kind id is empty"; return 1; }
  project=$(resource_label "$kind" "$id" com.docker.compose.project || true)
  owner=$(resource_label "$kind" "$id" com.vpnkit.local.owner || true)
  case "$kind" in
    container)
      actual_name=$(resource_name container "$id" || true)
      if ! local_compose_container_name_allowed "$actual_name" "$explicit_container_name"; then
        local_safety_error="container $id has unexpected name=${actual_name:-missing} for project=$LOCAL_PROJECT"
        return 1
      fi
      workdir=$(resource_label container "$id" com.docker.compose.project.working_dir || true)
      if [[ "$project" != "$LOCAL_PROJECT" || "$owner" != "$LOCAL_TEST_OWNER_LABEL" || "$workdir" != "$REPO_ROOT" ]]; then
        local_safety_error="container $id is not owned by project=$LOCAL_PROJECT owner=$LOCAL_TEST_OWNER_LABEL working_dir=$REPO_ROOT"
        return 1
      fi
      ;;
    network)
      compose_resource=$(resource_label network "$id" com.docker.compose.network || true)
      marker=$(resource_label network "$id" com.vpnkit.local.resource || true)
      actual_name=$(resource_name network "$id" || true)
      case "$compose_resource:$marker" in
        vpnkit-local:*) expected_name="${LOCAL_PROJECT}_vpnkit-local" ;;
        :client-smoke|"<no value>:client-smoke")
          expected_name=${LOCAL_CLIENT_NETWORK_NAME:-}
          [[ -n "$expected_name" ]] || {
            local_safety_error="network $id is a client-smoke resource outside the selected client scope"
            return 1
          }
          ;;
        *)
          local_safety_error="network $id has unexpected Compose/client resource labels: compose=${compose_resource:-missing} marker=${marker:-missing}"
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
  local kind=$1 project_ids named_ids name
  case "$kind" in
    container)
      project_ids=$(docker container ls -aq --filter "label=com.docker.compose.project=$LOCAL_PROJECT" 2>/dev/null) || { local_safety_error="cannot list Compose containers"; return 1; }
      ;;
    network)
      project_ids=$(docker network ls -q --filter "label=com.docker.compose.project=$LOCAL_PROJECT" 2>/dev/null) || { local_safety_error="cannot list Compose networks"; return 1; }
      ;;
    volume)
      project_ids=$(docker volume ls -q --filter "label=com.docker.compose.project=$LOCAL_PROJECT" 2>/dev/null) || { local_safety_error="cannot list Compose volumes"; return 1; }
      ;;
    *) local_safety_error="unsupported Compose resource kind: $kind"; return 1 ;;
  esac

  # Project-label listing catches resources whose names are wrong. Exact-name
  # listing catches a foreign or label-less resource that would collide with
  # this Compose project. Do not scan every owner-labelled resource: a
  # different project is unrelated and must remain usable.
  printf '%s\n' "$project_ids"
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    case "$kind" in
      container)
        if ! named_ids=$(docker container ls -aq --filter "name=^/${name}$" 2>/dev/null); then
          local_safety_error="cannot inspect Compose container names"
          return 1
        fi
        ;;
      network)
        if ! named_ids=$(docker network ls -q --filter "name=^${name}$" 2>/dev/null); then
          local_safety_error="cannot inspect Compose network names"
          return 1
        fi
        ;;
      volume)
        if ! named_ids=$(docker volume ls -q --filter "name=^${name}$" 2>/dev/null); then
          local_safety_error="cannot inspect Compose volume names"
          return 1
        fi
        ;;
    esac
    printf '%s\n' "$named_ids"
  done < <(local_compose_expected_names "$kind")
}

local_compose_project_collisions() {
  local kind ids id project
  # This is deliberately limited to the target project and exact expected
  # names returned above. Unrelated projects are not a cleanup veto.
  for kind in container network volume; do
    ids=$(local_compose_resource_ids "$kind") || return 1
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      project=$(resource_label "$kind" "$id" com.docker.compose.project || true)
      if [[ -n "$project" && "$project" != "$LOCAL_PROJECT" ]]; then
        local_safety_error="$kind $id collides with an expected resource name from Compose project $project"
        return 1
      fi
    done <<<"$(printf '%s\n' "$ids" | awk 'NF && !seen[$0]++')"
  done
}

local_compose_resources_owned() {
  local kind ids id
  command -v docker >/dev/null 2>&1 || { local_safety_error="docker is unavailable"; return 1; }
  # Validate only resources selected by this project or an exact expected
  # project resource name. Unrelated project resources remain out of scope.
  local_compose_project_collisions || return 1
  for kind in container network volume; do
    ids=$(local_compose_resource_ids "$kind") || return 1
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      local_resource_owned "$kind" "$id" || return 1
    done <<<"$(printf '%s\n' "$ids" | awk 'NF && !seen[$0]++')"
  done
}

local_client_cleanup_scope_owned() {
  local client_name=$1 client_network=$2 server_id=$3 smoke_dir=$4 id
  [[ "$client_name" == "$LOCAL_PROJECT-"* ]] || { local_safety_error="client container name is outside the local project namespace"; return 1; }
  [[ "$client_network" == "$LOCAL_PROJECT-"* ]] || { local_safety_error="client network name is outside the local project namespace"; return 1; }
  assert_user_owned_path local-client-smoke-dir "$smoke_dir" || { local_safety_error="local client smoke directory is not user-owned"; return 1; }
  if id=$(docker container inspect -f '{{.Id}}' "$client_name" 2>/dev/null); then
    # This container is created explicitly by the runner, so its exact name
    # is an additional expected-name capability rather than a prefix match.
    local_resource_owned container "$id" "$client_name" || return 1
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
    # Revalidate the complete local Compose ownership set immediately before
    # every Docker exec. A same-label wrong-name container must never receive
    # even a diagnostic command, while unrelated projects stay out of scope.
    local_compose_resources_owned || return 125
    docker exec "$SERVER_CONTAINER" sh -lc "$1"
  else
    ssh_run "$REMOTE_RUNTIME exec $SERVER_CONTAINER sh -lc $(printf '%q' "$1")"
  fi
}

host_local_helper_is_allowed() {
  local label=$1 candidate=$2 canonical fixture_root
  [[ -x "$candidate" && ! -L "$candidate" ]] || {
    record FAIL "host:$label" "required guarded helper is unavailable"
    return 1
  }
  path_has_symlink_component "$candidate" && {
    record FAIL "host:$label" "required guarded helper path contains a symlink"
    return 1
  }
  canonical=$(canonical_path "$candidate") || {
    record FAIL "host:$label" "required guarded helper path could not be canonicalized"
    return 1
  }
  if [[ "$canonical" == "$REPO_ROOT/scripts/vpnkit/"* ]]; then
    return 0
  fi
  fixture_root=$(canonical_path "$HOST_LOCAL_SECRETS_DIR")
  if [[ "${VPNKIT_LOCAL_TEST_FIXTURE:-0}" == 1 ]] && [[ "$fixture_root" == /tmp/* || "$fixture_root" == /var/tmp/* ]]; then
    [[ "$canonical" == "$fixture_root/"* ]] || {
      record FAIL "host:$label" "fixture helper is outside the isolated local secret root"
      return 1
    }
    return 0
  fi
  record FAIL "host:$label" "only the tracked guarded helper or an explicit temporary fixture is allowed"
  return 1
}

host_lifecycle_run() {
  local env_command
  local -a unset_overrides=()
  env_command=$(host_acceptance_command_path env) || return 1
  if (( HOST_LOCAL_LIVE_ACCEPT == 1 )); then
    unset_overrides=(
      -u VPNKIT_LOCAL_TEST_FIXTURE
      -u VPNKIT_LOCAL_TEST_NM_HELPER
      -u VPNKIT_LOCAL_TEST_UNDERLAY_HELPER
      -u VPNKIT_LOCAL_HOST_SMOKE_SCRIPT
      -u VPNKIT_LOCAL_TEST_PROJECT
      -u VPNKIT_LOCAL_TEST_CLIENT_CONTAINER
      -u VPNKIT_LOCAL_TEST_CLIENT_NETWORK
      -u VPNKIT_LOCAL_TEST_CLIENT_SUBNET
      -u VPNKIT_LOCAL_TEST_OPENVPN_PORT
      -u VPNKIT_LOCAL_TEST_SERVER_SUBNET
      -u VPNKIT_LOCAL_TEST_SERVER_ADDRESS
      -u VPNKIT_LOCAL_TEST_LOG_ROOT
      -u VPNKIT_LOCAL_DOCKER_SUBNET
      -u VPNKIT_LOCAL_CONTAINER_ADDRESS
      -u VPNKIT_LOCAL_OVPN_CIDR
      -u VPNKIT_LOCAL_IPV6_POLICY
      -u VPNKIT_LOCAL_ROUTE_TABLE
      -u VPNKIT_LOCAL_DESTINATION_RULE_PRIORITY
      -u VPNKIT_LOCAL_DESTINATION_FAIL_CLOSED_PRIORITY
      -u VPNKIT_LOCAL_RULE_PRIORITY
      -u VPNKIT_LOCAL_FAIL_CLOSED_PRIORITY
      -u VPNKIT_LOCAL_UPLINK_IFACE
      -u VPNKIT_LOCAL_UPLINK_TABLE
      -u VPNKIT_LOCAL_UPLINK_GATEWAY
    )
  fi
  "$env_command" "${unset_overrides[@]}" \
    PATH="${HOST_TRUSTED_PATH:-$PATH}" \
    VPNKIT_LOCAL_ENV_FILE=/dev/null \
    VPNKIT_LOCAL_SECRETS_DIR="$HOST_LOCAL_SECRETS_DIR" \
    VPNKIT_LOCAL_COMPOSE_PROJECT="$HOST_LOCAL_PROJECT" \
    VPNKIT_LOCAL_ENDPOINT="$HOST_CANONICAL_ENDPOINT" \
    VPNKIT_LOCAL_OPENVPN_PORT="$HOST_LOCAL_PORT" \
    VPNKIT_LOCAL_DOCKER_SUBNET="$HOST_LOCAL_SUBNET" \
    VPNKIT_LOCAL_CONTAINER_ADDRESS="$HOST_LOCAL_CONTAINER_ADDRESS" \
    VPNKIT_LOCAL_OVPN_CIDR="$HOST_CANONICAL_OVPN_CIDR" \
    VPNKIT_LOCAL_IPV6_POLICY="$HOST_CANONICAL_IPV6_POLICY" \
    VPNKIT_LOCAL_OPENVPN_PUSH_DNS="$HOST_LOCAL_PUSH_DNS" \
    VPNKIT_LOCAL_DESTINATION_RULE_PRIORITY="$HOST_CANONICAL_DESTINATION_RULE_PRIORITY" \
    VPNKIT_LOCAL_DESTINATION_FAIL_CLOSED_PRIORITY="$HOST_CANONICAL_DESTINATION_FAIL_CLOSED_PRIORITY" \
    VPNKIT_LOCAL_RULE_PRIORITY="$HOST_CANONICAL_RULE_PRIORITY" \
    VPNKIT_LOCAL_FAIL_CLOSED_PRIORITY="$HOST_CANONICAL_FAIL_CLOSED_PRIORITY" \
    VPNKIT_LOCAL_POLICY="$HOST_CANONICAL_POLICY" \
    VPNKIT_BOOTSTRAP_PICK_ON_START="$HOST_CANONICAL_BOOTSTRAP_PICK" \
    VPNKIT_BOOTSTRAP_MAX_NODES="$HOST_CANONICAL_BOOTSTRAP_MAX_NODES" \
    VPNKIT_LOCAL_BOOT_TIMEOUT_SECONDS="$HOST_LOCAL_BOOT_TIMEOUT" \
    VPNKIT_LOCAL_RETEST_TIMEOUT_SECONDS="$HOST_LOCAL_RETEST_TIMEOUT" \
    VPNKIT_LOCAL_NM_CONNECT_TIMEOUT_SECONDS="$HOST_LOCAL_NM_CONNECT_TIMEOUT" \
    VPNKIT_OPENVPN_BIND_ADDRESS="$HOST_CANONICAL_ENDPOINT" \
    VPNKIT_OPENVPN_PORT="$HOST_LOCAL_PORT" \
    VPNKIT_LOCAL_MANAGE_NETWORKMANAGER=true \
    VPNKIT_LOCAL_HOST_SMOKE_SCRIPT="$HOST_LOCAL_SMOKE" \
    "$HOST_LOCAL_LIFECYCLE" "$@"
}

HOST_ACCEPTANCE_UUID_PATTERN='^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'

host_acceptance_uuid_is_canonical() {
  [[ "$1" =~ $HOST_ACCEPTANCE_UUID_PATTERN ]]
}

# The NetworkManager helper deliberately keeps UUIDs in its private ownership
# capability rather than printing them in ordinary status evidence. Read that
# capability only after status has proved that the exact vpnkit-local profile is
# owned. A stale/foreign/malformed capability yields no exclusion (or a hard
# read failure); the active inventory is never filtered by display name.
host_read_owned_nm_uuid_state() {
  local state_path payload uuid fingerprint extra
  for state_path in \
    "$HOST_LOCAL_SECRETS_DIR/state/networkmanager-state" \
    "$HOST_LOCAL_SECRETS_DIR/state/networkmanager-uuid"; do
    [[ -e "$state_path" || -L "$state_path" ]] || continue
    [[ -f "$state_path" && ! -L "$state_path" ]] || return 1
    payload=$(<"$state_path") || return 1
    [[ "$payload" != *$'\n'* && "$payload" != *$'\r'* ]] || return 1
    case "$state_path" in
      *networkmanager-state)
        read -r uuid fingerprint extra <<<"$payload"
        [[ -n "$uuid" && -n "$fingerprint" && -z "$extra" ]] || return 1
        [[ "$fingerprint" =~ ^[0-9A-Fa-f]{64}$ ]] || return 1
        ;;
      *)
        read -r uuid extra <<<"$payload"
        [[ -n "$uuid" && -z "$extra" ]] || return 1
        ;;
    esac
    host_acceptance_uuid_is_canonical "$uuid" || return 1
    printf '%s\n' "${uuid,,}"
    return 0
  done
  return 1
}

host_owned_nm_uuid_from_status() {
  local status_output=$1 configured ownership status_uuid state_uuid
  configured=$(awk -F= '$1 == "configured" { print $2; exit }' <<<"$status_output")
  ownership=$(awk -F= '$1 == "ownership" { print $2; exit }' <<<"$status_output")
  if [[ "$ownership" != owned ]]; then
    [[ "$configured" == no ]] || return 1
    # No exclusion is authorized for missing, stale, or foreign capability
    # state. In particular, a foreign profile named vpnkit-local remains in
    # the UUID set because no display name is queried or compared here.
    return 0
  fi
  [[ "$configured" == yes ]] || return 1

  # Accept an explicit UUID only when a helper version chooses to include one
  # in status; current helpers keep it in the private state capability.
  status_uuid=$(awk -F= '$1 == "owned_uuid" || $1 == "uuid" { print $2; exit }' <<<"$status_output")
  if [[ -n "$status_uuid" ]]; then
    host_acceptance_uuid_is_canonical "$status_uuid" || return 1
    status_uuid=${status_uuid,,}
  else
    status_uuid=$(host_read_owned_nm_uuid_state) || return 1
  fi

  # If both status and the private capability expose the UUID, require exact
  # agreement before excluding anything from the active VPN inventory.
  if [[ -e "$HOST_LOCAL_SECRETS_DIR/state/networkmanager-state" || -e "$HOST_LOCAL_SECRETS_DIR/state/networkmanager-uuid" || \
        -L "$HOST_LOCAL_SECRETS_DIR/state/networkmanager-state" || -L "$HOST_LOCAL_SECRETS_DIR/state/networkmanager-uuid" ]]; then
    state_uuid=$(host_read_owned_nm_uuid_state) || return 1
    [[ "$state_uuid" == "$status_uuid" ]] || return 1
  fi
  printf '%s\n' "$status_uuid"
}

host_capture_work_vpn_set() {
  local destination=$1 status_output output nmcli_command owned_uuid
  local tmp line uuid type extra
  if (( $# >= 2 )); then
    status_output=$2
  else
    status_output=$(run_capture "$HOST_LOCAL_NM_HELPER" status) || return 1
  fi
  owned_uuid=$(host_owned_nm_uuid_from_status "$status_output") || return 1
  nmcli_command=$(host_acceptance_command_path nmcli) || return 1

  # UUID and TYPE are the only fields needed. They are delimiter-safe NM
  # values, so escaped colons/newlines in a display name cannot shift fields or
  # change the identity set. Never add NAME to this query.
  output=$("$nmcli_command" -t --escape yes -f UUID,TYPE connection show --active 2>/dev/null) || return 1
  tmp=$(mktemp "${destination}.XXXXXX") || return 1
  chmod 600 "$tmp" || { rm -f -- "$tmp"; return 1; }
  while IFS= read -r line; do
    line=${line%$'\r'}
    [[ -n "$line" ]] || continue
    IFS=: read -r uuid type extra <<<"$line"
    [[ -z "$extra" && -n "$uuid" && -n "$type" ]] || { rm -f -- "$tmp"; return 1; }
    host_acceptance_uuid_is_canonical "$uuid" || { rm -f -- "$tmp"; return 1; }
    case "$type" in
      vpn|wireguard|ipsec|openvpn|strongswan) ;;
      *) continue ;;
    esac
    uuid=${uuid,,}
    [[ -n "$owned_uuid" && "$uuid" == "$owned_uuid" ]] || printf '%s\n' "$uuid" >>"$tmp"
  done <<<"$output"

  : >"$destination" || { rm -f -- "$tmp"; return 1; }
  chmod 600 "$destination" || { rm -f -- "$tmp" "$destination"; return 1; }
  if ! LC_ALL=C sort -u "$tmp" >"$destination"; then
    rm -f -- "$tmp" "$destination"
    return 1
  fi
  rm -f -- "$tmp"
}

host_snapshot_file() {
  local source=$1 destination=$2
  if [[ -L "$source" ]]; then return 1; fi
  if [[ -e "$source" ]]; then
    [[ -f "$source" ]] || return 1
    cp -- "$source" "$destination" || return 1
    chmod 600 "$destination" || return 1
    printf 'yes\n' >"$destination.present"
    stat -c '%a' -- "$source" >"$destination.mode" || return 1
  else
    printf 'no\n' >"$destination.present"
  fi
}

host_snapshot_owned_state() {
  local destination=$1 source name
  mkdir -- "$destination" "$destination/files" || return 1
  chmod 700 "$destination" "$destination/files"
  for name in networkmanager-state networkmanager-uuid networkmanager-profile-fingerprint; do
    host_snapshot_file "$HOST_LOCAL_SECRETS_DIR/state/$name" "$destination/files/$name" || return 1
  done
  host_snapshot_file "$HOST_LOCAL_SECRETS_DIR/openvpn/client/vpnkit-local.ovpn" "$destination/files/profile" || return 1
}

host_restore_snapshot_file() {
  local source=$1 target=$2 present mode parent tmp
  present=$(<"$source.present") || return 1
  parent=$(dirname -- "$target")
  [[ -d "$parent" && ! -L "$parent" ]] || {
    [[ "$present" == no ]] && return 0
    return 1
  }
  if [[ "$present" == yes ]]; then
    [[ -f "$source" && ! -L "$source" ]] || return 1
    [[ ! -L "$target" && (! -e "$target" || -f "$target") ]] || return 1
    mode=$(<"$source.mode") || return 1
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
    tmp=$(mktemp "$parent/.vpnkit-host-restore.XXXXXX") || return 1
    if ! cp -- "$source" "$tmp" || ! chmod "$mode" "$tmp" || ! mv -f -- "$tmp" "$target"; then
      rm -f -- "$tmp" || true
      return 1
    fi
  else
    [[ ! -L "$target" && (! -e "$target" || -f "$target") ]] || return 1
    rm -f -- "$target"
  fi
}

host_restore_snapshot_owned_state() {
  local source=$1
  host_restore_snapshot_file "$source/files/networkmanager-state" "$HOST_LOCAL_SECRETS_DIR/state/networkmanager-state" || return 1
  host_restore_snapshot_file "$source/files/networkmanager-uuid" "$HOST_LOCAL_SECRETS_DIR/state/networkmanager-uuid" || return 1
  host_restore_snapshot_file "$source/files/networkmanager-profile-fingerprint" "$HOST_LOCAL_SECRETS_DIR/state/networkmanager-profile-fingerprint" || return 1
  host_restore_snapshot_file "$source/files/profile" "$HOST_LOCAL_SECRETS_DIR/openvpn/client/vpnkit-local.ovpn" || return 1
}

host_snapshot_owned_state_matches() {
  local source=$1 name target present
  for name in networkmanager-state networkmanager-uuid networkmanager-profile-fingerprint profile; do
    target="$HOST_LOCAL_SECRETS_DIR/state/$name"
    [[ "$name" == profile ]] && target="$HOST_LOCAL_SECRETS_DIR/openvpn/client/vpnkit-local.ovpn"
    present=$(<"$source/files/$name.present") || return 1
    if [[ "$present" == yes ]]; then
      [[ -f "$target" && ! -L "$target" ]] || return 1
      cmp -s -- "$source/files/$name" "$target" || return 1
    else
      [[ ! -e "$target" && ! -L "$target" ]] || return 1
    fi
  done
}

HOST_ACCEPTANCE_CLEANUP_NEEDED=0
HOST_ACCEPTANCE_SNAPSHOT_DIR=
HOST_ACCEPTANCE_BEFORE_CONFIGURED=no
HOST_ACCEPTANCE_CLEANUP_FAILED=0

host_acceptance_cleanup() {
  local out cleanup_nm
  (( HOST_ACCEPTANCE_CLEANUP_NEEDED == 1 )) || return 0
  HOST_ACCEPTANCE_CLEANUP_NEEDED=0
  if out=$(run_capture host_lifecycle_run stop); then
    record PASS "host:cleanup-stop" "guarded local lifecycle stop completed"
  else
    record FAIL "host:cleanup-stop" "guarded local lifecycle stop failed"
    HOST_ACCEPTANCE_CLEANUP_FAILED=1
  fi
  # `stop` disconnects the exact owned UUID but intentionally keeps a local
  # profile for ordinary interactive use. An acceptance run that imported a
  # previously absent profile removes only that exact owned capability and
  # restores the snapshotted local files; it never adopts/deletes work VPNs.
  if [[ "$HOST_ACCEPTANCE_BEFORE_CONFIGURED" == no ]]; then
    if out=$(run_capture "$HOST_LOCAL_NM_HELPER" remove --yes); then
      :
    else
      record FAIL "host:cleanup-networkmanager" "owned local NetworkManager capability cleanup failed"
      HOST_ACCEPTANCE_CLEANUP_FAILED=1
    fi
  fi
  if [[ -n "$HOST_ACCEPTANCE_SNAPSHOT_DIR" ]] && ! host_restore_snapshot_owned_state "$HOST_ACCEPTANCE_SNAPSHOT_DIR/nm"; then
    record FAIL "host:cleanup-snapshot" "preexisting local NetworkManager state could not be restored"
    HOST_ACCEPTANCE_CLEANUP_FAILED=1
  fi
  if [[ -n "$HOST_ACCEPTANCE_SNAPSHOT_DIR" && -f "$HOST_ACCEPTANCE_SNAPSHOT_DIR/work-vpn.before" ]]; then
    if cleanup_nm=$(run_capture "$HOST_LOCAL_NM_HELPER" status) && \
        host_capture_work_vpn_set "$HOST_ACCEPTANCE_SNAPSHOT_DIR/work-vpn.after-cleanup" "$cleanup_nm" && \
        cmp -s "$HOST_ACCEPTANCE_SNAPSHOT_DIR/work-vpn.before" "$HOST_ACCEPTANCE_SNAPSHOT_DIR/work-vpn.after-cleanup"; then
      record PASS "host:cleanup-work-vpn" "active work-VPN UUID set remained unchanged after guarded cleanup"
    else
      record FAIL "host:cleanup-work-vpn" "active work-VPN UUID set changed or could not be read after guarded cleanup"
      HOST_ACCEPTANCE_CLEANUP_FAILED=1
    fi
  fi
}

host_json_value() {
  local path=$1 key=$2
  python3 - "$path" "$key" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
for component in sys.argv[2].split("."):
    value = value[component]
print(value)
PY
}

run_local_kde_host_acceptance() {
  local out before_status after_status before_nm after_nm after_start_nm start_out nm_out underlay_out
  local before_container before_configured before_active after_container after_configured after_active
  local nm_device host_smoke_out profile_ok=0 mapping_ok=0 handshake_ok=0 rules_ok=0
  local work_after_ok=0 snapshot_ok=0 start_ok=0 command_path docker_command env_command bash_command
  local result_name=$HOST_ACCEPTANCE_RESULT_NAME
  local -a required_commands=(docker nmcli ip openvpn getent curl ping timeout python3)

  if (( HOST_LOCAL_LIVE_ACCEPT == 1 && APPROVE_LOCAL_KDE_HOST != 1 )); then
    record FAIL "host:approval" "local KDE host acceptance requires --approve-local-kde-host or VPNKIT_LOCAL_KDE_HOST_APPROVED=1"
    record FAIL "$result_name" "explicit host acceptance was not approved"
    return 1
  fi
  if (( HOST_LOCAL_LIVE_ACCEPT == 1 )); then
    if ! host_acceptance_validate_canonical_sources; then
      record FAIL "$result_name" "canonical local lifecycle/helper prerequisites are unavailable"
      return 1
    fi
  elif ! host_local_helper_is_allowed networkmanager-helper "$HOST_LOCAL_NM_HELPER" || \
      ! host_local_helper_is_allowed underlay-helper "$HOST_LOCAL_UNDERLAY_HELPER"; then
    record FAIL "$result_name" "guarded local helper prerequisites are unavailable"
    return 1
  fi
  if [[ ! -x "$HOST_LOCAL_LIFECYCLE" || ! -x "$HOST_LOCAL_SMOKE" ]]; then
    record FAIL "host:prerequisite" "guarded local lifecycle or existing host smoke is unavailable"
    record FAIL "$result_name" "explicit host acceptance prerequisites are unavailable"
    return 1
  fi

  for command_name in "${required_commands[@]}"; do
    if command_path=$(host_acceptance_command_path "$command_name"); then
      record PASS "host:command-$command_name" "required host command is available"
    else
      record FAIL "host:command-$command_name" "required host command is unavailable"
    fi
  done
  docker_command=$(host_acceptance_command_path docker || true)
  env_command=$(host_acceptance_command_path env || true)
  bash_command=$(host_acceptance_command_path bash || true)
  if [[ -z "$docker_command" || -z "$env_command" || -z "$bash_command" ]]; then
    record FAIL "$result_name" "required trusted host command is unavailable"
    return 1
  fi
  if ! out=$(run_capture_timeout "$SSH_TIMEOUT" "$docker_command" info); then
    record FAIL "host:docker" "local Docker daemon is unavailable"
  else
    record PASS "host:docker" "local Docker daemon is reachable"
  fi
  if ! out=$(run_capture_timeout "$SSH_TIMEOUT" "$docker_command" compose version); then
    record FAIL "host:docker-compose" "local Docker Compose plugin is unavailable"
  else
    record PASS "host:docker-compose" "local Docker Compose plugin is reachable"
  fi
  if (( FAIL > 0 )); then
    record FAIL "$result_name" "host acceptance prerequisites are unavailable"
    return 1
  fi

  HOST_ACCEPTANCE_SNAPSHOT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vpnkit-local-host-acceptance.XXXXXX") || {
    record FAIL "host:preflight-snapshot" "could not create a private host acceptance snapshot"
    record FAIL "$result_name" "host acceptance snapshot is unavailable"
    return 1
  }
  chmod 700 "$HOST_ACCEPTANCE_SNAPSHOT_DIR"
  trap 'host_acceptance_cleanup; [[ -z "$HOST_ACCEPTANCE_SNAPSHOT_DIR" ]] || rm -rf -- "$HOST_ACCEPTANCE_SNAPSHOT_DIR"' EXIT INT TERM
  if before_status=$(run_capture host_lifecycle_run status --json) && before_nm=$(run_capture "$HOST_LOCAL_NM_HELPER" status) \
      && host_capture_work_vpn_set "$HOST_ACCEPTANCE_SNAPSHOT_DIR/work-vpn.before" "$before_nm" \
      && host_snapshot_owned_state "$HOST_ACCEPTANCE_SNAPSHOT_DIR/nm"; then
    printf '%s\n' "$before_status" >"$HOST_ACCEPTANCE_SNAPSHOT_DIR/lifecycle.before.json"
    printf '%s\n' "$before_nm" >"$HOST_ACCEPTANCE_SNAPSHOT_DIR/nm.before"
    chmod 600 "$HOST_ACCEPTANCE_SNAPSHOT_DIR/lifecycle.before.json" "$HOST_ACCEPTANCE_SNAPSHOT_DIR/nm.before"
    snapshot_ok=1
    record PASS "host:preflight-snapshot" "preexisting local stack, NetworkManager capability, and work-VPN identity set snapshotted"
  else
    record FAIL "host:preflight-snapshot" "preexisting local stack or NetworkManager state could not be snapshotted"
  fi
  if (( snapshot_ok == 0 )); then
    record FAIL "$result_name" "host acceptance snapshot is unavailable"
    return 1
  fi

  before_container=$(host_json_value "$HOST_ACCEPTANCE_SNAPSHOT_DIR/lifecycle.before.json" container 2>/dev/null || true)
  before_configured=$(host_json_value "$HOST_ACCEPTANCE_SNAPSHOT_DIR/lifecycle.before.json" networkmanager.configured 2>/dev/null || true)
  before_active=$(host_json_value "$HOST_ACCEPTANCE_SNAPSHOT_DIR/lifecycle.before.json" networkmanager.active 2>/dev/null || true)
  HOST_ACCEPTANCE_BEFORE_CONFIGURED=$before_configured
  if [[ "$before_container" != absent || "$before_active" == yes ]]; then
    record FAIL "host:preexisting-local-state" "acceptance requires a stopped local stack and inactive vpnkit-local profile"
    record FAIL "$result_name" "preexisting local state was not safe to mutate"
    return 1
  fi

  # The trap covers failures after the guarded lifecycle is invoked. The
  # lifecycle itself has its own transaction rollback for failed start; this
  # final stop restores the successful acceptance path.
  HOST_ACCEPTANCE_CLEANUP_NEEDED=1
  trap 'host_acceptance_cleanup; [[ -z "$HOST_ACCEPTANCE_SNAPSHOT_DIR" ]] || rm -rf -- "$HOST_ACCEPTANCE_SNAPSHOT_DIR"' EXIT INT TERM
  if start_out=$(run_capture host_lifecycle_run start); then
    if [[ "$start_out" == *'container_state=healthy'* && "$start_out" == *'host_smoke=pass'* && "$start_out" == *'networkmanager=connected'* && "$start_out" == *'transaction_snapshot=complete'* && "$start_out" == *'active_work_vpn_set=unchanged'* ]]; then
      start_ok=1
      record PASS "host:lifecycle-start" "guarded local lifecycle reached healthy OpenVPN/NM readiness"
    else
      record FAIL "host:lifecycle-start" "guarded local lifecycle omitted required healthy/NM readiness markers"
    fi
  else
    record FAIL "host:lifecycle-start" "guarded local lifecycle start failed"
  fi

  if [[ -r "$TEST_PROFILE" ]] && awk -v port="$HOST_LOCAL_PORT" '
      $1 == "remote" { count++; if ($2 == "127.0.0.1" && $3 == port) found=1 }
      END { exit !(count == 1 && found == 1) }
    ' "$TEST_PROFILE"; then
    profile_ok=1
    record PASS "host:localhost-udp-profile" "owned OpenVPN profile uses 127.0.0.1 and the published UDP port"
  else
    record FAIL "host:localhost-udp-profile" "owned OpenVPN profile is not an exact 127.0.0.1 UDP published-port profile"
  fi

  if nm_out=$(run_capture "$HOST_LOCAL_NM_HELPER" verify); then
    nm_device=$(awk -F= '$1 == "device" { print $2; exit }' <<<"$nm_out")
    if [[ "$nm_out" == *'networkmanager_mapping=pass'* && "$nm_out" == *'owned_uuid_ip4_tun=pass'* ]]; then
      mapping_ok=1
      record PASS "host:owned-uuid-ip4-tun" "exact owned UUID to active IPv4 to tun mapping passed"
    else
      record FAIL "host:owned-uuid-ip4-tun" "exact owned UUID to active IPv4 to tun mapping was not proven"
    fi
    if [[ "$nm_out" == *'openvpn_handshake=pass'* ]]; then
      handshake_ok=1
      record PASS "host:openvpn-handshake" "NetworkManager reported the exact owned OpenVPN tunnel ready"
    else
      record FAIL "host:openvpn-handshake" "exact owned OpenVPN handshake evidence was not reported"
    fi
  else
    record FAIL "host:owned-uuid-ip4-tun" "guarded NetworkManager mapping verification failed"
    record FAIL "host:openvpn-handshake" "guarded NetworkManager handshake verification failed"
  fi

  if underlay_out=$(run_capture "$HOST_LOCAL_UNDERLAY_HELPER" verify); then
    if [[ "$underlay_out" == *'destination_lookup_rule=pass'* && "$underlay_out" == *'destination_fail_closed_rule=pass'* && "$underlay_out" == *'lookup_rule=pass'* && "$underlay_out" == *'fail_closed_rule=pass'* && "$underlay_out" == *'rule_order=pass'* ]] && \
        grep -Fqx 'canonical_priorities=ok' <<<"$underlay_out"; then
      rules_ok=1
      record PASS "host:destination-rules" "destination lookup/fail-closed routing and canonical priorities passed"
    else
      record FAIL "host:destination-rules" "destination routing verification omitted required pass markers"
    fi
  else
    record FAIL "host:destination-rules" "guarded destination routing rule verification failed"
  fi

  if (( mapping_ok == 1 )) && [[ "$nm_device" =~ ^tun[A-Za-z0-9_.-]{1,14}$ ]]; then
    if host_smoke_out=$(run_capture "$env_command" PATH="${HOST_TRUSTED_PATH:-$PATH}" VPNKIT_LOCAL_SMOKE_DEVICE="$nm_device" "$bash_command" "$HOST_LOCAL_SMOKE"); then
      if [[ "$host_smoke_out" == *'host_smoke=pass'* ]]; then
        record PASS "host:existing-host-smoke" "existing host smoke passed on the exact owned tunnel"
      else
        record FAIL "host:existing-host-smoke" "existing host smoke omitted its pass marker"
      fi
    else
      record FAIL "host:existing-host-smoke" "existing host smoke failed"
    fi
  else
    record FAIL "host:existing-host-smoke" "existing host smoke was not run without an exact owned tun mapping"
  fi

  if after_start_nm=$(run_capture "$HOST_LOCAL_NM_HELPER" status) && \
      host_capture_work_vpn_set "$HOST_ACCEPTANCE_SNAPSHOT_DIR/work-vpn.after-start" "$after_start_nm" && \
      cmp -s "$HOST_ACCEPTANCE_SNAPSHOT_DIR/work-vpn.before" "$HOST_ACCEPTANCE_SNAPSHOT_DIR/work-vpn.after-start"; then
    record PASS "host:work-vpn-set" "active work-VPN identity set remained unchanged during start"
  else
    record FAIL "host:work-vpn-set" "active work-VPN identity set changed or could not be read"
  fi

  host_acceptance_cleanup
  trap - EXIT INT TERM
  if after_status=$(run_capture host_lifecycle_run status --json) && after_nm=$(run_capture "$HOST_LOCAL_NM_HELPER" status) && \
      host_capture_work_vpn_set "$HOST_ACCEPTANCE_SNAPSHOT_DIR/work-vpn.after-stop" "$after_nm"; then
    printf '%s\n' "$after_status" >"$HOST_ACCEPTANCE_SNAPSHOT_DIR/lifecycle.after.json"
    printf '%s\n' "$after_nm" >"$HOST_ACCEPTANCE_SNAPSHOT_DIR/nm.after"
    chmod 600 "$HOST_ACCEPTANCE_SNAPSHOT_DIR/lifecycle.after.json" "$HOST_ACCEPTANCE_SNAPSHOT_DIR/nm.after"
    after_container=$(host_json_value "$HOST_ACCEPTANCE_SNAPSHOT_DIR/lifecycle.after.json" container 2>/dev/null || true)
    after_configured=$(host_json_value "$HOST_ACCEPTANCE_SNAPSHOT_DIR/lifecycle.after.json" networkmanager.configured 2>/dev/null || true)
    after_active=$(host_json_value "$HOST_ACCEPTANCE_SNAPSHOT_DIR/lifecycle.after.json" networkmanager.active 2>/dev/null || true)
    if [[ "$after_container" == "$before_container" && "$after_configured" == "$before_configured" && "$after_active" == "$before_active" ]] && \
        cmp -s "$HOST_ACCEPTANCE_SNAPSHOT_DIR/nm.before" "$HOST_ACCEPTANCE_SNAPSHOT_DIR/nm.after" && \
        host_snapshot_owned_state_matches "$HOST_ACCEPTANCE_SNAPSHOT_DIR/nm" && \
        cmp -s "$HOST_ACCEPTANCE_SNAPSHOT_DIR/work-vpn.before" "$HOST_ACCEPTANCE_SNAPSHOT_DIR/work-vpn.after-stop"; then
      record PASS "host:postcondition" "preexisting local and work-VPN state was restored"
      work_after_ok=1
    else
      record FAIL "host:postcondition" "preexisting local or work-VPN state was not restored"
    fi
  else
    record FAIL "host:postcondition" "post-stop local or work-VPN state could not be read"
  fi
  rm -rf -- "$HOST_ACCEPTANCE_SNAPSHOT_DIR"
  HOST_ACCEPTANCE_SNAPSHOT_DIR=

  if (( start_ok == 1 && profile_ok == 1 && mapping_ok == 1 && handshake_ok == 1 && rules_ok == 1 && work_after_ok == 1 && HOST_ACCEPTANCE_CLEANUP_FAILED == 0 && FAIL == 0 )); then
    record PASS "$result_name" "guarded lifecycle, NM mapping, OpenVPN handshake, destination rules, work-VPN preservation, and host smoke passed"
    return 0
  fi
  record FAIL "$result_name" "local KDE host acceptance did not satisfy every required readiness gate"
  return 1
}

run_local_kde_host_contract() {
  if [[ "${VPNKIT_LOCAL_TEST_FIXTURE:-0}" != 1 ]]; then
    # `test` is never a live alias.  Without the explicit fixture capability
    # it stops here, before command discovery, Docker, NetworkManager, route
    # probes, or the guarded lifecycle can be reached.
    record FAIL "$HOST_ACCEPTANCE_RESULT_NAME" "non-fixture local KDE --action test refuses before lifecycle/Docker/NetworkManager mutation; use an explicit mock fixture"
    return 1
  fi
  run_local_kde_host_acceptance
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

if [[ "$SCENARIO" == local-kde-host ]]; then
  host_acceptance_rc=0
  if [[ "$ACTION" == test ]]; then
    run_local_kde_host_contract || host_acceptance_rc=$?
  else
    run_local_kde_host_acceptance || host_acceptance_rc=$?
  fi
  [[ -z "$HOST_ACCEPTANCE_SNAPSHOT_DIR" ]] || rm -rf -- "$HOST_ACCEPTANCE_SNAPSHOT_DIR"
  if (( host_acceptance_rc == 0 && FAIL == 0 )); then
    finish_runner_early 0
  else
    finish_runner_early 1
  fi
fi

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
      if ! local_docker_invalidate_provenance; then
        record FAIL "lifecycle:provenance" "isolated local Docker project was removed but its freshness record could not be invalidated"
        return 1
      fi
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
    # A new up/build is a new deployment candidate. Remove any prior record
    # before its first mutation so a failed/partial attempt can never leave a
    # stale record that makes a later standalone `test` green.
    if ! local_docker_invalidate_provenance; then
      record FAIL "lifecycle:up-safety" "refusing local Docker start: $local_safety_error"
      return 1
    fi
    if out=$(run_capture env VPNKIT_TEST_LAB_SECRETS_DIR="$LOCAL_SCENARIO_DIR" VPNKIT_TEST_LAB_ENDPOINT=vpnkit VPNKIT_TEST_LAB_PORT=1194 VPNKIT_ROUTING_MODE=tun VPNKIT_RULESET_SOURCE_MODE=local-fixture VPNKIT_SELECTED_OUTBOUND_MODE=direct-fixture VPNKIT_OPENVPN_PUSH_DNS=8.8.8.8 "$REPO_ROOT/scripts/vpnkit/vpnkit-test-lab-setup.sh") \
      && render_out=$(run_capture env VPNKIT_LOCAL_SECRETS_DIR="$LOCAL_SCENARIO_DIR" VPNKIT_LOCAL_TEST_FIXTURE=1 VPNKIT_LOCAL_ALLOW_MISSING_SUBSCRIPTION=true VPNKIT_LOCAL_POLICY=strict VPNKIT_RULESET_SOURCE_MODE=local-fixture VPNKIT_SELECTED_OUTBOUND_MODE=direct-fixture "$REPO_ROOT/scripts/vpnkit/vpnkit-render-local-kde-configs.sh"); then
      if ! local_compose_resources_owned; then
        record FAIL "lifecycle:up-safety" "refusing local Docker start after fixture setup/render: $local_safety_error"
        return 1
      fi
      printf '%s\n' "$out"
      printf '%s\n' "$render_out"
      record PASS "lifecycle:prepare" "generated isolated local Docker fixture artifacts with local DNS policy"
    else
      printf '%s\n' "${out:-}"
      printf '%s\n' "${render_out:-}"
      record FAIL "lifecycle:prepare" "local Docker fixture setup or local policy render failed"
      return 1
    fi
    if ! local_compose_resources_owned; then
      record FAIL "lifecycle:up-safety" "refusing local Docker start immediately before Compose up: $local_safety_error"
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
        if ! local_docker_persist_provenance "$SERVER_CONTAINER"; then
          record FAIL "lifecycle:provenance" "isolated local Docker deploy completed without a fresh source/config/image/container provenance record"
          return 1
        fi
        record PASS "lifecycle:provenance" "isolated local Docker source/config and deployed image/container freshness recorded"
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
  if [[ "$SCENARIO" == local-docker ]] && ! ensure_local_docker_prerequisite; then
    if [[ "$ACTION" != test ]]; then
      finish_runner_early 1
    fi
  fi
  if [[ "$SCENARIO" == steamdeck-host ]] && ! ensure_steamdeck_prerequisite; then
    if [[ "$ACTION" != test ]]; then
      finish_runner_early 1
    fi
  fi
  case "$ACTION" in
    down)
      run_lifecycle_down
      (( FAIL == 0 )) && finish_runner_early 0 || finish_runner_early 1
      ;;
    up)
      run_lifecycle_up
      (( FAIL == 0 )) && finish_runner_early 0 || finish_runner_early 1
      ;;
    cycle)
      if ! run_lifecycle_down; then
        finish_runner_early 1
      fi
      run_lifecycle_up || true
      if [[ $FAIL -gt 0 ]]; then finish_runner_early 1; fi
      ;;
    test) ;;
  esac
fi

LOCAL_DOCKER_FRESHNESS_READY=0
if [[ "$SCENARIO" == "local-docker" && "$LOCAL_DOCKER_PREREQ_READY" == 1 ]]; then
  set_local_container
fi
# A standalone local-docker test is read-only with respect to deployment, but
# it is not allowed to infer freshness from a running container alone. The
# record must match current nonignored source, resolved Compose config, image,
# and container identity. Cycle uses the same gate after its successful up.
if [[ "$SCENARIO" == "local-docker" && ( "$ACTION" == test || "$ACTION" == cycle ) ]]; then
  if [[ "$LOCAL_DOCKER_PREREQ_READY" != 1 ]]; then
    record FAIL "lifecycle:test-freshness" "Docker readiness failed; standalone local-docker freshness is not proven"
  elif local_docker_verify_freshness; then
    LOCAL_DOCKER_FRESHNESS_READY=1
    record PASS "lifecycle:test-freshness" "source/config provenance and deployed image/container identity match"
  else
    record FAIL "lifecycle:test-freshness" "local-docker deployment is not fresh: ${local_safety_error:-provenance or deployed identity mismatch}"
  fi
fi

if [[ "$SCENARIO" == "steamdeck-host" && "$ACTION" == "test" ]]; then
  if [[ "$SERVER_CONTAINER" == "vpnkit" ]]; then
    record FAIL "lifecycle:test-safety" "refusing to test default/prod container name vpnkit for explicit steamdeck-host scenario"
  fi
  if [[ -z "$TEST_ENDPOINT" || "$endpoint_state" == "placeholder" ]]; then
    record FAIL "lifecycle:prereq-endpoint" "steamdeck-host requires non-placeholder VPNKIT_TEST_ENDPOINT or VPNKIT_STEAMDECK_LAN_ENDPOINT for live client smoke (source=$selected_endpoint_source)"
  fi
fi

# Server checks: explicit live scenarios treat unavailable required readiness
# gates as FAIL. Dependent diagnostics may still remain SKIP so later checks
# are attempted without turning an unavailable acceptance into green.
server_ready=0
if [[ "$SCENARIO" == "local-docker" ]]; then
  if [[ "$LOCAL_DOCKER_PREREQ_READY" == 1 && "$LOCAL_DOCKER_FRESHNESS_READY" == 1 ]]; then
    server_ready=1
  fi
elif [[ "$SCENARIO" == "steamdeck-host" && "$STEAMDECK_PREREQ_READY" == 1 ]]; then
  server_ready=1
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
    if [[ "$SCENARIO" == steamdeck-host ]]; then
      record FAIL "server:container-running" "cannot inspect the configured remote runtime/container"
    else
      record SKIP "server:container-running" "cannot inspect container/runtime: $out"
    fi
  fi
else
  if [[ "$SCENARIO" == local-docker && "$LOCAL_DOCKER_PREREQ_READY" != 1 ]]; then
    record FAIL "server:container-running" "required local Docker readiness gate failed"
  elif [[ "$SCENARIO" == local-docker && "$LOCAL_DOCKER_FRESHNESS_READY" != 1 ]]; then
    record FAIL "server:container-running" "required local Docker freshness gate failed"
  elif [[ "$SCENARIO" == steamdeck-host && "$STEAMDECK_PREREQ_READY" != 1 ]]; then
    record FAIL "server:container-running" "required SSH/runtime readiness gate failed"
  else
    record SKIP "server:container-running" "server runtime unavailable"
  fi
fi

# Local Docker inspection and exec are also mutating trust-boundary surfaces:
# prove the selected Compose resource set before allowing any container
# diagnostics. Remote Steam Deck checks use their separate isolated Podman
# path and are intentionally unchanged.
if [[ "$SCENARIO" == "local-docker" && $server_ready -eq 1 ]]; then
  if ! local_compose_resources_owned; then
    record FAIL "lifecycle:test-safety" "refusing local Docker inspection/exec: $local_safety_error"
    server_ready=0
    container_ready=0
  fi
fi

check_exec_contains() {
  local name=$1 cmd=$2 needle=$3 missing_status=${4:-FAIL} out
  if [[ $container_ready -ne 1 ]]; then record SKIP "$name" "server container unavailable"; return; fi
  if out=$(run_capture container_exec "$cmd"); then
    if [[ "$out" == *"$needle"* ]]; then record PASS "$name" "found $needle"; else record "$missing_status" "$name" "expected '$needle' not observed: $out"; fi
  else
    rc=$?
    if [[ "$SCENARIO" == local-docker && "$rc" -eq 125 ]]; then
      record FAIL "$name" "refusing local Docker exec after ownership recheck: ${local_safety_error:-ownership recheck failed}"
    else
      record SKIP "$name" "check command unavailable/failed: $out"
    fi
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
  LOCAL_CLIENT_NETWORK_NAME=$client_network
  LOCAL_CLIENT_CONTAINER_NAME=$client_name
  client_alias=vpnkit-test-server
  smoke_dir="$LOCAL_SCENARIO_DIR/client-smoke"
  smoke_profile="$smoke_dir/test-client.ovpn"
  local_client_cleanup() {
    local id
    # Revalidate the complete Compose/client capability before every cleanup
    # boundary. The client scope and the full project set can change between
    # any two Docker calls made by this runner.
    local_compose_resources_owned || return 1
    local_client_cleanup_scope_owned "$client_name" "$client_network" "$SERVER_CONTAINER" "$smoke_dir" || return 1
    if id=$(docker container inspect -f '{{.Id}}' "$client_name" 2>/dev/null); then
      local_client_cleanup_scope_owned "$client_name" "$client_network" "$SERVER_CONTAINER" "$smoke_dir" || return 1
      local_compose_resources_owned || return 1
      docker rm -f "$id" >/dev/null 2>&1 || return 1
    fi
    if id=$(docker network inspect -f '{{.Id}}' "$client_network" 2>/dev/null); then
      local_client_cleanup_scope_owned "$client_name" "$client_network" "$SERVER_CONTAINER" "$smoke_dir" || return 1
      local_compose_resources_owned || return 1
      docker network disconnect -f "$id" "$SERVER_CONTAINER" >/dev/null 2>&1 || true
      local_client_cleanup_scope_owned "$client_name" "$client_network" "$SERVER_CONTAINER" "$smoke_dir" || return 1
      local_compose_resources_owned || return 1
      docker network rm "$id" >/dev/null 2>&1 || return 1
    fi
    local_compose_resources_owned || return 1
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
    if ! local_compose_resources_owned; then
      record FAIL "client:local-docker-cleanup-safety" "refusing local client network creation after ownership recheck: $local_safety_error"
    elif ! out=$(run_capture docker network create --label "com.docker.compose.project=$LOCAL_PROJECT" --label "com.vpnkit.local.owner=$LOCAL_TEST_OWNER_LABEL" --label com.vpnkit.local.resource=client-smoke --subnet "$client_subnet" "$client_network"); then
      record FAIL "client:local-docker-profile-smoke" "isolated client network creation failed: $out"
    elif ! local_compose_resources_owned; then
      record FAIL "client:local-docker-cleanup-safety" "refusing local client network connect after ownership recheck: $local_safety_error"
    elif ! out=$(run_capture docker network connect --alias "$client_alias" "$client_network" "$SERVER_CONTAINER"); then
      record FAIL "client:local-docker-profile-smoke" "isolated server/client network attachment failed: $out"
    else
      client_image=$("${LOCAL_COMPOSE[@]}" --profile test config --images | grep -- '-ovpn-client-test$' | head -1 || true)
      if [[ -z "$client_image" ]]; then
        record FAIL "client:local-docker-profile-smoke" "OpenVPN client test image name was not resolved"
      elif ! local_compose_resources_owned; then
        record FAIL "client:local-docker-cleanup-safety" "refusing client-image build after ownership recheck: $local_safety_error"
      # Always ask Compose to build: layer caching keeps this cheap while
      # guaranteeing that required evidence rows come from the current source,
      # not a stale same-tag client image left by an earlier acceptance run.
      elif ! out=$(run_capture_timeout "$DEPLOY_TIMEOUT" "${LOCAL_COMPOSE[@]}" --profile test build ovpn-client-test); then
        record FAIL "client:local-docker-profile-smoke" "OpenVPN client test image build failed: $out"
      elif ! docker image inspect "$client_image" >/dev/null 2>&1; then
        record FAIL "client:local-docker-profile-smoke" "OpenVPN client test image was not resolved after build"
      elif ! local_compose_resources_owned; then
        record FAIL "client:local-docker-cleanup-safety" "refusing local client docker run after ownership recheck: $local_safety_error"
      elif out=$(run_capture_timeout "$CLIENT_TIMEOUT" docker run --rm --name "$client_name" --label "com.docker.compose.project=$LOCAL_PROJECT" --label "com.vpnkit.local.owner=$LOCAL_TEST_OWNER_LABEL" --label "com.docker.compose.project.working_dir=$REPO_ROOT" --label com.vpnkit.local.resource=client-smoke --network "$client_network" --cap-add NET_ADMIN --cap-add NET_RAW --device /dev/net/tun -e VPNKIT_NESTED_VPN_ENABLED=0 -v "$smoke_dir:/etc/openvpn/client:ro" "$client_image" /etc/openvpn/client/test-client.ovpn); then
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

[[ -z "${LOG_FD:-}" ]] || exec {LOG_FD}>&-
exec 1>&- 2>&-
wait || true
if [[ $FAIL -gt 0 ]]; then exit 1; fi
exit 0
