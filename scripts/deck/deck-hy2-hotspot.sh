#!/usr/bin/env bash
set -Eeuo pipefail

SSH_TARGET=${DECK_HY2_SSH_TARGET:-${VPNKIT_STEAMDECK_SSH_TARGET:-deck}}
CLIENT_CONFIG=${DECK_HY2_CLIENT_CONFIG:-clients/hysteria2/personal.yaml}
BASE_TEMPLATE=${DECK_HY2_BASE_TEMPLATE:-config/sing-box/config.tun.json.template}
REMOTE_STATE=${DECK_HY2_REMOTE_STATE:-/home/deck/.local/state/vpnkit-deck-hy2-hotspot}
PODMAN_CMD=${DECK_HY2_PODMAN:-"sudo podman --root /home/deck/.local/share/vpnkit-root-podman --runroot /run/vpnkit-root-podman"}
SINGBOX_MODE=${DECK_HY2_SINGBOX_MODE:-native}
SINGBOX_BIN=${DECK_HY2_SINGBOX_BIN:-/home/deck/.local/bin/sing-box}
SINGBOX_UNIT=${DECK_HY2_SINGBOX_UNIT:-vpnkit-deck-hy2-singbox.service}
SINGBOX_IMAGE=${DECK_HY2_SINGBOX_IMAGE:-docker.io/library/containerized-vpnkit-openvpn-singbox-vpnkit:latest}
SINGBOX_CONTAINER=${DECK_HY2_SINGBOX_CONTAINER:-vpnkit-deck-hy2-singbox}
HOTSPOT_CONTAINER=${DECK_HY2_HOTSPOT_CONTAINER:-vpnkit-deck-hy2-hotspot-ap}
HOTSPOT_IMAGE=${DECK_HY2_HOTSPOT_IMAGE:-localhost/vpnkit-deck-hy2-hotspot-ap:latest}
TUN_IFACE=${DECK_HY2_TUN_IFACE:-sb-tun0}
TUN_ADDR=${DECK_HY2_TUN_ADDR:-172.19.0.1/30}
HOTSPOT_PASSWORD=${DECK_HOTSPOT_PASSWORD:-}
HOTSPOT_SUBNET=${DECK_HOTSPOT_SUBNET:-10.42.0.0/24}
HOTSPOT_TABLE=${DECK_HY2_HOTSPOT_TABLE:-51902}
HOTSPOT_RULE_PRIO=${DECK_HY2_HOTSPOT_RULE_PRIO:-10002}
REPORT_DIR=${DECK_HY2_REPORT_DIR:-docs/plans/2026-06-22-steamdeck-hy2-hotspot-runtime/verification}
ACTION=${1:-}

usage() {
  cat <<'EOF'
Usage: scripts/deck/deck-hy2-hotspot.sh <up|down|status|test> [options]

Reusable Steam Deck lab helper:
  local personal Hysteria2 config -> sing-box TUN on Deck -> Deck hotspot routed through TUN.

Defaults:
  client config: clients/hysteria2/personal.yaml
  sing-box base: config/sing-box/config.tun.json.template
  ssh target:   deck
  hotspot SSID: inherited from scripts/deck/deck-hotspot-vpn-up.sh (default vpnkit-deck)

Environment:
  DECK_HOTSPOT_PASSWORD    WPA password for hotspot apply (required for up; not printed)
  DECK_HY2_CLIENT_CONFIG   personal .yaml or .uri source
  DECK_HY2_SINGBOX_MODE    native or podman (default native)
  DECK_HY2_SINGBOX_BIN     Deck path for native sing-box
  DECK_HY2_SINGBOX_IMAGE   Podman image with /usr/local/bin/sing-box, for podman mode
  DECK_HY2_*               other knobs shown near top of this script

Options:
  --ssh-target HOST
  --client-config PATH     Hysteria2 YAML or hysteria2:// URI file
  --image IMAGE            sing-box-capable Podman image on Deck
  --container NAME         distinct sing-box container name
  --remote-state DIR       Deck state dir
  --report-dir DIR         local redacted report dir
  -h|--help

Actions:
  up       Generate config, start sing-box, start hotspot, add policy route for hotspot subnet
  down     Remove hotspot, policy route, and sing-box container/state interface
  status   Read-only Deck status
  test     Read-only Deck gateway checks; client device checks still need to be run from a hotspot client
EOF
}

