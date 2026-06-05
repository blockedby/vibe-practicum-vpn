#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

START=0
usage(){ cat <<'USAGE'
Usage: ./scripts/install.sh [--start]

Prepare the local Steam Deck host OpenVPN client runtime. This creates local
ignored directories, copies .env.example to .env when absent, builds the Podman
image, and optionally starts it with --start.
USAGE
}
while [[ $# -gt 0 ]]; do case "$1" in
  --start) START=1; shift;;
  -h|--help) usage; exit 0;;
  *) echo "unknown argument: $1" >&2; usage >&2; exit 2;;
esac; done

REPORT=$(new_report_path install)
{
  write_header "Steam Deck host OpenVPN client install"
  preflight_common
  if [[ ! -f "$ENV_FILE" ]]; then
    run cp "$STEAM_DECK_CLIENT_DIR/.env.example" "$ENV_FILE"
    log "created .env from .env.example"
  else
    log ".env already exists; leaving it unchanged"
  fi
  run mkdir -p "$STEAM_DECK_CLIENT_DIR/local" "$LOG_DIR" "$REPORT_DIR"
  log "building image via ${PODMAN_CMD[*]}"
  run podman_cmd build -t "$IMAGE" -f "$STEAM_DECK_CLIENT_DIR/Containerfile" "$STEAM_DECK_CLIENT_DIR"
  if [[ $START -eq 1 ]]; then
    log "--start requested; chaining to up.sh"
    "$SCRIPT_DIR/up.sh"
  else
    log "install done; place client profile at $PROFILE then run ./scripts/up.sh"
  fi
} 2>&1 | redact | tee "$REPORT"
echo "report_path=$REPORT"
