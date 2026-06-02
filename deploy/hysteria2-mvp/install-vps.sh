#!/usr/bin/env bash
set -eu

# Install the Hysteria 2 MVP server on the VPS using Docker only.
# Rollback is intentionally simple:
#   docker rm -f vibe-hy2-mvp || true
#   ufw delete allow 18443/udp || true
#   rm -rf /opt/vibe-hy2-mvp
# This script never starts/stops/restarts tailscaled or sing-box services.

CONTAINER_NAME="${CONTAINER_NAME:-vibe-hy2-mvp}"
STATE_DIR="${STATE_DIR:-/opt/vibe-hy2-mvp}"
IMAGE="${HY2_IMAGE:-docker.io/tobyxdd/hysteria:v2.8.2}"
HY2_PUBLIC_PORT="${HY2_PUBLIC_PORT:-18443}"
HY2_LISTEN_PORT="${HY2_LISTEN_PORT:-$HY2_PUBLIC_PORT}"
SING_BOX_SOCKS_ADDR="${SING_BOX_SOCKS_ADDR:-192.0.2.10:2080}"
HY2_PUBLIC_HOST="${HY2_PUBLIC_HOST:-example-private-node.invalid}"
HY2_SNI="${HY2_SNI:-$HY2_PUBLIC_HOST}"
HY2_CERT_CN="${HY2_CERT_CN:-$HY2_PUBLIC_HOST}"
HY2_CERT_DAYS="${HY2_CERT_DAYS:-3650}"
DRY_RUN=0

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEMPLATE="$SCRIPT_DIR/server.yaml.template"
ENV_FILE="$STATE_DIR/state.env"
SERVER_CONFIG="$STATE_DIR/server.yaml"
CERT_FILE="$STATE_DIR/server.crt"
KEY_FILE="$STATE_DIR/server.key"

usage() {
  cat <<USAGE
Usage: $0 [--dry-run]

Environment overrides, intended to be set before the first install:
  HY2_PUBLIC_PORT        UDP port exposed on the VPS (default: 18443)
  HY2_LISTEN_PORT        Hysteria listen port in host-network mode (default: HY2_PUBLIC_PORT)
  SING_BOX_SOCKS_ADDR    existing sing-box SOCKS listener (default: 192.0.2.10:2080 placeholder; set real value before install)
  HY2_IMAGE              Docker image (default: docker.io/tobyxdd/hysteria:v2.8.2)
  HY2_PUBLIC_HOST        host/IP printed in the client URI (default: example-private-node.invalid)
  HY2_SNI                SNI for client URI/config (default: HY2_PUBLIC_HOST)
  STATE_DIR              state directory under /opt/vibe-hy2-mvp (default: /opt/vibe-hy2-mvp)

If $ENV_FILE already exists, its values are reused for idempotency. To change
ports/secrets after install, edit that file or roll back and reinstall.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

fatal() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fatal "required command not found: $1"
}

