#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SINGNOX_PACKAGE_DIR=$(cd "$SCRIPT_DIR/.." && pwd -P)

find_repo_root(){
  local dir=$SINGNOX_PACKAGE_DIR
  while [[ "$dir" != / ]]; do
    if [[ -d "$dir/.git" || -f "$dir/scripts/deck/deck-hy2-hotspot.sh" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

SINGNOX_REPO_ROOT=${SINGNOX_REPO_ROOT:-$(find_repo_root || true)}
SINGNOX_ENV_FILE=${SINGNOX_ENV_FILE:-$SINGNOX_PACKAGE_DIR/.env}

# Shell environment for a single invocation should override .env defaults.
SINGNOX_ENV_OVERRIDE_NAMES=(
  SINGNOX_SSH_TARGET SINGNOX_HY2_CLIENT_CONFIG SINGNOX_SINGBOX_TEMPLATE
  SINGNOX_OUTPUT_CONFIG SINGNOX_RULE_SET_DIR SINGNOX_REPORT_DIR SINGNOX_LOG_DIR
  SINGNOX_SINGBOX_BIN SINGNOX_SINGBOX_MODE SINGNOX_SINGBOX_UNIT
  SINGNOX_SINGBOX_CONTAINER SINGNOX_SINGBOX_IMAGE SINGNOX_HOTSPOT_CONTAINER
  SINGNOX_HOTSPOT_IMAGE SINGNOX_HOTSPOT_SSID SINGNOX_HOTSPOT_PASSWORD
  SINGNOX_HOTSPOT_SUBNET SINGNOX_TUN_IFACE SINGNOX_TUN_ADDR
  SINGNOX_REMOTE_STATE SINGNOX_PODMAN SINGNOX_SINGBOX_SOURCE_BIN
  SINGNOX_SINGBOX_SOURCE_ARCHIVE DECK_HOTSPOT_PASSWORD
)
declare -A SINGNOX_ENV_OVERRIDES=()
for name in "${SINGNOX_ENV_OVERRIDE_NAMES[@]}"; do
  if [[ -v $name ]]; then
    SINGNOX_ENV_OVERRIDES[$name]=${!name}
  fi
done
if [[ -r "$SINGNOX_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$SINGNOX_ENV_FILE"
  set +a
fi
for name in "${!SINGNOX_ENV_OVERRIDES[@]}"; do
  printf -v "$name" '%s' "${SINGNOX_ENV_OVERRIDES[$name]}"
  export "$name"
done

path_from_package(){
  local value=$1
  if [[ "$value" = /* ]]; then
    printf '%s\n' "$value"
  else
    printf '%s/%s\n' "$SINGNOX_PACKAGE_DIR" "$value"
  fi
}

SINGNOX_SSH_TARGET=${SINGNOX_SSH_TARGET:-${DECK_HY2_SSH_TARGET:-${VPNKIT_STEAMDECK_SSH_TARGET:-deck}}}
SINGNOX_HY2_CLIENT_CONFIG=$(path_from_package "${SINGNOX_HY2_CLIENT_CONFIG:-local/hysteria2-client.yaml}")
SINGNOX_SINGBOX_TEMPLATE=$(path_from_package "${SINGNOX_SINGBOX_TEMPLATE:-config/sing-box/config.tun.json.template}")
SINGNOX_OUTPUT_CONFIG=$(path_from_package "${SINGNOX_OUTPUT_CONFIG:-runtime/sing-box/config.json}")
SINGNOX_RULE_SET_DIR=$(path_from_package "${SINGNOX_RULE_SET_DIR:-runtime/sing-box/rule-sets}")
SINGNOX_REPORT_DIR=$(path_from_package "${SINGNOX_REPORT_DIR:-reports}")
SINGNOX_LOG_DIR=$(path_from_package "${SINGNOX_LOG_DIR:-logs}")
SINGNOX_SINGBOX_BIN=${SINGNOX_SINGBOX_BIN:-/home/deck/.local/bin/sing-box}
SINGNOX_SINGBOX_MODE=${SINGNOX_SINGBOX_MODE:-native}
SINGNOX_SINGBOX_UNIT=${SINGNOX_SINGBOX_UNIT:-singnox-hotspot-singbox.service}
SINGNOX_SINGBOX_CONTAINER=${SINGNOX_SINGBOX_CONTAINER:-singnox-hotspot-singbox}
SINGNOX_SINGBOX_IMAGE=${SINGNOX_SINGBOX_IMAGE:-docker.io/library/containerized-vpnkit-openvpn-singbox-vpnkit:latest}
SINGNOX_HOTSPOT_CONTAINER=${SINGNOX_HOTSPOT_CONTAINER:-singnox-hotspot-ap}
SINGNOX_HOTSPOT_IMAGE=${SINGNOX_HOTSPOT_IMAGE:-localhost/singnox-hotspot-ap:latest}
SINGNOX_HOTSPOT_SSID=${SINGNOX_HOTSPOT_SSID:-vpnkit-deck}
SINGNOX_HOTSPOT_PASSWORD=${SINGNOX_HOTSPOT_PASSWORD:-${DECK_HOTSPOT_PASSWORD:-}}
SINGNOX_HOTSPOT_SUBNET=${SINGNOX_HOTSPOT_SUBNET:-10.42.0.0/24}
SINGNOX_TUN_IFACE=${SINGNOX_TUN_IFACE:-sb-tun0}
SINGNOX_TUN_ADDR=${SINGNOX_TUN_ADDR:-172.19.0.1/30}
SINGNOX_REMOTE_STATE=${SINGNOX_REMOTE_STATE:-/home/deck/.local/state/singnox-hotspot-client}
SINGNOX_PODMAN=${SINGNOX_PODMAN:-"sudo podman --root /home/deck/.local/share/vpnkit-root-podman --runroot /run/vpnkit-root-podman"}

mkdir -p "$SINGNOX_REPORT_DIR" "$SINGNOX_LOG_DIR" "$(dirname "$SINGNOX_OUTPUT_CONFIG")" "$SINGNOX_RULE_SET_DIR"

log(){ printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
redact(){
  sed -E \
    -e 's#hysteria2://[^[:space:]]+#hysteria2://[redacted]#g' \
    -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' \
    -e 's/([0-9a-f]{2}:){5}[0-9a-f]{2}/<MAC>/Ig' \
    -e 's/(password|auth|token|secret)([":= ]+)[^", }]+/\1\2<redacted>/Ig'
}
require_repo_helper(){
  if [[ -z "$SINGNOX_REPO_ROOT" || ! -x "$SINGNOX_REPO_ROOT/scripts/deck/deck-hy2-hotspot.sh" ]]; then
    cat >&2 <<MSG
missing executable repo helper: scripts/deck/deck-hy2-hotspot.sh
Run from a full vibe-practicum-vpn checkout, or set SINGNOX_REPO_ROOT to one.
MSG
    exit 10
  fi
}
export_deck_helper_env(){
  export DECK_HY2_CLIENT_CONFIG=$SINGNOX_HY2_CLIENT_CONFIG
  export DECK_HY2_BASE_TEMPLATE=$SINGNOX_SINGBOX_TEMPLATE
  export DECK_HY2_REPORT_DIR=$SINGNOX_REPORT_DIR
  export DECK_HY2_REMOTE_STATE=$SINGNOX_REMOTE_STATE
  export DECK_HY2_SINGBOX_MODE=$SINGNOX_SINGBOX_MODE
  export DECK_HY2_SINGBOX_BIN=$SINGNOX_SINGBOX_BIN
  export DECK_HY2_SINGBOX_UNIT=$SINGNOX_SINGBOX_UNIT
  export DECK_HY2_SINGBOX_IMAGE=$SINGNOX_SINGBOX_IMAGE
  export DECK_HY2_SINGBOX_CONTAINER=$SINGNOX_SINGBOX_CONTAINER
  export DECK_HY2_TUN_IFACE=$SINGNOX_TUN_IFACE
  export DECK_HY2_TUN_ADDR=$SINGNOX_TUN_ADDR
  export DECK_HY2_PODMAN=$SINGNOX_PODMAN
  export DECK_HOTSPOT_PASSWORD=$SINGNOX_HOTSPOT_PASSWORD
  export DECK_HOTSPOT_CONTAINER=$SINGNOX_HOTSPOT_CONTAINER
  export DECK_HOTSPOT_IMAGE=$SINGNOX_HOTSPOT_IMAGE
  export DECK_HOTSPOT_SSID=$SINGNOX_HOTSPOT_SSID
  export DECK_HOTSPOT_SUBNET=$SINGNOX_HOTSPOT_SUBNET
}
