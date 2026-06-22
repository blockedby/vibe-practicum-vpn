#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

require_repo_helper
export_deck_helper_env
exec "$SINGNOX_REPO_ROOT/scripts/deck/deck-hy2-hotspot.sh" down \
  --ssh-target "$SINGNOX_SSH_TARGET" \
  --remote-state "$SINGNOX_REMOTE_STATE" \
  --report-dir "$SINGNOX_REPORT_DIR"
