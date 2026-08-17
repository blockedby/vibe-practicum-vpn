#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
setup="$root/docker/vpnkit/setup-routing.sh"
entrypoint="$root/docker/vpnkit/entrypoint.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/vpnkit-routing-barrier.XXXXXX")
stateful_owner_dir=
trap 'rm -rf -- "$tmp"; [[ -z "${stateful_owner_dir:-}" ]] || rm -rf -- "$stateful_owner_dir"' EXIT
mkdir -p "$tmp/bin"
cat >"$tmp/bin/iptables" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp/bin/iptables"
export PATH="$tmp/bin:$PATH"

bash -n "$setup" "$entrypoint"

install_output=$(VPNKIT_ROUTING_DRY_RUN=true OVPN_CIDR=198.18.0.0/24 bash "$setup" --install-fail-closed-barrier 2>&1)
grep -Fq -- '-N OVPN_FAIL_CLOSED' <<<"$install_output"
grep -Fq -- '-A OVPN_FAIL_CLOSED -j DROP' <<<"$install_output"
grep -Fq -- '-I INPUT 1 -s 198.18.0.0/24 -j OVPN_FAIL_CLOSED' <<<"$install_output"
grep -Fq -- '-I FORWARD 1 -s 198.18.0.0/24 -j OVPN_FAIL_CLOSED' <<<"$install_output"
! grep -Fq -- '-m comment' <<<"$install_output"
! grep -Eq 'route|rule|sysctl' <<<"$install_output"

if unsafe_output=$(VPNKIT_ROUTING_DRY_RUN=true OVPN_CIDR=198.18.0.0/24 OPENVPN_FAIL_CLOSED_CHAIN=INPUT bash "$setup" --remove-fail-closed-barrier 2>&1); then
  echo 'built-in fail-closed chain override unexpectedly accepted' >&2
  exit 1
fi
grep -Fq 'chain override is not permitted' <<<"$unsafe_output"
! grep -Eq -- ' -F INPUT| -X INPUT| -D INPUT' <<<"$unsafe_output"

foreign_bin="$tmp/foreign-bin"
mkdir -p "$foreign_bin"
cat >"$foreign_bin/iptables" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FOREIGN_IPTABLES_LOG"
if [[ " $* " == *' -N OVPN_FAIL_CLOSED '* ]]; then exit 1; fi
exit 0
EOF
chmod +x "$foreign_bin/iptables"
foreign_log="$tmp/foreign-iptables.log"
foreign_owner="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/vpnkit-barrier-test-owner"
rm -f -- "$foreign_owner"
if foreign_output=$(PATH="$foreign_bin:$PATH" FOREIGN_IPTABLES_LOG="$foreign_log" VPNKIT_FAIL_CLOSED_OWNER_FILE="$foreign_owner" OVPN_CIDR=198.18.0.0/24 bash "$setup" --install-fail-closed-barrier 2>&1); then
  echo 'pre-existing foreign chain unexpectedly adopted' >&2
  exit 1
fi
grep -Fq 'pre-existing unowned fail-closed chain' <<<"$foreign_output"
! grep -Eq -- '(^| )(-F|-X|-A|-I|-D)( |$)' "$foreign_log"

# REV-001: a process can die after -N succeeds but before the owner marker is
# atomically installed.  Keep a stateful iptables mock across invocations so
# the retry has to prove the chain is empty and unreferenced before adopting it.
stateful_bin="$tmp/stateful-bin"
mkdir -p "$stateful_bin"
cat >"$stateful_bin/iptables" <<'EOF'
#!/usr/bin/env bash
set -u
state=${MOCK_IPTABLES_STATE:?}
log=${MOCK_IPTABLES_LOG:?}
mkdir -p "$(dirname -- "$state")"
: >>"$log"
printf '%s\n' "$*" >>"$log"
touch "$state"

