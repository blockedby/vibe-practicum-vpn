#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Run a public-safe OpenVPN profile check in a throwaway Docker client container.

Usage:
  scripts/vpnkit-profile-check.sh /path/to/profile.ovpn

The script mounts only the profile's parent directory read-only, starts OpenVPN in
an ephemeral container, waits for tunnel initialization, then checks:
  - route selection and ICMP to 1.1.1.1/8.8.8.8
  - DNS through an explicit public resolver for example.com, x.com, ya.ru, linkedin.com
  - HTTPS access to x.com, ya.ru, and linkedin.com
  - public IP identity via ifconfig.me, api.ipify.org, and Yandex Internetometer
  - IPv6 public reachability/leak signal
  - literal-IP HTTPS reachability

Output redacts IP addresses and prints hashes for observed IPs. It does not print
profile contents, private keys, endpoints, or generated config material.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

PROFILE=${1:-}
if [[ -z "$PROFILE" ]]; then
  echo "missing profile path" >&2
  usage >&2
  exit 2
fi
if [[ ! -r "$PROFILE" ]]; then
  echo "profile is not readable: $PROFILE" >&2
  exit 1
fi

PROFILE_DIR=$(cd "$(dirname "$PROFILE")" && pwd -P)
PROFILE_NAME=$(basename "$PROFILE")
IMAGE=${VPNKIT_PROFILE_CHECK_IMAGE:-vibe-practicum-vpn-ovpn-client-test:latest}
CONTAINER_NAME=${VPNKIT_PROFILE_CHECK_CONTAINER_NAME:-"vpnkit-profile-check-$$"}
WAIT_SECONDS=${VPNKIT_PROFILE_CHECK_WAIT_SECONDS:-60}

if [[ "${VPNKIT_PROFILE_CHECK_SKIP_BUILD:-0}" != "1" ]]; then
  docker build -q -t "$IMAGE" docker/ovpn-client-test >/dev/null
elif ! docker image inspect "$IMAGE" >/dev/null 2>&1 \
  || ! docker run --rm --entrypoint test "$IMAGE" -x /usr/local/bin/profile-check.sh >/dev/null 2>&1; then
  docker build -q -t "$IMAGE" docker/ovpn-client-test >/dev/null
fi

redact() {
  sed -E \
    -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' \
    -e 's/([A-Za-z0-9._-]+):1194/<remote>:1194/g'
}

docker run --rm \
  --name "$CONTAINER_NAME" \
  --cap-add NET_ADMIN \
  --cap-add NET_RAW \
  --device /dev/net/tun:/dev/net/tun \
  -v "$PROFILE_DIR:/profiles:ro" \
  --entrypoint bash \
  "$IMAGE" \
  -lc '
    set -euo pipefail
    profile="/profiles/'"$PROFILE_NAME"'"
    wait_seconds='"$WAIT_SECONDS"'
    log=/tmp/openvpn.log
    openvpn --config "$profile" --verb 3 >"$log" 2>&1 &
    pid=$!
    cleanup(){ kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; }
    trap cleanup EXIT

    ready=0
    for _ in $(seq 1 "$wait_seconds"); do
      if grep -q "Initialization Sequence Completed" "$log" && ip -4 addr show tun0 >/dev/null 2>&1; then
        ready=1
        break
      fi
      if ! kill -0 "$pid" 2>/dev/null; then
        echo "openvpn_status=exited_before_ready"
        grep -E "AUTH_FAILED|TLS Error|Options error|Peer Connection Initiated|PUSH_REPLY|Initialization Sequence Completed" "$log" | tail -80 || true
        exit 20
      fi
      sleep 1
    done
    if [ "$ready" != 1 ]; then
      echo "openvpn_status=timeout_waiting_for_ready"
      grep -E "AUTH_FAILED|TLS Error|Options error|Peer Connection Initiated|PUSH_REPLY|Initialization Sequence Completed" "$log" | tail -120 || true
      exit 21
    fi

    echo "openvpn_status=ready"
    if grep -q "WARNING: You have specified redirect-gateway" "$log"; then
      echo "duplicate_redirect_warning=yes"
    else
      echo "duplicate_redirect_warning=no"
    fi
    grep -E "Peer Connection Initiated|PUSH_REPLY|Initialization Sequence Completed|Data Channel" "$log" | tail -20 || true
    /usr/local/bin/profile-check.sh
  ' 2>&1 | redact
