#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

install_dir=$(dirname "$SINGNOX_SINGBOX_BIN")
mkdir -p "$install_dir"

if command -v "$SINGNOX_SINGBOX_BIN" >/dev/null 2>&1; then
  log "sing-box already present at $SINGNOX_SINGBOX_BIN"
  "$SINGNOX_SINGBOX_BIN" version | head -5
  exit 0
fi

if [[ -n "${SINGNOX_SINGBOX_SOURCE_BIN:-}" ]]; then
  source_bin=$(path_from_package "$SINGNOX_SINGBOX_SOURCE_BIN")
  [[ -x "$source_bin" || -r "$source_bin" ]] || { echo "missing source binary: $source_bin" >&2; exit 12; }
  install -m 0755 "$source_bin" "$SINGNOX_SINGBOX_BIN"
  log "installed sing-box from local source binary to $SINGNOX_SINGBOX_BIN"
  "$SINGNOX_SINGBOX_BIN" version | head -5
  exit 0
fi

if [[ -n "${SINGNOX_SINGBOX_SOURCE_ARCHIVE:-}" ]]; then
  archive=$(path_from_package "$SINGNOX_SINGBOX_SOURCE_ARCHIVE")
  [[ -r "$archive" ]] || { echo "missing source archive: $archive" >&2; exit 12; }
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  tar -xf "$archive" -C "$tmp"
  found=$(find "$tmp" -type f -name sing-box -perm -u+x | head -1)
  [[ -n "$found" ]] || { echo "archive did not contain executable sing-box" >&2; exit 12; }
  install -m 0755 "$found" "$SINGNOX_SINGBOX_BIN"
  log "installed sing-box from local archive to $SINGNOX_SINGBOX_BIN"
  "$SINGNOX_SINGBOX_BIN" version | head -5
  exit 0
fi

cat >&2 <<MSG
sing-box is not installed at $SINGNOX_SINGBOX_BIN.
Place an operator-provided binary or release archive under this package's ignored local/ directory, then set one of these in .env:
  SINGNOX_SINGBOX_SOURCE_BIN=local/sing-box
  SINGNOX_SINGBOX_SOURCE_ARCHIVE=local/sing-box-linux-amd64.tar.gz
This script intentionally does not download binaries by default.
MSG
exit 2
