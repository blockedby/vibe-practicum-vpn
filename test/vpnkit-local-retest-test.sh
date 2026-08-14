#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
lifecycle="$root/scripts/vpnkit/vpnkit-local.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/vpnkit-local-retest.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
printf '1\n' >"$tmp/generation"

cat >"$tmp/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$*" == *'compose'*'ps -q vpnkit'* ]]; then
  printf 'local-cid\n'
  exit 0
fi
if [[ "$1" == inspect ]]; then
  printf 'healthy\n'
  exit 0
fi
if [[ "$1" == exec* || "$*" == exec* ]]; then
  if [[ "$*" == *'test ! -e'* ]]; then
    [[ ! -e "$MOCK_REQUEST" ]]
    exit
  fi
  if [[ "$*" == *'cat '* ]]; then
    cat "$MOCK_GENERATION"
    exit 0
  fi
  if [[ "$*" == *'vibe-vpn --config'* ]]; then
    if [[ ${MOCK_RESTART_SUCCEEDS:-1} == 1 ]]; then
      printf '2\n' >"$MOCK_GENERATION"
      rm -f "$MOCK_REQUEST"
    fi
    exit 0
  fi
fi
exit 99
EOF
chmod +x "$tmp/bin/docker"
export PATH="$tmp/bin:$PATH"
export MOCK_GENERATION="$tmp/generation" MOCK_REQUEST="$tmp/request"
export VPNKIT_LOCAL_MANAGE_NETWORKMANAGER=false
export VPNKIT_LOCAL_RETEST_TIMEOUT_SECONDS=2
export VPNKIT_LOCAL_SINGBOX_GENERATION_FILE=/run/vpnkit/sing-box-generation
export VPNKIT_LOCAL_SINGBOX_RESTART_FILE=/run/vpnkit/restart-sing-box

# A successful pick is not accepted until the request has disappeared and the
# generation changed; the mock performs both transitions on the pick call.
output=$(bash "$lifecycle" retest select)
grep -Fxq 'vpnkit_local_retest_select=ok' <<<"$output"
grep -Fxq 'selection_details=redacted' <<<"$output"

# A completed pick with no runtime generation change must fail boundedly.
printf '1\n' >"$tmp/generation"
rm -f "$tmp/request"
if MOCK_RESTART_SUCCEEDS=0 bash "$lifecycle" retest select >/dev/null 2>&1; then
  echo 'retest accepted an unchanged runtime generation' >&2
  exit 1
fi

printf 'vpnkit local retest generation mock tests passed\n'
