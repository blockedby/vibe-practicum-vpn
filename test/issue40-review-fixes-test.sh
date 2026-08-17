#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/vpnkit-issue40-review.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

bash -n "$ROOT/test/containers-test.sh" \
  "$ROOT/docker/ovpn-client-test/run-tests.sh" \
  "$ROOT/scripts/vpnkit/vpnkit-render-local-kde-configs.sh" \
  "$ROOT/docker/vpnkit/setup-routing.sh" \
  "$ROOT/docker/vpnkit/dns-failover-watchdog.sh" \
  "$ROOT/docker/vpnkit/vpnkit-healthcheck.sh" \
  || fail 'owned shell files are not syntactically valid'

grep -Fq 'ports: !override' "$ROOT/compose.local.yaml" || fail 'local Compose ports are not an overriding loopback publication'
grep -Fq '127.0.0.1:${VPNKIT_LOCAL_OPENVPN_PORT:-${VPNKIT_OPENVPN_PORT:-21194}}:1194/udp' "$ROOT/compose.local.yaml" || fail 'local Compose publication is not loopback-only'
grep -Fq 'com.vpnkit.local.owner' "$ROOT/compose.local.yaml" || fail 'local Compose ownership labels are missing'
grep -Fq '${VPNKIT_LOCAL_RESOURCE_OWNER:-local-lifecycle}' "$ROOT/compose.local.yaml" || fail 'local Compose does not distinguish lifecycle ownership from test ownership'
! grep -Fq './logs/' "$ROOT/compose.local.yaml" || fail 'local Compose still bind-mounts a host log root'
grep -Fq 'VPNKIT_LOCAL_SECRETS_DIR must stay' "$ROOT/scripts/vpnkit/vpnkit-render-local-kde-configs.sh" || fail 'local renderer accepts arbitrary secret roots'

grep -Fq 'local_compose_resources_owned' "$ROOT/test/containers-test.sh" || fail 'runner has no Compose ownership preflight'
grep -Fq 'local_compose_project_collisions' "$ROOT/test/containers-test.sh" || fail 'runner does not reject alternate Compose project collisions'
grep -Fq 'export VPNKIT_LOCAL_RESOURCE_OWNER="$LOCAL_TEST_OWNER_LABEL"' "$ROOT/test/containers-test.sh" || fail 'runner does not export the test-only owner label'
grep -Fq 'local_client_cleanup_scope_owned' "$ROOT/test/containers-test.sh" || fail 'runner has no client cleanup ownership preflight'
grep -Fq 'refusing unsafe remote lab state path' "$ROOT/test/containers-test.sh" || fail 'remote lab cleanup path is not bounded'
grep -Fq 'host_acceptance_reject_overrides' "$ROOT/test/containers-test.sh" || fail 'live local KDE acceptance does not reject fixture/override seams'
grep -Fq 'host_acceptance_validate_safe_config' "$ROOT/test/containers-test.sh" || fail 'live local KDE acceptance does not validate the sourced safe config contract'
grep -Fq 'HOST_CANONICAL_DESTINATION_RULE_PRIORITY=998' "$ROOT/test/containers-test.sh" || fail 'live local KDE acceptance lacks canonical routing identity values'
grep -Fq 'run_local_kde_host_contract' "$ROOT/test/containers-test.sh" || fail 'local KDE test action is not separated from live acceptance'
grep -Fq 'non-fixture local KDE --action test refuses' "$ROOT/test/containers-test.sh" || fail 'non-fixture local KDE test does not refuse before mutation'
grep -Fq 'command -p -v' "$ROOT/test/containers-test.sh" || fail 'live local KDE acceptance does not bind trusted absolute commands'
grep -Fq 'host:localhost-udp-underlay-nm-contract' "$ROOT/test/containers-test.sh" || fail 'mock local KDE path lacks a distinct contract row'
grep -Fq 'local_docker_source_digest' "$ROOT/test/containers-test.sh" || fail 'local-docker runner has no source provenance digest'
grep -Fq 'local_docker_verify_freshness' "$ROOT/test/containers-test.sh" || fail 'local-docker test has no freshness verification'
grep -Fq 'local Docker provenance record' "$ROOT/test/containers-test.sh" || fail 'local-docker provenance record safety is missing'
grep -Fq -- '-f UUID,TYPE connection show --active' "$ROOT/test/containers-test.sh" || fail 'work-VPN capture does not use minimal UUID/TYPE fields'
! grep -Fq -- '-f NAME,UUID,TYPE connection show --active' "$ROOT/test/containers-test.sh" || fail 'work-VPN capture still parses display names'
grep -Fq 'host_owned_nm_uuid_from_status' "$ROOT/test/containers-test.sh" || fail 'work-VPN capture lacks owned helper UUID proof'
grep -Fq 'host:cleanup-work-vpn' "$ROOT/test/containers-test.sh" || fail 'cleanup work-VPN comparison is missing'
grep -Fq 'canonical_priorities=ok' "$ROOT/test/containers-test.sh" || fail 'runner does not require canonical underlay priorities'
grep -Fq 'vpnkit|vpnkit-local' "$ROOT/test/containers-test.sh" || fail 'protected project guard is missing'
grep -Fq 'PASS icmp:1.1.1.1' "$ROOT/test/containers-test.sh" || fail 'runner does not require 1.1.1.1 ICMP evidence'
grep -Fq 'PASS ipv6:connectivity-fail-closed' "$ROOT/test/containers-test.sh" || fail 'runner does not require IPv6 fail-closed evidence'
grep -Fq 'PASS udp:google-dns' "$ROOT/test/containers-test.sh" || fail 'runner does not require practical UDP evidence'
grep -Fq 'server:dns-failover-shape' "$ROOT/test/containers-test.sh" || fail 'runner does not validate rendered DNS failover shape'
grep -Fq 'dns_source_shape_cmd' "$ROOT/test/containers-test.sh" || fail 'runner conflates immutable DNS policy with watchdog runtime'
grep -Fq 'vpnkit-render-local-kde-configs.sh' "$ROOT/test/containers-test.sh" || fail 'runner fixture does not render the local Cloudflare/Google policy'
grep -Fq -- '--profile test build ovpn-client-test' "$ROOT/test/containers-test.sh" || fail 'runner can reuse a stale client-test image'
grep -Fq 'row SKIP udp:arbitrary' "$ROOT/docker/ovpn-client-test/run-tests.sh" || fail 'arbitrary UDP coverage is not an honest bounded skip'

