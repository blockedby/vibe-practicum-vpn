#!/usr/bin/env bash
set -euo pipefail

MANIFEST="config/vpnkit-manifest.example.yaml"
SERVER=""
CLIENT=""
OUT_DIR="generated/openvpn-profiles"
PROFILE_INTENT="test"
MODE="fixture"

usage() {
  cat <<'USAGE'
Usage: scripts/vpnkit-render-profile-for-pair.sh --server <id> --client <id> [options]

Options:
  --manifest <path>   Manifest YAML (default: config/vpnkit-manifest.example.yaml)
  --out-dir <dir>     Output directory (default: generated/openvpn-profiles)
  --profile-intent <intent>
                      Profile intent to render: test or production (default: test)
  --fixture           Render public-safe fixture profile material (default)
  --real              Require real local binding environment values; never prints them

Writes a pair-specific .ovpn file with mode 0600 and prints only path/metadata.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2;;
    --server) SERVER="$2"; shift 2;;
    --client) CLIENT="$2"; shift 2;;
    --out-dir) OUT_DIR="$2"; shift 2;;
    --profile-intent) PROFILE_INTENT="$2"; shift 2;;
    --fixture) MODE="fixture"; shift;;
    --real) MODE="real"; shift;;
    -h|--help) usage; exit 0;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2;;
  esac
done
[[ -n "$SERVER" && -n "$CLIENT" ]] || { echo "--server and --client are required" >&2; exit 2; }
[[ "$SERVER" =~ ^[A-Za-z0-9._-]+$ && "$CLIENT" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "server/client ids must be safe names" >&2; exit 2; }
[[ "$PROFILE_INTENT" == "test" || "$PROFILE_INTENT" == "production" ]] || { echo "--profile-intent must be test or production" >&2; exit 2; }

resolve_json=$(python3 scripts/vpnkit-manifest-validate.py --manifest "$MANIFEST" --server "$SERVER" --client "$CLIENT" --profile-intent "$PROFILE_INTENT")
port=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["profile"]["port"])' <<<"$resolve_json")
proto=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["profile"]["proto"])' <<<"$resolve_json")
pair=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["pair"])' <<<"$resolve_json")
profile_intent=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["profileIntent"])' <<<"$resolve_json")

safe_file="${pair}.ovpn"
[[ "$safe_file" != */* && "$safe_file" != "." && "$safe_file" != ".." ]] || { echo "unsafe output file name" >&2; exit 2; }

if [[ "$MODE" == "fixture" ]]; then
  remote="vpnkit-fixture.invalid"
  ca='VPNKIT-FIXTURE-CA-NOT-A-REAL-CERTIFICATE'
  cert='VPNKIT-FIXTURE-CLIENT-CERT-NOT-A-REAL-CERTIFICATE'
  key='VPNKIT-FIXTURE-CLIENT-KEY-NOT-REAL-SECRET-MATERIAL'
  ta='VPNKIT-FIXTURE-TLS-AUTH-NOT-REAL-SECRET-MATERIAL'
else
  binding_env_name() {
    python3 -c 'import json,sys; data=json.load(sys.stdin); ref=data["bindings"].get(sys.argv[1],{}).get("ref",""); print(ref[6:] if ref.startswith("local:") else "")' "$1" <<<"$resolve_json"
  }
  remote_env_name=$(python3 -c 'import json,sys; ref=json.load(sys.stdin)["profile"]["remote_ref"]; print(ref[6:] if ref.startswith("local:") else "")' <<<"$resolve_json")
  ca_env_name=$(binding_env_name ca)
  cert_env_name=$(binding_env_name cert)
  key_env_name=$(binding_env_name key)
  ta_env_name=$(binding_env_name tls_auth)
  missing=0
  for v in "$remote_env_name" "$ca_env_name" "$cert_env_name" "$key_env_name" "$ta_env_name"; do
    if [[ -z "$v" ]]; then echo "manifest selected a required binding without a local env reference" >&2; missing=1; continue; fi
    if [[ -z "${!v:-}" ]]; then echo "missing required local binding env: $v" >&2; missing=1; fi
  done
  [[ $missing -eq 0 ]] || { echo "real mode cannot render without local bindings; no secret material printed" >&2; exit 3; }
  remote="${!remote_env_name}"; ca="${!ca_env_name}"; cert="${!cert_env_name}"; key="${!key_env_name}"; ta="${!ta_env_name}"
fi

umask 077
mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR" 2>/dev/null || true
output="$OUT_DIR/$safe_file"
cat >"$output" <<PROFILE
client
dev tun
proto $proto
remote $remote $port
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
auth-nocache
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-256-CBC
data-ciphers-fallback AES-256-CBC
cipher AES-256-GCM
key-direction 1
verb 3
<ca>
$ca
</ca>
<cert>
$cert
</cert>
<key>
$key
</key>
<tls-auth>
$ta
</tls-auth>
PROFILE
chmod 600 "$output"
printf 'profile_written=%s\n' "$output"
printf 'profile_intent=%s\n' "$profile_intent"
printf 'mode=%s\n' "$MODE"
printf 'permissions=%s\n' "$(stat -c '%a' "$output" 2>/dev/null || stat -f '%Lp' "$output")"
printf 'secret_material=not_printed\n'