has_chain() {
  case "$1" in
    INPUT|FORWARD) return 0 ;;
  esac
  grep -Fqx -- "chain|$1" "$state"
}
has_rule() {
  grep -Fqx -- "rule|$1|$2" "$state"
}
append_rule() {
  printf 'rule|%s|%s\n' "$1" "$2" >>"$state"
}
insert_rule() {
  local chain=$1 rule=$2 tmp="${state}.tmp.$$" line inserted=0
  : >"$tmp"
  while IFS= read -r line; do
    if [[ $inserted == 0 && "$line" == "rule|$chain|"* ]]; then
      printf 'rule|%s|%s\n' "$chain" "$rule" >>"$tmp"
      inserted=1
    fi
    printf '%s\n' "$line" >>"$tmp"
  done <"$state"
  (( inserted == 0 )) && printf 'rule|%s|%s\n' "$chain" "$rule" >>"$tmp"
  mv -f -- "$tmp" "$state"
}
remove_one_rule() {
  local chain=$1 rule=$2 tmp="${state}.tmp.$$" line removed=0
  : >"$tmp"
  while IFS= read -r line; do
    if [[ $removed == 0 && "$line" == "rule|$chain|$rule" ]]; then
      removed=1
      continue
    fi
    printf '%s\n' "$line" >>"$tmp"
  done <"$state"
  if (( removed == 1 )); then
    mv -f -- "$tmp" "$state"
    return 0
  fi
  rm -f -- "$tmp"
  return 1
}
flush_chain() {
  local chain=$1 tmp="${state}.tmp.$$" line
  : >"$tmp"
  while IFS= read -r line; do
    [[ "$line" == "rule|$chain|"* ]] && continue
    printf '%s\n' "$line" >>"$tmp"
  done <"$state"
  mv -f -- "$tmp" "$state"
}
emit_snapshot() {
  local kind chain rule
  while IFS='|' read -r kind chain rule; do
    case "$kind" in
      chain) printf '%s\n' "-N $chain" ;;
      rule) printf '%s\n' "-A $chain $rule" ;;
    esac
  done <"$state"
}
emit_chain() {
  local wanted=$1 kind chain rule
  has_chain "$wanted" || return 1
  while IFS='|' read -r kind chain rule; do
    [[ "$chain" == "$wanted" ]] || continue
    case "$kind" in
      chain) printf '%s\n' "-N $chain" ;;
      rule) printf '%s\n' "-A $chain $rule" ;;
    esac
  done <"$state"
}

[[ ${1:-} == -t && ${2:-} == filter ]] || exit 2
case "${3:-}" in
  -N)
    chain=${4:-}
    has_chain "$chain" && exit 1
    printf 'chain|%s\n' "$chain" >>"$state"
    if [[ ${MOCK_INTERRUPT_AFTER_NEW_CHAIN:-0} == 1 && ! -e "$state.interrupted" ]]; then
      : >"$state.interrupted"
      # Kill the setup process, not this mock child: the real failure is the
      # process boundary between -N and the owner-marker write.
      kill -TERM "$PPID"
    fi
    exit 0
    ;;
  -S)
    if [[ -n ${4:-} ]]; then
      emit_chain "$4"
    else
      emit_snapshot
    fi
    exit $?
    ;;
  -C)
    has_chain "${4:-}" && has_rule "${4:-}" "${*:5}"
    exit $?
    ;;
  -A)
    has_chain "${4:-}" || exit 1
    append_rule "${4:-}" "${*:5}"
    exit 0
    ;;
  -I)
    has_chain "${4:-}" || exit 1
    [[ ${5:-} == 1 ]] || exit 2
    insert_rule "${4:-}" "${*:6}"
    exit 0
    ;;
  -D)
    remove_one_rule "${4:-}" "${*:5}"
    exit $?
    ;;
  -F)
    has_chain "${4:-}" || exit 1
    flush_chain "${4:-}"
    exit 0
    ;;
  -X)
    chain=${4:-}
    has_chain "$chain" || exit 1
    while IFS='|' read -r kind current rule; do
      [[ "$kind" == rule ]] || continue
      [[ "$current" != "$chain" ]] || exit 1
      [[ "$rule" == *" -j $chain"* || "$rule" == *" -g $chain"* ]] && exit 1
    done <"$state"
    tmp="${state}.tmp.$$"
    awk -F'|' -v target="$chain" '$1 != "chain" || $2 != target' "$state" >"$tmp"
    mv -f -- "$tmp" "$state"
    exit 0
    ;;