grep -Fq '/usr/local/bin/dns-failover-watchdog.sh --pid' "$ROOT/compose.local.yaml" || fail 'local Compose watchdog is not wired'
! grep -Fq 'sed -i' "$ROOT/compose.local.yaml" || fail 'DNS mutation logic remains inline in Compose'
grep -Fq 'probe cloudflare-dns.com 1.1.1.1' "$ROOT/docker/vpnkit/dns-failover-watchdog.sh" || fail 'Cloudflare health probe is missing'
grep -Fq 'probe dns.google 8.8.8.8' "$ROOT/docker/vpnkit/dns-failover-watchdog.sh" || fail 'Google fallback health probe is missing'
grep -Fq 'flock -x -w' "$ROOT/docker/vpnkit/dns-failover-watchdog.sh" || fail 'watchdog does not acquire the shared state lock'
grep -Fq '/.vibe-vpn.lock' "$ROOT/docker/vpnkit/dns-failover-watchdog.sh" || fail 'watchdog lock path is not the shared vibe-vpn lock'
grep -Fq 'sing-box check -c' "$ROOT/docker/vpnkit/dns-failover-watchdog.sh" || fail 'watchdog does not validate candidates with sing-box'
grep -Fq 'mv -f -- "$candidate" "$RUNTIME"' "$ROOT/docker/vpnkit/dns-failover-watchdog.sh" || fail 'watchdog does not atomically replace the runtime config'
grep -Fq '[[ -s "$token_tmp" ]]' "$ROOT/docker/vpnkit/dns-failover-watchdog.sh" || fail 'watchdog restart token write is missing'
grep -Fq 'main entrypoint pid' "$ROOT/docker/vpnkit/dns-failover-watchdog.sh" || fail 'watchdog does not fail when its supervised main exits'
grep -Fq 'setsid /usr/local/bin/entrypoint.sh &' "$ROOT/compose.local.yaml" || fail 'local Compose does not isolate the main process group'
grep -Fq 'setsid /usr/local/bin/dns-failover-watchdog.sh --pid "$$main_pid" &' "$ROOT/compose.local.yaml" || fail 'local Compose does not isolate the watchdog process group'
grep -Fq 'wait -n "$$main_pid" "$$watch_pid"' "$ROOT/compose.local.yaml" || fail 'local Compose does not wait for either supervisor child'
grep -Fq 'trap on_exit EXIT' "$ROOT/compose.local.yaml" || fail 'local Compose supervisor has no exit cleanup trap'
grep -Fq 'kill -"$$signal" -- "-$$pid"' "$ROOT/compose.local.yaml" || fail 'local Compose supervisor does not terminate process groups'
grep -Fq 'util-linux' "$ROOT/docker/vpnkit/Dockerfile" || fail 'Docker image does not explicitly install util-linux/flock'
grep -Fq 'dns-failover-watchdog.sh' "$ROOT/docker/vpnkit/Dockerfile" || fail 'watchdog is not copied into the image'
# Keep the source-CIDR chain fail-closed barrier; the healthcheck must not
# regress to the unavailable xt_comment match extension.
grep -Fq 'fail_closed_barrier_absent' "$ROOT/docker/vpnkit/vpnkit-healthcheck.sh" || fail 'healthcheck lost the chain barrier check'
grep -Fq -- '-S "$openvpn_fail_closed_chain"' "$ROOT/docker/vpnkit/vpnkit-healthcheck.sh" || fail 'healthcheck lost the chain existence check'
! grep -Fq -- '-m comment' "$ROOT/docker/vpnkit/vpnkit-healthcheck.sh" || fail 'healthcheck regressed to xt_comment'
# REV-001: retry adoption must prove a zero-rule, unreferenced partial chain;
# cleanup must also preserve the DROP chain if a foreign jump appears later.
grep -Fq 'fail_closed_chain_is_pristine_partial' "$ROOT/docker/vpnkit/setup-routing.sh" || fail 'setup-routing lacks strict partial-chain recovery proof'
grep -Fq 'fail_closed_chain_referenced_in_snapshot' "$ROOT/docker/vpnkit/setup-routing.sh" || fail 'setup-routing lacks all-chain reference proof'
grep -Fq 'refusing cleanup of referenced owned fail-closed chain' "$ROOT/docker/vpnkit/setup-routing.sh" || fail 'cleanup can flush a referenced fail-closed chain'

python3 - "$ROOT/config/sing-box/config.tun.json.template" <<'PY'
import json
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
text = text.replace('{{SELECTED_NATIVE_OUT_JSON}}', '{"type":"direct","tag":"selected-native-out"}')
text = text.replace('{{RU_RULE_SETS_JSON}}', '{"type":"local","tag":"geoip-ru","format":"source","path":"/tmp/geoip"}, {"type":"local","tag":"geosite-category-ru","format":"source","path":"/tmp/geosite"}')
cfg = json.loads(text)
servers = {entry['tag']: entry for entry in cfg['dns']['servers']}
assert cfg['dns']['final'] == 'remote-dns'
assert servers['remote-dns'] == {
    'tag': 'remote-dns', 'type': 'tls', 'server': '8.8.8.8',
    'detour': 'selected-native-out',
}
assert servers['remote-dns-fallback'] == {
    'tag': 'remote-dns-fallback', 'type': 'tls', 'server': '8.8.4.4',
    'detour': 'selected-native-out',
}
PY

rejects=(
  'VPNKIT_LOCAL_TEST_PROJECT=vpnkit'
  'VPNKIT_LOCAL_TEST_PROJECT=vpnkit-local'
  "VPNKIT_TEST_LAB_SECRETS_DIR=$ROOT/secrets/vpnkit-local"
  "VPNKIT_CONTAINERS_TEST_LOG=$ROOT/logs/vpnkit-local/issue40.log"
)
for assignment in "${rejects[@]}"; do
  if [[ "$assignment" == VPNKIT_CONTAINERS_TEST_LOG=* ]]; then
    if env $assignment "$ROOT/test/containers-test.sh" --scenario local-docker --action down \
        >"$TMP/reject.out" 2>&1; then rc=0; else rc=$?; fi
  else
    if env $assignment VPNKIT_CONTAINERS_TEST_LOG="$TMP/runner.log" \
        "$ROOT/test/containers-test.sh" --scenario local-docker --action down \
        >"$TMP/reject.out" 2>&1; then rc=0; else rc=$?; fi
  fi
  [[ $rc -ne 0 ]] || fail "runner accepted protected input: $assignment"
done

# REV-002: log creation must never follow a user-controlled link or truncate a
# shared inode. Use only a harmless Docker mock so these checks cannot touch a
# live daemon or any repository secret.
log_mock_dir="$TMP/log-boundary-mock"
mkdir -p "$log_mock_dir" "$TMP/log-lab" "$TMP/log-sentinels" "$TMP/real-log-parent"
cat >"$log_mock_dir/docker" <<'EOF'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >>"$MOCK_DOCKER_LOG"
case "${1:-}" in
  container|network|volume)
    [[ "${2:-}" == ls ]] && exit 0
    ;;
  compose)
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$log_mock_dir/docker"
: >"$TMP/log-mock.log"
run_log_runner() {
  local log_path=$1 output=$2
  PATH="$log_mock_dir:$PATH" MOCK_DOCKER_LOG="$TMP/log-mock.log" \
    VPNKIT_TEST_LAB_SECRETS_DIR="$TMP/log-lab" \
    VPNKIT_TEST_PROFILE="$TMP/log-lab/password=supersecret.ovpn" \
    VPNKIT_CONTAINERS_TEST_LOG="$log_path" \
    "$ROOT/test/containers-test.sh" --scenario local-docker --action down \
    >"$output" 2>&1
}

printf 'symlink sentinel\n' >"$TMP/symlink-target"
ln -s -- "$TMP/symlink-target" "$TMP/log-sentinels/final-symlink.log"
if run_log_runner "$TMP/log-sentinels/final-symlink.log" "$TMP/final-symlink.out"; then
  fail 'runner accepted a final log symlink'
