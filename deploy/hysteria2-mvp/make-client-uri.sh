#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE=${HY2_ENV_FILE:-"$SCRIPT_DIR/server.env"}
PRINT_QR=1

usage() {
  cat <<'EOF'
Usage: make-client-uri.sh [options]

Print a Hysteria 2 onboarding URI from the server env. If qrencode is installed,
also print an ANSI QR code suitable for scanning in mobile clients.

Options:
  --env-file PATH     Server env file to source (default: ./server.env)
  --no-qr             Print URI only
  -h, --help          Show this help

Required env is the same as run-client-podman.sh:
  HY2_AUTH_PASSWORD, HY2_OBFS_PASSWORD, HY2_PIN_SHA256/HY2_CERT_PIN_SHA256/
  HY2_CERT_SHA256, and HY2_SERVER or host+port keys. HY2_INSECURE defaults to true for the self-signed
  MVP cert and HY2_SNI defaults to HY2_PUBLIC_HOST or positions.peacedata.company.
EOF
}

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

abspath() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$PWD" "$1" ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || die "--env-file requires a path"
      ENV_FILE=$2
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

ENV_FILE=$(abspath "$ENV_FILE")
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
else
  log "warning: env file not found: $ENV_FILE; using already-exported environment"
fi

first_nonempty() {
  local name
  for name in "$@"; do
    if [[ -n "${!name:-}" ]]; then
      printf '%s\n' "${!name}"
      return 0
    fi
  done
  return 1
}

require_value() {
  local value=$1
  local label=$2
  [[ -n "$value" ]] || die "missing $label in env"
  printf '%s\n' "$value"
}

format_host_port() {
  local host=$1
  local port=$2
  if [[ "$host" == \[*\] ]]; then
    printf '%s:%s\n' "$host" "$port"
  elif [[ "$host" == *:* ]]; then
    printf '[%s]:%s\n' "$host" "$port"
  else
    printf '%s:%s\n' "$host" "$port"
  fi
}

urlencode() {
  local value=$1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$value"
  elif command -v python >/dev/null 2>&1; then
    python -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$value"
  else
    die "python3 is required for percent-encoding URI values"
  fi
}

server_port=$(first_nonempty HY2_PUBLIC_PORT HY2_PORT HY2_UDP_PORT || true)
server_port=${server_port:-18443}
server=$(first_nonempty HY2_SERVER HY2_SERVER_ADDR || true)
if [[ -z "$server" ]]; then
  server_host=$(first_nonempty HY2_HOST HY2_PUBLIC_HOST HY2_DOMAIN HY2_SERVER_HOST VPS_HOST VPS_IP || true)
  server_host=$(require_value "$server_host" "server host (HY2_SERVER or HY2_HOST/HY2_PUBLIC_HOST/HY2_DOMAIN/VPS_HOST)")
  server=$(format_host_port "$server_host" "$server_port")
elif [[ "$server" != *:* && "$server" != *,* ]]; then
  server=$(format_host_port "$server" "$server_port")
fi

auth_password=$(first_nonempty HY2_AUTH_PASSWORD HY2_PASSWORD AUTH_PASSWORD || true)
auth_password=$(require_value "$auth_password" "HY2_AUTH_PASSWORD")
obfs_password=$(first_nonempty HY2_OBFS_PASSWORD OBFS_PASSWORD || true)
obfs_password=$(require_value "$obfs_password" "HY2_OBFS_PASSWORD")

pin_sha256=$(first_nonempty HY2_PIN_SHA256 HY2_CERT_PIN_SHA256 HY2_CERT_SHA256 CERT_SHA256 || true)
if [[ -z "$pin_sha256" ]]; then
  cert_candidates=()
  [[ -n "${HY2_CERT_PATH:-}" ]] && cert_candidates+=("$HY2_CERT_PATH")
  cert_candidates+=("$(dirname -- "$ENV_FILE")/server.crt" "/opt/vibe-hy2-mvp/server.crt")
  for cert in "${cert_candidates[@]}"; do
    if [[ -r "$cert" ]]; then
      command -v openssl >/dev/null 2>&1 || die "openssl is required to compute HY2_PIN_SHA256 from $cert"
      pin_sha256=$(openssl x509 -noout -fingerprint -sha256 -in "$cert" | sed 's/^.*=//')
      break
    fi
  done
fi
pin_sha256=$(require_value "$pin_sha256" "HY2_PIN_SHA256/HY2_CERT_PIN_SHA256/HY2_CERT_SHA256 or readable server.crt")

sni=${HY2_SNI:-${HY2_PUBLIC_HOST:-positions.peacedata.company}}
insecure=${HY2_INSECURE:-true}
case "${insecure,,}" in
  1|true|yes|on) insecure=1 ;;
  0|false|no|off) insecure=0 ;;
  *) die "HY2_INSECURE must be true/false or 1/0" ;;
esac

uri="hysteria2://$(urlencode "$auth_password")@${server}/?insecure=${insecure}&pinSHA256=$(urlencode "$pin_sha256")&obfs=salamander&obfs-password=$(urlencode "$obfs_password")&sni=$(urlencode "$sni")"

printf '%s\n' "$uri"

if [[ "$PRINT_QR" -eq 1 ]]; then
  if command -v qrencode >/dev/null 2>&1; then
    printf '\n'
    qrencode -t ANSIUTF8 "$uri"
  else
    log "qrencode not found; printed URI only"
  fi
fi
