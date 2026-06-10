#!/usr/bin/env bash
set -Eeuo pipefail

ENDPOINT=${VPNKIT_STEAMDECK_CLIENT_ENDPOINT:-}
PORT=${VPNKIT_OPENVPN_PORT:-1194}
PROFILE=${VPNKIT_STEAMDECK_CLIENT_PROFILE:-secrets/vps/openvpn/client/test-client.ovpn}
IMAGE=${VPNKIT_STEAMDECK_CLIENT_IMAGE:-vpnkit-ovpn-client-test:steamdeck}
RUNTIME=${VPNKIT_CONTAINER_RUNTIME:-docker}
LOG_FILE=${VPNKIT_STEAMDECK_CLIENT_LOG_FILE:-}
CLIENT_TIMEOUT=${VPNKIT_STEAMDECK_CLIENT_TIMEOUT:-180}
NESTED_PROFILE=${VPNKIT_STEAMDECK_NESTED_CLIENT_PROFILE:-}
NESTED_ENABLED=${VPNKIT_STEAMDECK_NESTED_VPN_ENABLED:-1}
NESTED_TARGET=${VPNKIT_STEAMDECK_NESTED_TARGET:-10.89.0.1}
NESTED_PEER=${VPNKIT_STEAMDECK_NESTED_PEER:-10.90.0.1}
KEEP_TEMP=0
CONTAINER_NAME=""

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
  --timeout SECONDS     Bound client container run (default: 180 or VPNKIT_STEAMDECK_CLIENT_TIMEOUT)
  --nested-profile PATH Nested OpenVPN client profile to require after outer tunnel
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
    --timeout) CLIENT_TIMEOUT=${2:?missing value}; shift 2 ;;
    --nested-profile) NESTED_PROFILE=${2:?missing value}; shift 2 ;;
    --keep-temp) KEEP_TEMP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$ENDPOINT" ]]; then echo "missing --endpoint" >&2; usage >&2; exit 2; fi
if [[ ! "$PORT" =~ ^[0-9]+$ ]]; then echo "invalid --port: $PORT" >&2; exit 2; fi
if [[ ! "$CLIENT_TIMEOUT" =~ ^[0-9]+$ || "$CLIENT_TIMEOUT" -lt 1 ]]; then echo "invalid --timeout: $CLIENT_TIMEOUT" >&2; exit 2; fi
if [[ ! -r "$PROFILE" ]]; then echo "missing client profile: $PROFILE" >&2; exit 1; fi
if [[ "$NESTED_ENABLED" != "0" && -n "$NESTED_PROFILE" && ! -r "$NESTED_PROFILE" ]]; then echo "missing nested client profile: $NESTED_PROFILE" >&2; exit 1; fi
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
cleanup() {
  if [[ -n "$CONTAINER_NAME" ]]; then "$RUNTIME" rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true; fi
  [[ $KEEP_TEMP -eq 1 ]] || rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

mkdir -p "$tmp/client" "$tmp/nested"
sed "s/^remote .*/remote $ENDPOINT $PORT/" "$PROFILE" > "$tmp/client/test-client.ovpn"
chmod 600 "$tmp/client/test-client.ovpn"
if [[ -n "$NESTED_PROFILE" ]]; then
  cp "$NESTED_PROFILE" "$tmp/nested/test-client.ovpn"
  chmod 600 "$tmp/nested/test-client.ovpn"
fi

printf '[%s] endpoint: %s:%s\n' "$(date -u +%FT%TZ)" "$ENDPOINT" "$PORT"
printf '[%s] runtime: %s image: %s\n' "$(date -u +%FT%TZ)" "$RUNTIME" "$IMAGE"
printf '[%s] timeout: %ss\n' "$(date -u +%FT%TZ)" "$CLIENT_TIMEOUT"
printf '[%s] nested_vpn_enabled: %s nested_profile: %s\n' "$(date -u +%FT%TZ)" "$NESTED_ENABLED" "$([[ -n "$NESTED_PROFILE" ]] && echo set || echo missing)"
"$RUNTIME" build -t "$IMAGE" docker/ovpn-client-test >/dev/null
CONTAINER_NAME="vpnkit-client-${ENDPOINT//[^A-Za-z0-9_.-]/-}-$$"
timeout -k 5s "$CLIENT_TIMEOUT" "$RUNTIME" run --rm \
  --name "$CONTAINER_NAME" \
  --cap-add NET_ADMIN --cap-add NET_RAW \
  --device /dev/net/tun \
  -v "$tmp/client:/etc/openvpn/client:ro" \
  -v "$tmp/nested:/etc/openvpn/nested:ro" \
  -v "$PWD/logs:/var/log/vpnkit" \
  -e VPNKIT_NESTED_VPN_ENABLED="$NESTED_ENABLED" \
  -e VPNKIT_NESTED_TARGET="$NESTED_TARGET" \
  -e VPNKIT_NESTED_PEER="$NESTED_PEER" \
  "$IMAGE" /etc/openvpn/client/test-client.ovpn
