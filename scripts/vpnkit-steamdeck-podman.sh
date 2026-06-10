#!/usr/bin/env bash
set -Eeuo pipefail

SSH_TARGET=${VPNKIT_TEST_SSH_TARGET:-${VPNKIT_STEAMDECK_SSH_TARGET:-${VPNKIT_STEAMDECK_SSH_HOST:-deck}}}
REMOTE_DIR=${VPNKIT_STEAMDECK_REMOTE_DIR:-'~/.local/state/vpnkit'}
IMAGE=${VPNKIT_STEAMDECK_IMAGE:-localhost/vpnkit:steamdeck}
CONTAINER=${VPNKIT_STEAMDECK_CONTAINER:-vpnkit}
OPENVPN_PORT=${VPNKIT_OPENVPN_PORT:-1194}
ROUTING_MODE=${VPNKIT_ROUTING_MODE:-tun}
CONFIG_SOURCE=${VPNKIT_STEAMDECK_CONFIG_SOURCE:-secrets/vps/rendered}
LAN_ENDPOINT=${VPNKIT_STEAMDECK_LAN_ENDPOINT:-}
TAILSCALE_ENDPOINT=${VPNKIT_STEAMDECK_TAILSCALE_ENDPOINT:-}
LOG_FILE=${VPNKIT_STEAMDECK_LOG_FILE:-}
ALLOW_PRODUCTION_CONTAINER=${VPNKIT_STEAMDECK_ALLOW_PRODUCTION_CONTAINER:-0}
SSH_TIMEOUT=${VPNKIT_STEAMDECK_SSH_TIMEOUT:-${VPNKIT_TEST_SSH_TIMEOUT:-12}}
REMOTE_CMD_TIMEOUT=${VPNKIT_STEAMDECK_REMOTE_CMD_TIMEOUT:-${VPNKIT_TEST_REMOTE_CMD_TIMEOUT:-120}}
BUILD_TIMEOUT=${VPNKIT_STEAMDECK_BUILD_TIMEOUT:-${VPNKIT_TEST_BUILD_TIMEOUT:-600}}
RUN_TIMEOUT=${VPNKIT_STEAMDECK_RUN_TIMEOUT:-${VPNKIT_TEST_RUN_TIMEOUT:-120}}
LOGS_TIMEOUT=${VPNKIT_STEAMDECK_LOGS_TIMEOUT:-${VPNKIT_TEST_LOGS_TIMEOUT:-60}}
VERIFY_TIMEOUT=${VPNKIT_STEAMDECK_VERIFY_TIMEOUT:-${VPNKIT_TEST_VERIFY_TIMEOUT:-180}}
SSH_OPTS=()

usage() {
  cat <<'EOF'
Usage: scripts/vpnkit-steamdeck-podman.sh [options] <action>

Actions:
  check-ssh   Read-only SSH and Podman discovery on the Deck
  resolve-remote-dir
              Read-only check: print the normalized remote state dir
  sync        Transfer tracked build context plus rendered gitignored configs
  build       Build the vpnkit image on the Deck with podman
  run         Recreate/start the vpnkit container on the Deck
  deploy      sync + build + run + verify
  status      Show podman container status
  verify      Run process/config health checks inside the container
  logs        Show redacted container logs
  stop        Stop the container if present
  cleanup     Stop/remove the container and optional image with --remove-image

Options:
  --ssh-target HOST        SSH alias/host (env VPNKIT_STEAMDECK_SSH_TARGET; default deck)
  --remote-dir DIR         Remote state dir (env VPNKIT_STEAMDECK_REMOTE_DIR; default ~/.local/state/vpnkit)
  --image IMAGE            Podman image tag (env VPNKIT_STEAMDECK_IMAGE)
  --container NAME         Container name (env VPNKIT_STEAMDECK_CONTAINER; default vpnkit)
  --openvpn-port PORT      Host UDP port mapped to container 1194/udp (env VPNKIT_OPENVPN_PORT)
  --routing-mode MODE      Container routing mode: tun, redirect, or tproxy (env VPNKIT_ROUTING_MODE; default tun)
  --config-source DIR      Local rendered config dir (env VPNKIT_STEAMDECK_CONFIG_SOURCE; default secrets/vps/rendered)
  --lan-endpoint HOST      Optional LAN endpoint to ping from this host after deploy
  --tailscale-endpoint IP  Optional Tailscale endpoint to ping from this host after deploy
  --ssh-option OPT         Extra ssh option, repeatable (for example '-p 2222')
  --log-file PATH          Write redacted command output to PATH as well as stdout
  --remove-image           With cleanup, also remove image

Timeout env knobs (seconds): VPNKIT_STEAMDECK_SSH_TIMEOUT, VPNKIT_STEAMDECK_REMOTE_CMD_TIMEOUT,
  VPNKIT_STEAMDECK_BUILD_TIMEOUT, VPNKIT_STEAMDECK_RUN_TIMEOUT, VPNKIT_STEAMDECK_LOGS_TIMEOUT,
  VPNKIT_STEAMDECK_VERIFY_TIMEOUT. VPNKIT_TEST_* equivalents are accepted by the test harness.
  -h, --help               Show help

The script never prints config file contents. It transfers rendered configs as files and logs only file names,
sizes, and redacted runtime excerpts.
EOF
}

