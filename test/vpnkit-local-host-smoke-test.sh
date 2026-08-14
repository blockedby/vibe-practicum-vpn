#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
script="$root/scripts/vpnkit/vpnkit-local-host-smoke.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/vpnkit-local-host-smoke.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat >"$tmp/bin/ip" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$*" == '-4 route get 1.1.1.1' ]]; then
  printf '%s\n' "1.1.1.1 dev ${MOCK_ROUTE_DEVICE:-tun7} src 10.89.0.2"
  exit 0
fi
if [[ "$*" == '-6 route get '* ]]; then
  exit 2
fi
exit 1
EOF
cat >"$tmp/bin/getent" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '93.184.216.34 STREAM example.com'
EOF
cat >"$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$tmp/bin/ping" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *' -6 '*) exit 1 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$tmp/bin"/*
export PATH="$tmp/bin:$PATH"

bash -n "$script"
if grep -Eiq '(^|[^[:alnum:]_])(docker|nmcli|sudo)([^[:alnum:]_]|$)' "$script"; then
  echo 'host smoke contains a forbidden mutating integration' >&2
  exit 1
fi
if ! output=$(VPNKIT_LOCAL_SMOKE_TIMEOUT_SECONDS=2 VPNKIT_LOCAL_SMOKE_DEVICE=tun7 bash "$script" 2>&1); then
  echo "$output" >&2
  exit 1
fi
grep -Fxq 'host_smoke=pass' <<<"$output"
grep -Fxq 'route=pass' <<<"$output"
grep -Fxq 'dns=pass' <<<"$output"
grep -Fxq 'literal_ip_https=pass' <<<"$output"
grep -Fxq 'ipv6_block=pass' <<<"$output"

# Exact-device routing is required even when every application probe is
# mocked successful.  A different tun, ppp, or vpn device must fail closed.
for bad_device in tun8 ppp0 vpn0; do
  if MOCK_ROUTE_DEVICE="$bad_device" VPNKIT_LOCAL_SMOKE_DEVICE=tun7 bash "$script" >/dev/null 2>&1; then
    echo "route accepted non-owned device: $bad_device" >&2
    exit 1
  fi
done
if VPNKIT_LOCAL_SMOKE_DEVICE=ppp0 MOCK_ROUTE_DEVICE=ppp0 bash "$script" >/dev/null 2>&1; then
  echo 'host smoke accepted forbidden ppp0' >&2
  exit 1
fi
printf 'vpnkit local host smoke mock tests passed\n'
