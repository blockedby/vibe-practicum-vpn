#!/usr/bin/env bash
set -eu

# Roll back only the Hysteria 2 MVP server resources created by install-vps.sh.
# It intentionally does not stop/restart/disable tailscaled or sing-box services
# and does not edit any existing routing or iptables policy.

CONTAINER_NAME="${CONTAINER_NAME:-vibe-hy2-mvp}"
STATE_DIR="${STATE_DIR:-/opt/vibe-hy2-mvp}"
ENV_FILE="$STATE_DIR/state.env"
HY2_PUBLIC_PORT="${HY2_PUBLIC_PORT:-18443}"
DRY_RUN=0

usage() {
  cat <<USAGE
Usage: $0 [--dry-run]

Removes only:
  - Docker container named $CONTAINER_NAME
  - UFW allow rule for HY2_PUBLIC_PORT/udp (default/current: $HY2_PUBLIC_PORT/udp)
  - State directory $STATE_DIR
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

fatal() {
  echo "ERROR: $*" >&2
  exit 1
}

validate_state_dir() {
  case "$STATE_DIR" in
    /opt/vibe-hy2-mvp|/opt/vibe-hy2-mvp/*) ;;
    *) fatal "STATE_DIR must be /opt/vibe-hy2-mvp or below it, got: $STATE_DIR" ;;
  esac
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+ '
    printf '%s ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

validate_state_dir

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run: no changes made. Planned rollback commands:"
else
  [ "$(id -u)" -eq 0 ] || fatal "run as root on the VPS"
fi

if command -v docker >/dev/null 2>&1; then
  if docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
    run docker rm -f "$CONTAINER_NAME"
  else
    echo "Docker container not present: $CONTAINER_NAME"
  fi
else
  echo "WARN: docker not found; cannot remove container $CONTAINER_NAME" >&2
fi

if command -v ufw >/dev/null 2>&1; then
  run ufw delete allow "${HY2_PUBLIC_PORT}/udp" || true
else
  echo "WARN: ufw not found; remove UDP ${HY2_PUBLIC_PORT} from your VPS firewall if needed" >&2
fi

if [ -d "$STATE_DIR" ]; then
  run rm -rf -- "$STATE_DIR"
else
  echo "State directory not present: $STATE_DIR"
fi

cat <<DONE

Rollback complete/planned for $CONTAINER_NAME.
Post-rollback read-only checks you may run:
  systemctl is-active tailscaled.service sing-box-vibe-router.service
  ss -lunp | grep '${HY2_PUBLIC_PORT}' || true
  docker ps --filter name=${CONTAINER_NAME}
DONE