[[ -n "$ACTION" ]] || { usage >&2; exit 2; }
if [[ "$ACTION" == "-h" || "$ACTION" == "--help" ]]; then usage; exit 0; fi
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh-target) SSH_TARGET=${2:?}; shift 2 ;;
    --client-config) CLIENT_CONFIG=${2:?}; shift 2 ;;
    --image) SINGBOX_IMAGE=${2:?}; shift 2 ;;
    --container) SINGBOX_CONTAINER=${2:?}; shift 2 ;;
    --remote-state) REMOTE_STATE=${2:?}; shift 2 ;;
    --report-dir) REPORT_DIR=${2:?}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$SSH_TARGET$SINGBOX_CONTAINER$TUN_IFACE" =~ ^[A-Za-z0-9_.:@/-]+$ ]] || { echo "unsafe target/container/interface" >&2; exit 2; }
mkdir -p "$REPORT_DIR"

redact() {
  sed -E \
    -e 's#hysteria2://[^[:space:]]+#hysteria2://[redacted]#g' \
    -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' \
    -e 's/([0-9a-f]{2}:){5}[0-9a-f]{2}/<MAC>/Ig' \
    -e 's/[0-9a-f]{4}(:[0-9a-f]{0,4}){2,7}/<IPv6>/Ig' \
    -e 's/(password|auth|obfs[^:=]*)([":= ]+)[^", }]+/\1\2<redacted>/Ig' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/<redacted-userhost>/g'
}
q() { printf '%q' "$1"; }
remote() { ssh "$SSH_TARGET" "$@"; }
remote_bash() { ssh "$SSH_TARGET" 'bash -s'; }