esac
exit 2
EOF
chmod +x "$stateful_bin/iptables"
stateful_state="$tmp/stateful-iptables.state"
stateful_log="$tmp/stateful-iptables.log"
: >"$stateful_state"
: >"$stateful_log"
stateful_runtime_root=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
stateful_owner_dir="$stateful_runtime_root/vpnkit-routing-barrier-$BASHPID"
mkdir -p -- "$stateful_owner_dir"
stateful_owner="$stateful_owner_dir/owner"
stateful_path="$stateful_bin:$PATH"
if interrupted_output=$(PATH="$stateful_path" MOCK_IPTABLES_STATE="$stateful_state" MOCK_IPTABLES_LOG="$stateful_log" \
    MOCK_INTERRUPT_AFTER_NEW_CHAIN=1 VPNKIT_FAIL_CLOSED_OWNER_FILE="$stateful_owner" \
    OVPN_CIDR=198.18.0.0/24 bash "$setup" --install-fail-closed-barrier 2>&1); then
  echo 'interrupt-after-N mock unexpectedly completed' >&2
  exit 1
else
  interrupted_rc=$?
fi
[[ "$interrupted_rc" -ne 0 ]]
grep -Fqx 'chain|OVPN_FAIL_CLOSED' "$stateful_state"
! grep -Fq 'rule|' "$stateful_state"
[[ ! -e "$stateful_owner" ]]
if ! retry_output=$(PATH="$stateful_path" MOCK_IPTABLES_STATE="$stateful_state" MOCK_IPTABLES_LOG="$stateful_log" \
    VPNKIT_FAIL_CLOSED_OWNER_FILE="$stateful_owner" OVPN_CIDR=198.18.0.0/24 \
    bash "$setup" --install-fail-closed-barrier 2>&1); then
  printf '%s\n' "$retry_output" >&2
  exit 1
fi
grep -Fqx 'OVPN_FAIL_CLOSED' "$stateful_owner"
grep -Fqx 'rule|OVPN_FAIL_CLOSED|-j DROP' "$stateful_state"
grep -Fqx 'rule|INPUT|-s 198.18.0.0/24 -j OVPN_FAIL_CLOSED' "$stateful_state"
grep -Fqx 'rule|FORWARD|-s 198.18.0.0/24 -j OVPN_FAIL_CLOSED' "$stateful_state"
# Cleanup can be retried after every successful boundary, including after the
# marker and chain have already been removed.
PATH="$stateful_path" MOCK_IPTABLES_STATE="$stateful_state" MOCK_IPTABLES_LOG="$stateful_log" \
  VPNKIT_FAIL_CLOSED_OWNER_FILE="$stateful_owner" OVPN_CIDR=198.18.0.0/24 \
  bash "$setup" --remove-fail-closed-barrier >/dev/null
PATH="$stateful_path" MOCK_IPTABLES_STATE="$stateful_state" MOCK_IPTABLES_LOG="$stateful_log" \
  VPNKIT_FAIL_CLOSED_OWNER_FILE="$stateful_owner" OVPN_CIDR=198.18.0.0/24 \
  bash "$setup" --remove-fail-closed-barrier >/dev/null
! grep -Fq 'chain|OVPN_FAIL_CLOSED' "$stateful_state"
[[ ! -e "$stateful_owner" ]]

assert_unowned_state_rejected() {
  local label=$1
  cp -- "$stateful_state" "$stateful_state.before"
  rm -f -- "$stateful_owner"
  : >"$stateful_log"
  if foreign_state_output=$(PATH="$stateful_path" MOCK_IPTABLES_STATE="$stateful_state" MOCK_IPTABLES_LOG="$stateful_log" \
      VPNKIT_FAIL_CLOSED_OWNER_FILE="$stateful_owner" OVPN_CIDR=198.18.0.0/24 \
      bash "$setup" --install-fail-closed-barrier 2>&1); then
    echo "$label unowned chain unexpectedly accepted" >&2
    exit 1
  fi
  grep -Fq 'pre-existing unowned fail-closed chain' <<<"$foreign_state_output"
  cmp -s "$stateful_state.before" "$stateful_state"
  [[ ! -e "$stateful_owner" ]]
  ! grep -Eq -- '(^| )(-F|-X|-A|-I|-D)( |$)' "$stateful_log"
}

