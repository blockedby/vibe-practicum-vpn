#!/usr/bin/env bash
set -Eeuo pipefail

# Mock-only contract tests for the issue #40 host routing helper.  The mock
# commands are first in PATH; no host ip, nmcli, systemd, Docker, or live
# networking command is reached by this test.

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$ROOT_DIR/scripts/vpnkit/vpnkit-local-underlay-routing.sh"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vpnkit-local-underlay.XXXXXX")
MOCK_BIN="$TMP_DIR/bin"
MOCK_LOG="$TMP_DIR/commands.log"
MOCK_RULES="$TMP_DIR/rules"
FAKE_ROOT="$TMP_DIR/root"
mkdir -p "$MOCK_BIN" "$FAKE_ROOT"
touch "$MOCK_LOG"

cleanup() {
  rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT

fail_test() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_contains() {
  local path=$1
  local pattern=$2
  grep -Fq -- "$pattern" "$path" || fail_test "missing expected file content"
}

assert_no_file_pattern() {
  local path=$1
  local pattern=$2
  ! grep -Eq -- "$pattern" "$path" || fail_test "unexpected file content"
}

cat > "$MOCK_RULES" <<'EOF_RULES'
0:	from all lookup local
1000:	from 198.18.0.0/24 lookup 51840
1001:	from 198.18.0.0/24 unreachable
32766:	from all lookup main
32767:	from all lookup default
EOF_RULES

cat > "$MOCK_BIN/ip" <<'EOF_IP'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'ip %s\n' "$*" >> "$MOCK_LOG"

if [[ "$*" == "-4 rule show" ]]; then
  cat "$MOCK_RULES"
  exit 0
fi
if [[ "$1" == "-4" && "$2" == "rule" && "$3" == "add" ]]; then
  if [[ "$*" == *" unreachable" ]]; then
    printf '1001:\tfrom 198.18.0.0/24 unreachable\n' >> "$MOCK_RULES"
  else
    printf '1000:\tfrom 198.18.0.0/24 lookup 51840\n' >> "$MOCK_RULES"
  fi
  exit 0
fi
if [[ "$1" == "-4" && "$2" == "rule" && "$3" == "del" ]]; then
  priority=${5:-}
  awk -v p="${priority}:" '$1 != p { print }' "$MOCK_RULES" > "${MOCK_RULES}.tmp"
  mv -f "${MOCK_RULES}.tmp" "$MOCK_RULES"
  exit 0
fi

if [[ "$*" == "-4 route show table all" ]]; then
  if [[ ${MOCK_TABLE_MISSING:-0} != 1 ]]; then
    if [[ ${MOCK_BAD_UPLINK:-0} == 1 ]]; then
      printf '%s\n' 'default via 192.0.2.1 dev ppp0 proto dhcp src 192.0.2.10 metric 100'
    else
      printf '%s\n' 'default via 192.0.2.1 dev enp42s0 table 51840 proto 242 metric 42040'
    fi
  fi
  if [[ ${MOCK_BAD_UPLINK:-0} == 1 ]]; then
    cat <<'EOF_BAD_ROUTES'
default via 192.0.2.1 dev ppp0 proto dhcp src 192.0.2.10 metric 100
192.0.2.0/24 dev ppp0 proto kernel scope link src 192.0.2.10 metric 100
EOF_BAD_ROUTES
  else
    cat <<'EOF_ROUTES'
default via 192.0.2.1 dev enp42s0 proto dhcp src 192.0.2.10 metric 100
192.0.2.0/24 dev enp42s0 proto kernel scope link src 192.0.2.10 metric 100
EOF_ROUTES
  fi
  exit 0
fi
if [[ "$*" == "-4 route show table 51840" ]]; then
  if [[ ${MOCK_TABLE_MISSING:-0} == 1 ]]; then exit 2; fi
  cat <<'EOF_MANAGED'
192.0.2.0/24 dev enp42s0 proto 99 scope link metric 42040
default via 192.0.2.1 dev enp42s0 proto 99 metric 42040
EOF_MANAGED
  exit 0
fi

# Route add/replace/delete are intentionally accepted but never touch the
# kernel.  Their arguments remain in the mock log for exact-cleanup asserts.
exit 0
EOF_IP

cat > "$MOCK_BIN/nmcli" <<'EOF_NMCLI'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'nmcli %s\n' "$*" >> "$MOCK_LOG"
if [[ ${MOCK_BAD_UPLINK:-0} == 1 ]]; then
  printf '%s\n' 'ppp0:ethernet:connected'
  printf '%s\n' 'vpn0:ethernet:connected'
else
  printf '%s\n' 'enp99s0:ethernet:connected'
  printf '%s\n' 'enp42s0:ethernet:connected'
  printf '%s\n' 'tun-work:tun:connected'
fi
EOF_NMCLI

cat > "$MOCK_BIN/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'systemctl %s\n' "$*" >> "$MOCK_LOG"
if [[ ${MOCK_SYSTEMCTL_FAIL:-0} == 1 ]]; then
  exit 1
fi
exit 0
EOF_SYSTEMCTL

cat > "$MOCK_BIN/id" <<'EOF_ID'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${1:-}" == "-u" ]]; then
  if [[ ${MOCK_NONROOT:-0} == 1 ]]; then
    printf '1000\n'
  else
    printf '0\n'
  fi
else
  printf 'mock\n'
fi
EOF_ID

chmod +x "$MOCK_BIN"/*
export PATH="$MOCK_BIN:$PATH"
export MOCK_LOG MOCK_RULES
export VPNKIT_LOCAL_UNDERLAY_ROOT="$FAKE_ROOT"
export VPNKIT_LOCAL_DOCKER_SUBNET=198.18.0.0/24
export VPNKIT_LOCAL_ROUTE_TABLE=51840

# Static safety contract: no privilege escalation helper, Docker command, or
# broad route/rule flush is present in the implementation.
assert_no_file_pattern "$HELPER" '(^|[[:space:]])sudo([[:space:]]|$)'
assert_no_file_pattern "$HELPER" 'ip([[:space:]].*)?(route|rule)[[:space:]]+flush'
assert_no_file_pattern "$HELPER" 'nmcli[[:space:]].*(connection|con)[[:space:]]+(up|down|modify|delete|add)'
grep -Fq 'DEFAULT_DOCKER_SUBNET="172.30.89.0/24"' "$HELPER" || fail_test "helper default subnet drifted from compose.local.yaml"
grep -Fq 'VPNKIT_LOCAL_DOCKER_SUBNET:-172.30.89.0/24' "$ROOT_DIR/compose.local.yaml" || fail_test "compose local subnet default drifted from helper"

# Explicit and automatic discovery must reject PPP/VPN interfaces even when a
# fixture marks them connected or gives them a default route.
for bad_iface in ppp0 vpn0; do
  if VPNKIT_LOCAL_UPLINK_IFACE="$bad_iface" bash "$HELPER" plan >/dev/null 2>&1; then
    fail_test "explicit non-physical uplink was accepted: $bad_iface"
  fi
done
bad_auto_output=$(MOCK_BAD_UPLINK=1 bash "$HELPER" plan 2>&1) || fail_test 'automatic discovery plan unexpectedly errored'
grep -Fq 'physical_uplink_table=unavailable' <<<"$bad_auto_output" || fail_test 'automatic discovery accepted a PPP/VPN uplink'
VPNKIT_LOCAL_UPLINK_IFACE=auto bash "$HELPER" plan >/dev/null 2>&1 || fail_test 'auto uplink mode rejected valid physical fixture'

# Help is non-mutating and does not even need mocked host discovery.
: > "$MOCK_LOG"
bash "$HELPER" --help >/dev/null 2>&1 || fail_test "help contract failed"
[[ ! -s "$MOCK_LOG" ]] || fail_test "help probed a host command"

# Default invocation is plan and must remain read-only.  Its diagnostics must
# not echo the fixture's route values.
: > "$MOCK_LOG"
plan_output=$(bash "$HELPER" 2>&1) || fail_test "default plan failed"
grep -Fq 'mutation=none' <<< "$plan_output" || fail_test "plan was not non-mutating"
grep -Fq 'physical_uplink_table=ready' <<< "$plan_output" || fail_test "plan did not discover fixture uplink"
if grep -Eq '192\.0\.2\.|enp42s0|51840' <<< "$plan_output"; then
  fail_test "plan leaked route values"
fi
if grep -Eq 'ip .* (route (add|replace|del)|rule (add|del))' "$MOCK_LOG"; then
  fail_test "plan mutated routing"
fi
if grep -Fq 'systemctl' "$MOCK_LOG"; then
  fail_test "plan touched systemd"
fi

# Install requires the explicit confirmation flag before even attempting a
# host mutation.
: > "$MOCK_LOG"
if bash "$HELPER" install >/dev/null 2>&1; then
  fail_test "install accepted missing confirmation"
fi
[[ ! -s "$MOCK_LOG" ]] || fail_test "unconfirmed install reached a host command"

# An unrelated config at the bounded target path is never adopted or
# overwritten by an install attempt.
unmanaged_config="$FAKE_ROOT/etc/vpnkit-local-underlay-routing.conf"
mkdir -p "${unmanaged_config%/*}"
printf '%s\n' 'unrelated=true' > "$unmanaged_config"
: > "$MOCK_LOG"
if bash "$HELPER" install --yes >/dev/null 2>&1; then
  fail_test "install adopted unmanaged config"
fi
assert_file_contains "$unmanaged_config" 'unrelated=true'
if grep -Eq 'ip .* (route (add|replace|del)|rule (add|del))' "$MOCK_LOG"; then
  fail_test "unmanaged config caused route mutation"
fi
rm -f -- "$unmanaged_config"

# Mock-root installation exercises the route/rule ordering and public-safe
# bounded templates without touching the real /etc, systemd, or route state.
cat > "$MOCK_RULES" <<'EOF_BUILTIN_RULES'
0:	from all lookup local
32766:	from all lookup main
32767:	from all lookup default
EOF_BUILTIN_RULES
: > "$MOCK_LOG"
bash "$HELPER" install --yes >/dev/null 2>&1 || fail_test "mock install failed"
block_add_line=$(grep -n 'ip -4 rule add priority 1001' "$MOCK_LOG" | head -1 | cut -d: -f1)
route_replace_line=$(grep -n 'ip -4 route replace' "$MOCK_LOG" | head -1 | cut -d: -f1)
lookup_add_line=$(grep -n 'ip -4 rule add priority 1000' "$MOCK_LOG" | head -1 | cut -d: -f1)
[[ -n "$block_add_line" && -n "$route_replace_line" && -n "$lookup_add_line" ]] || fail_test "install did not exercise managed mutations"
(( block_add_line < route_replace_line && route_replace_line < lookup_add_line )) \
  || fail_test "install did not establish blocker before lookup"

CONFIG="$FAKE_ROOT/etc/vpnkit-local-underlay-routing.conf"
SERVICE="$FAKE_ROOT/etc/systemd/system/vpnkit-local-underlay-routing.service"
DISPATCHER="$FAKE_ROOT/etc/NetworkManager/dispatcher.d/90-vpnkit-local-underlay-routing"
INSTALLED_HELPER="$FAKE_ROOT/usr/local/libexec/vpnkit-local-underlay-routing"
[[ -f "$CONFIG" && -f "$SERVICE" && -f "$DISPATCHER" && -x "$INSTALLED_HELPER" ]] || fail_test "bounded install files missing"
assert_file_contains "$SERVICE" 'ExecStart='
assert_file_contains "$DISPATCHER" '--runtime-refresh'
[[ $(head -1 "$DISPATCHER") == '#!/usr/bin/env bash' ]] || fail_test "dispatcher template is not executable-safe"
assert_no_file_pattern "$SERVICE" '192\.0\.2\.|enp42s0|51840'
assert_no_file_pattern "$DISPATCHER" '192\.0\.2\.|enp42s0|51840'

verify_output=$(bash "$HELPER" verify 2>&1) || fail_test "verify failed after mock install"
grep -Fq 'lookup_rule=pass' <<< "$verify_output" || fail_test "lookup rule was not verified"
grep -Fq 'fail_closed_rule=pass' <<< "$verify_output" || fail_test "fail-closed rule was not verified"
grep -Fq 'rule_order=pass' <<< "$verify_output" || fail_test "rule ordering was not verified"
if grep -Eq '192\.0\.2\.|enp42s0|51840' <<< "$verify_output"; then
  fail_test "verify leaked route values"
fi

# A never-created numeric table is an empty owned table, not a fatal read
# error. Refresh must install its first routes while the blocker is retained.
export MOCK_TABLE_MISSING=1
bash "$HELPER" --runtime-refresh >/dev/null 2>&1 || fail_test "refresh rejected a never-created owned table"
unset MOCK_TABLE_MISSING

status_output=$(bash "$HELPER" status 2>&1) || fail_test "status failed after mock install"
grep -Fq 'mutation=none' <<< "$status_output" || fail_test "status was not read-only"
if grep -Eq '192\.0\.2\.|enp42s0|51840' <<< "$status_output"; then
  fail_test "status leaked route values"
fi

# A broader, earlier source rule must fail verification rather than bypassing
# the helper's fail-closed boundary.
printf '%s\n' '500: from 198.18.0.0/25 lookup 777' >> "$MOCK_RULES"
if bash "$HELPER" verify >/dev/null 2>&1; then
  fail_test "verify accepted an earlier overlapping source rule"
fi
awk '$1 != "500:" { print }' "$MOCK_RULES" > "${MOCK_RULES}.tmp"
mv -f "${MOCK_RULES}.tmp" "$MOCK_RULES"

# A failed systemd step must leave the previously managed file set intact.
export MOCK_SYSTEMCTL_FAIL=1
if bash "$HELPER" install --yes >/dev/null 2>&1; then
  fail_test "failed systemd install unexpectedly succeeded"
fi
unset MOCK_SYSTEMCTL_FAIL
[[ -f "$CONFIG" && -f "$SERVICE" && -f "$DISPATCHER" && -x "$INSTALLED_HELPER" ]] \
  || fail_test "failed install did not restore managed files"
grep -Eq '^1000:[[:space:]]+from 198\.18\.0\.0/24 lookup 51840$' "$MOCK_RULES" || fail_test "lookup rule was not restored"
grep -Eq '^1001:[[:space:]]+from 198\.18\.0\.0/24 unreachable$' "$MOCK_RULES" || fail_test "fail-closed rule was not restored"

# Both mutation contracts require direct root as well as --yes.
: > "$MOCK_LOG"
export MOCK_NONROOT=1
if bash "$HELPER" uninstall --yes >/dev/null 2>&1; then
  fail_test "uninstall accepted non-root caller"
fi
unset MOCK_NONROOT
[[ ! -s "$MOCK_LOG" ]] || fail_test "non-root uninstall reached a host command"

# Uninstall must require root plus --yes.  The confirmed mock uninstall must
# issue exact deletes for marked routes/rules and never flush a table.
bash "$HELPER" uninstall --yes >/dev/null 2>&1 || fail_test "mock uninstall failed"
if [[ -e "$CONFIG" || -e "$SERVICE" || -e "$DISPATCHER" || -e "$INSTALLED_HELPER" ]]; then
  fail_test "uninstall left managed files"
fi
grep -Fq 'ip -4 rule del priority 1000 from 198.18.0.0/24 table 51840' "$MOCK_LOG" \
  || fail_test "uninstall did not remove exact lookup rule"
grep -Fq 'ip -4 rule del priority 1001 from 198.18.0.0/24 unreachable' "$MOCK_LOG" \
  || fail_test "uninstall did not remove exact fail-closed rule"
grep -Fq 'ip -4 route del default via 192.0.2.1 dev enp42s0 table 51840 proto 99 metric 42040' "$MOCK_LOG" \
  || fail_test "uninstall did not remove exact managed default"
if grep -Eq 'route flush|rule flush|ip route del table 51840$' "$MOCK_LOG"; then
  fail_test "uninstall used broad cleanup"
fi

printf '%s\n' 'vpnkit-local-underlay-routing mock tests: PASS'
