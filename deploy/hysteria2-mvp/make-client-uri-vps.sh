#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SSH_HOST=${SSH_HOST:-${VPNKIT_VPS_SSH_HOST:-example-vps-host}}
REMOTE_ENV=${HY2_REMOTE_ENV:-/opt/vibe-hy2-mvp/server.env}
LOCAL_ENV=${HY2_LOCAL_ENV:-}
PRINT_QR=1

usage() {
  cat <<'EOF'
Usage: make-client-uri-vps.sh [options]

Fetch the private Hysteria 2 MVP server env from the VPS over SSH and print the
onboarding hysteria2:// URI. If qrencode is installed locally, an ANSI QR is
printed too.

Options:
  --ssh-host HOST       SSH host alias (default: ${VPNKIT_VPS_SSH_HOST:-example-vps-host})
  --remote-env PATH     Remote env path (default: /opt/vibe-hy2-mvp/server.env)
  --local-env PATH      Use an existing local env file instead of SSH fetch
  --no-qr               Print URI only
  -h, --help            Show this help

Security: the printed URI/QR contains the shared HY2 auth and obfs secrets.
Only run this in a trusted terminal/chat.
EOF
}

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh-host)
      [[ $# -ge 2 ]] || die "--ssh-host requires a value"
      SSH_HOST=$2
      shift 2
      ;;
    --remote-env)
      [[ $# -ge 2 ]] || die "--remote-env requires a path"
      REMOTE_ENV=$2
      shift 2
      ;;
    --local-env)
      [[ $# -ge 2 ]] || die "--local-env requires a path"
      LOCAL_ENV=$2
      shift 2
      ;;
    --no-qr)
      PRINT_QR=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

if [[ -n "$LOCAL_ENV" ]]; then
  [[ -r "$LOCAL_ENV" ]] || die "local env is not readable: $LOCAL_ENV"
  args=(--env-file "$LOCAL_ENV")
  [[ "$PRINT_QR" -eq 0 ]] && args+=(--no-qr)
  exec "$SCRIPT_DIR/make-client-uri.sh" "${args[@]}"
fi

command -v ssh >/dev/null 2>&1 || die "ssh not found"
[[ -x "$SCRIPT_DIR/make-client-uri.sh" ]] || die "missing executable: $SCRIPT_DIR/make-client-uri.sh"

tmp=$(mktemp "${TMPDIR:-/tmp}/vibe-hy2-env.XXXXXX")
chmod 0600 "$tmp"
cleanup() {
  if command -v shred >/dev/null 2>&1; then
    shred -u "$tmp" 2>/dev/null || rm -f "$tmp"
  else
    rm -f "$tmp"
  fi
}
trap cleanup EXIT

ssh -o ControlMaster=no -o ControlPath=none "$SSH_HOST" \
  "sudo -n test -r '$REMOTE_ENV' && sudo -n cat '$REMOTE_ENV'" > "$tmp"

args=(--env-file "$tmp")
[[ "$PRINT_QR" -eq 0 ]] && args+=(--no-qr)
exec "$SCRIPT_DIR/make-client-uri.sh" "${args[@]}"