# A rule inside the same-name chain is foreign state, even though there is no
# external jump into it.
cat >"$stateful_state" <<'EOF'
chain|OVPN_FAIL_CLOSED
rule|OVPN_FAIL_CLOSED|-j DROP
EOF
assert_unowned_state_rejected 'nonempty'
# An empty chain with an external jump is equally unsafe to adopt.
cat >"$stateful_state" <<'EOF'
chain|OVPN_FAIL_CLOSED
rule|INPUT|-s 198.18.0.0/24 -j OVPN_FAIL_CLOSED
EOF
assert_unowned_state_rejected 'referenced'

apply_output=$(VPNKIT_ROUTING_DRY_RUN=true VPNKIT_ROUTING_MODE=redirect OVPN_CIDR=198.18.0.0/24 bash "$setup" 2>&1)
first_barrier=$(grep -n -- '-I INPUT 1 -s 198.18.0.0/24' <<<"$apply_output" | head -1 | cut -d: -f1)
first_routing=$(grep -n -- 'OVPN_REDIRECT_TO_SINGBOX' <<<"$apply_output" | head -1 | cut -d: -f1)
last_remove=$(grep -n -- '-D INPUT -s 198.18.0.0/24' <<<"$apply_output" | tail -1 | cut -d: -f1)
[[ -n "$first_barrier" && -n "$first_routing" && -n "$last_remove" ]]
(( first_barrier < first_routing && first_routing < last_remove ))

remove_output=$(VPNKIT_ROUTING_DRY_RUN=true OVPN_CIDR=198.18.0.0/24 bash "$setup" --remove-fail-closed-barrier 2>&1)
grep -Fq -- '-D INPUT -s 198.18.0.0/24 -j OVPN_FAIL_CLOSED' <<<"$remove_output"
grep -Fq -- '-D FORWARD -s 198.18.0.0/24 -j OVPN_FAIL_CLOSED' <<<"$remove_output"
grep -Fq -- '-F OVPN_FAIL_CLOSED' <<<"$remove_output"
grep -Fq -- '-X OVPN_FAIL_CLOSED' <<<"$remove_output"

# The entrypoint must install the barrier before OpenVPN and stop processes
# before cleanup removes it.
barrier_line=$(grep -n -- '--install-fail-closed-barrier' "$entrypoint" | tail -1 | cut -d: -f1)
openvpn_line=$(grep -n '^openvpn --config' "$entrypoint" | head -1 | cut -d: -f1)
setup_line=$(grep -n '^/usr/local/bin/setup-routing.sh$' "$entrypoint" | tail -1 | cut -d: -f1)
cleanup_remove_line=$(grep -n -- '--remove-fail-closed-barrier' "$entrypoint" | head -1 | cut -d: -f1)
stop_pid_line=$(grep -n '^  stop_pid' "$entrypoint" | tail -1 | cut -d: -f1)
[[ "$barrier_line" -lt "$openvpn_line" && "$openvpn_line" -lt "$setup_line" ]]
[[ "$stop_pid_line" -lt "$cleanup_remove_line" ]]

grep -Fq 'fail_closed_barrier_absent' "$root/docker/vpnkit/vpnkit-healthcheck.sh"
grep -Fq -- '-S "$openvpn_fail_closed_chain"' "$root/docker/vpnkit/vpnkit-healthcheck.sh"
! grep -Fq -- '-m comment' "$setup"
! grep -Fq 'run iptables -I INPUT 1 -i tun0 -s "$OVPN_CIDR" -m mark' "$setup"
grep -Fq 'run iptables -I INPUT 2 -i tun0 -s "$OVPN_CIDR" -m mark' "$setup"
printf 'vpnkit routing barrier mock/static tests passed\n'
