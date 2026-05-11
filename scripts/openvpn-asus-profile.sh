#!/usr/bin/env bash
set -euo pipefail

SSH_HOST="${SSH_HOST:-vibe-practicum}"
OPENVPN_ASUS_EXPORT="${OPENVPN_ASUS_EXPORT:-0}"
OPENVPN_PORT="${OPENVPN_PORT:-1194}"
OPENVPN_ASUS_REDIRECT_GATEWAY="${OPENVPN_ASUS_REDIRECT_GATEWAY:-0}"
REMOTE_STATE_DIR="${REMOTE_STATE_DIR:-/etc/vibe-vpn/openvpn-asus}"
OPENVPN_CLIENT_CN="${OPENVPN_CLIENT_CN:-asus}"
PROFILE_NAME="${PROFILE_NAME:-${OPENVPN_CLIENT_CN}-vibe-practicum.ovpn}"

require_export_inputs() {
  if [[ "$OPENVPN_ASUS_EXPORT" != "1" ]]; then
    return 0
  fi
  local missing=0
  for name in PUBLIC_ENDPOINT OUT_DIR VIBE_PRACTICUM_SUDO_PASSWORD; do
    if [[ -z "${!name:-}" ]]; then
      echo "Set $name when OPENVPN_ASUS_EXPORT=1" >&2
      missing=1
    fi
  done
  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi
  if [[ ! "$OPENVPN_CLIENT_CN" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "OPENVPN_CLIENT_CN must contain only letters, numbers, dot, underscore, or dash" >&2
    exit 1
  fi
  if [[ "$PROFILE_NAME" == */* || "$PROFILE_NAME" == "." || "$PROFILE_NAME" == ".." ]]; then
    echo "PROFILE_NAME must be a file name, not a path" >&2
    exit 1
  fi
}

shell_quote() {
  printf "%q" "$1"
}

print_plan() {
  cat <<PLAN
ASUS OpenVPN profile export plan (dry run)

No remote command has been executed and no profile has been generated.
Set OPENVPN_ASUS_EXPORT=1 plus PUBLIC_ENDPOINT, OUT_DIR, and
VIBE_PRACTICUM_SUDO_PASSWORD to export secret material from SSH_HOST=$SSH_HOST.

Required remote files:
  $REMOTE_STATE_DIR/ca.crt
  $REMOTE_STATE_DIR/$OPENVPN_CLIENT_CN.crt
  $REMOTE_STATE_DIR/$OPENVPN_CLIENT_CN.key
  $REMOTE_STATE_DIR/ta.key

Output path when enabled:
  OUT_DIR/$PROFILE_NAME

Profile defaults:
  client, dev tun, proto udp
  remote PUBLIC_ENDPOINT $OPENVPN_PORT
  remote-cert-tls server
  auth SHA256
  data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
  data-ciphers-fallback AES-256-CBC
  cipher AES-256-GCM
  tls-auth with key-direction 1
  redirect-gateway def1 only when OPENVPN_ASUS_REDIRECT_GATEWAY=1

secret_material: not printed
PLAN
}

fetch_remote_file() {
  local remote_path="$1" local_path="$2"
  {
    printf 'VIBE_PRACTICUM_SUDO_PASSWORD=%s\n' "$(shell_quote "$VIBE_PRACTICUM_SUDO_PASSWORD")"
    printf 'REMOTE_PATH=%s\n' "$(shell_quote "$remote_path")"
    cat <<'REMOTE'
set -euo pipefail
printf '%s\n' "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S -p '' cat "$REMOTE_PATH"
REMOTE
  } | ssh "$SSH_HOST" bash -s >"$local_path"
}

extract_pem_block() {
  local begin="$1" end="$2" src="$3"
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { printing=1 }
    printing { print }
    $0 == end { printing=0 }
  ' "$src"
}

export_profile() {
  local out_dir="$OUT_DIR"
  local output="$out_dir/$PROFILE_NAME"
  local tmpdir ca cert key ta
  tmpdir="$(mktemp -d)"
  ca="$tmpdir/ca.crt"
  cert="$tmpdir/$OPENVPN_CLIENT_CN.crt"
  key="$tmpdir/$OPENVPN_CLIENT_CN.key"
  ta="$tmpdir/ta.key"
  trap 'rm -rf "$tmpdir"' EXIT

  umask 077
  mkdir -p "$out_dir"
  chmod 700 "$out_dir" 2>/dev/null || true

  fetch_remote_file "$REMOTE_STATE_DIR/ca.crt" "$ca"
  fetch_remote_file "$REMOTE_STATE_DIR/$OPENVPN_CLIENT_CN.crt" "$cert"
  fetch_remote_file "$REMOTE_STATE_DIR/$OPENVPN_CLIENT_CN.key" "$key"
  fetch_remote_file "$REMOTE_STATE_DIR/ta.key" "$ta"

  local redirect_line=""
  if [[ "$OPENVPN_ASUS_REDIRECT_GATEWAY" == "1" ]]; then
    redirect_line="redirect-gateway def1"
  fi

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
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
data-ciphers-fallback AES-256-CBC
cipher AES-256-GCM
key-direction 1
verb 3
PROFILE
    if [[ -n "$redirect_line" ]]; then
      printf '%s\n' "$redirect_line"
    fi
    echo "<ca>"
    extract_pem_block "-----BEGIN CERTIFICATE-----" "-----END CERTIFICATE-----" "$ca"
    echo "</ca>"
    echo "<cert>"
    extract_pem_block "-----BEGIN CERTIFICATE-----" "-----END CERTIFICATE-----" "$cert"
    echo "</cert>"
    echo "<key>"
    cat "$key"
    echo "</key>"
    echo "<tls-auth>"
    cat "$ta"
    echo "</tls-auth>"
  } >"$output"
  chmod 600 "$output"

  echo "profile_written=$output"
  echo "permissions=$(stat -c '%a' "$output" 2>/dev/null || stat -f '%Lp' "$output")"
  echo "secret_material: not printed"
}

require_export_inputs
if [[ "$OPENVPN_ASUS_EXPORT" != "1" ]]; then
  print_plan
  exit 0
fi

export_profile
