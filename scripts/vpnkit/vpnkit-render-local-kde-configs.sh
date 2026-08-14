#!/usr/bin/env bash
# Render local CachyOS/KDE sing-box and vibe-vpn configs without printing secrets.
set -Eeuo pipefail
umask 077

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)
BASE=${VPNKIT_LOCAL_SECRETS_DIR:-secrets/vpnkit-local}
POLICY=${VPNKIT_LOCAL_POLICY:-strict}
RULESET_MODE=${VPNKIT_RULESET_SOURCE_MODE:-remote}
SELECTED_OUTBOUND_MODE=${VPNKIT_SELECTED_OUTBOUND_MODE:-subscription}
ALLOW_MISSING_SUBSCRIPTION=${VPNKIT_LOCAL_ALLOW_MISSING_SUBSCRIPTION:-false}
case "$BASE" in /*) ;; *) BASE="$REPO_ROOT/$BASE" ;; esac
BASE=$(realpath -m -- "$BASE")
case "$BASE" in
  "$REPO_ROOT/secrets/vpnkit-local"|"$REPO_ROOT/secrets/vpnkit-local/"*|\
  "$REPO_ROOT/secrets/vpnkit-labs/"*|/tmp/*|/var/tmp/*) ;;
  *)
    echo 'VPNKIT_LOCAL_SECRETS_DIR must stay in the local, isolated lab, or temporary tree' >&2
    exit 2
    ;;
esac
[[ "$BASE" != /tmp && "$BASE" != /var/tmp && "$BASE" != "$REPO_ROOT/secrets/vpnkit-labs" ]] || {
  echo 'VPNKIT_LOCAL_SECRETS_DIR is too broad' >&2
  exit 2
}
if [[ -e "$BASE" && ! -O "$BASE" ]]; then
  echo 'VPNKIT_LOCAL_SECRETS_DIR is not user-owned' >&2
  exit 2
fi
case "$POLICY" in strict|smart) ;; *) echo 'VPNKIT_LOCAL_POLICY must be strict or smart' >&2; exit 2 ;; esac
case "$RULESET_MODE" in remote|local-fixture) ;; *) echo 'VPNKIT_RULESET_SOURCE_MODE must be remote or local-fixture' >&2; exit 2 ;; esac
case "$SELECTED_OUTBOUND_MODE" in
  subscription) ;;
  direct-fixture)
    [[ "$RULESET_MODE" == local-fixture && "${VPNKIT_LOCAL_TEST_FIXTURE:-}" == 1 ]] || {
      echo 'direct-fixture outbound is restricted to explicit local test fixtures' >&2
      exit 2
    }
    ;;
  *) echo 'VPNKIT_SELECTED_OUTBOUND_MODE must be subscription or direct-fixture' >&2; exit 2 ;;
esac

SUBSCRIPTION="$BASE/vibe-vpn/sub_url"
case "${ALLOW_MISSING_SUBSCRIPTION,,}" in
  1|true|yes|on) ;;
  *) [[ -s "$SUBSCRIPTION" ]] || { echo 'local subscription file is missing or empty' >&2; exit 3; } ;;
esac

RENDERED="$BASE/rendered"
SINGBOX_DIR="$RENDERED/sing-box"
VIBE_DIR="$RENDERED/vibe-vpn"
mkdir -p "$SINGBOX_DIR/rule-sets" "$VIBE_DIR"
chmod 700 "$BASE" "$RENDERED" "$SINGBOX_DIR" "$SINGBOX_DIR/rule-sets" "$VIBE_DIR"

python3 - "$REPO_ROOT/config/sing-box/config.tun.json.template" "$SINGBOX_DIR/config.json" "$POLICY" "$RULESET_MODE" "$SELECTED_OUTBOUND_MODE" <<'PY'
import json
import pathlib
import sys

template_path, output_path, policy, ruleset_mode, selected_outbound_mode = sys.argv[1:]
# This placeholder is validated but never started in local real mode:
# entrypoint must replace it with a benchmarked subscription node before
# sing-box/OpenVPN. Disposable acceptance explicitly requests a direct outbound
# so it can test the server data path without private subscription material.
if selected_outbound_mode == "direct-fixture":
    bootstrap = {"type": "direct", "tag": "selected-native-out"}
else:
    bootstrap = {
        "type": "vless",
        "tag": "selected-native-out",
        "server": "192.0.2.1",
        "server_port": 443,
        "uuid": "00000000-0000-4000-8000-000000000000",
        "tls": {"enabled": True, "server_name": "bootstrap.example.invalid"},
    }
remote_sets = [
    {
        "type": "remote", "tag": "geoip-ru", "format": "binary",
        "url": "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geoip/geoip-ru.srs",
        "download_detour": "direct-out",
    },
    {
        "type": "remote", "tag": "geosite-category-ru", "format": "binary",
        "url": "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geosite/geosite-category-ru.srs",
        "download_detour": "direct-out",
    },
]
local_sets = [
    {"type": "local", "tag": "geoip-ru", "format": "source", "path": "/etc/sing-box/rule-sets/geoip-ru.json"},
    {"type": "local", "tag": "geosite-category-ru", "format": "source", "path": "/etc/sing-box/rule-sets/geosite-category-ru.json"},
]
sets = local_sets if ruleset_mode == "local-fixture" else remote_sets
text = pathlib.Path(template_path).read_text(encoding="utf-8")
text = text.replace("{{SELECTED_NATIVE_OUT_JSON}}", json.dumps(bootstrap, indent=4))
text = text.replace("{{RU_RULE_SETS_JSON}}", ",\n".join(json.dumps(item, indent=8) for item in sets))
config = json.loads(text)
# The shared TUN template keeps the production Google DNS contract (8.8.8.8
# primary, 8.8.4.4 fallback).  This local-only renderer intentionally replaces
# that contract with HTTPS probes through Cloudflare DoH (1.1.1.1) and Google
# DoH (8.8.8.8); the production template is never rewritten.
#
# sing-box 1.13 does not provide a DNS-server health selector. The local Compose
# watchdog probes these two tagged providers through the local SOCKS inbound and
# changes only dns.final in the persisted runtime config when the primary fails.
# Keep both tags concrete and keep the local primary as the default for cold
# start.
dns_servers = {server.get("tag"): server for server in config.get("dns", {}).get("servers", [])}
for tag in ("remote-dns", "remote-dns-fallback"):
    if tag not in dns_servers:
        raise SystemExit(f"sing-box template is missing required DNS server tag: {tag}")
dns_servers["remote-dns"].update({"type": "https", "server": "1.1.1.1", "server_port": 443, "path": "/dns-query", "tls": {"enabled": True, "server_name": "cloudflare-dns.com"}})
dns_servers["remote-dns-fallback"].update({"type": "https", "server": "8.8.8.8", "server_port": 443, "path": "/dns-query", "tls": {"enabled": True, "server_name": "dns.google"}})
if selected_outbound_mode == "direct-fixture":
    # sing-box rejects a DNS detour to an empty direct outbound as nonsensical.
    # Omitting detour has the same direct behavior in the disposable fixture;
    # real local mode keeps the selected subscription detour.
    dns_servers["remote-dns"].pop("detour", None)
    dns_servers["remote-dns-fallback"].pop("detour", None)
config["dns"]["final"] = "remote-dns"
if policy == "strict":
    route = config["route"]
    route["rules"] = [
        rule for rule in route.get("rules", [])
        if rule.get("protocol") == "dns" or rule.get("action") == "sniff"
    ]
    route["rule_set"] = []
pathlib.Path(output_path).write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
PY
chmod 600 "$SINGBOX_DIR/config.json"

cp "$REPO_ROOT"/config/sing-box/rule-sets/*.json "$SINGBOX_DIR/rule-sets/"
if [[ "$RULESET_MODE" == local-fixture ]]; then
  cat >"$SINGBOX_DIR/rule-sets/geoip-ru.json" <<'EOF'
{"version":1,"rules":[{"ip_cidr":["5.0.0.0/8"]}]}
EOF
  cat >"$SINGBOX_DIR/rule-sets/geosite-category-ru.json" <<'EOF'
{"version":1,"rules":[{"domain_suffix":["ru"]}]}
EOF
fi
chmod 600 "$SINGBOX_DIR"/rule-sets/*.json

cat >"$VIBE_DIR/config.yaml" <<'EOF'
subscription_file: /etc/vibe-vpn/sub_url
extra_nodes_file: /etc/vibe-vpn/extra-nodes.json
runtime: singbox
sing_box_bin: /usr/local/bin/sing-box
sing_box_config: /var/lib/vpnkit/sing-box/config.json
sing_box_service: vpnkit-supervised-sing-box
sing_box_restart_mode: request-file
sing_box_restart_file: /run/vpnkit/restart-sing-box
# Daemon/manual apply must wait until the entrypoint consumes the request,
# completes fail-closed routing setup, and advances this generation marker.
sing_box_restart_ack_generation_file: /run/vpnkit/sing-box-generation
sing_box_restart_ack_timeout: 60s
state_dir: /var/lib/vibe-vpn
production_socks: 127.0.0.1:2080
test_socks: 127.0.0.1:18080
test_url: https://proof.ovh.net/files/10Mb.dat
test_limit_kib: 64
timeout_seconds: 12
service:
  enabled: true
  startup_test: false
  mode: fastest-rotation
test:
  interval: 30m
health:
  normal_interval: 5s
  failure_retry_delays: [1s, 2s, 3s]
  probe_timeout: 5s
  required_urls:
    - https://example.com/
  diagnostic_urls:
    - https://ya.ru/
logging:
  path: /var/log/vibe-vpn/
  retention: 12h
  also_journal: false
EOF
if [[ -s "$SUBSCRIPTION" ]]; then install -m 0600 "$SUBSCRIPTION" "$VIBE_DIR/sub_url"; fi
[[ -s "$BASE/vibe-vpn/extra-nodes.json" ]] && install -m 0600 "$BASE/vibe-vpn/extra-nodes.json" "$VIBE_DIR/extra-nodes.json" || printf '[]\n' >"$VIBE_DIR/extra-nodes.json"
chmod 600 "$VIBE_DIR/config.yaml" "$VIBE_DIR/extra-nodes.json"

printf 'vpnkit_local_render=ok\n'
printf 'policy=%s\n' "$POLICY"
printf 'ruleset_mode=%s\n' "$RULESET_MODE"
printf 'dns_failover=compose_local_watchdog\n'
printf 'secret_material=not_printed\n'
