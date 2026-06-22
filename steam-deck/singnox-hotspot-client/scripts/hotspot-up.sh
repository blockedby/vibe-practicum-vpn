#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

require_repo_helper
[[ -r "$SINGNOX_HY2_CLIENT_CONFIG" ]] || { echo "missing Hysteria2 client config: $SINGNOX_HY2_CLIENT_CONFIG" >&2; exit 12; }
[[ ${#SINGNOX_HOTSPOT_PASSWORD} -ge 8 ]] || { echo "set SINGNOX_HOTSPOT_PASSWORD in .env or DECK_HOTSPOT_PASSWORD in the shell" >&2; exit 12; }

"$SCRIPT_DIR/render-sing-box-config.sh"
export_deck_helper_env
exec "$SINGNOX_REPO_ROOT/scripts/deck/deck-hy2-hotspot.sh" up \
  --ssh-target "$SINGNOX_SSH_TARGET" \
  --client-config "$SINGNOX_HY2_CLIENT_CONFIG" \
  --remote-state "$SINGNOX_REMOTE_STATE" \
  --report-dir "$SINGNOX_REPORT_DIR"
