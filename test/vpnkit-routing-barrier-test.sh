#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
setup="$root/docker/vpnkit/setup-routing.sh"
entrypoint="$root/docker/vpnkit/entrypoint.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/vpnkit-routing-barrier.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
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
