#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

USAGE=$(cat <<'EOF'
Usage: deploy-local-singbox-config.sh [--client-config PATH] [--target PATH] [--service NAME] [--no-restart]

Apply rendered sing-box config to this host's local sing-box config path.

Options:
  --client-config PATH   Hysteria2 YAML/URI file (default: SINGNOX_HY2_CLIENT_CONFIG)
  --target PATH          Target config path (default: /etc/sing-box/config.json)
  --service NAME         systemd unit to restart (default: sing-box.service or SINGNOX_SINGBOX_SERVICE)
  --no-restart           Render/install only, do not restart service
  -h, --help            Show help
EOF
)

if [[ ${1-} == -h || ${1-} == --help ]]; then
  echo "$USAGE"
  exit 0
fi

TARGET_SYSTEM_CONFIG="/etc/sing-box/config.json"
SINGBOX_SERVICE="${SINGNOX_SINGBOX_SERVICE:-sing-box.service}"
DO_RESTART=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --client-config)
      SINGNOX_HY2_CLIENT_CONFIG=${2:?}
      shift 2
      ;;
    --target)
      TARGET_SYSTEM_CONFIG=${2:?}
      shift 2
      ;;
    --service)
      SINGBOX_SERVICE=${2:?}
      shift 2
      ;;
    --no-restart)
      DO_RESTART=0
      shift
      ;;
    *)
      echo "unknown argument: $1"
      echo "$USAGE" >&2
      exit 1
      ;;
  esac
done

if ! [[ -r "$SINGNOX_HY2_CLIENT_CONFIG" ]]; then
  echo "missing Hysteria2 client config: ${SINGNOX_HY2_CLIENT_CONFIG}" >&2
  echo "$USAGE" >&2
  exit 1
fi

run_as_root() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    if sudo -n "$@"; then
      :
    else
      echo "sudo requires interactive auth; re-running with prompt (if allowed)..." >&2
      sudo "$@"
    fi
  fi
}

target_config=$SINGNOX_HY2_CLIENT_CONFIG
rendered_config=$SINGNOX_OUTPUT_CONFIG

echo "rendering config from: $target_config"
SINGNOX_HY2_CLIENT_CONFIG="$target_config" \
  "$SCRIPT_DIR/render-sing-box-config.sh"

if ! [[ -r "$rendered_config" ]]; then
  echo "render failed: expected $rendered_config" >&2
  exit 1
fi

backup_path="${TARGET_SYSTEM_CONFIG}.backup.$(date -u +%Y%m%dT%H%M%SZ)"
if [[ -r "$TARGET_SYSTEM_CONFIG" ]]; then
  run_as_root cp -p "$TARGET_SYSTEM_CONFIG" "$backup_path"
  echo "backup=$backup_path"
else
  echo "backup: no existing $TARGET_SYSTEM_CONFIG"
fi

run_as_root install -m 600 "$rendered_config" "$TARGET_SYSTEM_CONFIG"
echo "installed=$TARGET_SYSTEM_CONFIG"

if [[ "$DO_RESTART" -ne 1 ]]; then
  echo "restart skipped (--no-restart)"
  echo ""
  echo "Rollback:
  run_as_root cp -p \"$backup_path\" \"$TARGET_SYSTEM_CONFIG\" && run_as_root systemctl restart \"$SINGBOX_SERVICE\""
  exit 0
fi

if command -v systemctl >/dev/null 2>&1; then
  run_as_root systemctl restart "$SINGBOX_SERVICE"
  echo "restart=$SINGBOX_SERVICE"
  run_as_root systemctl status --no-pager "$SINGBOX_SERVICE" | sed -n '1,5p'
else
  echo "systemctl not available; restart manually"
  echo ""
  echo "Rollback:
  run_as_root cp -p \"$backup_path\" \"$TARGET_SYSTEM_CONFIG\""
  exit 1
fi

echo ""
echo "Rollback:
  run_as_root cp -p \"$backup_path\" \"$TARGET_SYSTEM_CONFIG\"\n  run_as_root systemctl restart \"$SINGBOX_SERVICE\""