REMOVE_IMAGE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh-target) SSH_TARGET=${2:?missing value}; shift 2 ;;
    --remote-dir) REMOTE_DIR=${2:?missing value}; shift 2 ;;
    --image) IMAGE=${2:?missing value}; shift 2 ;;
    --container) CONTAINER=${2:?missing value}; shift 2 ;;
    --openvpn-port) OPENVPN_PORT=${2:?missing value}; shift 2 ;;
    --routing-mode) ROUTING_MODE=${2:?missing value}; shift 2 ;;
    --config-source) CONFIG_SOURCE=${2:?missing value}; shift 2 ;;
    --lan-endpoint) LAN_ENDPOINT=${2:?missing value}; shift 2 ;;
    --tailscale-endpoint) TAILSCALE_ENDPOINT=${2:?missing value}; shift 2 ;;
    --ssh-option)
      # Accept either one shell-style pair such as '-p 2222' or a single ssh option.
      read -r -a _vpnkit_ssh_opt <<< "${2:?missing value}"
      SSH_OPTS+=("${_vpnkit_ssh_opt[@]}")
      shift 2
      ;;
    --log-file) LOG_FILE=${2:?missing value}; shift 2 ;;
    --remove-image) REMOVE_IMAGE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) break ;;
  esac
done
ACTION=${1:-}
if [[ -z "$ACTION" ]]; then usage >&2; exit 2; fi