validate_state_dir() {
  case "$STATE_DIR" in
    /opt/vibe-hy2-mvp|/opt/vibe-hy2-mvp/*) ;;
    *) fatal "STATE_DIR must be /opt/vibe-hy2-mvp or below it, got: $STATE_DIR" ;;
  esac
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\\&/]/\\&/g'
}

render_template() {
  tmp=$(mktemp "$STATE_DIR/server.yaml.XXXXXX")
  sed \
    -e "s/{{HY2_LISTEN_PORT}}/$(escape_sed_replacement "$HY2_LISTEN_PORT")/g" \
    -e "s/{{HY2_AUTH_PASSWORD}}/$(escape_sed_replacement "$HY2_AUTH_PASSWORD")/g" \
    -e "s/{{HY2_OBFS_PASSWORD}}/$(escape_sed_replacement "$HY2_OBFS_PASSWORD")/g" \
    -e "s/{{SING_BOX_SOCKS_ADDR}}/$(escape_sed_replacement "$SING_BOX_SOCKS_ADDR")/g" \
    "$TEMPLATE" > "$tmp"
  if grep -q '{{' "$tmp"; then
    rm -f "$tmp"
    fatal "unrendered placeholder left in $TEMPLATE"
  fi
  chmod 0644 "$tmp"
  mv "$tmp" "$SERVER_CONFIG"
}

cert_pin_sha256() {
  # Hysteria's tls.pinSHA256 expects the OpenSSL SHA-256 fingerprint form.
  openssl x509 -noout -fingerprint -sha256 -in "$CERT_FILE" | sed 's/^.*=//'
}

urlencode() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
  else
    # Good enough for generated values; python3 path above is preferred.
    printf '%s' "$1" | sed -e 's/%/%25/g' -e 's/+/%2B/g' -e 's,/,%2F,g' -e 's/:/%3A/g' -e 's/=/%3D/g'
  fi
}

print_plan() {
  cat <<PLAN
Dry run: no changes made.
Would:
  - create/reuse $STATE_DIR
  - generate random auth and Salamander obfs secrets if missing
  - generate a self-signed certificate and pinSHA256 if missing
  - render $SERVER_CONFIG from $TEMPLATE
  - add UFW rule: allow ${HY2_PUBLIC_PORT}/udp comment 'vibe hy2 mvp'
  - pull Docker image: $IMAGE
  - recreate only Docker container: $CONTAINER_NAME
  - run the Hysteria container with Docker host networking and listen on UDP ${HY2_LISTEN_PORT}
  - mount $STATE_DIR read-only at /etc/hysteria
  - route Hysteria outbounds through SOCKS5 $SING_BOX_SOCKS_ADDR
Would not:
  - use Podman
  - add any extra Linux capability
  - stop, restart, disable, or edit tailscaled/sing-box services
PLAN
}

validate_state_dir
[ -f "$TEMPLATE" ] || fatal "missing template: $TEMPLATE"

if [ "$DRY_RUN" -eq 1 ]; then
  print_plan
  exit 0
fi

[ "$(id -u)" -eq 0 ] || fatal "run as root on the VPS"
require_cmd docker
require_cmd openssl
require_cmd sed
require_cmd mktemp

if command -v systemctl >/dev/null 2>&1; then
  systemctl is-active --quiet tailscaled.service \
    || fatal "tailscaled.service is not active; refusing to deploy without the expected baseline"
  systemctl is-active --quiet sing-box-vibe-router.service \
    || fatal "sing-box-vibe-router.service is not active; refusing to deploy without the required SOCKS baseline"
fi

install -d -m 0700 "$STATE_DIR"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi

case "$SING_BOX_SOCKS_ADDR" in
  ""|192.0.2.10:2080)
    fatal "set SING_BOX_SOCKS_ADDR to the real private sing-box SOCKS listener before installing"
    ;;
esac

HY2_AUTH_PASSWORD="${HY2_AUTH_PASSWORD:-$(openssl rand -hex 32)}"
HY2_OBFS_PASSWORD="${HY2_OBFS_PASSWORD:-$(openssl rand -hex 32)}"
HY2_PUBLIC_PORT="${HY2_PUBLIC_PORT:-18443}"
HY2_LISTEN_PORT="${HY2_LISTEN_PORT:-$HY2_PUBLIC_PORT}"
SING_BOX_SOCKS_ADDR="${SING_BOX_SOCKS_ADDR:-192.0.2.10:2080}"
HY2_PUBLIC_HOST="${HY2_PUBLIC_HOST:-example-private-node.invalid}"
HY2_SNI="${HY2_SNI:-$HY2_PUBLIC_HOST}"
HY2_CERT_CN="${HY2_CERT_CN:-$HY2_PUBLIC_HOST}"
IMAGE="${HY2_IMAGE:-$IMAGE}"

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
  rm -f "$CERT_FILE" "$KEY_FILE"
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -days "$HY2_CERT_DAYS" \
    -subj "/CN=$HY2_CERT_CN" >/dev/null 2>&1
  chmod 0600 "$KEY_FILE"
  chmod 0644 "$CERT_FILE"
fi

HY2_CERT_PIN_SHA256=$(cert_pin_sha256)

umask 077
cat > "$ENV_FILE" <<STATE
# Hysteria 2 MVP state. Keep this file private.
HY2_PUBLIC_PORT='$HY2_PUBLIC_PORT'
HY2_LISTEN_PORT='$HY2_LISTEN_PORT'
HY2_IMAGE='$IMAGE'
SING_BOX_SOCKS_ADDR='$SING_BOX_SOCKS_ADDR'
HY2_AUTH_PASSWORD='$HY2_AUTH_PASSWORD'
HY2_OBFS_PASSWORD='$HY2_OBFS_PASSWORD'
HY2_CERT_PIN_SHA256='$HY2_CERT_PIN_SHA256'
HY2_CERT_CN='$HY2_CERT_CN'
HY2_PUBLIC_HOST='$HY2_PUBLIC_HOST'
HY2_HOST='$HY2_PUBLIC_HOST'
HY2_SNI='$HY2_SNI'
HY2_INSECURE='true'
STATE
chmod 0600 "$ENV_FILE"
cp "$ENV_FILE" "$STATE_DIR/server.env"
chmod 0600 "$STATE_DIR/server.env"

render_template

if command -v ufw >/dev/null 2>&1; then
  ufw allow "${HY2_PUBLIC_PORT}/udp" comment 'vibe hy2 mvp'
else
  echo "WARN: ufw not found; open UDP ${HY2_PUBLIC_PORT} with your VPS firewall if needed" >&2
fi

docker pull "$IMAGE"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  --network host \
  -v "${STATE_DIR}:/etc/hysteria:ro" \
  "$IMAGE" \
  server -c /etc/hysteria/server.yaml

pin_query=$(urlencode "$HY2_CERT_PIN_SHA256")
client_uri="hysteria2://${HY2_AUTH_PASSWORD}@${HY2_PUBLIC_HOST}:${HY2_PUBLIC_PORT}/?insecure=1&pinSHA256=${pin_query}&obfs=salamander&obfs-password=${HY2_OBFS_PASSWORD}&sni=$(urlencode "$HY2_SNI")"

cat <<DONE

Installed $CONTAINER_NAME.
State directory: $STATE_DIR
Rendered config: $SERVER_CONFIG
Certificate pinSHA256: $HY2_CERT_PIN_SHA256
SOCKS outbound: $SING_BOX_SOCKS_ADDR
Published UDP: ${HY2_PUBLIC_PORT} (Docker host network; Hysteria listens on ${HY2_LISTEN_PORT})

Client URI (replace placeholder host if HY2_PUBLIC_HOST was not set):
$client_uri

Verify with:
  ./status-vps.sh

Rollback with:
  ./rollback-vps.sh
DONE
