#!/usr/bin/env bash
set -Eeuo pipefail

BASE=${VPNKIT_TEST_LAB_SECRETS_DIR:-secrets/vpnkit-labs/steamdeck-host}
CLIENT_NAME=${VPNKIT_TEST_LAB_CLIENT_NAME:-test-client}
SERVER_NAME=${VPNKIT_TEST_LAB_SERVER_NAME:-vibe-asus}
ENDPOINT=${VPNKIT_TEST_LAB_ENDPOINT:-127.0.0.1}
PORT=${VPNKIT_TEST_LAB_PORT:-1194}
ROUTING_MODE=${VPNKIT_ROUTING_MODE:-tun}

usage() {
  cat <<'EOF'
Usage: scripts/vpnkit-test-lab-setup.sh [--endpoint HOST] [--port PORT]

Generate isolated throwaway test-lab OpenVPN PKI, client profile, and rendered
vpnkit config under a gitignored secrets/vpnkit-labs/<scenario> tree. The script prints only
paths and metadata; it never prints PEM/profile/config contents.

Environment:
  VPNKIT_TEST_LAB_SECRETS_DIR   Output base (default: secrets/vpnkit-labs/steamdeck-host)
  VPNKIT_TEST_LAB_ENDPOINT      Client profile remote host (default: 127.0.0.1)
  VPNKIT_TEST_LAB_PORT          Client profile remote port (default: 1194)
  VPNKIT_ROUTING_MODE           Render routing mode (default: tun)
  VPNKIT_RULESET_SOURCE_MODE    RU rule-set source mode (default: local-fixture for labs; renderer default is remote)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --endpoint) ENDPOINT=${2:?missing value}; shift 2 ;;
    --port) PORT=${2:?missing value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }; }
need openssl
need python3

PKI="$BASE/openvpn/pki"
SERVER_DIR="$BASE/openvpn/server"
CLIENT_DIR="$BASE/openvpn/client"
RENDERED="$BASE/rendered"
mkdir -p "$PKI" "$SERVER_DIR" "$CLIENT_DIR" "$BASE/sing-box" "$BASE/vibe-vpn"
chmod 700 "$BASE" "$BASE/openvpn" "$PKI" "$CLIENT_DIR" "$BASE/sing-box" "$BASE/vibe-vpn"

make_ca() {
  [[ -s "$PKI/ca.crt" && -s "$PKI/ca.key" ]] && return 0
  openssl req -x509 -newkey rsa:2048 -days 7 -nodes -sha256 \
    -subj '/CN=vpnkit-test-lab-ca' -keyout "$PKI/ca.key" -out "$PKI/ca.crt" >/dev/null 2>&1
}
make_cert() {
  local name=$1 ext=$2
  if [[ -s "$PKI/$name.crt" && -s "$PKI/$name.key" ]] && openssl x509 -in "$PKI/$name.crt" -noout -text 2>/dev/null | grep -q 'X509v3 Key Usage'; then
    return 0
  fi
  rm -f "$PKI/$name.crt" "$PKI/$name.key" "$PKI/$name.csr"
  openssl req -newkey rsa:2048 -nodes -subj "/CN=vpnkit-test-lab-$name" \
    -keyout "$PKI/$name.key" -out "$PKI/$name.csr" >/dev/null 2>&1
  openssl x509 -req -in "$PKI/$name.csr" -CA "$PKI/ca.crt" -CAkey "$PKI/ca.key" -CAcreateserial \
    -days 7 -sha256 -extfile <(printf '%s\n' "$ext") -out "$PKI/$name.crt" >/dev/null 2>&1
  rm -f "$PKI/$name.csr"
}
make_ca
make_cert "$SERVER_NAME" $'keyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth'
make_cert ignat $'keyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=clientAuth'
if [[ ! -s "$PKI/ta.key" ]]; then
  if command -v openvpn >/dev/null 2>&1; then
    openvpn --genkey secret "$PKI/ta.key" >/dev/null 2>&1
  else
    openssl rand -hex 256 > "$PKI/ta.key"
  fi
fi
chmod 600 "$PKI"/*

cat > "$SERVER_DIR/ccd-ignat" <<'EOF'
# test-lab client-specific config placeholder
EOF
chmod 600 "$SERVER_DIR/ccd-ignat"

cat > "$BASE/sing-box/tproxy-canary.json" <<'EOF'
{
  "outbounds": [
    {"type":"vless","tag":"selected-native-out","server":"127.0.0.1","server_port":443,"uuid":"00000000-0000-4000-8000-000000000000","tls":{"enabled":true,"server_name":"example.com"}}
  ]
}
EOF
chmod 600 "$BASE/sing-box/tproxy-canary.json"
printf '[]\n' > "$BASE/vibe-vpn/extra-nodes.json"
chmod 600 "$BASE/vibe-vpn/extra-nodes.json"

VPNKIT_SECRETS_DIR="$BASE" VPNKIT_ROUTING_MODE="$ROUTING_MODE" VPNKIT_RULESET_SOURCE_MODE="${VPNKIT_RULESET_SOURCE_MODE:-local-fixture}" scripts/vpnkit-render-local-configs.sh >/dev/null

python3 - "$CLIENT_DIR/test-client.ovpn" "$ENDPOINT" "$PORT" <<'PY'
import pathlib, sys
path=pathlib.Path(sys.argv[1]); endpoint=sys.argv[2]; port=sys.argv[3]
text=path.read_text()
lines=[]
remote_done=False
for line in text.splitlines():
    if line.startswith('remote '):
        if not remote_done:
            lines.append(f'remote {endpoint} {port} udp')
            remote_done=True
    else:
        lines.append(line)
if not remote_done:
    lines.insert(0, f'remote {endpoint} {port} udp')
path.write_text('\n'.join(lines)+'\n')
PY
chmod 600 "$CLIENT_DIR/test-client.ovpn" "$RENDERED"/openvpn/pki/* "$RENDERED/sing-box/config.json" "$RENDERED/vibe-vpn/config.yaml" 2>/dev/null || true

printf 'test_lab_base=%s\n' "$BASE"
printf 'rendered_config_dir=%s\n' "$RENDERED"
printf 'client_profile=%s\n' "$CLIENT_DIR/test-client.ovpn"
printf 'routing_mode=%s\n' "$ROUTING_MODE"
printf 'endpoint_set=%s\n' "$([[ -n "$ENDPOINT" ]] && echo yes || echo no)"
printf 'generated=ok (contents not printed)\n'