fi
cmp -s "$TMP/symlink-target" <(printf 'symlink sentinel\n') || fail 'final symlink target changed'
[[ ! -s "$TMP/log-mock.log" ]] || fail 'final symlink reached Docker before log rejection'

ln -s -- "$TMP/real-log-parent" "$TMP/log-sentinels/parent-symlink"
printf 'component sentinel\n' >"$TMP/component-target"
ln -- "$TMP/component-target" "$TMP/real-log-parent/component.log"
if run_log_runner "$TMP/log-sentinels/parent-symlink/component.log" "$TMP/parent-symlink.out"; then
  fail 'runner accepted a log parent symlink'
fi
cmp -s "$TMP/component-target" <(printf 'component sentinel\n') || fail 'parent symlink target changed'
[[ ! -s "$TMP/log-mock.log" ]] || fail 'parent symlink reached Docker before log rejection'

printf 'hardlink sentinel\n' >"$TMP/hardlink-target"
ln -- "$TMP/hardlink-target" "$TMP/log-sentinels/hardlinked.log"
hardlink_count=$(stat -c '%h' "$TMP/hardlink-target")
if run_log_runner "$TMP/log-sentinels/hardlinked.log" "$TMP/hardlink.out"; then
  fail 'runner accepted a hardlinked log target'
fi
cmp -s "$TMP/hardlink-target" <(printf 'hardlink sentinel\n') || fail 'hardlink target changed'
[[ "$(stat -c '%h' "$TMP/hardlink-target")" == "$hardlink_count" ]] || fail 'hardlink count changed'
[[ ! -s "$TMP/log-mock.log" ]] || fail 'hardlink reached Docker before log rejection'

# Exercise the ownership boundary when this test account can observe a
# root-owned, non-writable system directory. Skip only when no such harmless
# candidate exists (or when the test itself is running as root).
non_user_parent=
if [[ "$(id -u)" != 0 ]]; then
  for candidate in /usr/local /usr/share /etc; do
    if [[ -d "$candidate" && ! -O "$candidate" && ! -w "$candidate" ]]; then
      non_user_parent=$candidate
      break
    fi
  done
fi
if [[ -n "$non_user_parent" ]]; then
  non_user_log="$non_user_parent/.vpnkit-issue40-review-$BASHPID.log"
  [[ ! -e "$non_user_log" && ! -L "$non_user_log" ]] || fail 'non-user-owned sentinel path unexpectedly exists'
  if run_log_runner "$non_user_log" "$TMP/non-user-owned.out"; then
    fail 'runner accepted a non-user-owned log parent'
  fi
  [[ ! -e "$non_user_log" && ! -L "$non_user_log" ]] || fail 'non-user-owned parent was modified'
  [[ ! -s "$TMP/log-mock.log" ]] || fail 'non-user-owned parent reached Docker before log rejection'
fi

broad_log="/tmp/.vpnkit-issue40-review-$BASHPID.log"
[[ ! -e "$broad_log" && ! -L "$broad_log" ]] || fail 'broad temporary sentinel path unexpectedly exists'
if run_log_runner "$broad_log" "$TMP/broad-path.out"; then
  fail 'runner accepted a broad temporary log parent'
fi
[[ ! -e "$broad_log" && ! -L "$broad_log" ]] || fail 'broad temporary parent was modified'
[[ ! -s "$TMP/log-mock.log" ]] || fail 'broad temporary parent reached Docker before log rejection'

normal_log="$TMP/log-sentinels/new.log"
if ! run_log_runner "$normal_log" "$TMP/normal-log.out"; then
  fail 'runner rejected a normal new log'
fi
[[ -f "$normal_log" && ! -L "$normal_log" ]] || fail 'normal log is not a regular non-symlink file'
[[ "$(stat -c '%a' "$normal_log")" == 600 ]] || fail 'normal log is not mode 600'
[[ "$(stat -c '%h' "$normal_log")" == 1 ]] || fail 'normal log is hardlinked'
grep -Fq 'vpnkit unified container test harness starting' "$TMP/normal-log.out" || fail 'normal log was not emitted to console'
grep -Fq 'vpnkit unified container test harness starting' "$normal_log" || fail 'normal log was not emitted to file'
grep -Fq 'password=[redacted]' "$TMP/normal-log.out" || fail 'console output was not redacted'
grep -Fq 'password=[redacted]' "$normal_log" || fail 'file output was not redacted'
! grep -Fq 'password=supersecret' "$TMP/normal-log.out" || fail 'console output leaked the profile sentinel'
! grep -Fq 'password=supersecret' "$normal_log" || fail 'file output leaked the profile sentinel'

# REV-001: explicit local-docker actions cannot turn an unavailable Docker
# daemon into green dependent SKIPs. The runner still reaches its later rows
# for the read-only `test` action, but the required readiness row is FAIL.
unavailable_docker_dir="$TMP/unavailable-docker"
mkdir -p "$unavailable_docker_dir"
cat >"$unavailable_docker_dir/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker unavailable sentinel\n' >&2
exit 42
EOF
chmod +x "$unavailable_docker_dir/docker"
for local_action in up test down cycle; do
  local_output="$TMP/local-docker-unavailable-$local_action.out"
  if PATH="$unavailable_docker_dir:$PATH" \
      VPNKIT_TEST_LAB_SECRETS_DIR="$TMP/local-docker-unavailable-lab" \
      VPNKIT_TEST_PROFILE="$TMP/local-docker-unavailable-lab/test-client.ovpn" \
      VPNKIT_CONTAINERS_TEST_LOG="$TMP/local-docker-unavailable-$local_action.log" \
      "$ROOT/test/containers-test.sh" --scenario local-docker --action "$local_action" \
      >"$local_output" 2>&1; then
    fail "local-docker $local_action accepted unavailable Docker"
  fi
  grep -Fq 'FAIL server:local-docker-reachable' "$local_output" || fail "local-docker $local_action did not fail its Docker readiness row"
  ! grep -Fq 'SKIP server:local-docker-reachable' "$local_output" || fail "local-docker $local_action softened Docker failure to SKIP"
done

# Configured SSH aliases/private hostnames must not appear in either output
# sink. Keep intentional public probe domains visible so this is targeted
# redaction rather than a blanket hostname replacement.
unavailable_ssh_dir="$TMP/unavailable-ssh"
mkdir -p "$unavailable_ssh_dir"
cat >"$unavailable_ssh_dir/ssh" <<'EOF'
#!/usr/bin/env bash
printf 'ssh failed for private-hostname-sentinel; public probes example.com dns.google remain public\n' >&2
exit 255
EOF
chmod +x "$unavailable_ssh_dir/ssh"
ssh_failure_output="$TMP/steamdeck-ssh-unavailable.out"
if PATH="$unavailable_ssh_dir:$PATH" \
    VPNKIT_TEST_SSH_TARGET=private-hostname-sentinel \
    VPNKIT_PRIVATE_HOSTNAME_SENTINEL=private-hostname-sentinel \
    VPNKIT_TEST_ENDPOINT=127.0.0.1 \
    VPNKIT_TEST_LAB_SECRETS_DIR="$TMP/steamdeck-ssh-unavailable-lab" \
    VPNKIT_TEST_PROFILE="$TMP/steamdeck-ssh-unavailable-lab/test-client.ovpn" \
    VPNKIT_CONTAINERS_TEST_LOG="$TMP/steamdeck-ssh-unavailable.log" \
    "$ROOT/test/containers-test.sh" --scenario steamdeck-host --action test \
    >"$ssh_failure_output" 2>&1; then
  fail 'steamdeck-host accepted unavailable SSH prerequisite'
