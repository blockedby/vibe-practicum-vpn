#!/usr/bin/env bash
set -euo pipefail
BASE=${VPNKIT_SECRETS_DIR:-secrets/vps}
RENDERED="$BASE/rendered"
mkdir -p "$RENDERED/openvpn/pki" "$RENDERED/openvpn/ccd" "$RENDERED/sing-box/rule-sets" "$RENDERED/vibe-vpn" "$BASE/openvpn/client"
cp config/openvpn/server.tpl "$RENDERED/openvpn/server.conf"
cp "$BASE/openvpn/pki/ca.crt" "$BASE/openvpn/pki/ta.key" "$BASE/openvpn/pki/vibe-asus.crt" "$BASE/openvpn/pki/vibe-asus.key" "$RENDERED/openvpn/pki/"
cp "$BASE/openvpn/server/ccd-ignat" "$RENDERED/openvpn/ccd/ignat" 2>/dev/null || true
routing_mode=${VPNKIT_ROUTING_MODE:-redirect}
routing_mode=${routing_mode,,}
case "$routing_mode" in
  redirect|tproxy) singbox_template=config/sing-box/config.json.template ;;
  tun) singbox_template=config/sing-box/config.tun.json.template ;;
  *) echo "unsupported VPNKIT_ROUTING_MODE=$VPNKIT_ROUTING_MODE (expected redirect, tproxy, or tun)" >&2; exit 2 ;;
esac
python3 - "$BASE/sing-box/tproxy-canary.json" "$singbox_template" "$RENDERED/sing-box/config.json" <<'PY'
import ipaddress, json, socket, sys
src, tmpl, out = sys.argv[1:]
data=json.load(open(src))
vless=[o for o in data.get('outbounds',[]) if o.get('tag')=='selected-native-out' and o.get('type')=='vless']
if not vless:
    raise SystemExit('selected-native-out vless outbound not found')
selected=dict(vless[0])
server=selected.get('server')
if server:
    try:
        ipaddress.ip_address(server)
    except ValueError:
        # Avoid a runtime bootstrap loop where sing-box must resolve its own VLESS
        # server through the VLESS outbound before the outbound is connected. Keep
        # TLS/SNI settings untouched; only the dial address is pre-resolved during
        # local secret rendering, and the rendered file remains gitignored.
        selected['server']=socket.getaddrinfo(server, selected.get('server_port', 443), socket.AF_INET, socket.SOCK_STREAM)[0][4][0]
text=open(tmpl).read().replace('{{SELECTED_NATIVE_OUT_JSON}}', json.dumps(selected, indent=4))
open(out,'w').write(text)
PY
cp config/sing-box/rule-sets/*.json "$RENDERED/sing-box/rule-sets/"
python3 - "$BASE/openvpn/pki" config/openvpn/test-client.ovpn.template "$BASE/openvpn/client/test-client.ovpn" <<'PY'
import pathlib, sys
p=pathlib.Path(sys.argv[1]); text=pathlib.Path(sys.argv[2]).read_text()
repl={
 '{{CA_CRT}}':(p/'ca.crt').read_text().strip(),
 '{{CLIENT_CRT}}':(p/'ignat.crt').read_text().strip(),
 '{{CLIENT_KEY}}':(p/'ignat.key').read_text().strip(),
 '{{TA_KEY}}':(p/'ta.key').read_text().strip(),
}
for k,v in repl.items(): text=text.replace(k,v)
pathlib.Path(sys.argv[3]).write_text(text)
PY
cp config/vibe-vpn/container-lab.yaml.template "$RENDERED/vibe-vpn/config.yaml"
if [[ -r "$BASE/vibe-vpn/sub_url" ]]; then
  cp "$BASE/vibe-vpn/sub_url" "$RENDERED/vibe-vpn/sub_url"
elif [[ -r "$BASE/vibe-vpn/subscription.url" ]]; then
  cp "$BASE/vibe-vpn/subscription.url" "$RENDERED/vibe-vpn/sub_url"
elif [[ -r "$BASE/vibe-vpn/subscription.txt" ]]; then
  cp "$BASE/vibe-vpn/subscription.txt" "$RENDERED/vibe-vpn/sub_url"
elif [[ -r "$BASE/sub_url" ]]; then
  cp "$BASE/sub_url" "$RENDERED/vibe-vpn/sub_url"
else
  cat > "$RENDERED/vibe-vpn/README.missing-subscription" <<'EOF'
Missing vibe-vpn subscription input.

Create one of these gitignored files, then rerun scripts/vpnkit-render-local-configs.sh:
- secrets/vps/vibe-vpn/sub_url
- secrets/vps/vibe-vpn/subscription.url
- secrets/vps/vibe-vpn/subscription.txt
- secrets/vps/sub_url
EOF
fi
if [[ -r "$BASE/vibe-vpn/extra-nodes.json" ]]; then
  cp "$BASE/vibe-vpn/extra-nodes.json" "$RENDERED/vibe-vpn/extra-nodes.json"
else
  printf '[]\n' > "$RENDERED/vibe-vpn/extra-nodes.json"
fi
if [[ -r "$BASE/vibe-vpn/example-extra-node-hy2-auth" ]]; then
  cp "$BASE/vibe-vpn/example-extra-node-hy2-auth" "$RENDERED/vibe-vpn/example-extra-node-hy2-auth"
fi
chmod 600 "$RENDERED/sing-box/config.json" "$RENDERED/sing-box/rule-sets"/*.json "$BASE/openvpn/client/test-client.ovpn" "$RENDERED/vibe-vpn/config.yaml" "$RENDERED/vibe-vpn/extra-nodes.json"
if [[ -f "$RENDERED/vibe-vpn/sub_url" ]]; then chmod 600 "$RENDERED/vibe-vpn/sub_url"; fi
if [[ -f "$RENDERED/vibe-vpn/example-extra-node-hy2-auth" ]]; then chmod 600 "$RENDERED/vibe-vpn/example-extra-node-hy2-auth"; fi
echo "Rendered $RENDERED/openvpn/server.conf, $RENDERED/sing-box/config.json, $RENDERED/vibe-vpn/config.yaml, and $BASE/openvpn/client/test-client.ovpn"
if [[ ! -f "$RENDERED/vibe-vpn/sub_url" ]]; then
  echo "WARNING: missing vibe-vpn subscription input; see $RENDERED/vibe-vpn/README.missing-subscription" >&2
fi
