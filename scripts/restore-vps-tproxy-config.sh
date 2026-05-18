#!/usr/bin/env bash
set -euo pipefail

SSH_HOST="${SSH_HOST:-vibe-practicum}"
CONFIG="${CONFIG:-/etc/sing-box-vibe/tproxy-canary.json}"
BACKUP_DIR="${BACKUP_DIR:-/etc/sing-box-vibe/backups}"
BACKUP_PATH="${BACKUP_PATH:-}"
LIST_BACKUPS="${LIST_BACKUPS:-0}"
VIBE_PRACTICUM_SUDO_PASSWORD="${VIBE_PRACTICUM_SUDO_PASSWORD:-}"

ssh "$SSH_HOST" \
  "CONFIG='$CONFIG' BACKUP_DIR='$BACKUP_DIR' BACKUP_PATH='$BACKUP_PATH' LIST_BACKUPS='$LIST_BACKUPS' VIBE_PRACTICUM_SUDO_PASSWORD='$VIBE_PRACTICUM_SUDO_PASSWORD' bash -s" <<'REMOTE'
set -euo pipefail
sudo_cmd() {
  if [[ -n "${VIBE_PRACTICUM_SUDO_PASSWORD:-}" ]]; then
    printf '%s\n' "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S "$@"
  else
    sudo -n "$@"
  fi
}

if [[ "$LIST_BACKUPS" == "1" ]]; then
  sudo_cmd find "$BACKUP_DIR" -maxdepth 1 -type f -name 'tproxy-canary.json.*.bak' -printf '%TY-%Tm-%Td %TH:%TM:%TS %p\n' 2>/dev/null | sort || true
  exit 0
fi

if [[ -z "$BACKUP_PATH" ]]; then
  BACKUP_PATH="$(sudo_cmd find "$BACKUP_DIR" -maxdepth 1 -type f -name 'tproxy-canary.json.*.bak' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1 {print $2}')"
fi

if [[ -z "$BACKUP_PATH" ]]; then
  echo "no backup found in $BACKUP_DIR" >&2
  exit 2
fi

sudo_cmd test -r "$BACKUP_PATH"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
sudo_cmd cp "$BACKUP_PATH" "$tmp"
sudo_cmd chown "$(id -u):$(id -g)" "$tmp"

sing-box check -c "$tmp"

restore_backup="$CONFIG.pre-restore.$(date -u +%Y%m%dT%H%M%SZ).bak"
sudo_cmd cp -a "$CONFIG" "$restore_backup"
sudo_cmd install -m 0644 "$tmp" "$CONFIG"
sudo_cmd systemctl restart sing-box-vibe-router
sudo_cmd systemctl is-active --quiet sing-box-vibe-router

echo "restored $CONFIG from $BACKUP_PATH"
echo "pre-restore copy saved at $restore_backup"
REMOTE