fi
grep -Fq 'FAIL server:ssh-reachable' "$ssh_failure_output" || fail 'steamdeck-host did not fail SSH readiness'
! grep -Fq 'SKIP server:ssh-reachable' "$ssh_failure_output" || fail 'steamdeck-host softened SSH failure to SKIP'
! grep -Fq 'private-hostname-sentinel' "$ssh_failure_output" || fail 'console leaked configured private SSH hostname'
! grep -Fq 'private-hostname-sentinel' "$TMP/steamdeck-ssh-unavailable.log" || fail 'log leaked configured private SSH hostname'
grep -Fq 'example.com' "$ssh_failure_output" || fail 'console needlessly redacted public probe hostname'
grep -Fq 'example.com' "$TMP/steamdeck-ssh-unavailable.log" || fail 'log needlessly redacted public probe hostname'

# A reachable SSH transport with no configured remote runtime is also a
# required failure, not a green container-running SKIP.
runtime_unavailable_dir="$TMP/runtime-unavailable"
mkdir -p "$runtime_unavailable_dir"
cat >"$runtime_unavailable_dir/ssh" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *' command -v '*) printf 'remote runtime missing on private-runtime-host\n' >&2; exit 127 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$runtime_unavailable_dir/ssh"
runtime_failure_output="$TMP/steamdeck-runtime-unavailable.out"
if PATH="$runtime_unavailable_dir:$PATH" \
    VPNKIT_TEST_SSH_TARGET=private-runtime-host \
    VPNKIT_TEST_ENDPOINT=127.0.0.1 \
    VPNKIT_TEST_LAB_SECRETS_DIR="$TMP/steamdeck-runtime-unavailable-lab" \
    VPNKIT_TEST_PROFILE="$TMP/steamdeck-runtime-unavailable-lab/test-client.ovpn" \
    VPNKIT_CONTAINERS_TEST_LOG="$TMP/steamdeck-runtime-unavailable.log" \
    "$ROOT/test/containers-test.sh" --scenario steamdeck-host --action test \
    >"$runtime_failure_output" 2>&1; then
  fail 'steamdeck-host accepted missing remote runtime'
fi
grep -Fq 'PASS server:ssh-reachable' "$runtime_failure_output" || fail 'steamdeck runtime test did not preserve SSH readiness evidence'
grep -Fq 'FAIL server:runtime-reachable' "$runtime_failure_output" || fail 'steamdeck runtime failure was not recorded'
! grep -Fq 'SKIP server:runtime-reachable' "$runtime_failure_output" || fail 'steamdeck runtime failure was softened to SKIP'
! grep -Fq 'private-runtime-host' "$runtime_failure_output" || fail 'console leaked private runtime hostname'
! grep -Fq 'private-runtime-host' "$TMP/steamdeck-runtime-unavailable.log" || fail 'log leaked private runtime hostname'

# Unrelated Compose projects are deliberately outside this runner's cleanup
# scope. The mock exposes a foreign owner-labelled resource only if the code
# regresses to a global owner scan; the expected result is a bounded down of
# this project's (empty) resource set.
mock_docker_dir="$TMP/mock-docker"
mkdir -p "$mock_docker_dir"
cat >"$mock_docker_dir/docker" <<'EOF'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >>"$MOCK_DOCKER_LOG"
case "${1:-}" in
  container|network|volume)
    if [[ "${2:-}" == ls ]]; then
      if [[ "$*" == *'label=com.vpnkit.local.owner'* ]]; then
        printf 'unrelated-resource\n'
      fi
      exit 0
    fi
    ;;
  inspect)
    # No target or exact-name resource is returned by the ls mocks above.
    exit 0
    ;;
  compose)
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$mock_docker_dir/docker"
: >"$TMP/mock-docker.log"
if ! PATH="$mock_docker_dir:$PATH" MOCK_DOCKER_LOG="$TMP/mock-docker.log" \
    VPNKIT_CONTAINERS_TEST_LOG="$TMP/collision-runner.log" \
    "$ROOT/test/containers-test.sh" --scenario local-docker --action down \
    >"$TMP/collision-runner.out" 2>&1; then
  fail 'runner rejected an unrelated Compose project resource'
fi
grep -Eq '^compose .*down' "$TMP/mock-docker.log" || fail 'runner did not perform bounded cleanup for its empty project'

# REV-003/R2-002: keep a resource fully owned through the initial preflight,
# then inject the same-project/same-owner/same-workdir container with an
# unexpected name across an external interval.  The mock is deliberately
# stateful so a one-time preflight cannot make the later mutation safe.
stateful_docker_dir="$TMP/stateful-docker"
mkdir -p "$stateful_docker_dir"
cat >"$stateful_docker_dir/docker" <<'EOF'
#!/usr/bin/env bash
set -u
state_file=${MOCK_DOCKER_STATE:?}
log_file=${MOCK_DOCKER_LOG:?}
mode=${MOCK_DOCKER_MODE:?}
lab_dir=${MOCK_LAB_DIR:?}
phase=$(<"$state_file")
joined="$*"

printf 'CALL phase=%s %s\n' "$phase" "$joined" >>"$log_file"
set_phase() {
  local next=$1
  printf '%s\n' "$next" >"$state_file"
  printf 'INJECT %s\n' "$next" >>"$log_file"
  phase=$next
}

# Fixture setup/render is outside Docker.  The first Docker ownership query
# after the rendered fixture appears is therefore the post-setup boundary.
if [[ "$mode" == up && "$phase" == initial && -s "$lab_dir/rendered/sing-box/config.json" ]]; then
  set_phase up-injected
fi

current_server_id=${MOCK_STATEFUL_CONTAINER_ID:-owned-container-id}
current_server_name=vpnkit-local-lab-vpnkit-1
current_server_image=${MOCK_STATEFUL_IMAGE:-sha256:stateful-image}
case "$phase" in
  *injected)
    current_server_id=wrong-container-id
    current_server_name=vpnkit-local-lab-not-the-vpnkit-service
    ;;
esac
network_state="${state_file}.network"
client_state="${state_file}.client"

if [[ "${1:-}" == container && "${2:-}" == ls ]]; then
  if [[ "$joined" == *'label=com.docker.compose.project=vpnkit-local-lab'* ]]; then
    [[ "$phase" == initial ]] && printf 'INITIAL_OWNED_PRECHECK\n' >>"$log_file"
    printf '%s\n' "$current_server_id"
  elif [[ -e "$client_state" ]]; then
    printf 'client-container-id\n'
  fi
  exit 0
fi
if [[ "${1:-}" == network && "${2:-}" == ls ]]; then
  if [[ -e "$network_state" && "$joined" == *'label=com.docker.compose.project=vpnkit-local-lab'* ]]; then
    printf 'client-network-id\n'
  elif [[ -e "$network_state" && "$joined" == *'name=^vpnkit-local-lab-client-smoke$'* ]]; then
    printf 'client-network-id\n'
  fi
  exit 0
