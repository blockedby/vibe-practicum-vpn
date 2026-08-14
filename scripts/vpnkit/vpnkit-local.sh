#!/usr/bin/env bash
# Non-privileged local vpnkit lifecycle adapter for the issue #40 TUI.
set -Eeuo pipefail
umask 077

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)
LOCAL_ENV=${VPNKIT_LOCAL_ENV_FILE:-$REPO_ROOT/config/vpnkit-local.local.env}
if [[ -r "$LOCAL_ENV" ]]; then
  set -a
  # Operator-owned, gitignored file. Subscription/auth values still belong in secrets/.
  # shellcheck disable=SC1090
  . "$LOCAL_ENV"
  set +a
fi

BASE_INPUT=${VPNKIT_LOCAL_SECRETS_DIR:-$REPO_ROOT/secrets/vpnkit-local}
case "$BASE_INPUT" in /*) BASE_REQUEST=$BASE_INPUT ;; *) BASE_REQUEST="$REPO_ROOT/$BASE_INPUT" ;; esac
PROJECT=${VPNKIT_LOCAL_COMPOSE_PROJECT:-vpnkit-local}

# This adapter is deliberately narrower than Compose itself.  A local command
# must never be able to turn an environment typo into a production project or
# an unrelated secret root.  Validation happens before COMPOSE is assembled or
# any helper is allowed to create files.
path_has_symlink() {
  local path=$1 current=/ part
  local -a parts=()
  IFS=/ read -r -a parts <<<"${path#/}"
  for part in "${parts[@]}"; do
    [[ -n "$part" && "$part" != . ]] || continue
    if [[ "$part" == .. ]]; then
      current=${current%/*}
      [[ -n "$current" ]] || current=/
      continue
    fi
    [[ "$current" == / ]] && current="/$part" || current="$current/$part"
    [[ -L "$current" ]] && return 0
  done
  return 1
}

validate_project_identity() {
  [[ "$PROJECT" =~ ^vpnkit-local(-[a-z0-9][a-z0-9_-]{0,31})?$ ]] || {
    echo 'VPNKIT_LOCAL_COMPOSE_PROJECT must be vpnkit-local or a vpnkit-local-* test project' >&2
    return 20
  }
  case "$PROJECT" in
    *-prod*|*-production*|*-live*)
      echo 'refusing production-like local Docker project identity' >&2
      return 20
      ;;
  esac
}

validate_secret_root_identity() {
  local local_root="$REPO_ROOT/secrets/vpnkit-local"
  local labs_root="$REPO_ROOT/secrets/vpnkit-labs"
  local existing

  path_has_symlink "$BASE_REQUEST" && {
    echo 'VPNKIT_LOCAL_SECRETS_DIR must not contain symlink components' >&2
    return 20
  }
  BASE=$(realpath -m -- "$BASE_REQUEST") || {
    echo 'VPNKIT_LOCAL_SECRETS_DIR could not be canonicalized' >&2
    return 20
  }
  case "$BASE" in
    "$local_root"|"$local_root"/*) ;;
    "$labs_root"/*) ;;
    /tmp/vpnkit-local-*|/var/tmp/vpnkit-local-*) ;;
    /tmp/*|/var/tmp/*)
      [[ "${VPNKIT_LOCAL_TEST_FIXTURE:-}" == 1 ]] || {
        echo 'unprefixed temporary secret roots require VPNKIT_LOCAL_TEST_FIXTURE=1' >&2
        return 20
      }
      ;;
    *)
      echo 'VPNKIT_LOCAL_SECRETS_DIR must stay in the local, isolated lab, or test temporary tree' >&2
      return 20
      ;;
  esac
  [[ "$BASE" != /tmp && "$BASE" != /var/tmp && "$BASE" != "$labs_root" && "$BASE" != /tmp/vpnkit-local- && "$BASE" != /var/tmp/vpnkit-local- ]] || {
    echo 'VPNKIT_LOCAL_SECRETS_DIR is too broad' >&2
    return 20
  }
  path_has_symlink "$BASE" && {
    echo 'VPNKIT_LOCAL_SECRETS_DIR must not resolve through a symlink' >&2
    return 20
  }

  if [[ -e "$BASE" || -L "$BASE" ]]; then
    [[ -d "$BASE" && ! -L "$BASE" && -O "$BASE" ]] || {
      echo 'VPNKIT_LOCAL_SECRETS_DIR must be an owned directory' >&2
      return 20
    }
  else
    existing=$BASE
    while [[ ! -e "$existing" && ! -L "$existing" && "$existing" != / ]]; do
      existing=${existing%/*}
      [[ -n "$existing" ]] || existing=/
    done
    [[ -d "$existing" && ! -L "$existing" ]] || {
      echo 'VPNKIT_LOCAL_SECRETS_DIR parent is not a directory' >&2
      return 20
    }
  fi
}

validate_local_subtree_identities() {
  local suffix
  for suffix in \
    state vibe-vpn openvpn openvpn/pki openvpn/server openvpn/client \
    rendered rendered/openvpn rendered/sing-box rendered/vibe-vpn; do
    path_has_symlink "$BASE/$suffix" && {
      echo 'local secret subtree must not contain symlink components' >&2
      return 20
    }
  done
  return 0
}

validate_project_identity || exit $?
validate_secret_root_identity || exit $?
validate_local_subtree_identities || exit $?

PORT=${VPNKIT_LOCAL_OPENVPN_PORT:-21194}
ENDPOINT=${VPNKIT_LOCAL_ENDPOINT:-127.0.0.1}
PUSH_DNS=${VPNKIT_LOCAL_OPENVPN_PUSH_DNS:-8.8.8.8}
POLICY_FILE="$BASE/state/routing-policy"
BOOT_TIMEOUT=${VPNKIT_LOCAL_BOOT_TIMEOUT_SECONDS:-900}
RETEST_TIMEOUT=${VPNKIT_LOCAL_RETEST_TIMEOUT_SECONDS:-180}
MANAGE_NETWORKMANAGER=${VPNKIT_LOCAL_MANAGE_NETWORKMANAGER:-true}
UNDERLAY_HELPER="$REPO_ROOT/scripts/vpnkit/vpnkit-local-underlay-routing.sh"
NM_HELPER="$REPO_ROOT/scripts/vpnkit/vpnkit-local-networkmanager.sh"
HOST_SMOKE=${VPNKIT_LOCAL_HOST_SMOKE_SCRIPT:-$REPO_ROOT/scripts/vpnkit/vpnkit-local-host-smoke.sh}
SINGBOX_RESTART_FILE=${VPNKIT_LOCAL_SINGBOX_RESTART_FILE:-/run/vpnkit/restart-sing-box}
SINGBOX_GENERATION_FILE=${VPNKIT_LOCAL_SINGBOX_GENERATION_FILE:-/run/vpnkit/sing-box-generation}

# Tests may use a fake helper, but only as an explicitly marked fixture wholly
# inside the already-validated temporary secret root.  There is no production
# override for the NetworkManager or underlay helper identities.
validate_test_fixture_helpers() {
  local candidate
  if [[ -n "${VPNKIT_LOCAL_TEST_NM_HELPER:-}" ]]; then
    [[ "${VPNKIT_LOCAL_TEST_FIXTURE:-}" == 1 && ( "$BASE" == /tmp/* || "$BASE" == /var/tmp/* ) ]] || {
      echo 'VPNKIT_LOCAL_TEST_NM_HELPER requires a temporary fixture root' >&2
      return 20
    }
    candidate=$VPNKIT_LOCAL_TEST_NM_HELPER
    path_has_symlink "$candidate" && return 20
    candidate=$(realpath -m -- "$candidate") || return 20
    [[ "$candidate" == "$BASE/"* && -x "$candidate" && ! -L "$candidate" ]] || {
      echo 'test NetworkManager helper must be executable inside the local test root' >&2
      return 20
    }
    path_has_symlink "$candidate" && return 20
    NM_HELPER=$candidate
  fi
  if [[ -n "${VPNKIT_LOCAL_TEST_UNDERLAY_HELPER:-}" ]]; then
    [[ "${VPNKIT_LOCAL_TEST_FIXTURE:-}" == 1 && ( "$BASE" == /tmp/* || "$BASE" == /var/tmp/* ) ]] || {
      echo 'VPNKIT_LOCAL_TEST_UNDERLAY_HELPER requires a temporary fixture root' >&2
      return 20
    }
    candidate=$VPNKIT_LOCAL_TEST_UNDERLAY_HELPER
    path_has_symlink "$candidate" && return 20
    candidate=$(realpath -m -- "$candidate") || return 20
    [[ "$candidate" == "$BASE/"* && -x "$candidate" && ! -L "$candidate" ]] || {
      echo 'test underlay helper must be executable inside the local test root' >&2
      return 20
    }
    path_has_symlink "$candidate" && return 20
    UNDERLAY_HELPER=$candidate
  fi
}
validate_test_fixture_helpers || exit $?
COMPOSE=(docker compose -p "$PROJECT" -f "$REPO_ROOT/docker-compose.yml" -f "$REPO_ROOT/compose.local.yaml")
NM_CONFIGURED=unavailable
NM_ACTIVE=unavailable
NM_DEVICE=unavailable

export VPNKIT_LOCAL_SECRETS_DIR="$BASE"
# Do not allow an inherited profile override to redirect the fixed local NM
# helper outside this validated secret root.
export VPNKIT_LOCAL_PROFILE="$BASE/openvpn/client/vpnkit-local.ovpn"
export VPNKIT_LOCAL_NM_CONNECTION=vpnkit-local
export VPNKIT_OPENVPN_BIND_ADDRESS=127.0.0.1
export VPNKIT_OPENVPN_PORT="$PORT"
export VPNKIT_BOOTSTRAP_PICK_ON_START=${VPNKIT_BOOTSTRAP_PICK_ON_START:-true}

sync_local_path() {
  local path=$1
  # Python gives us O_NOFOLLOW and a real fsync for both regular files and the
  # containing directory.  Minimal lab images may not have Python; in that
  # case a policy commit remains atomic, but durability is best effort.
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$path" >/dev/null 2>&1 <<'PY'
import os
import sys

path = sys.argv[1]
flags = os.O_RDONLY
if hasattr(os, "O_NOFOLLOW"):
    flags |= os.O_NOFOLLOW
if os.path.isdir(path) and hasattr(os, "O_DIRECTORY"):
    flags |= os.O_DIRECTORY
fd = os.open(path, flags)
try:
    os.fsync(fd)
finally:
    os.close(fd)
PY
    return $?
  fi
  return 0
}

atomic_policy_restore() {
  local source=$1 target=$2
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$source" "$target" >/dev/null 2>&1 <<'PY' && return 0
import os
import sys

source, target = sys.argv[1:]
if os.path.islink(source):
    raise SystemExit(1)
os.replace(source, target)
PY
  fi
  mv -f -- "$source" "$target"
}

unlink_policy_no_follow() {
  local path=$1
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$path" >/dev/null 2>&1 <<'PY' && return 0
import os
import sys

path = sys.argv[1]
try:
    os.unlink(path)
except FileNotFoundError:
    pass
PY
  fi
  rm -f -- "$path"
}

policy_path_is_safe() {
  [[ ! -L "$BASE/state" ]] || {
    echo 'local routing policy directory must not be a symlink' >&2
    return 1
  }
  if [[ -e "$BASE/state" && ! -d "$BASE/state" ]]; then
    echo 'local routing policy directory must be a directory' >&2
    return 1
  fi
  [[ ! -L "$POLICY_FILE" ]] || {
    echo 'local routing policy must not be a symlink' >&2
    return 1
  }
  if [[ -e "$POLICY_FILE" && ! -f "$POLICY_FILE" ]]; then
    echo 'local routing policy must be a regular file' >&2
    return 1
  fi
}

safe_policy() {
  local value=${VPNKIT_LOCAL_POLICY:-}
  policy_path_is_safe || return 2
  if [[ -r "$POLICY_FILE" ]]; then value=$(<"$POLICY_FILE") || return 1; fi
  case "$value" in strict|smart) printf '%s\n' "$value" ;; '') printf 'strict\n' ;; *) echo 'invalid local routing policy state' >&2; return 2 ;; esac
}

policy_state_dir_for_write() {
  [[ ! -L "$BASE" ]] || return 1
  if [[ ! -e "$BASE" ]]; then
    mkdir -- "$BASE" || return 1
  fi
  [[ -d "$BASE" && ! -L "$BASE" ]] || return 1
  chmod 700 "$BASE" || return 1

  [[ ! -L "$BASE/state" ]] || return 1
  if [[ ! -e "$BASE/state" ]]; then
    mkdir -- "$BASE/state" || return 1
  fi
  [[ -d "$BASE/state" && ! -L "$BASE/state" ]] || return 1
  chmod 700 "$BASE/state" || return 1
}

remove_policy() {
  policy_path_is_safe || return 1
  [[ -e "$POLICY_FILE" ]] || return 0
  rm -f -- "$POLICY_FILE" || return 1
  sync_local_path "$BASE/state" || return 1
}

write_policy() {
  local value=$1 stage='' backup='' rollback_failed=0
  case "$value" in strict|smart) ;; *) return 2 ;; esac
  policy_state_dir_for_write || return 1
  policy_path_is_safe || return 1

  # Stage in the policy's directory so the final mv is a same-filesystem
  # rename.  The old inode is held by a hard link until the directory fsync
  # succeeds; this lets a post-rename durability failure restore exact prior
  # bytes and mode without following a policy symlink.
  stage=$(mktemp "$BASE/state/.routing-policy.XXXXXX") || return 1
  if ! [[ -f "$stage" && ! -L "$stage" ]]; then
    rm -f -- "$stage" || true
    return 1
  fi
  if ! printf '%s\n' "$value" >"$stage"; then
    rm -f -- "$stage" || true
    return 1
  fi
  # chmod is intentionally before rename.  A failure here leaves the old
  # policy inode untouched and the staged file is removed below.
  if ! chmod 600 "$stage" || ! sync_local_path "$stage"; then
    rm -f -- "$stage" || true
    return 1
  fi

  if [[ -e "$POLICY_FILE" ]]; then
    backup=$(mktemp "$BASE/state/.routing-policy-backup.XXXXXX") || {
      rm -f -- "$stage" || true
      return 1
    }
    if ! rm -f -- "$backup" || ! ln -- "$POLICY_FILE" "$backup"; then
      rm -f -- "$stage" "$backup" || true
      return 1
    fi
  fi
  policy_path_is_safe || {
    rm -f -- "$stage" "$backup" || true
    return 1
  }
  # Sync the directory before commit where possible.  This is not visible
  # state, and a failure here still guarantees the old policy remains.
  sync_local_path "$BASE/state" || {
    rm -f -- "$stage" "$backup" || true
    return 1
  }
  if ! mv -f -- "$stage" "$POLICY_FILE"; then
    rm -f -- "$stage" "$backup" || true
    return 1
  fi
  stage=''

  if ! sync_local_path "$BASE/state"; then
    # A directory fsync failure is a failed commit, not a reason to leave the
    # candidate policy visible.  The backup is an exact old inode; for an
    # initially absent policy remove the candidate instead.
    if [[ -n "$backup" && -e "$backup" ]]; then
      atomic_policy_restore "$backup" "$POLICY_FILE" || rollback_failed=1
      backup=''
    else
      unlink_policy_no_follow "$POLICY_FILE" || rollback_failed=1
    fi
    sync_local_path "$BASE/state" >/dev/null 2>&1 || true
    rm -f -- "$stage" "$backup" || true
    (( rollback_failed == 0 )) || return 1
    return 1
  fi
  rm -f -- "$backup" || true
}

validate_networkmanager_setting() {
  case "${MANAGE_NETWORKMANAGER,,}" in
    1|true|yes|on|0|false|no|off) ;;
    *) echo 'VPNKIT_LOCAL_MANAGE_NETWORKMANAGER must be true or false' >&2; return 2 ;;
  esac
}

networkmanager_enabled() {
  case "${MANAGE_NETWORKMANAGER,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

container_id() { "${COMPOSE[@]}" ps -q vpnkit 2>/dev/null || true; }
container_state() {
  local cid
  cid=$(container_id)
  [[ -n "$cid" ]] || { printf 'absent\n'; return; }
  docker inspect "$cid" --format '{{if not .State.Running}}stopped{{else if .State.Health}}{{.State.Health.Status}}{{else}}running{{end}}' 2>/dev/null || printf 'unknown\n'
}

render_all() {
  local policy=${1:-}
  [[ -n "$policy" ]] || policy=$(safe_policy)
  case "$policy" in strict|smart) ;; *) return 2 ;; esac
  "$REPO_ROOT/scripts/vpnkit/vpnkit-local-assets.sh" --secrets-dir "$BASE" --endpoint "$ENDPOINT" --port "$PORT" --push-dns "$PUSH_DNS" >/dev/null
  VPNKIT_LOCAL_POLICY="$policy" "$REPO_ROOT/scripts/vpnkit/vpnkit-render-local-kde-configs.sh" >/dev/null
}

wait_healthy() {
  local cid state deadline
  [[ "$BOOT_TIMEOUT" =~ ^[0-9]+$ ]] && (( BOOT_TIMEOUT >= 1 && BOOT_TIMEOUT <= 7200 )) || { echo 'VPNKIT_LOCAL_BOOT_TIMEOUT_SECONDS must be in 1..7200' >&2; return 2; }
  cid=$(container_id)
  [[ -n "$cid" ]] || return 1
  deadline=$((SECONDS + BOOT_TIMEOUT))
  while (( SECONDS < deadline )); do
    state=$(container_state)
    case "$state" in
      healthy) return 0 ;;
      stopped|absent) return 1 ;;
    esac
    sleep 1
  done
  return 1
}

# Read only the fixed local NM helper status. Values are deliberately reduced
# to yes/no, so status and transaction diagnostics never expose profile data.
safe_networkmanager_device() {
  local device=$1
  [[ "$device" =~ ^tun[A-Za-z0-9_.-]{0,14}$ ]] || return 1
  (( ${#device} <= 15 )) || return 1
  [[ "$device" != ppp0 && "$device" != vpn0 ]]
}

read_networkmanager_state() {
  if ! networkmanager_enabled; then
    NM_CONFIGURED=not-managed
    NM_ACTIVE=not-managed
    NM_DEVICE=not-managed
    return 0
  fi
  [[ -x "$NM_HELPER" ]] || return 1
  local output configured active device
  output=$("$NM_HELPER" status 2>/dev/null) || return 1
  configured=$(awk -F= '$1 == "configured" { print $2; exit }' <<<"$output")
  active=$(awk -F= '$1 == "active" { print $2; exit }' <<<"$output")
  device=$(awk -F= '$1 == "device" { print $2; exit }' <<<"$output")
  case "$configured:$active" in
    yes:yes)
      safe_networkmanager_device "$device" || return 1
      ;;
    yes:no|no:no)
      [[ "$device" == none || -z "$device" ]] || return 1
      device=none
      ;;
    no:yes)
      return 1
      ;;
    *)
      return 1
      ;;
  esac
  NM_CONFIGURED=$configured
  NM_ACTIVE=$active
  NM_DEVICE=$device
}

networkmanager_status_values() {
  if ! networkmanager_enabled; then
    printf 'not-managed not-managed\n'
    return 0
  fi
  if read_networkmanager_state; then
    printf '%s %s\n' "$NM_CONFIGURED" "$NM_ACTIVE"
  else
    printf 'unavailable unavailable\n'
  fi
}

# Snapshot active VPN identities before the first Docker call. The snapshot is
# local temporary state only; it is never printed and is compared after start.
capture_active_vpn_identities() {
  local destination=$1 output
  command -v nmcli >/dev/null 2>&1 || return 1
  output=$(nmcli -t --escape no -f NAME,UUID,TYPE connection show --active 2>/dev/null) || return 1
  awk -F: '
    NF >= 3 && ($3 == "vpn" || $3 == "wireguard" || $3 == "ipsec" || $3 == "openvpn" || $3 == "strongswan") {
      printf "%s\t%s\t%s\n", $1, $2, $3
    }
  ' <<<"$output" | LC_ALL=C sort -u >"$destination"
  chmod 600 "$destination"
}

filter_other_vpn_identities() {
  local source=$1
  awk -F '\t' '$1 != "vpnkit-local" { print }' "$source" | LC_ALL=C sort -u
}

verify_other_active_vpn_set() {
  local before=$1 after=$2 before_other=$3 after_other=$4
  capture_active_vpn_identities "$after" || return 1
  filter_other_vpn_identities "$before" >"$before_other"
  filter_other_vpn_identities "$after" >"$after_other"
  cmp -s "$before_other" "$after_other"
}

snapshot_owned_nm_file() {
  local source=$1 destination=$2
  if [[ -L "$source" ]]; then return 1; fi
  if [[ -e "$source" ]]; then
    [[ -f "$source" ]] || return 1
    cat -- "$source" >"$destination" || return 1
    chmod 600 "$destination" || return 1
    stat -c '%a' -- "$source" >"$destination.mode" || return 1
    printf 'yes\n' >"$destination.present"
  else
    printf 'no\n' >"$destination.present"
  fi
}

snapshot_owned_nm_capability() {
  local destination=$1 name
  mkdir -- "$destination/files" || return 1
  chmod 700 "$destination/files" || return 1
  for name in networkmanager-state networkmanager-uuid networkmanager-profile-fingerprint; do
    snapshot_owned_nm_file "$BASE/state/$name" "$destination/files/$name" || return 1
  done
  snapshot_owned_nm_file "$BASE/openvpn/client/vpnkit-local.ovpn" "$destination/files/profile" || return 1
}

snapshot_owned_uuid() {
  local destination=$1 name uuid fingerprint payload
  for name in networkmanager-state networkmanager-uuid; do
    [[ "$(<"$destination/files/$name.present")" == yes ]] || continue
    payload=$(<"$destination/files/$name") || return 1
    case "$name" in
      networkmanager-state) read -r uuid fingerprint <<<"$payload" || return 1 ;;
      networkmanager-uuid) read -r uuid <<<"$payload" || return 1 ;;
    esac
    [[ -n "$uuid" ]] && { printf '%s\n' "${uuid,,}"; return 0; }
  done
  return 1
}

restore_owned_nm_file() {
  local destination=$1 name=$2 target=$3 source="$destination/files/$2"
  local present mode tmp parent
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
    tmp=$(mktemp "$parent/.$name.restore.XXXXXX") || return 1
    if ! chmod 600 "$tmp" || ! cat -- "$source" >"$tmp" || ! chmod "$mode" "$tmp" || ! sync_local_path "$tmp"; then
      rm -f -- "$tmp" || true
      return 1
    fi
    if ! mv -f -- "$tmp" "$target"; then
      rm -f -- "$tmp" || true
      return 1
    fi
  else
    [[ ! -L "$target" && (! -e "$target" || -f "$target") ]] || return 1
    [[ ! -e "$target" ]] || rm -f -- "$target" || return 1
  fi
  sync_local_path "$parent"
}

restore_owned_nm_capability_files() {
  local destination=$1
  restore_owned_nm_file "$destination" networkmanager-state "$BASE/state/networkmanager-state" || return 1
  restore_owned_nm_file "$destination" networkmanager-uuid "$BASE/state/networkmanager-uuid" || return 1
  restore_owned_nm_file "$destination" networkmanager-profile-fingerprint "$BASE/state/networkmanager-profile-fingerprint" || return 1
  restore_owned_nm_file "$destination" profile "$BASE/openvpn/client/vpnkit-local.ovpn" || return 1
}

owned_nm_capability_matches_snapshot() {
  local destination=$1 name present target source
  for name in networkmanager-state networkmanager-uuid networkmanager-profile-fingerprint profile; do
    source="$destination/files/$name"
    target="$BASE/openvpn/client/vpnkit-local.ovpn"
    case "$name" in networkmanager-state|networkmanager-uuid|networkmanager-profile-fingerprint) target="$BASE/state/$name" ;; esac
    present=$(<"$source.present") || return 1
    if [[ "$present" == yes ]]; then
      [[ -f "$target" && ! -L "$target" ]] || return 1
      cmp -s -- "$source" "$target" || return 1
    else
      [[ ! -e "$target" && ! -L "$target" ]] || return 1
    fi
  done
}

restore_networkmanager_capability() {
  local destination=$1 configured_before=$2 active_before=$3 device_before=$4
  local failed=0 current_configured current_active current_device current_uuid before_uuid
  networkmanager_enabled || return 0
  read_networkmanager_state || return 1
  current_configured=$NM_CONFIGURED
  current_active=$NM_ACTIVE
  current_device=$NM_DEVICE
  current_uuid=$(read_current_owned_uuid 2>/dev/null || true)
  before_uuid=$(snapshot_owned_uuid "$destination" 2>/dev/null || true)

  # Remove only a newly-created/replaced local capability.  A pre-existing
  # owned UUID is left in NetworkManager so rollback can preserve it exactly.
  if [[ "$configured_before" == no && "$current_configured" == yes ]]; then
    [[ "$current_active" == yes ]] && "$NM_HELPER" disconnect --yes >/dev/null 2>&1 || true
    "$NM_HELPER" remove --yes >/dev/null 2>&1 || failed=1
  elif [[ "$configured_before" == yes && "$current_configured" == yes && -n "$before_uuid" && "$current_uuid" != "$before_uuid" ]]; then
    [[ "$current_active" == yes ]] && "$NM_HELPER" disconnect --yes >/dev/null 2>&1 || true
    "$NM_HELPER" remove --yes >/dev/null 2>&1 || failed=1
  fi

  # Restore the source profile and the helper's persisted ownership capability
  # before any compensating import.  These files are the exact UUID/fingerprint
  # identity used by the fixed helper; no arbitrary NM profile is touched.
  restore_owned_nm_capability_files "$destination" || failed=1

  if [[ "$configured_before" == yes ]]; then
    if ! read_networkmanager_state || [[ "$NM_CONFIGURED" != yes ]]; then
      "$NM_HELPER" import --yes >/dev/null 2>&1 || failed=1
    fi
  else
    if read_networkmanager_state && [[ "$NM_CONFIGURED" == yes ]]; then
      "$NM_HELPER" disconnect --yes >/dev/null 2>&1 || true
      "$NM_HELPER" remove --yes >/dev/null 2>&1 || failed=1
    fi
  fi

  if read_networkmanager_state; then
    if [[ "$active_before" == yes && "$NM_ACTIVE" != yes ]]; then
      "$NM_HELPER" connect --yes >/dev/null 2>&1 || failed=1
    elif [[ "$active_before" != yes && "$NM_ACTIVE" == yes ]]; then
      "$NM_HELPER" disconnect --yes >/dev/null 2>&1 || failed=1
    fi
  else
    failed=1
  fi
  if ! read_networkmanager_state; then
    failed=1
  else
    [[ "$NM_CONFIGURED" == "$configured_before" && "$NM_ACTIVE" == "$active_before" && "$NM_DEVICE" == "$device_before" ]] || failed=1
  fi
  owned_nm_capability_matches_snapshot "$destination" || failed=1
  return "$failed"
}

read_current_owned_uuid() {
  local state_file="$BASE/state/networkmanager-state" uuid fingerprint payload
  if [[ -f "$state_file" && ! -L "$state_file" ]]; then
    payload=$(<"$state_file") || return 1
    read -r uuid fingerprint <<<"$payload" || return 1
    [[ -n "$uuid" ]] && { printf '%s\n' "${uuid,,}"; return 0; }
  fi
  state_file="$BASE/state/networkmanager-uuid"
  if [[ -f "$state_file" && ! -L "$state_file" ]]; then
    payload=$(<"$state_file") || return 1
    read -r uuid <<<"$payload" || return 1
    [[ -n "$uuid" ]] && { printf '%s\n' "${uuid,,}"; return 0; }
  fi
  return 1
}

rollback_start_transaction() {
  local stack_attempted=$1 stack_was_healthy=$2 stack_before_id=$3 configured_before=$4 active_before=$5 device_before=$6 nm_snapshot=$7
  local failed=0 restored_id

  if networkmanager_enabled; then
    restore_networkmanager_capability "$nm_snapshot" "$configured_before" "$active_before" "$device_before" || failed=1
  fi
  if [[ "$stack_attempted" == true ]]; then
    if [[ "$stack_was_healthy" == true ]]; then
      # Never tear down a healthy pre-call local stack.  If the failed Compose
      # call left the exact healthy container in place, preserve it without a
      # second mutation.  Only a changed/missing/unhealthy container needs a
      # bounded Compose-up restoration.
      restored_id=$(container_id)
      if [[ "$restored_id" != "$stack_before_id" || "$(container_state)" != healthy ]]; then
        "${COMPOSE[@]}" up -d --build vpnkit >/dev/null 2>&1 || failed=1
        wait_healthy || failed=1
        restored_id=$(container_id)
      fi
      [[ -z "$stack_before_id" || "$restored_id" == "$stack_before_id" ]] || failed=1
    else
      "${COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || failed=1
    fi
  fi
  return "$failed"
}

start_failure() {
  local reason=$1 stack_attempted=$2 stack_was_healthy=$3 stack_before_id=$4 configured_before=$5 active_before=$6 device_before=$7 snapshot=$8 nm_snapshot=$9
  local rollback_failed=0
  rollback_start_transaction "$stack_attempted" "$stack_was_healthy" "$stack_before_id" "$configured_before" "$active_before" "$device_before" "$nm_snapshot" || rollback_failed=1
  if networkmanager_enabled; then
    verify_other_active_vpn_set "$snapshot" "${snapshot}.after" "${snapshot}.before-other" "${snapshot}.after-other" || rollback_failed=1
  fi
  rm -rf -- "$(dirname -- "$snapshot")"
  if (( rollback_failed )); then
    echo "$reason; local rollback incomplete" >&2
  else
    echo "$reason; local stack was rolled back" >&2
  fi
  return 1
}

start_stack() {
  validate_networkmanager_setting || return

  local snapshot_dir snapshot snapshot_after nm_snapshot
  snapshot_dir=$(mktemp -d "${TMPDIR:-/tmp}/vpnkit-local-start.XXXXXX") || {
    echo 'could not create local start transaction snapshot' >&2
    return 1
  }
  chmod 700 "$snapshot_dir"
  snapshot="$snapshot_dir/active-vpn"
  snapshot_after="${snapshot}.after"
  nm_snapshot="$snapshot_dir/nm"
  mkdir -- "$nm_snapshot"
  chmod 700 "$nm_snapshot"

  local configured_before=not-managed active_before=not-managed device_before=not-managed
  local stack_attempted=false stack_was_healthy=false stack_before_id= stack_before_state=absent
  if networkmanager_enabled; then
    if ! read_networkmanager_state; then
      rm -rf -- "$snapshot_dir"
      echo 'NetworkManager status could not be read before local start' >&2
      return 1
    fi
    configured_before=$NM_CONFIGURED
    active_before=$NM_ACTIVE
    device_before=$NM_DEVICE
    if ! capture_active_vpn_identities "$snapshot" || ! snapshot_owned_nm_capability "$nm_snapshot"; then
      rm -rf -- "$snapshot_dir"
      echo 'NetworkManager capability could not be snapshotted before local start' >&2
      return 1
    fi
  else
    : >"$snapshot"
    chmod 600 "$snapshot"
  fi

  command -v docker >/dev/null 2>&1 || {
    rm -rf -- "$snapshot_dir"
    echo 'docker is unavailable' >&2
    return 1
  }
  # Probe only this validated Compose project before rendering.  The result is
  # part of the transaction: a healthy pre-call container is never rolled down
  # as compensation for a later local start failure.
  stack_before_id=$(container_id)
  if [[ -n "$stack_before_id" ]]; then
    stack_before_state=$(container_state)
    [[ "$stack_before_state" == healthy ]] && stack_was_healthy=true
  fi
  if networkmanager_enabled; then
    "$UNDERLAY_HELPER" verify >/dev/null || {
      rm -rf -- "$snapshot_dir"
      echo 'install and verify the vpnkit local underlay helper before NetworkManager start' >&2
      return 1
    }
  fi
  if ! render_all; then
    if networkmanager_enabled; then
      start_failure 'local vpnkit assets could not be rendered' false "$stack_was_healthy" "$stack_before_id" "$configured_before" "$active_before" "$device_before" "$snapshot" "$nm_snapshot"
    else
      rm -rf -- "$snapshot_dir"
      echo 'local vpnkit assets could not be rendered' >&2
    fi
    return
  fi

  # Mark the transaction before calling Compose: a partially-created project
  # is bounded, while a healthy pre-existing project is restored with Compose
  # up rather than destructively brought down.
  stack_attempted=true
  if ! "${COMPOSE[@]}" up -d --build vpnkit >/dev/null; then
    start_failure 'local vpnkit stack failed to start' "$stack_attempted" "$stack_was_healthy" "$stack_before_id" "$configured_before" "$active_before" "$device_before" "$snapshot" "$nm_snapshot"
    return
  fi
  if ! wait_healthy; then
    start_failure 'local vpnkit failed closed before readiness' "$stack_attempted" "$stack_was_healthy" "$stack_before_id" "$configured_before" "$active_before" "$device_before" "$snapshot" "$nm_snapshot"
    return
  fi

  local nm_result=not-changed host_smoke_result=not-managed
  if networkmanager_enabled; then
    # Preserve an already-owned capability byte-for-byte.  Import is only a
    # creation step when this exact local profile was not configured before the
    # call; a pre-existing active profile needs no mutation at all.
    if [[ "$configured_before" != yes ]]; then
      if ! "$NM_HELPER" import --yes >/dev/null || ! "$NM_HELPER" connect --yes >/dev/null; then
        start_failure 'NetworkManager activation failed' "$stack_attempted" "$stack_was_healthy" "$stack_before_id" "$configured_before" "$active_before" "$device_before" "$snapshot" "$nm_snapshot"
        return
      fi
    elif [[ "$active_before" != yes ]]; then
      if ! "$NM_HELPER" connect --yes >/dev/null; then
        start_failure 'NetworkManager activation failed' "$stack_attempted" "$stack_was_healthy" "$stack_before_id" "$configured_before" "$active_before" "$device_before" "$snapshot" "$nm_snapshot"
        return
      fi
    fi
    if ! read_networkmanager_state || [[ "$NM_ACTIVE" != yes ]]; then
      start_failure 'NetworkManager did not revalidate vpnkit-local as active' "$stack_attempted" "$stack_was_healthy" "$stack_before_id" "$configured_before" "$active_before" "$device_before" "$snapshot" "$nm_snapshot"
      return
    fi
    if ! VPNKIT_LOCAL_SMOKE_DEVICE="$NM_DEVICE" bash "$HOST_SMOKE" >/dev/null 2>&1; then
      start_failure 'same-host local VPN smoke failed' "$stack_attempted" "$stack_was_healthy" "$stack_before_id" "$configured_before" "$active_before" "$device_before" "$snapshot" "$nm_snapshot"
      return
    fi
    host_smoke_result=pass
    if ! verify_other_active_vpn_set "$snapshot" "$snapshot_after" "${snapshot}.before-other" "${snapshot}.after-other"; then
      start_failure 'active VPN set changed outside vpnkit-local' "$stack_attempted" "$stack_was_healthy" "$stack_before_id" "$configured_before" "$active_before" "$device_before" "$snapshot" "$nm_snapshot"
      return
    fi
    nm_result=connected
  fi

  rm -rf -- "$snapshot_dir"
  printf 'vpnkit_local_start=ok\n'
  printf 'container_state=healthy\n'
  printf 'networkmanager=%s\n' "$nm_result"
  printf 'host_smoke=%s\n' "$host_smoke_result"
}

stop_stack() {
  validate_networkmanager_setting || return
  local nm_result=not-changed
  if networkmanager_enabled; then
    "$NM_HELPER" disconnect --yes >/dev/null
    nm_result=disconnected
  fi
  "${COMPOSE[@]}" down --remove-orphans >/dev/null
  printf 'vpnkit_local_stop=ok\n'
  printf 'networkmanager=%s\n' "$nm_result"
}

container_runtime_generation() {
  local cid=$1
  docker exec "$cid" sh -lc '
    value=$(cat "$1" 2>/dev/null) || exit 2
    case "$value" in
      ""|*[!0-9]*) exit 2 ;;
      *) printf "%s\n" "$value" ;;
    esac
  ' sh "$SINGBOX_GENERATION_FILE"
}

container_request_absent() {
  local cid=$1
  docker exec "$cid" sh -lc 'test ! -e "$1"' sh "$SINGBOX_RESTART_FILE"
}

wait_for_retest_runtime() {
  local cid=$1 generation_before=$2 deadline current
  [[ "$RETEST_TIMEOUT" =~ ^[0-9]+$ ]] && (( RETEST_TIMEOUT >= 1 && RETEST_TIMEOUT <= 3600 )) || { echo 'VPNKIT_LOCAL_RETEST_TIMEOUT_SECONDS must be in 1..3600' >&2; return 2; }
  deadline=$((SECONDS + RETEST_TIMEOUT))
  while (( SECONDS < deadline )); do
    if container_request_absent "$cid" 2>/dev/null; then
      current=$(container_runtime_generation "$cid" 2>/dev/null || true)
      if [[ -n "$current" && "$current" != "$generation_before" ]] && [[ "$(container_state)" == healthy ]]; then
        return 0
      fi
    fi
    sleep 1
  done
  return 1
}

retest_select() {
  local cid generation_before log
  cid=$(container_id)
  [[ -n "$cid" && $(container_state) == healthy ]] || { echo 'vpnkit local is not healthy' >&2; return 1; }
  if ! container_request_absent "$cid" >/dev/null 2>&1; then
    echo 'a prior sing-box restart request is still pending' >&2
    return 1
  fi
  generation_before=$(container_runtime_generation "$cid" 2>/dev/null) || {
    echo 'sing-box runtime generation is unavailable' >&2
    return 1
  }
  log=/var/log/vibe-vpn/manual-selection.log
  if ! docker exec "$cid" sh -lc 'umask 077; vibe-vpn --config /etc/vibe-vpn/config.yaml pick >"$1" 2>&1' sh "$log"; then
    echo 'upstream retest/select failed; details remain in private container log' >&2
    return 1
  fi
  if ! wait_for_retest_runtime "$cid" "$generation_before"; then
    echo 'upstream selection completed without a consumed restart and healthy runtime' >&2
    return 1
  fi
  printf 'vpnkit_local_retest_select=ok\n'
  printf 'selection_details=redacted\n'
}

recreate_local_stack() {
  local policy=${1:-}
  [[ -n "$policy" ]] || policy=$(safe_policy)
  render_all "$policy" || return 1
  "${COMPOSE[@]}" up -d --build --force-recreate vpnkit >/dev/null || return 1
  wait_healthy
}

restore_networkmanager_state() {
  local configured_before=$1 active_before=$2
  networkmanager_enabled || return 0
  local failed=0
  if ! read_networkmanager_state; then return 1; fi

  if [[ "$configured_before" == no && "$NM_CONFIGURED" == yes ]]; then
    "$NM_HELPER" disconnect --yes >/dev/null 2>&1 || failed=1
    "$NM_HELPER" remove --yes >/dev/null 2>&1 || failed=1
  elif [[ "$configured_before" == yes && "$NM_CONFIGURED" == no ]]; then
    "$NM_HELPER" import --yes >/dev/null 2>&1 || failed=1
  fi

  if [[ "$active_before" == yes && "$NM_ACTIVE" != yes ]]; then
    "$NM_HELPER" connect --yes >/dev/null 2>&1 || failed=1
  elif [[ "$active_before" != yes && "$NM_ACTIVE" == yes ]]; then
    "$NM_HELPER" disconnect --yes >/dev/null 2>&1 || failed=1
  fi
  read_networkmanager_state || failed=1
  [[ "$NM_CONFIGURED" == "$configured_before" && "$NM_ACTIVE" == "$active_before" ]] || failed=1
  return "$failed"
}

toggle_mode() {
  validate_networkmanager_setting || return
  local current next was_running=false
  current=$(safe_policy)
  [[ "$current" == strict ]] && next=smart || next=strict
  [[ $(container_state) == healthy ]] && was_running=true

  local configured_before=not-managed active_before=not-managed
  if networkmanager_enabled; then
    if ! read_networkmanager_state; then
      echo 'NetworkManager status could not be read before policy toggle' >&2
      return 1
    fi
    configured_before=$NM_CONFIGURED
    active_before=$NM_ACTIVE
  fi

  local render_attempted=false stack_attempted=false toggle_failed=0
  if [[ "$was_running" == true ]]; then
    render_attempted=true
    stack_attempted=true
    # Render and recreate the candidate policy before committing its state
    # file.  A failed runtime transaction therefore cannot commit `next` even
    # if compensation itself later encounters an injected filesystem failure.
    if ! recreate_local_stack "$next"; then toggle_failed=1; fi
  fi
  if (( toggle_failed == 0 )) && networkmanager_enabled; then
    if ! read_networkmanager_state || [[ "$NM_CONFIGURED" != "$configured_before" || "$NM_ACTIVE" != "$active_before" ]]; then
      toggle_failed=1
    fi
  fi
  if (( toggle_failed == 0 )); then
    if ! write_policy "$next"; then toggle_failed=1; fi
  fi

  if (( toggle_failed != 0 )); then
    local rollback_failed=0
    # The old policy file was never replaced until the candidate runtime had
    # passed.  Re-render the old policy only when a runtime candidate ran.
    if [[ "$render_attempted" == true ]]; then
      if ! recreate_local_stack "$current"; then rollback_failed=1; fi
    elif [[ "$stack_attempted" == true ]]; then
      "${COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || rollback_failed=1
    fi
    restore_networkmanager_state "$configured_before" "$active_before" || rollback_failed=1
    if (( rollback_failed )); then
      echo 'policy switch failed; prior policy/runtime rollback incomplete' >&2
    else
      echo 'policy switch failed; prior policy/runtime was restored' >&2
    fi
    return 1
  fi

  printf 'vpnkit_local_toggle=ok\n'
  printf 'routing_policy=%s\n' "$next"
}

diagnostics() {
  local state policy helper=not-installed nm_configured=unavailable nm_active=unavailable
  state=$(container_state)
  policy=$(safe_policy)
  if [[ -x "$UNDERLAY_HELPER" ]]; then helper=available; fi
  if read_networkmanager_state; then
    nm_configured=$NM_CONFIGURED
    nm_active=$NM_ACTIVE
  fi
  printf 'vpnkit_local_diagnostics=ok\n'
  printf 'container_state=%s\n' "$state"
  printf 'routing_policy=%s\n' "$policy"
  printf 'subscription=%s\n' "$([[ -s "$BASE/vibe-vpn/sub_url" ]] && echo configured || echo missing)"
  printf 'client_profile=%s\n' "$([[ -s "$BASE/openvpn/client/vpnkit-local.ovpn" ]] && echo ready || echo missing)"
  printf 'host_route_helper=%s\n' "$helper"
  printf 'networkmanager=configured:%s active:%s\n' "$nm_configured" "$nm_active"
  printf 'private_values=not_printed\n'
}

status_json() {
  local nm_configured nm_active
  read -r nm_configured nm_active < <(networkmanager_status_values)
  python3 - "$(container_state)" "$(safe_policy)" "$([[ -s "$BASE/vibe-vpn/sub_url" ]] && echo configured || echo missing)" "$nm_configured" "$nm_active" <<'PY'
import json,sys
print(json.dumps({
    "schema": 1,
    "container": sys.argv[1],
    "routing_policy": sys.argv[2],
    "subscription": sys.argv[3],
    "networkmanager": {"configured": sys.argv[4], "active": sys.argv[5]},
}, sort_keys=True))
PY
}

usage() {
  cat <<'EOF'
Usage: scripts/vpnkit/vpnkit-local.sh start|stop|status [--json]|retest select|toggle mode|diagnostics

This lifecycle adapter manages only the isolated local Compose project and the
fixed `vpnkit-local` NetworkManager profile. It never targets production `vpnkit`.
EOF
}

case "${1:-}" in
  start) [[ $# -eq 1 ]] || { usage >&2; exit 2; }; start_stack ;;
  stop) [[ $# -eq 1 ]] || { usage >&2; exit 2; }; stop_stack ;;
  status) [[ $# -le 2 ]] || { usage >&2; exit 2; }; [[ "${2:-}" == --json ]] && status_json || diagnostics ;;
  retest) [[ "${2:-}" == select && $# -eq 2 ]] || { usage >&2; exit 2; }; retest_select ;;
  toggle) [[ "${2:-}" == mode && $# -eq 2 ]] || { usage >&2; exit 2; }; toggle_mode ;;
  diagnostics) [[ $# -eq 1 ]] || { usage >&2; exit 2; }; diagnostics ;;
  -h|--help|'') usage ;;
  *) usage >&2; exit 2 ;;
esac
