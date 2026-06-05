#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
STEAM_DECK_CLIENT_DIR=$(cd "$SCRIPT_DIR/.." && pwd -P)
ENV_FILE="$STEAM_DECK_CLIENT_DIR/.env"
if [[ -r "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

CONTAINER=${VPNKIT_DECK_CLIENT_CONTAINER:-vpnkit-host-ovpn-client}
IMAGE=${VPNKIT_DECK_CLIENT_IMAGE:-localhost/vpnkit-host-ovpn-client:latest}
PROFILE=${VPNKIT_DECK_CLIENT_PROFILE:-$STEAM_DECK_CLIENT_DIR/local/client.ovpn}
LOG_DIR=${VPNKIT_DECK_LOG_DIR:-$STEAM_DECK_CLIENT_DIR/logs}
VPN_IFACE=${VPNKIT_DECK_VPN_IFACE:-tun0}
REPORT_DIR=${VPNKIT_DECK_REPORT_DIR:-$STEAM_DECK_CLIENT_DIR/reports}
PODMAN_RAW=${VPNKIT_DECK_PODMAN:-podman}
read -r -a PODMAN_CMD <<<"$PODMAN_RAW"

mkdir -p "$LOG_DIR" "$REPORT_DIR" "$STEAM_DECK_CLIENT_DIR/local"

new_report_path(){
  local name=$1
  printf '%s/%s-%s.log' "$REPORT_DIR" "$name" "$(date -u +%Y%m%dT%H%M%SZ)"
}

redact(){
  sed -E \
    -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' \
    -e 's/([0-9a-f]{2}:){5}[0-9a-f]{2}/<MAC>/Ig' \
    -e 's#(remote |remote=|server=)[^[:space:]]+#\1<redacted>#Ig' \
    -e 's#(vless|trojan|ss|hysteria2)://[^[:space:]]+#\1://[redacted]#g' \
    -e 's/(password|private[_-]?key|token|secret)[=: ][^[:space:]]+/\1=<redacted>/Ig'
}

log(){ printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
run(){ log "+ $*"; "$@"; }

hash8(){
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -c1-8
  elif command -v md5sum >/dev/null 2>&1; then
    printf '%s' "$1" | md5sum | cut -c1-8
  else
    printf unavailable
  fi
}

podman_cmd(){ "${PODMAN_CMD[@]}" "$@"; }

preflight_common(){
  command -v "${PODMAN_CMD[0]}" >/dev/null 2>&1 || { echo "missing podman command: ${PODMAN_CMD[0]}" >&2; exit 10; }
  [[ -e /dev/net/tun ]] || { echo "missing /dev/net/tun on Steam Deck host" >&2; exit 11; }
}

preflight_profile(){
  [[ -r "$PROFILE" ]] || {
    cat >&2 <<'MSG'
missing OpenVPN profile.
Place a real client profile at ./local/client.ovpn on the Steam Deck, or set VPNKIT_DECK_CLIENT_PROFILE in .env.
Do not commit the profile.
MSG
    echo "expected_profile_path=$PROFILE" >&2
    exit 12
  }
}

write_header(){
  local title=$1
  echo "# $title"
  echo "timestamp=$(date -u +%FT%TZ)"
  echo "workdir=$STEAM_DECK_CLIENT_DIR"
  echo "container=$CONTAINER"
  echo "image=$IMAGE"
  echo "vpn_iface=$VPN_IFACE"
  echo "log_dir=$LOG_DIR"
  echo
}
