#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE=${HY2_ENV_FILE:-"$SCRIPT_DIR/server.env"}
CONFIG_FILE=${HY2_CLIENT_CONFIG:-"$SCRIPT_DIR/client.yaml"}
TEMPLATE_FILE=${HY2_CLIENT_TEMPLATE:-"$SCRIPT_DIR/client.yaml.template"}
IMAGE=${HY2_IMAGE:-"docker.io/tobyxdd/hysteria:v2.8.2"}
CONTAINER_NAME=${HY2_CLIENT_CONTAINER:-"vibe-hy2-client"}
RENDER_ONLY=0

usage() {
  cat <<'EOF'
Usage: run-client-podman.sh [options]

Render client.yaml from the Hysteria 2 server env, then run a local Podman
sandbox client exposing only loopback proxies:
  SOCKS5 127.0.0.1:1080
  HTTP   127.0.0.1:8081

Options:
  --env-file PATH     Server env file to source (default: ./server.env)
  --config PATH       Rendered client config path (default: ./client.yaml)
  --template PATH     Client template path (default: ./client.yaml.template)
  --image IMAGE       Hysteria image (default: docker.io/tobyxdd/hysteria:v2.8.2)
  --name NAME         Podman container name (default: vibe-hy2-client)
  --render-only       Only render client.yaml; do not start Podman
  -h, --help          Show this help

Accepted env keys:
  Required: HY2_AUTH_PASSWORD, HY2_OBFS_PASSWORD, and HY2_PIN_SHA256
            (or HY2_CERT_PIN_SHA256/HY2_CERT_SHA256/CERT_SHA256, or a
            readable server.crt)
  Server:   HY2_SERVER or HY2_SERVER_ADDR, otherwise HY2_HOST/HY2_PUBLIC_HOST/
            HY2_DOMAIN/HY2_SERVER_HOST/VPS_HOST/VPS_IP plus HY2_PORT
  Optional: HY2_PORT or HY2_PUBLIC_PORT (default 18443), HY2_SNI
            (default HY2_PUBLIC_HOST or positions.peacedata.company), HY2_INSECURE (default true)
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
    --config)
      [[ $# -ge 2 ]] || die "--config requires a path"
      CONFIG_FILE=$2
      shift 2
      ;;
    --template)
      [[ $# -ge 2 ]] || die "--template requires a path"
      TEMPLATE_FILE=$2
      shift 2
      ;;
    --image)
      [[ $# -ge 2 ]] || die "--image requires an image"
      IMAGE=$2
      shift 2
      ;;
    --name)
      [[ $# -ge 2 ]] || die "--name requires a container name"
      CONTAINER_NAME=$2
      shift 2
      ;;
    --render-only)
      RENDER_ONLY=1
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
CONFIG_FILE=$(abspath "$CONFIG_FILE")
TEMPLATE_FILE=$(abspath "$TEMPLATE_FILE")

if [[ -f "$ENV_FILE" ]]; then
  # The env file is trusted server output copied locally for onboarding.
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
    # Treat a bare colon-containing host as IPv6 and bracket it for host:port.
    printf '[%s]:%s\n' "$host" "$port"
  else
    printf '%s:%s\n' "$host" "$port"
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
  1|true|yes|on) insecure=true ;;
  0|false|no|off) insecure=false ;;
  *) die "HY2_INSECURE must be true/false or 1/0" ;;
esac

reject_newline() {
  local value=$1
  local label=$2
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    die "$label must not contain newlines"
  fi
}

yaml_quote() {
  reject_newline "$1" "YAML value"
  local s=$1
  s=${s//\'/\'\'}
  printf "'%s'" "$s"
}

sed_replacement_escape() {
  printf '%s' "$1" | sed -e 's/[|&\\]/\\&/g'
}

[[ -f "$TEMPLATE_FILE" ]] || die "template not found: $TEMPLATE_FILE"
mkdir -p -- "$(dirname -- "$CONFIG_FILE")"

sed \
  -e "s|{{HY2_SERVER}}|$(sed_replacement_escape "$(yaml_quote "$server")")|g" \
  -e "s|{{HY2_AUTH_PASSWORD}}|$(sed_replacement_escape "$(yaml_quote "$auth_password")")|g" \
  -e "s|{{HY2_TLS_INSECURE}}|$insecure|g" \
  -e "s|{{HY2_PIN_SHA256}}|$(sed_replacement_escape "$(yaml_quote "$pin_sha256")")|g" \
  -e "s|{{HY2_SNI}}|$(sed_replacement_escape "$(yaml_quote "$sni")")|g" \
  -e "s|{{HY2_OBFS_PASSWORD}}|$(sed_replacement_escape "$(yaml_quote "$obfs_password")")|g" \
  "$TEMPLATE_FILE" >"$CONFIG_FILE"

log "rendered client config: $CONFIG_FILE"

if [[ "$RENDER_ONLY" -eq 1 ]]; then
  exit 0
fi

command -v podman >/dev/null 2>&1 || die "podman not found"

log "starting $CONTAINER_NAME with loopback-only host ports 127.0.0.1:1080 and 127.0.0.1:8081"
log "this does not add host routes, TUN devices, TPROXY rules, or host-network mode"

exec podman run --rm --name "$CONTAINER_NAME" \
  -p 127.0.0.1:1080:1080/tcp \
  -p 127.0.0.1:8081:8081/tcp \
  -v "$CONFIG_FILE:/etc/hysteria/client.yaml:ro,Z" \
  "$IMAGE" \
  client -c /etc/hysteria/client.yaml
