#!/usr/bin/env bash
set -euo pipefail

SSH_HOST="${SSH_HOST:-${VPNKIT_VPS_SSH_HOST:-example-vps-host}}"
PUBLIC_ENDPOINT="${PUBLIC_ENDPOINT:-${VPNKIT_VPS_PUBLIC_ENDPOINT:-203.0.113.10}}"
OPENVPN_PORT="${OPENVPN_PORT:-1194}"
REMOTE_STATE_DIR="${REMOTE_STATE_DIR:-/etc/vibe-vpn/openvpn-asus}"
CCD_DIR="${CCD_DIR:-/etc/openvpn/ccd-vibe-asus}"
OUT_DIR="${OUT_DIR:-./out/openvpn-pool-tproxy-profiles}"
PROFILE_SUFFIX="${PROFILE_SUFFIX:-${VPNKIT_VPS_SSH_HOST:-example-vps-host}-pool-tproxy.ovpn}"
DNS1="${DNS1:-8.8.8.8}"
DNS2="${DNS2:-8.8.4.4}"
EXPORT=0
FORCE=0
CN=""

usage() {
  cat <<'USAGE'
Generate an OpenVPN dynamic-pool TPROXY profile for ${VPNKIT_VPS_SSH_HOST:-example-vps-host}.

Usage:
  scripts/openvpn-asus-pool-tproxy-profile.sh --export <client-cn>
  scripts/openvpn-asus-pool-tproxy-profile.sh --dry-run <client-cn>

What it does in --export mode:
  - SSHes to SSH_HOST (default: ${VPNKIT_VPS_SSH_HOST:-example-vps-host}) and uses sudo -n.
  - Creates/reuses an EasyRSA client cert for <client-cn>.
  - Writes CCD with DNS + redirect-gateway, but NO ifconfig-push.
  - Lets OpenVPN assign 10.89.0.20-10.89.0.254 from the dynamic pool.
  - Exports one embedded .ovpn into OUT_DIR with mode 0600.

Required live prerequisite:
  /usr/local/sbin/vibe-openvpn-asus-rules must capture dynamic pool
  10.89.0.20-10.89.0.254 into VIBE_OVPN_ASUS_TP and accept mark 0x1 INPUT.

Examples:
  PUBLIC_ENDPOINT=${VPNKIT_VPS_PUBLIC_ENDPOINT:-203.0.113.10} OUT_DIR=/home/kcnc/vibe-openvpn-asus-profile \
    scripts/openvpn-asus-pool-tproxy-profile.sh --export vasya-phone

Options:
  --export <cn>   Create/reuse cert and export profile.
  --dry-run <cn>  Print plan only. This is the default if --export is omitted.
  --force         Allow overwriting an existing local output file.
  -h, --help      Show this help.

Secret material is written only to files and is never printed intentionally.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --export)
      EXPORT=1
      shift
      CN="${1:-}"
      ;;
    --dry-run)
      EXPORT=0
      shift
      CN="${1:-}"
      ;;
    --force)
      FORCE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$CN" ]]; then
        echo "Unexpected extra argument: $1" >&2
        usage >&2
        exit 2
      fi
      CN="$1"
      ;;
  esac
  shift || true
done

if [[ -z "$CN" ]]; then
  echo "Missing client CN" >&2
  usage >&2
  exit 2
fi

if [[ ! "$CN" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$ ]]; then
  echo "Invalid CN: use 2-63 chars: letters, numbers, dot, underscore, dash; start with letter/number" >&2
  exit 2
fi

case "$CN" in
  asus|asus-tproxy)
    echo "Refusing reserved CN: $CN" >&2
    exit 2
    ;;
esac