make_config() {
  [[ -r "$CLIENT_CONFIG" ]] || { echo "missing client config: $CLIENT_CONFIG" >&2; exit 2; }
  [[ -r "$BASE_TEMPLATE" ]] || { echo "missing base template: $BASE_TEMPLATE" >&2; exit 2; }
  CLIENT_CONFIG="$CLIENT_CONFIG" BASE_TEMPLATE="$BASE_TEMPLATE" TUN_IFACE="$TUN_IFACE" TUN_ADDR="$TUN_ADDR" python3 - <<'PY'
import ipaddress, json, os, re, socket, sys
from urllib.parse import urlparse, unquote, parse_qs

client = os.environ['CLIENT_CONFIG']
template_path = os.environ['BASE_TEMPLATE']
tun_iface = os.environ['TUN_IFACE']
tun_addr = os.environ['TUN_ADDR']

def obfs_password(obfs):
    salamander = (obfs or {}).get('salamander')
    if isinstance(salamander, dict):
        return str(salamander.get('password') or '').strip()
    return str(salamander or '').strip()

def parse_yaml(path):
    try:
        import yaml
    except Exception as e:
        raise SystemExit('PyYAML is required to parse YAML client configs; use personal.uri or install PyYAML') from e
    d = yaml.safe_load(open(path))
    server = str(d['server']).strip()
    if server.startswith('['):
        host = server[1:].split(']', 1)[0]
        port = int(server.rsplit(':', 1)[1])
    else:
        host, port_s = server.rsplit(':', 1)
        port = int(port_s)
    tls = d.get('tls') or {}
    obfs = d.get('obfs') or {}
    return {
        'host': host,
        'port': port,
        'auth': str(d['auth']).strip(),
        'sni': str(tls.get('sni') or host).strip(),
        'insecure': bool(tls.get('insecure')),
        'obfs': obfs_password(obfs),
    }

def parse_uri(path):
    u = open(path).read().strip()
    r = urlparse(u)
    if r.scheme not in ('hysteria2', 'hy2', 'hysteria'):
        raise SystemExit('not a hysteria2 URI')
    qs = parse_qs(r.query)
    auth = unquote(r.netloc.rsplit('@', 1)[0]) if '@' in r.netloc else unquote(r.username or '')
    return {
        'host': r.hostname,
        'port': int(r.port or 443),
        'auth': auth,
        'sni': (qs.get('sni') or qs.get('peer') or [r.hostname])[0],
        'insecure': (qs.get('insecure') or ['0'])[0] in ('1', 'true', 'yes'),
        'obfs': (qs.get('obfs-password') or qs.get('obfs') or [''])[0],
    }

src = parse_uri(client) if client.endswith('.uri') else parse_yaml(client)
server = src['host']
try:
    ipaddress.ip_address(server)
except ValueError:
    # Resolve locally before copying to the Deck so Deck-side DNS/hotspot state
    # cannot block dialing the Hysteria2 server. TLS SNI stays unchanged below.
    server = socket.getaddrinfo(server, src['port'], socket.AF_INET, socket.SOCK_DGRAM)[0][4][0]
outbound = {
    'type': 'hysteria2',
    'tag': 'selected-native-out',
    'server': server,
    'server_port': src['port'],
    'password': src['auth'],
    'up_mbps': 100,
    'down_mbps': 100,
    'tls': {'enabled': True, 'server_name': src['sni']},
}
if src.get('insecure'):
    outbound['tls']['insecure'] = True
if src.get('obfs'):
    outbound['obfs'] = {'type': 'salamander', 'password': src['obfs']}

t = open(template_path).read()
# Keep prod template shape, but make it self-contained for the Deck helper by using empty local rule sets.
empty_rule_sets = '\n      {"type":"local","tag":"geoip-ru","format":"source","path":"/etc/sing-box/rule-sets/geoip-ru.json"},\n      {"type":"local","tag":"geosite-category-ru","format":"source","path":"/etc/sing-box/rule-sets/geosite-category-ru.json"}\n'
t = t.replace('{{SELECTED_NATIVE_OUT_JSON}}', json.dumps(outbound, indent=4))
t = t.replace('{{RU_RULE_SETS_JSON}}', empty_rule_sets)
c = json.loads(t)
for inbound in c.get('inbounds', []):
    if inbound.get('type') == 'tun':
        inbound['interface_name'] = tun_iface
        inbound['address'] = [tun_addr]
        inbound['auto_route'] = False
        inbound['strict_route'] = False
        inbound['stack'] = 'system'
# Avoid host port conflicts and avoid SOCKS path crashes in this Deck lab helper.
c['inbounds'] = [i for i in c.get('inbounds', []) if i.get('type') != 'socks']
# Make DNS hijack match raw client UDP/TCP 53 packets before sniff/final routing.
route = c.setdefault('route', {})
rules = route.get('rules') or []
route['rules'] = [{'port': 53, 'action': 'hijack-dns'}] + rules
print(json.dumps(c, indent=2))
PY
}

write_empty_rules() {
  local dir=$1
  mkdir -p "$dir"
  printf '{"version":1,"rules":[]}\n' > "$dir/vpnkit-adblock.json"
  printf '{"version":1,"rules":[]}\n' > "$dir/vpnkit-dev-direct.json"
  printf '{"version":1,"rules":[]}\n' > "$dir/geoip-ru.json"
  printf '{"version":1,"rules":[]}\n' > "$dir/geosite-category-ru.json"
}

