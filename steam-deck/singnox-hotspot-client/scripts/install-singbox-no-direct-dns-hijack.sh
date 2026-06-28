#!/usr/bin/env bash
set -Eeuo pipefail

# Usage:
#   sudo ./scripts/install-singbox-no-direct-dns-hijack.sh [options]
#
# Applies a provided temp config to /etc/sing-box/config.json, backups current config,
# and restarts sing-box.service.
#
# Options:
#   --input FILE          Source config (default: /tmp/config.json.no-direct-dns-hijack)
#   --target FILE         Destination config (default: /etc/sing-box/config.json)
#   --service NAME        systemd service (default: sing-box.service)
#   --no-restart          Render/copy only, do not restart
#   --mode local|deck      Preserve mode note in logs only (default: local)
#   -h, --help

USAGE='Usage: install-singbox-no-direct-dns-hijack.sh [--input FILE] [--target FILE] [--service NAME] [--no-restart]'

INPUT="/tmp/config.json.no-direct-dns-hijack"
TARGET="/etc/sing-box/config.json"
SERVICE="sing-box.service"
DO_RESTART=1
MODE="local"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      INPUT=${2:?}
      shift 2
      ;;
    --target)
      TARGET=${2:?}
      shift 2
      ;;
    --service)
      SERVICE=${2:?}
      shift 2
      ;;
    --mode)
      MODE=${2:?}
      shift 2
      ;;
    --no-restart)
      DO_RESTART=0
      shift
      ;;
    -h|--help)
      echo "$USAGE"
      exit 0
      ;;
    *)
      echo "unknown argument: $1"
      echo "$USAGE"
      exit 1
      ;;
  esac
done

if [[ ! -r "$INPUT" ]]; then
  echo "missing readable input config: $INPUT" >&2
  exit 1
fi

run_as_root() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

BACKUP="${TARGET}.backup.$(date -u +%Y%m%dT%H%M%SZ)"
run_as_root cp -p "$TARGET" "$BACKUP"
echo "backup=$BACKUP"
run_as_root install -m 600 "$INPUT" "$TARGET"
echo "installed=$TARGET"
echo "mode=$MODE"

if [[ "$DO_RESTART" -eq 1 ]]; then
  if command -v systemctl >/dev/null 2>&1; then
    run_as_root systemctl restart "$SERVICE"
    echo "restart=$SERVICE"
    run_as_root systemctl status --no-pager "$SERVICE" | sed -n '1,5p'
  else
    echo "systemctl unavailable; restart manually"
    exit 1
  fi
else
  echo "restart skipped"
fi

echo "
Rollback:
  sudo cp -p \"$BACKUP\" \"$TARGET\"\n  sudo systemctl restart \"$SERVICE\""