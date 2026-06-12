#!/usr/bin/env bash
set -euo pipefail

MANIFEST=${VPNKIT_TEST_MANIFEST:-config/vpnkit-manifest.example.yaml}
OUT_DIR=${VPNKIT_TEST_MANIFEST_OUT_DIR:-generated/openvpn-profiles}
SERVER=${VPNKIT_TEST_MANIFEST_SERVER:-steamdeck}
CLIENT=${VPNKIT_TEST_MANIFEST_CLIENT:-host-machine}

rm -f "$OUT_DIR"/steamdeck-host-machine-test.ovpn "$OUT_DIR"/steamdeck-host-machine-production.ovpn 2>/dev/null || true

for intent in test production; do
  resolved=$(python3 scripts/vpnkit/vpnkit-manifest-validate.py --manifest "$MANIFEST" --server "$SERVER" --client "$CLIENT" --profile-intent "$intent")
  actual_intent=$(python3 -c 'import json,sys; data=json.load(sys.stdin); print(data["profileIntent"]); assert data["profile"]["intent"] == data["profileIntent"]' <<<"$resolved")
  [[ "$actual_intent" == "$intent" ]]
  pair=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["pair"])' <<<"$resolved")
  [[ "$pair" == *"$intent"* ]]
done

render_out=$(scripts/vpnkit/vpnkit-render-profile-for-pair.sh --manifest "$MANIFEST" --server "$SERVER" --client "$CLIENT" --profile-intent test --out-dir "$OUT_DIR" --fixture)
printf '%s\n' "$render_out" | grep -q '^profile_intent=test$'
printf '%s\n' "$render_out" | grep -q '^secret_material=not_printed$'
profile_path=$(printf '%s\n' "$render_out" | awk -F= '/^profile_written=/{print $2; exit}')
[[ "$profile_path" == "$OUT_DIR"/steamdeck-host-machine-test.ovpn ]]
[[ -f "$profile_path" ]]
perms=$(stat -c '%a' "$profile_path" 2>/dev/null || stat -f '%Lp' "$profile_path")
[[ "$perms" == "600" ]]

# Do not inspect or print generated profile contents; path and mode are sufficient for this public-safe check.