PROFILE_NAME="${CN}-${PROFILE_SUFFIX}"
if [[ "$PROFILE_NAME" == */* || "$PROFILE_NAME" == "." || "$PROFILE_NAME" == ".." ]]; then
  echo "Unsafe profile file name: $PROFILE_NAME" >&2
  exit 2
fi

OUTPUT="$OUT_DIR/$PROFILE_NAME"

cat <<PLAN
OpenVPN dynamic-pool TPROXY profile plan

client_cn: $CN
ssh_host: $SSH_HOST
public_endpoint: $PUBLIC_ENDPOINT:$OPENVPN_PORT/udp
remote_state_dir: $REMOTE_STATE_DIR
ccd_dir: $CCD_DIR
local_output: $OUTPUT
pool: 10.89.0.20-10.89.0.254 (server-assigned; no ifconfig-push)
pushed_options:
  dhcp-option DNS $DNS1
  dhcp-option DNS $DNS2
  redirect-gateway def1 bypass-dhcp
secret_material: not printed
PLAN

if [[ "$EXPORT" != "1" ]]; then
  echo
  echo "Dry run only. Use --export $CN to create/export."
  exit 0
fi

if [[ -e "$OUTPUT" && "$FORCE" != "1" ]]; then
  echo "Output already exists: $OUTPUT (use --force to overwrite)" >&2
  exit 1
fi

umask 077
mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR" 2>/dev/null || true

REMOTE_PROFILE="/tmp/${PROFILE_NAME}"

ssh "$SSH_HOST" sudo -n bash -s -- "$CN" "$PUBLIC_ENDPOINT" "$OPENVPN_PORT" "$REMOTE_STATE_DIR" "$CCD_DIR" "$REMOTE_PROFILE" "$DNS1" "$DNS2" <<'REMOTE'
set -euo pipefail
CN="$1"
PUBLIC_ENDPOINT="$2"
OPENVPN_PORT="$3"
STATE_DIR="$4"
CCD_DIR="$5"
REMOTE_PROFILE="$6"
DNS1="$7"
DNS2="$8"
EASYRSA_DIR="$STATE_DIR/easy-rsa"

case "$CN" in
  asus|asus-tproxy)
    echo "reserved CN refused" >&2
    exit 2
    ;;
esac
if [[ ! "$CN" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$ ]]; then
  echo "invalid CN" >&2
  exit 2
fi

for p in "$STATE_DIR/ca.crt" "$STATE_DIR/ta.key" "$EASYRSA_DIR" "$CCD_DIR"; do
  if [[ ! -e "$p" ]]; then
    echo "missing required path: $p" >&2
    exit 1
  fi
done

if [[ ! -f "$EASYRSA_DIR/pki/issued/$CN.crt" || ! -f "$EASYRSA_DIR/pki/private/$CN.key" ]]; then
  (cd "$EASYRSA_DIR" && EASYRSA_BATCH=1 ./easyrsa build-client-full "$CN" nopass >/dev/null 2>&1)
fi

install -o root -g root -m 644 "$EASYRSA_DIR/pki/issued/$CN.crt" "$STATE_DIR/$CN.crt"
install -o root -g root -m 600 "$EASYRSA_DIR/pki/private/$CN.key" "$STATE_DIR/$CN.key"

ccd_tmp="$(mktemp)"
profile_tmp="$(mktemp)"
trap 'rm -f "$ccd_tmp" "$profile_tmp"' EXIT

{
  printf 'push "dhcp-option DNS %s"\n' "$DNS1"
  printf 'push "dhcp-option DNS %s"\n' "$DNS2"
  printf 'push "redirect-gateway def1 bypass-dhcp"\n'
} >"$ccd_tmp"
install -o root -g root -m 644 "$ccd_tmp" "$CCD_DIR/$CN"

extract_pem_block() {
  local begin="$1" end="$2" src="$3"
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { printing=1 }
    printing { print }
    $0 == end { printing=0 }
  ' "$src"
}

{
  cat <<PROFILE
client
dev tun
proto udp
remote $PUBLIC_ENDPOINT $OPENVPN_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
auth-nocache
cipher AES-256-CBC
key-direction 1
redirect-gateway def1
verb 3
PROFILE
  echo "<ca>"
  extract_pem_block "-----BEGIN CERTIFICATE-----" "-----END CERTIFICATE-----" "$STATE_DIR/ca.crt"
  echo "</ca>"
  echo "<cert>"
  extract_pem_block "-----BEGIN CERTIFICATE-----" "-----END CERTIFICATE-----" "$STATE_DIR/$CN.crt"
  echo "</cert>"
  echo "<key>"
  cat "$STATE_DIR/$CN.key"
  echo "</key>"
  echo "<tls-auth>"
  cat "$STATE_DIR/ta.key"
  echo "</tls-auth>"
} >"$profile_tmp"

install -o root -g root -m 600 "$profile_tmp" "$REMOTE_PROFILE"
printf 'remote_profile=%s\n' "$REMOTE_PROFILE"
printf 'ccd_written=%s\n' "$CCD_DIR/$CN"
printf 'cert_status=%s\n' "ready"
printf 'secret_material: not printed\n'
REMOTE

ssh "$SSH_HOST" sudo -n cat "$REMOTE_PROFILE" >"$OUTPUT"
chmod 600 "$OUTPUT"

python3 - "$OUTPUT" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text(errors='ignore')
missing = [name for name in ('ca','cert','key','tls-auth') if not re.search(rf'<{name}>\n.+?\n</{name}>', s, re.S)]
if missing:
    raise SystemExit('profile validation failed, missing blocks: ' + ', '.join(missing))
if '[REDACTED' in s:
    raise SystemExit('profile validation failed: redacted marker found')
if 'PRIVATE KEY' not in s:
    raise SystemExit('profile validation failed: private key block not detected')
print(f'profile_written={p}')
print(f'bytes={p.stat().st_size}')
print(f'permissions={oct(p.stat().st_mode & 0o777)[2:]}')
print('validation=ok')
print('secret_material: not printed')
PY
