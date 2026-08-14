#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/vpnkit-issue40-review.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

bash -n "$ROOT/test/containers-test.sh" \
  "$ROOT/docker/ovpn-client-test/run-tests.sh" \
  "$ROOT/scripts/vpnkit/vpnkit-render-local-kde-configs.sh" \
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

# Mock a lifecycle-owned stack under a different project.  The runner must
# reject before invoking `down -v --remove-orphans`; a Compose implementation
# that ignores the preflight would make this test fail via the logged command.
mock_docker_dir="$TMP/mock-docker"
mkdir -p "$mock_docker_dir"
cat >"$mock_docker_dir/docker" <<'EOF'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >>"$MOCK_DOCKER_LOG"
case "${1:-}" in
  container)
    [[ "${2:-}" == ls ]] && exit 0
    ;;
  network)
    if [[ "${2:-}" == ls ]]; then
      printf 'foreign-network\n'
      exit 0
    fi
    ;;
  volume)
    [[ "${2:-}" == ls ]] && exit 0
    ;;
  inspect)
    joined="$*"
    case "$joined" in
      *'com.docker.compose.project'*) printf 'vpnkit-local\n' ;;
      *'com.vpnkit.local.owner'*) printf 'local-lifecycle\n' ;;
      *'com.docker.compose.network'*) printf 'vpnkit-local\n' ;;
      *'{{.Name}}'*) printf 'vpnkit-local_vpnkit-local\n' ;;
    esac
    exit 0
    ;;
  compose)
    # This is intentionally successful: the assertion below proves it was
    # never reached, rather than relying on a mocked failure status.
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$mock_docker_dir/docker"
: >"$TMP/mock-docker.log"
if PATH="$mock_docker_dir:$PATH" MOCK_DOCKER_LOG="$TMP/mock-docker.log" \
    VPNKIT_CONTAINERS_TEST_LOG="$TMP/collision-runner.log" \
    "$ROOT/test/containers-test.sh" --scenario local-docker --action down \
    >"$TMP/collision-runner.out" 2>&1; then
  fail 'runner accepted an alternate-project lifecycle collision'
fi
! grep -Eq '^compose .*down' "$TMP/mock-docker.log" || fail 'runner invoked destructive Compose cleanup after a collision'
grep -Fq 'alternate Compose project' "$TMP/collision-runner.out" || fail 'collision rejection did not identify the alternate project'

if VPNKIT_LOCAL_SECRETS_DIR="$ROOT/secrets/vps" VPNKIT_LOCAL_ALLOW_MISSING_SUBSCRIPTION=true \
    VPNKIT_RULESET_SOURCE_MODE=local-fixture \
    "$ROOT/scripts/vpnkit/vpnkit-render-local-kde-configs.sh" \
    >"$TMP/renderer-reject.out" 2>&1; then
  fail 'local renderer accepted the production secrets root'
fi

local_render_base="$TMP/local-render"
VPNKIT_LOCAL_SECRETS_DIR="$local_render_base" VPNKIT_LOCAL_ALLOW_MISSING_SUBSCRIPTION=true \
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