redact_stream() {
  sed -E \
    -e 's#vless://[^[:space:]]+#vless://[redacted]#g' \
    -e 's#(https?://)[^[:space:]]*(token|sub|subscription|api_key|apikey|key)[^[:space:]]*#\1[redacted-url]#ig' \
    -e 's/([0-9a-f]{8}-[0-9a-f-]{27,})/[redacted-uuid]/ig' \
    -e 's/(private[_-]?key[":= ]+)[^", ]+/\1[redacted]/ig' \
    -e 's/(password[":= ]+)[^", ]+/\1[redacted]/ig'
}
if [[ -n "$LOG_FILE" ]]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  exec > >(redact_stream | tee "$LOG_FILE") 2>&1
fi

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
remote() { timeout --preserve-status "$REMOTE_CMD_TIMEOUT" ssh -o ConnectTimeout="$SSH_TIMEOUT" "${SSH_OPTS[@]}" "$SSH_TARGET" "$@"; }
remote_sh() { timeout --preserve-status "$REMOTE_CMD_TIMEOUT" ssh -o ConnectTimeout="$SSH_TIMEOUT" "${SSH_OPTS[@]}" "$SSH_TARGET" 'bash -s' -- "$@"; }
remote_timeout() { local seconds=$1; shift; timeout --preserve-status "$seconds" ssh -o ConnectTimeout="$SSH_TIMEOUT" "${SSH_OPTS[@]}" "$SSH_TARGET" "$@"; }
remote_sh_timeout() { local seconds=$1; shift; timeout --preserve-status "$seconds" ssh -o ConnectTimeout="$SSH_TIMEOUT" "${SSH_OPTS[@]}" "$SSH_TARGET" 'bash -s' -- "$@"; }
normalize_remote_dir() {
  remote_sh "$REMOTE_DIR" <<'REMOTE'
set -Eeuo pipefail
remote_dir=$1
case "$remote_dir" in
  '~') printf '%s\n' "$HOME" ;;
  '~/'*) printf '%s/%s\n' "$HOME" "${remote_dir#~/}" ;;
  /*) printf '%s\n' "$remote_dir" ;;
  *) echo "remote dir must be absolute or start with ~/: $remote_dir" >&2; exit 2 ;;
esac
REMOTE
}
need_config() {
  for path in "$CONFIG_SOURCE/openvpn/server.conf" "$CONFIG_SOURCE/sing-box/config.json" "$CONFIG_SOURCE/vibe-vpn/config.yaml"; do
    [[ -r "$path" ]] || { echo "missing required rendered input: $path" >&2; exit 1; }
  done
  if [[ ! -r "$CONFIG_SOURCE/vibe-vpn/sub_url" ]]; then
    echo "notice: optional vibe-vpn sub_url missing; server smoke can proceed because the daemon is not required for OpenVPN/sing-box checks" >&2
  fi
}

sync_context() {
  need_config
  log "creating remote directories under $REMOTE_DIR on $SSH_TARGET"
  remote "mkdir -p '$REMOTE_DIR/src' '$REMOTE_DIR/secrets/vps/rendered' '$REMOTE_DIR/state/vibe-vpn' '$REMOTE_DIR/state/sing-box' '$REMOTE_DIR/logs/vibe-vpn'"
  log "transferring tracked repository build context (git archive; no .gitignored secrets)"
  git archive --format=tar HEAD | timeout --preserve-status "$REMOTE_CMD_TIMEOUT" ssh -o ConnectTimeout="$SSH_TIMEOUT" "${SSH_OPTS[@]}" "$SSH_TARGET" "tar -xf - -C '$REMOTE_DIR/src'"
  log "transferring rendered config files from $CONFIG_SOURCE (contents not printed)"
  tar -C "$CONFIG_SOURCE" -cf - openvpn sing-box vibe-vpn | timeout --preserve-status "$REMOTE_CMD_TIMEOUT" ssh -o ConnectTimeout="$SSH_TIMEOUT" "${SSH_OPTS[@]}" "$SSH_TARGET" "tar -xf - -C '$REMOTE_DIR/secrets/vps/rendered'"
  remote "find '$REMOTE_DIR/secrets/vps/rendered' -type f -printf '%P %s bytes\\n' | sort"
}

build_image() {
  remote_timeout "$BUILD_TIMEOUT" "cd '$REMOTE_DIR/src' && podman build -t '$IMAGE' -f docker/vpnkit/Dockerfile ."
}

run_container() {
  if [[ "$CONTAINER" == "vpnkit" && "$ALLOW_PRODUCTION_CONTAINER" != "1" ]]; then
    echo "refusing to recreate production/default container 'vpnkit'; set --container to a distinct test name or VPNKIT_STEAMDECK_ALLOW_PRODUCTION_CONTAINER=1 for an explicitly approved production action" >&2
    exit 2
  fi
  case "$ROUTING_MODE" in tun|redirect|tproxy) ;; *) echo "unsupported routing mode: $ROUTING_MODE" >&2; exit 2 ;; esac
  remote_sh_timeout "$RUN_TIMEOUT" "$REMOTE_DIR" "$CONTAINER" "$IMAGE" "$OPENVPN_PORT" "$ROUTING_MODE" <<'REMOTE'
set -Eeuo pipefail
REMOTE_DIR=$1; CONTAINER=$2; IMAGE=$3; OPENVPN_PORT=$4; ROUTING_MODE=$5
podman rm -f "$CONTAINER" >/dev/null 2>&1 || true
mkdir -p "$REMOTE_DIR/state/sing-box"
rm -f "$REMOTE_DIR/state/sing-box/config.json"
podman run -d --name "$CONTAINER" --replace \
  --privileged \
  --cap-add NET_ADMIN --cap-add NET_RAW \
  --device /dev/net/tun:/dev/net/tun \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  --sysctl net.ipv4.conf.all.rp_filter=0 \
  --sysctl net.ipv4.conf.default.rp_filter=0 \
  -p "${OPENVPN_PORT}:1194/udp" \
  -e VPNKIT_ROUTING_MODE="$ROUTING_MODE" \
  -v "$REMOTE_DIR/secrets/vps/rendered/openvpn:/etc/openvpn:ro" \
  -v "$REMOTE_DIR/secrets/vps/rendered/sing-box:/etc/sing-box:ro" \
  -v "$REMOTE_DIR/secrets/vps/rendered/vibe-vpn:/etc/vibe-vpn:ro" \
  -v "$REMOTE_DIR/state/vibe-vpn:/var/lib/vibe-vpn" \
  -v "$REMOTE_DIR/state/sing-box:/var/lib/vpnkit/sing-box" \
  -v "$REMOTE_DIR/logs:/var/log/vpnkit" \
  -v "$REMOTE_DIR/logs/vibe-vpn:/var/log/vibe-vpn" \
  "$IMAGE"
REMOTE
}

verify_container() {
  remote_sh_timeout "$VERIFY_TIMEOUT" "$CONTAINER" "$LOGS_TIMEOUT" "$VERIFY_TIMEOUT" <<'REMOTE' | redact_stream
set -Eeuo pipefail
CONTAINER=$1; LOGS_TIMEOUT=$2; VERIFY_TIMEOUT=$3
timeout --preserve-status "$VERIFY_TIMEOUT" podman ps --filter "name=^${CONTAINER}$" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
timeout --preserve-status "$LOGS_TIMEOUT" podman logs --tail 80 "$CONTAINER" || true
timeout --preserve-status "$VERIFY_TIMEOUT" podman exec "$CONTAINER" pgrep -a openvpn
timeout --preserve-status "$VERIFY_TIMEOUT" podman exec "$CONTAINER" pgrep -a sing-box
timeout --preserve-status "$VERIFY_TIMEOUT" podman exec "$CONTAINER" sing-box check -c /var/lib/vpnkit/sing-box/config.json
if timeout --preserve-status "$VERIFY_TIMEOUT" podman exec "$CONTAINER" test -r /etc/vibe-vpn/sub_url; then
  timeout --preserve-status "$VERIFY_TIMEOUT" podman exec "$CONTAINER" /usr/local/bin/vibe-vpn doctor --config /etc/vibe-vpn/config.yaml
else
  echo "vibe-vpn doctor skipped: no lab subscription file mounted; OpenVPN/sing-box checks remain authoritative for disabled-daemon lab path"
fi
REMOTE
  [[ -z "$LAN_ENDPOINT" ]] || { log "host LAN ping $LAN_ENDPOINT"; ping -c 2 -W 2 "$LAN_ENDPOINT" || true; }
  [[ -z "$TAILSCALE_ENDPOINT" ]] || { log "host Tailscale ping $TAILSCALE_ENDPOINT"; ping -c 2 -W 2 "$TAILSCALE_ENDPOINT" || true; }
}

case "$ACTION" in
  check-ssh) remote "hostname; podman --version; id -u; test -e /dev/net/tun && echo /dev/net/tun:present || echo /dev/net/tun:missing" ;;
  resolve-remote-dir) normalize_remote_dir ;;
  sync) REMOTE_DIR=$(normalize_remote_dir); sync_context ;;
  build) REMOTE_DIR=$(normalize_remote_dir); build_image ;;
  run) REMOTE_DIR=$(normalize_remote_dir); run_container ;;
  deploy) REMOTE_DIR=$(normalize_remote_dir); sync_context; build_image; run_container; sleep 5; verify_container ;;
  status) remote "podman ps -a --filter 'name=^${CONTAINER}$' --format 'table {{.Names}}\\t{{.Status}}\\t{{.Image}}\\t{{.Ports}}'" ;;
  verify) verify_container ;;
  logs) remote_timeout "$LOGS_TIMEOUT" "podman logs --tail 200 '$CONTAINER'" | redact_stream ;;
  stop) remote "podman stop '$CONTAINER' || true" ;;
  cleanup) remote "podman rm -f '$CONTAINER' || true; if [[ '$REMOVE_IMAGE' = 1 ]]; then podman rmi '$IMAGE' || true; fi" ;;
  *) echo "unknown action: $ACTION" >&2; usage >&2; exit 2 ;;
esac
