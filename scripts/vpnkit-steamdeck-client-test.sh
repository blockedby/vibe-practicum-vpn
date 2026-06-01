#!/usr/bin/env bash
set -Eeuo pipefail

ENDPOINT=${VPNKIT_STEAMDECK_CLIENT_ENDPOINT:-}
PORT=${VPNKIT_OPENVPN_PORT:-1194}
PROFILE=${VPNKIT_STEAMDECK_CLIENT_PROFILE:-secrets/vps/openvpn/client/test-client.ovpn}
IMAGE=${VPNKIT_STEAMDECK_CLIENT_IMAGE:-vpnkit-ovpn-client-test:steamdeck}
RUNTIME=${VPNKIT_CONTAINER_RUNTIME:-docker}
LOG_FILE=${VPNKIT_STEAMDECK_CLIENT_LOG_FILE:-}
KEEP_TEMP=0

usage() {
  cat <<'EOF'
Usage: scripts/vpnkit-steamdeck-client-test.sh --endpoint HOST [options]

Runs the existing OpenVPN client test container from this host against a Steam Deck
vpnkit endpoint. The generated endpoint-specific profile is written to a temp dir
and removed by default. Secrets/profile contents are not printed.

Options:
  --endpoint HOST       Steam Deck LAN/Tailscale IP or hostname (required)
  --port PORT           OpenVPN UDP port (default: 1194)
  --profile PATH        Source rendered client profile (default: secrets/vps/openvpn/client/test-client.ovpn)
  --runtime docker|podman  Local container runtime for the client test (default: docker)
  --image IMAGE         Local client-test image tag (default: vpnkit-ovpn-client-test:steamdeck)
  --log-file PATH       Write redacted output to PATH as well as stdout
  --keep-temp           Keep generated temp profile directory for debugging
  -h, --help            Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --endpoint) ENDPOINT=${2:?missing value}; shift 2 ;;
    --port) PORT=${2:?missing value}; shift 2 ;;
    --profile) PROFILE=${2:?missing value}; shift 2 ;;
    --runtime) RUNTIME=${2:?missing value}; shift 2 ;;
    --image) IMAGE=${2:?missing value}; shift 2 ;;
    --log-file) LOG_FILE=${2:?missing value}; shift 2 ;;
    --keep-temp) KEEP_TEMP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$ENDPOINT" ]]; then echo "missing --endpoint" >&2; usage >&2; exit 2; fi
if [[ ! "$PORT" =~ ^[0-9]+$ ]]; then echo "invalid --port: $PORT" >&2; exit 2; fi
if [[ ! -r "$PROFILE" ]]; then echo "missing client profile: $PROFILE" >&2; exit 1; fi
case "$RUNTIME" in docker|podman) ;; *) echo "unsupported --runtime: $RUNTIME" >&2; exit 2 ;; esac

redact_stream() {
  sed -E \
    -e 's#vless://[^[:space:]]+#vless://[redacted]#g' \
    -e 's#(https?://)[^[:space:]]*(token|sub|subscription|api_key|apikey|key)[^[:space:]]*#\1[redacted-url]#ig' \
    -e 's/([0-9a-f]{8}-[0-9a-f-]{27,})/[redacted-uuid]/ig' \
    -e 's/(private[_-]?key[":= ]+)[^", ]+/\1[redacted]/ig' \
    -e 's/(password[":= ]+)[^", ]+/\1[redacted]/ig'
}

if [[ -n "$LOG_FILE" ]]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  exec > >(redact_stream | tee "$LOG_FILE") 2>&1
fi

tmp=$(mktemp -d -t vpnkit-steamdeck-client.XXXXXX)
cleanup() { [[ $KEEP_TEMP -eq 1 ]] || rm -rf "$tmp"; }
trap cleanup EXIT

mkdir -p "$tmp/client"
sed "s/^remote .*/remote $ENDPOINT $PORT/" "$PROFILE" > "$tmp/client/test-client.ovpn"
chmod 600 "$tmp/client/test-client.ovpn"

printf '[%s] endpoint: %s:%s\n' "$(date -u +%FT%TZ)" "$ENDPOINT" "$PORT"
printf '[%s] runtime: %s image: %s\n' "$(date -u +%FT%TZ)" "$RUNTIME" "$IMAGE"
"$RUNTIME" build -t "$IMAGE" docker/ovpn-client-test >/dev/null
"$RUNTIME" run --rm \
  --name "vpnkit-client-${ENDPOINT//[^A-Za-z0-9_.-]/-}-$$" \
  --cap-add NET_ADMIN --cap-add NET_RAW \
  --device /dev/net/tun \
  -v "$tmp/client:/etc/openvpn/client:ro" \
  -v "$PWD/logs:/var/log/vpnkit" \
  "$IMAGE" /etc/openvpn/client/test-client.ovpn