up() {
  [[ ${#HOTSPOT_PASSWORD} -ge 8 ]] || { echo "set DECK_HOTSPOT_PASSWORD to an 8+ char WPA password" >&2; exit 2; }
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  make_config > "$tmp/config.json"
  chmod 600 "$tmp/config.json"
  write_empty_rules "$tmp/rule-sets"

  local report="$REPORT_DIR/deck-hy2-hotspot-up-$(date -u +%Y%m%dT%H%M%SZ).md"
  {
    echo "# Deck HY2 hotspot up report"
    echo
    echo "- Timestamp: $(date -u +%FT%TZ)"
    echo "- SSH target: <redacted>"
    echo "- Client config: $(basename "$CLIENT_CONFIG")"
    echo "- Sing-box mode: $SINGBOX_MODE"
    echo "- Sing-box unit/container: $SINGBOX_UNIT / $SINGBOX_CONTAINER"
    echo
    echo '```text'
    remote "sudo mkdir -p $(q "$REMOTE_STATE")/rule-sets $(q "$REMOTE_STATE")/backups"
    tar -C "$tmp" -cf - config.json rule-sets | ssh "$SSH_TARGET" "sudo tar -xf - -C $(q "$REMOTE_STATE") && sudo chmod 600 $(q "$REMOTE_STATE")/config.json"
    if [[ "$SINGBOX_MODE" == "native" ]]; then
      remote "set -e; sudo mkdir -p /etc/sing-box/rule-sets; sudo cp $(q "$REMOTE_STATE")/rule-sets/*.json /etc/sing-box/rule-sets/; sudo chmod 644 /etc/sing-box/rule-sets/*.json; sudo systemctl stop $(q "$SINGBOX_UNIT") >/dev/null 2>&1 || true; sudo systemctl reset-failed $(q "$SINGBOX_UNIT") >/dev/null 2>&1 || true; sudo ip link del $(q "$TUN_IFACE") >/dev/null 2>&1 || true; sudo ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true $(q "$SINGBOX_BIN") check -c $(q "$REMOTE_STATE")/config.json >/tmp/deck-hy2-singbox-check.out 2>&1 || { sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' /tmp/deck-hy2-singbox-check.out; exit 1; }; sudo systemd-run --unit=$(q "$SINGBOX_UNIT") --description=vpnkit-deck-hy2-singbox --setenv=ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true --setenv=ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true $(q "$SINGBOX_BIN") run -c $(q "$REMOTE_STATE")/config.json >/dev/null; sleep 5; if systemctl is-active --quiet $(q "$SINGBOX_UNIT"); then echo singbox_status=active; else sudo systemctl status --no-pager $(q "$SINGBOX_UNIT") || true; exit 1; fi; ip link show $(q "$TUN_IFACE") >/dev/null && echo tun=present || echo tun=absent"
    else
      remote "set -e; read -r -a PODMAN <<< $(q "$PODMAN_CMD"); \${PODMAN[@]} rm -f $(q "$SINGBOX_CONTAINER") >/dev/null 2>&1 || true; sudo ip link del $(q "$TUN_IFACE") >/dev/null 2>&1 || true; \${PODMAN[@]} run --rm --network host --privileged -e ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true -e ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true -v $(q "$REMOTE_STATE")/config.json:/etc/sing-box/config.json:ro -v $(q "$REMOTE_STATE")/rule-sets:/etc/sing-box/rule-sets:ro --entrypoint /usr/local/bin/sing-box $(q "$SINGBOX_IMAGE") check -c /etc/sing-box/config.json >/tmp/deck-hy2-singbox-check.out 2>&1 || { sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' /tmp/deck-hy2-singbox-check.out; exit 1; }; \${PODMAN[@]} run -d --name $(q "$SINGBOX_CONTAINER") --replace --network host --privileged -e ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true -e ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true -v $(q "$REMOTE_STATE")/config.json:/etc/sing-box/config.json:ro -v $(q "$REMOTE_STATE")/rule-sets:/etc/sing-box/rule-sets:ro --entrypoint /usr/local/bin/sing-box $(q "$SINGBOX_IMAGE") run -c /etc/sing-box/config.json >/dev/null; sleep 5; echo singbox_status=\$(\${PODMAN[@]} ps -a --filter name=$(q "$SINGBOX_CONTAINER") --format '{{.Status}}' | head -1); ip link show $(q "$TUN_IFACE") >/dev/null && echo tun=present || echo tun=absent"
    fi
    DECK_HOTSPOT_PASSWORD="$HOTSPOT_PASSWORD" DECK_HOTSPOT_CONTAINER="$HOTSPOT_CONTAINER" DECK_HOTSPOT_IMAGE="$HOTSPOT_IMAGE" scripts/deck/deck-hotspot-vpn-up.sh --ssh-target "$SSH_TARGET" --vpn-iface "$TUN_IFACE" --apply --yes --report "$REPORT_DIR/deck-hy2-hotspot-inner-up-$(date -u +%Y%m%dT%H%M%SZ).md"
    remote "set -e; sudo ip route replace default dev $(q "$TUN_IFACE") table $(q "$HOTSPOT_TABLE"); sudo ip rule del from $(q "$HOTSPOT_SUBNET") table $(q "$HOTSPOT_TABLE") priority $(q "$HOTSPOT_RULE_PRIO") >/dev/null 2>&1 || true; sudo ip rule add from $(q "$HOTSPOT_SUBNET") table $(q "$HOTSPOT_TABLE") priority $(q "$HOTSPOT_RULE_PRIO"); echo hotspot_policy_route=installed"
    remote "ip -br addr | grep -E '$(q "$TUN_IFACE")|ap0|wlan0' || true; sudo nft list table inet vpnkit_deck_hotspot || true"
    echo '```'
  } 2>&1 | redact | tee "$report"
  echo "report_path=$report"
}

down() {
  local report="$REPORT_DIR/deck-hy2-hotspot-down-$(date -u +%Y%m%dT%H%M%SZ).md"
  {
    echo "# Deck HY2 hotspot down report"
    echo
    echo "- Timestamp: $(date -u +%FT%TZ)"
    echo '```text'
    DECK_HOTSPOT_CONTAINER="$HOTSPOT_CONTAINER" scripts/deck/deck-hotspot-vpn-down.sh --ssh-target "$SSH_TARGET" --report "$REPORT_DIR/deck-hy2-hotspot-inner-down-$(date -u +%Y%m%dT%H%M%SZ).md" || true
    remote "set +e; read -r -a PODMAN <<< $(q "$PODMAN_CMD"); sudo ip rule del from $(q "$HOTSPOT_SUBNET") table $(q "$HOTSPOT_TABLE") priority $(q "$HOTSPOT_RULE_PRIO") 2>/dev/null; sudo ip route flush table $(q "$HOTSPOT_TABLE") 2>/dev/null; sudo systemctl stop $(q "$SINGBOX_UNIT") 2>/dev/null; sudo systemctl reset-failed $(q "$SINGBOX_UNIT") 2>/dev/null; \${PODMAN[@]} rm -f $(q "$SINGBOX_CONTAINER") 2>/dev/null; sudo ip link del $(q "$TUN_IFACE") 2>/dev/null; echo down_done"
    echo '```'
  } 2>&1 | redact | tee "$report"
  echo "report_path=$report"
}

status() {
  remote "set +e; read -r -a PODMAN <<< $(q "$PODMAN_CMD"); echo systemd; systemctl is-active $(q "$SINGBOX_UNIT") 2>/dev/null || true; echo containers; \${PODMAN[@]} ps -a --filter name=vpnkit-deck --format '{{.Names}} {{.Status}} {{.Image}}'; echo interfaces; ip -br addr | grep -E '$(q "$TUN_IFACE")|ap0|wlan0' || true; echo rules; ip rule show | grep -E '$(q "$HOTSPOT_TABLE")|$(q "$HOTSPOT_SUBNET")' || true; echo nft; sudo nft list tables | grep vpnkit || true" | redact
}

test_gateway() {
  DECK_HOTSPOT_CONTAINER="$HOTSPOT_CONTAINER" scripts/deck/deck-hotspot-vpn-test.sh --ssh-target "$SSH_TARGET" --vpn-iface "$TUN_IFACE" --report "$REPORT_DIR/deck-hy2-hotspot-test-$(date -u +%Y%m%dT%H%M%SZ).md"
}

case "$ACTION" in
  up) up ;;
  down) down ;;
  status) status ;;
  test) test_gateway ;;
  *) echo "unknown action: $ACTION" >&2; usage >&2; exit 2 ;;
esac
