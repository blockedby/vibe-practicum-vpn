#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

[[ -r "$SINGNOX_HY2_CLIENT_CONFIG" ]] || { echo "missing Hysteria2 client config: $SINGNOX_HY2_CLIENT_CONFIG" >&2; exit 12; }
[[ -r "$SINGNOX_SINGBOX_TEMPLATE" ]] || { echo "missing sing-box template: $SINGNOX_SINGBOX_TEMPLATE" >&2; exit 12; }

CLIENT_CONFIG=$SINGNOX_HY2_CLIENT_CONFIG \
SINGBOX_TEMPLATE=$SINGNOX_SINGBOX_TEMPLATE \
OUTPUT_CONFIG=$SINGNOX_OUTPUT_CONFIG \
RULE_SET_DIR=$SINGNOX_RULE_SET_DIR \
TUN_IFACE=$SINGNOX_TUN_IFACE \
TUN_ADDR=$SINGNOX_TUN_ADDR \
python3 - <<'PY'
import json, os, re, socket
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

client_path = Path(os.environ['CLIENT_CONFIG'])
template_path = Path(os.environ['SINGBOX_TEMPLATE'])
output_path = Path(os.environ['OUTPUT_CONFIG'])
rule_set_dir = Path(os.environ['RULE_SET_DIR'])
tun_iface = os.environ['TUN_IFACE']
tun_addr = os.environ['TUN_ADDR']

def scalar(value):
    value = value.strip()
    if value in ('', 'null', 'Null', 'NULL'):
        return ''
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    return value

def simple_yaml(path):
    data = {}
    parents = []
    for raw in path.read_text().splitlines():
        if not raw.strip() or raw.lstrip().startswith('#'):
            continue
        indent = len(raw) - len(raw.lstrip(' '))
        key, sep, value = raw.strip().partition(':')
        if not sep:
            continue
        while parents and parents[-1][0] >= indent:
            parents.pop()
        if value.strip() == '':
            node = {}
            if parents:
                parents[-1][1][key] = node
            else:
                data[key] = node
            parents.append((indent, node))
        else:
            if parents:
                parents[-1][1][key] = scalar(value)
            else:
                data[key] = scalar(value)
    return data

def load_yaml(path):
    try:
        import yaml  # type: ignore
        loaded = yaml.safe_load(path.read_text())
        if isinstance(loaded, dict):
            return loaded
    except Exception:
        pass
    return simple_yaml(path)

def parse_host_port(server):
    server = str(server).strip()
    if server.startswith('['):
        return server[1:].split(']', 1)[0], int(server.rsplit(':', 1)[1])
    host, port = server.rsplit(':', 1)
    return host, int(port)

def obfs_password(obfs):
    salamander = (obfs or {}).get('salamander')
    if isinstance(salamander, dict):
        return str(salamander.get('password') or '').strip()
    return str(salamander or '').strip()

def parse_yaml_client(path):
    data = load_yaml(path)
    tls = data.get('tls') or {}
    obfs = data.get('obfs') or {}
    host, port = parse_host_port(data['server'])
    insecure = str(tls.get('insecure', 'false')).lower() in ('1', 'true', 'yes')
    return {
        'host': host,
        'port': port,
        'auth': str(data['auth']).strip(),
        'sni': str(tls.get('sni') or host).strip(),
        'insecure': insecure,
        'obfs': obfs_password(obfs),
    }

def parse_uri_client(path):
    raw = path.read_text().strip()
    parsed = urlparse(raw)
    if parsed.scheme not in ('hysteria2', 'hy2', 'hysteria'):
        raise SystemExit('not a Hysteria2 URI')
    qs = parse_qs(parsed.query)
    auth = unquote(parsed.netloc.rsplit('@', 1)[0]) if '@' in parsed.netloc else unquote(parsed.username or '')
    return {
        'host': parsed.hostname,
        'port': int(parsed.port or 443),
        'auth': auth,
        'sni': (qs.get('sni') or qs.get('peer') or [parsed.hostname])[0],
        'insecure': (qs.get('insecure') or ['0'])[0].lower() in ('1', 'true', 'yes'),
        'obfs': (qs.get('obfs-password') or qs.get('obfs') or [''])[0],
    }

source = parse_uri_client(client_path) if client_path.suffix == '.uri' else parse_yaml_client(client_path)
if not source.get('host') or not source.get('auth'):
    raise SystemExit('Hysteria2 client config is missing host or auth')
server = source['host']
if not re.match(r'^[0-9A-Fa-f:.]+$', server):
    # Resolve before Deck-side hotspot/DNS state can affect dialing. TLS SNI remains unchanged.
    server = socket.getaddrinfo(server, source['port'], socket.AF_INET, socket.SOCK_DGRAM)[0][4][0]

outbound = {
    'type': 'hysteria2',
    'tag': 'selected-native-out',
    'server': server,
    'server_port': source['port'],
    'password': source['auth'],
    'up_mbps': 100,
    'down_mbps': 100,
    'tls': {'enabled': True, 'server_name': source['sni']},
}
if source.get('insecure'):
    outbound['tls']['insecure'] = True
if source.get('obfs'):
    outbound['obfs'] = {'type': 'salamander', 'password': source['obfs']}

rule_sets_json = '''
      {"type":"local","tag":"geoip-ru","format":"source","path":"/etc/sing-box/rule-sets/geoip-ru.json"},
      {"type":"local","tag":"geosite-category-ru","format":"source","path":"/etc/sing-box/rule-sets/geosite-category-ru.json"}
'''
rendered = template_path.read_text()
rendered = rendered.replace('{{SELECTED_NATIVE_OUT_JSON}}', json.dumps(outbound, indent=4))
rendered = rendered.replace('{{RU_RULE_SETS_JSON}}', rule_sets_json)
config = json.loads(rendered)
for inbound in config.get('inbounds', []):
    if inbound.get('type') == 'tun':
        inbound['interface_name'] = tun_iface
        inbound['address'] = [tun_addr]
        inbound['auto_route'] = False
        inbound['strict_route'] = False
        inbound['stack'] = 'system'
config['inbounds'] = [inbound for inbound in config.get('inbounds', []) if inbound.get('type') != 'socks']
for rule_set in config.setdefault('route', {}).get('rule_set') or []:
    path = Path(rule_set.get('path', ''))
    if path.name:
        rule_set['path'] = str(rule_set_dir / path.name)

output_path.parent.mkdir(parents=True, exist_ok=True)
# Only create local rule-set placeholders for package-relative/local output paths.
# Remote absolute paths are valid inside the Deck config but must not be created
# on the workstation while rendering.
if str(rule_set_dir).startswith(str(Path.cwd())) or not rule_set_dir.is_absolute():
    rule_set_dir.mkdir(parents=True, exist_ok=True)
    for name in ('vpnkit-adblock.json', 'vpnkit-dev-direct.json', 'geoip-ru.json', 'geosite-category-ru.json'):
        target = rule_set_dir / name
        if not target.exists():
            target.write_text('{"version":1,"rules":[]}\n')
output_path.write_text(json.dumps(config, indent=2) + '\n')
output_path.chmod(0o600)
PY

log "rendered sing-box config to $SINGNOX_OUTPUT_CONFIG"
if command -v "$SINGNOX_SINGBOX_BIN" >/dev/null 2>&1; then
  ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true \
  ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true \
    "$SINGNOX_SINGBOX_BIN" check -c "$SINGNOX_OUTPUT_CONFIG" 2>&1 | redact
else
  log "sing-box binary not found at $SINGNOX_SINGBOX_BIN; skipped sing-box check"
fi