fi
if [[ "${1:-}" == volume && "${2:-}" == ls ]]; then
  exit 0
fi

if [[ "${1:-}" == container && "${2:-}" == inspect ]]; then
  if [[ -e "$client_state" ]]; then
    printf 'client-container-id\n'
    exit 0
  fi
  exit 1
fi
if [[ "${1:-}" == network && "${2:-}" == inspect ]]; then
  if [[ -e "$network_state" ]]; then
    printf 'client-network-id\n'
    exit 0
  fi
  exit 1
fi

if [[ "${1:-}" == inspect ]]; then
  id=${!#}
  if [[ "$joined" == *'State.Running'* ]]; then
    printf 'true\n'
  elif [[ "$joined" == *'State.Health'* ]]; then
    printf 'healthy\n'
  elif [[ "$joined" == *'{{.Id}}'* ]]; then
    printf '%s\n' "$current_server_id"
  elif [[ "$joined" == *'{{.Image}}'* ]]; then
    printf '%s\n' "$current_server_image"
  elif [[ "$joined" == *'{{.Name}}'* ]]; then
    if [[ "$id" == client-network-id ]]; then
      printf 'vpnkit-local-lab-client-smoke\n'
    elif [[ "$id" == client-container-id ]]; then
      printf 'vpnkit-local-lab-client-smoke\n'
    else
      printf '/%s\n' "$current_server_name"
    fi
  elif [[ "$joined" == *'com.docker.compose.project.working_dir'* ]]; then
    printf '%s\n' "$MOCK_WORKDIR"
  elif [[ "$joined" == *'com.vpnkit.local.resource'* ]]; then
    printf 'client-smoke\n'
  elif [[ "$joined" == *'com.vpnkit.local.owner'* ]]; then
    printf 'containers-test\n'
  elif [[ "$joined" == *'com.docker.compose.project'* ]]; then
    printf 'vpnkit-local-lab\n'
  elif [[ "$joined" == *'com.docker.compose.network'* || "$joined" == *'com.docker.compose.volume'* ]]; then
    printf '<no value>\n'
  fi
  exit 0
fi

if [[ "${1:-}" == image && "${2:-}" == inspect ]]; then
  [[ "${MOCK_STATEFUL_IMAGE_MISSING:-0}" != 1 ]] || exit 1
  exit 0
fi

if [[ "${1:-}" == network && "${2:-}" == create ]]; then
  : >"$network_state"
  printf 'NETWORK_CREATE\n' >>"$log_file"
  exit 0
fi
if [[ "${1:-}" == network && "${2:-}" == connect ]]; then
  printf 'NETWORK_CONNECT\n' >>"$log_file"
  if [[ "$mode" == client && "$phase" == initial ]]; then
    set_phase client-injected
  fi
  exit 0
fi
if [[ "${1:-}" == network && "${2:-}" == disconnect ]]; then
  printf 'NETWORK_DISCONNECT\n' >>"$log_file"
  exit 0
fi
if [[ "${1:-}" == network && "${2:-}" == rm ]]; then
  printf 'NETWORK_RM\n' >>"$log_file"
  rm -f "$network_state"
  exit 0
fi
if [[ "${1:-}" == rm ]]; then
  printf 'DOCKER_RM\n' >>"$log_file"
  rm -f "$client_state"
  exit 0
fi
if [[ "${1:-}" == exec ]]; then
  case "$phase" in
    *injected) printf 'EXEC_AFTER_INJECT\n' >>"$log_file" ;;
    *) printf 'EXEC_INITIAL\n' >>"$log_file" ;;
  esac
  printf 'openvpn sing-box tun0 sb-tun0 selected-native-out direct-out block-out tun socks remote-dns remote-dns-fallback 1.1.1.1 8.8.8.8\n'
  exit 0
fi
if [[ "${1:-}" == run ]]; then
  printf 'DOCKER_RUN\n' >>"$log_file"
  if [[ "$mode" == cycle ]]; then
    printf '%s\n' \
      'PASS openvpn:tun0' 'PASS route:via-tun0' 'PASS udp:google-dns' \
      'PASS https:hostname' 'PASS https:literal-ip' 'PASS icmp:1.1.1.1' \
      'PASS icmp:8.8.8.8' 'PASS ipv6:no-default-route' \
      'PASS ipv6:connectivity-fail-closed' 'PASS ipv6:icmp-fail-closed'
  fi
  exit 0
fi
if [[ "${1:-}" == compose ]]; then
  case "$joined" in
    *' config --images'*) printf 'vpnkit-local-lab-ovpn-client-test\n' ;;
    *' config --format json'*) printf '%s\n' '{"services":{"vpnkit":{"image":"vpnkit-local-lab-vpnkit"}}}' ;;
    *' ps -q vpnkit'*) printf '%s\n' "$current_server_id" ;;
    *' up '*) printf 'COMPOSE_UP\n' >>"$log_file" ;;
    *' build '*) printf 'COMPOSE_BUILD\n' >>"$log_file" ;;
    *' down '*) printf 'COMPOSE_DOWN\n' >>"$log_file" ;;
  esac
  exit 0
fi

exit 0
EOF
chmod +x "$stateful_docker_dir/docker"

write_stateful_provenance() {
  local lab_dir=$1 source_digest config_digest provenance_digest
  source_digest=$(python3 - "$ROOT" <<'PY'
import hashlib
import pathlib
import stat
import subprocess
import sys
root = pathlib.Path(sys.argv[1]).resolve()
raw = subprocess.check_output(["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"])
h = hashlib.sha256()
for raw_name in sorted(raw.split(b"\0")):
    if not raw_name:
        continue
    name = raw_name.decode()
    if name == "secrets" or name.startswith("secrets/") or name == "logs" or name.startswith("logs/"):
        continue
    path = root / name
    try:
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
            continue
        payload = path.read_bytes()
    except OSError:
        continue
    h.update(b"path\0" + raw_name + b"\0bytes\0" + payload)
print(h.hexdigest())
PY
)
  config_digest=$(printf '%s\n' '{"services":{"vpnkit":{"image":"vpnkit-local-lab-vpnkit"}}}' | sha256sum | awk '{print $1}')
  provenance_digest=$(printf 'schema=1\nproject=vpnkit-local-lab\nsource=%s\nconfig=%s\n' "$source_digest" "$config_digest" | sha256sum | awk '{print $1}')
  mkdir -p "$lab_dir"
  chmod 700 "$lab_dir"
  cat >"$lab_dir/.containers-test-provenance" <<EOF
schema=1
project=vpnkit-local-lab
source_digest=$source_digest
config_digest=$config_digest
provenance_digest=$provenance_digest
image_id=sha256:stateful-image
container_id=owned-container-id
EOF
  chmod 600 "$lab_dir/.containers-test-provenance"
}

run_stateful_runner() {
  local mode=$1 lab_dir=$2 log_file=$3 output=$4 state_file="$5" action=${6:-}
  [[ -n "$action" ]] || action=$([[ "$mode" == up ]] && printf up || printf test)
  if [[ "$mode" == client ]]; then
    write_stateful_provenance "$lab_dir"
  fi
  PATH="$stateful_docker_dir:$PATH" \
    MOCK_DOCKER_MODE="$mode" MOCK_DOCKER_STATE="$state_file" MOCK_DOCKER_LOG="$log_file" MOCK_LAB_DIR="$lab_dir" MOCK_WORKDIR="$ROOT" \
    VPNKIT_TEST_LAB_SECRETS_DIR="$lab_dir" VPNKIT_CONTAINERS_TEST_LOG="$TMP/$(basename "$log_file").runner.log" \
    "$ROOT/test/containers-test.sh" --scenario local-docker --action "$action" \
    >"$output" 2>&1
}

up_lab="$TMP/stateful-up-lab"
up_log="$TMP/stateful-up-docker.log"
up_state="$TMP/stateful-up.state"
printf 'initial\n' >"$up_state"
: >"$up_log"
if run_stateful_runner up "$up_lab" "$up_log" "$TMP/stateful-up.out" "$up_state"; then
  fail 'runner accepted a post-render same-label wrong-name container before Compose up'
fi
grep -Fqx 'INJECT up-injected' "$up_log" || fail 'up mock did not inject after fixture setup/render'
grep -Fq 'INITIAL_OWNED_PRECHECK' "$up_log" || fail 'up mock did not prove initial ownership preflight'
! grep -Fqx 'COMPOSE_UP' "$up_log" || fail 'runner invoked Compose up after the post-render ownership failure'
! grep -Fqx 'COMPOSE_BUILD' "$up_log" || fail 'runner invoked a build after the post-render ownership failure'
! grep -Fqx 'DOCKER_RUN' "$up_log" || fail 'runner invoked docker run after the post-render ownership failure'
! grep -Fqx 'EXEC_AFTER_INJECT' "$up_log" || fail 'runner executed after the post-render ownership failure'
! grep -Fqx 'COMPOSE_DOWN' "$up_log" || fail 'runner invoked Compose down after the post-render ownership failure'
grep -Fq 'FAIL lifecycle:up-safety' "$TMP/stateful-up.out" || fail 'post-render ownership failure was not a hard lifecycle FAIL'
[[ ! -e "$up_lab/.containers-test-provenance" ]] || fail 'failed local-docker up published a provenance record'

client_lab="$TMP/stateful-client-lab"
mkdir -p "$client_lab/openvpn/client"
printf '%s\n' 'client' 'dev tun' 'proto udp' 'remote vpnkit 1194' >"$client_lab/openvpn/client/test-client.ovpn"
chmod 600 "$client_lab/openvpn/client/test-client.ovpn"
client_log="$TMP/stateful-client-docker.log"
client_state="$TMP/stateful-client.state"
printf 'initial\n' >"$client_state"
: >"$client_log"
if run_stateful_runner client "$client_lab" "$client_log" "$TMP/stateful-client.out" "$client_state"; then
  fail 'runner accepted a post-preparation same-label wrong-name container before client-image build'
fi
grep -Fq 'INITIAL_OWNED_PRECHECK' "$client_log" || fail 'client mock did not prove initial ownership preflight'
grep -Fqx 'NETWORK_CREATE' "$client_log" || fail 'client mock did not observe the isolated network create'
grep -Fqx 'NETWORK_CONNECT' "$client_log" || fail 'client mock did not observe the isolated network connect'
grep -Fqx 'INJECT client-injected' "$client_log" || fail 'client mock did not inject after client preparation'
! grep -Fqx 'COMPOSE_UP' "$client_log" || fail 'runner invoked Compose up in the client TOCTOU case'
! grep -Fqx 'COMPOSE_BUILD' "$client_log" || fail 'runner built the client image after the ownership failure'
! grep -Fqx 'DOCKER_RUN' "$client_log" || fail 'runner invoked docker run after the ownership failure'
! grep -Fqx 'EXEC_AFTER_INJECT' "$client_log" || fail 'runner executed after the client ownership failure'
! grep -Fqx 'COMPOSE_DOWN' "$client_log" || fail 'runner invoked Compose down after the client ownership failure'
grep -Fq 'FAIL client:local-docker-cleanup-safety' "$TMP/stateful-client.out" || fail 'client ownership failure was not a hard safety FAIL'
grep -Fq 'PASS lifecycle:test-freshness' "$TMP/stateful-client.out" || fail 'client TOCTOU fixture did not first prove deployment freshness'

# REV-004: standalone local-docker test refuses missing, altered, and stale
# deployment evidence before it can create a client network or run a client.
run_seeded_stateful_test() {
  local mode=$1 lab_dir=$2 log_file=$3 output=$4 state_file=$5
  PATH="$stateful_docker_dir:$PATH" \
    MOCK_DOCKER_MODE="$mode" MOCK_DOCKER_STATE="$state_file" MOCK_DOCKER_LOG="$log_file" MOCK_LAB_DIR="$lab_dir" MOCK_WORKDIR="$ROOT" \
    VPNKIT_TEST_LAB_SECRETS_DIR="$lab_dir" VPNKIT_CONTAINERS_TEST_LOG="$TMP/$(basename "$log_file").runner.log" \
    "$ROOT/test/containers-test.sh" --scenario local-docker --action test \
    >"$output" 2>&1
}

missing_lab="$TMP/stateful-missing-lab"
mkdir -p "$missing_lab/openvpn/client"
printf '%s\n' client dev tun proto udp 'remote vpnkit 1194' >"$missing_lab/openvpn/client/test-client.ovpn"
chmod 600 "$missing_lab/openvpn/client/test-client.ovpn"
printf 'initial\n' >"$TMP/stateful-missing.state"
: >"$TMP/stateful-missing-docker.log"
if run_seeded_stateful_test missing "$missing_lab" "$TMP/stateful-missing-docker.log" "$TMP/stateful-missing.out" "$TMP/stateful-missing.state"; then
  fail 'standalone local-docker test accepted missing provenance'
fi
grep -Fq 'FAIL lifecycle:test-freshness' "$TMP/stateful-missing.out" || fail 'missing provenance was not a freshness failure'
! grep -Fqx 'NETWORK_CREATE' "$TMP/stateful-missing-docker.log" || fail 'missing provenance allowed client network mutation'

stale_lab="$TMP/stateful-stale-lab"
mkdir -p "$stale_lab/openvpn/client"
printf '%s\n' client dev tun proto udp 'remote vpnkit 1194' >"$stale_lab/openvpn/client/test-client.ovpn"
chmod 600 "$stale_lab/openvpn/client/test-client.ovpn"
write_stateful_provenance "$stale_lab"
printf 'initial\n' >"$TMP/stateful-stale.state"
: >"$TMP/stateful-stale-docker.log"
if MOCK_STATEFUL_CONTAINER_ID=stale-container MOCK_STATEFUL_IMAGE=sha256:stale-image \
    run_seeded_stateful_test stale "$stale_lab" "$TMP/stateful-stale-docker.log" "$TMP/stateful-stale.out" "$TMP/stateful-stale.state"; then
  fail 'standalone local-docker test accepted stale image/container identity'
fi
grep -Fq 'deployed image or container identity is stale' "$TMP/stateful-stale.out" || fail 'stale image/container identity was not reported'
! grep -Fqx 'NETWORK_CREATE' "$TMP/stateful-stale-docker.log" || fail 'stale image/container evidence allowed client network mutation'

config_lab="$TMP/stateful-config-lab"
mkdir -p "$config_lab/openvpn/client"
printf '%s\n' client dev tun proto udp 'remote vpnkit 1194' >"$config_lab/openvpn/client/test-client.ovpn"
chmod 600 "$config_lab/openvpn/client/test-client.ovpn"
write_stateful_provenance "$config_lab"
sed -i 's/^config_digest=.*/config_digest=0000000000000000000000000000000000000000000000000000000000000000/' "$config_lab/.containers-test-provenance"
printf 'initial\n' >"$TMP/stateful-config.state"
: >"$TMP/stateful-config-docker.log"
if run_seeded_stateful_test config "$config_lab" "$TMP/stateful-config-docker.log" "$TMP/stateful-config.out" "$TMP/stateful-config.state"; then
  fail 'standalone local-docker test accepted altered Compose provenance'
fi
grep -Fq 'source or Compose config changed since the recorded deployment' "$TMP/stateful-config.out" || fail 'altered Compose provenance was not reported'
! grep -Fqx 'NETWORK_CREATE' "$TMP/stateful-config-docker.log" || fail 'altered Compose provenance allowed client network mutation'

# A successful down/up/test cycle still publishes and consumes the same
# freshness record; freshness is a gate, not a reason to make cycle fail.
cycle_lab="$TMP/stateful-cycle-lab"
cycle_log="$TMP/stateful-cycle-docker.log"
cycle_state="$TMP/stateful-cycle.state"
printf 'initial\n' >"$cycle_state"
: >"$cycle_log"
if ! run_stateful_runner cycle "$cycle_lab" "$cycle_log" "$TMP/stateful-cycle.out" "$cycle_state" cycle; then
  cat "$TMP/stateful-cycle.out" >&2
  fail 'successful local-docker cycle was rejected by freshness evidence'
fi
grep -Fq 'PASS lifecycle:provenance' "$TMP/stateful-cycle.out" || fail 'cycle did not persist provenance after successful up/build'
grep -Fq 'PASS lifecycle:test-freshness' "$TMP/stateful-cycle.out" || fail 'cycle did not consume fresh provenance'
[[ -f "$cycle_lab/.containers-test-provenance" ]] || fail 'cycle did not leave a private provenance record'
[[ "$(stat -c '%a' "$cycle_lab/.containers-test-provenance")" == 600 ]] || fail 'cycle provenance record is not private'

if VPNKIT_LOCAL_SECRETS_DIR="$ROOT/secrets/vps" VPNKIT_LOCAL_ALLOW_MISSING_SUBSCRIPTION=true \
    VPNKIT_RULESET_SOURCE_MODE=local-fixture \
    "$ROOT/scripts/vpnkit/vpnkit-render-local-kde-configs.sh" \
    >"$TMP/renderer-reject.out" 2>&1; then
  fail 'local renderer accepted the production secrets root'
fi

local_render_base="$TMP/local-render"
VPNKIT_LOCAL_TEST_FIXTURE=1 VPNKIT_LOCAL_SECRETS_DIR="$local_render_base" VPNKIT_LOCAL_ALLOW_MISSING_SUBSCRIPTION=true \
  VPNKIT_RULESET_SOURCE_MODE=local-fixture \
  "$ROOT/scripts/vpnkit/vpnkit-render-local-kde-configs.sh" >"$TMP/local-render.out"
python3 - "$local_render_base/rendered/sing-box/config.json" <<'PY'
import json
import pathlib
import sys

cfg = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
servers = {entry['tag']: entry for entry in cfg['dns']['servers']}
assert cfg['dns']['final'] == 'remote-dns'
assert servers['remote-dns']['type'] == 'https'
assert servers['remote-dns']['server'] == '1.1.1.1'
assert servers['remote-dns']['tls']['server_name'] == 'cloudflare-dns.com'
assert servers['remote-dns-fallback']['type'] == 'https'
assert servers['remote-dns-fallback']['server'] == '8.8.8.8'
assert servers['remote-dns-fallback']['tls']['server_name'] == 'dns.google'
PY

watch_root="$TMP/watchdog"
mkdir -p "$watch_root/bin" "$watch_root/runtime" "$watch_root/state" "$watch_root/run"
cat >"$watch_root/runtime/config.json" <<'JSON'
{
  "dns": {
    "servers": [
      {"tag": "remote-dns"},
      {"tag": "remote-dns-fallback"}
    ],
    "final": "remote-dns"
  }
}
JSON
cat >"$watch_root/bin/sing-box" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == check && "${2:-}" == -c && -s "${3:-}" ]] || exit 2
[[ "${MOCK_SING_BOX_FAIL:-0}" != 1 ]] || exit 1
grep -Eq '"final"[[:space:]]*:[[:space:]]*"remote-dns(-fallback)?"' "$3"
printf '%s\n' "$3" >>"$MOCK_SING_BOX_LOG"
EOF
chmod +x "$watch_root/bin/sing-box"
watch_env=(
  "VPNKIT_DNS_FAILOVER_STATE_DIR=$watch_root/state"
  "VPNKIT_DNS_FAILOVER_RUNTIME=$watch_root/runtime/config.json"
  "VPNKIT_DNS_FAILOVER_RESTART_FILE=$watch_root/run/restart-sing-box"
  "VPNKIT_DNS_FAILOVER_SING_BOX_BIN=$watch_root/bin/sing-box"
  "MOCK_SING_BOX_LOG=$watch_root/sing-box-check.log"
)
flock -x "$watch_root/state/.vibe-vpn.lock" -c 'sleep 1' &
lock_holder=$!
sleep 0.1
if env "${watch_env[@]}" VPNKIT_DNS_FAILOVER_LOCK_WAIT_SECONDS=0 \
    "$ROOT/docker/vpnkit/dns-failover-watchdog.sh" --once --target remote-dns-fallback; then
  fail 'watchdog changed runtime while the shared state lock was held'
fi
wait "$lock_holder"
grep -Eq '"final"[[:space:]]*:[[:space:]]*"remote-dns"' "$watch_root/runtime/config.json" || fail 'watchdog lock mock did not leave primary DNS active'
env "${watch_env[@]}" "$ROOT/docker/vpnkit/dns-failover-watchdog.sh" --once --target remote-dns-fallback >"$TMP/watchdog.out"
grep -Eq '"final"[[:space:]]*:[[:space:]]*"remote-dns-fallback"' "$watch_root/runtime/config.json" || fail 'watchdog did not switch to the fallback'
[[ -s "$watch_root/run/restart-sing-box" ]] || fail 'watchdog wrote an empty restart token'
check_path=$(head -n 1 "$watch_root/sing-box-check.log")
[[ "$check_path" == "$watch_root/runtime/"* ]] || fail 'sing-box was not asked to validate a same-directory candidate'
! compgen -G "$watch_root/runtime/.config.json.dns-failover.*" >/dev/null || fail 'watchdog left a runtime candidate behind'

cat >"$watch_root/runtime/config.json" <<'JSON'
{
  "dns": {
    "servers": [
      {"tag": "remote-dns"},
      {"tag": "remote-dns-fallback"}
    ],
    "final": "remote-dns"
  }
}
JSON
rm -f "$watch_root/run/restart-sing-box"
if env "${watch_env[@]}" MOCK_SING_BOX_FAIL=1 \
    "$ROOT/docker/vpnkit/dns-failover-watchdog.sh" --once --target remote-dns-fallback; then
  fail 'watchdog accepted an invalid sing-box candidate'
fi
grep -Eq '"final"[[:space:]]*:[[:space:]]*"remote-dns"' "$watch_root/runtime/config.json" || fail 'invalid candidate replaced the live runtime'
[[ ! -e "$watch_root/run/restart-sing-box" ]] || fail 'invalid candidate emitted a restart token'

# The watchdog must notice a dead main PID even when no DNS runtime is
# available; this is the direct liveness half of the Compose supervisor.
sleep 30 &
watch_main_pid=$!
env VPNKIT_DNS_FAILOVER_RUNTIME="$watch_root/runtime/missing.json" \
    VPNKIT_DNS_FAILOVER_STATE_DIR="$watch_root/state" \
    VPNKIT_DNS_FAILOVER_INTERVAL_SECONDS=1 \
    timeout -k 1s 5s "$ROOT/docker/vpnkit/dns-failover-watchdog.sh" --pid "$watch_main_pid" \
    >"$TMP/watchdog-liveness.out" 2>&1 &
watchdog_liveness_pid=$!
sleep 0.2
kill "$watch_main_pid" 2>/dev/null || true
wait "$watch_main_pid" 2>/dev/null || true
if wait "$watchdog_liveness_pid"; then
  watchdog_liveness_rc=0
else
  watchdog_liveness_rc=$?
fi
[[ "$watchdog_liveness_rc" -ne 0 && "$watchdog_liveness_rc" -ne 124 ]] || fail 'watchdog did not fail promptly after its main PID exited'
grep -Fq 'no longer alive' "$TMP/watchdog-liveness.out" || fail 'watchdog liveness failure was not reported'

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  env -u VPNKIT_OPENVPN_PORT -u VPNKIT_OPENVPN_BIND_ADDRESS \
      -u VPNKIT_LOCAL_OPENVPN_PORT -u VPNKIT_LOCAL_SECRETS_DIR \
      -u VPNKIT_LOCAL_RESOURCE_OWNER \
      docker compose -p issue40-review-default -f "$ROOT/docker-compose.yml" \
      -f "$ROOT/compose.local.yaml" config --format json >"$TMP/compose-default.json"
  env -u VPNKIT_OPENVPN_PORT -u VPNKIT_OPENVPN_BIND_ADDRESS \
      -u VPNKIT_LOCAL_OPENVPN_PORT -u VPNKIT_LOCAL_SECRETS_DIR \
      VPNKIT_LOCAL_RESOURCE_OWNER=containers-test \
      docker compose -p issue40-review-check -f "$ROOT/docker-compose.yml" \
      -f "$ROOT/compose.local.yaml" config --format json >"$TMP/compose.json"

  supervisor_script="$TMP/compose-supervisor.sh"
  fake_main="$TMP/fake-main.sh"
  fake_watch="$TMP/fake-watch.sh"
  cat >"$fake_main" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$$" >"$FAKE_MAIN_PID_FILE"
case "${FAKE_MAIN_MODE:-hold}" in
  exit) exit 23 ;;
  clean) exit 0 ;;
  hold)
    sleep 60 &
    child_pid=$!
    printf '%s\n' "$child_pid" >"$FAKE_MAIN_CHILD_PID_FILE"
    trap 'kill "$child_pid" 2>/dev/null || true; wait "$child_pid" 2>/dev/null || true; exit 0' INT TERM
    wait "$child_pid"
    ;;
  *) exit 24 ;;
esac
EOF
  cat >"$fake_watch" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
main_pid=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pid) main_pid=${2:?missing PID}; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$main_pid" ]] || exit 25
[[ "${FAKE_WATCH_MODE:-hold}" == exit ]] && exit 31
trap 'exit 0' INT TERM
while kill -0 "$main_pid" 2>/dev/null; do sleep 0.1; done
exit 0
EOF
  chmod +x "$fake_main" "$fake_watch"
  python3 - "$TMP/compose.json" "$supervisor_script" "$fake_main" "$fake_watch" "$TMP/compose-default.json" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
service = data['services']['vpnkit']
default_data = json.loads(pathlib.Path(sys.argv[5]).read_text(encoding='utf-8'))
assert default_data['services']['vpnkit']['labels']['com.vpnkit.local.owner'] == 'local-lifecycle'

ports = service['ports']
assert len(ports) == 1, ports
assert ports[0]['host_ip'] == '127.0.0.1', ports
assert ports[0]['target'] == 1194, ports
assert service['labels']['com.vpnkit.local.owner'] == 'containers-test'
for volume in service['volumes']:
    if volume['target'] in ('/var/log/vpnkit', '/var/log/vibe-vpn'):
        assert not volume['source'].startswith('.'), volume

command = service['command']
if isinstance(command, list):
    assert len(command) == 1, command
    command = command[0]
assert isinstance(command, str)
assert '$$' in command, 'Compose supervisor command does not use escaped dollar expansion'
command = command.replace('$$', '$')
for marker in ('main_pid=$!', 'watch_pid=$!', 'wait -n "$main_pid" "$watch_pid"', 'setsid '):
    assert marker in command, marker
command = command.replace('/usr/local/bin/entrypoint.sh', sys.argv[3])
command = command.replace('/usr/local/bin/dns-failover-watchdog.sh', sys.argv[4])
pathlib.Path(sys.argv[2]).write_text('#!/usr/bin/env bash\n' + command + '\n', encoding='utf-8')
PY
  chmod +x "$supervisor_script"

  run_supervisor_failure_case() {
    local name=$1 main_mode=$2 watch_mode=$3 pid_file="$TMP/$1-main.pid" child_pid_file="$TMP/$1-child.pid" output="$TMP/$1.out" rc main_pid child_pid
    rm -f "$pid_file" "$child_pid_file"
    if FAKE_MAIN_MODE="$main_mode" FAKE_WATCH_MODE="$watch_mode" FAKE_MAIN_PID_FILE="$pid_file" FAKE_MAIN_CHILD_PID_FILE="$child_pid_file" \
        timeout -k 1s 8s bash "$supervisor_script" >"$output" 2>&1; then
      rc=0
    else
      rc=$?
    fi
    [[ "$rc" -ne 0 ]] || fail "Compose supervisor accepted $name child failure"
    [[ "$rc" -ne 124 ]] || fail "Compose supervisor hung during $name child failure"
    if [[ -s "$pid_file" ]]; then
      main_pid=$(<"$pid_file")
      ! kill -0 "$main_pid" 2>/dev/null || fail "Compose supervisor left $name main process alive"
    fi
    if [[ -s "$child_pid_file" ]]; then
      child_pid=$(<"$child_pid_file")
      ! kill -0 "$child_pid" 2>/dev/null || fail "Compose supervisor left $name descendant alive"
    fi
  }
  run_supervisor_failure_case main-exit exit hold
  run_supervisor_failure_case main-clean-exit clean hold
  run_supervisor_failure_case watchdog-exit hold exit
else
  printf 'SKIP docker Compose config/supervisor check: Docker Compose unavailable\n'
fi

printf 'issue-40 review-fix tests passed\n'
