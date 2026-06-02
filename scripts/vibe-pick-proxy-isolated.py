#!/usr/bin/env python3
"""Pick the fastest VLESS node from a subscription without touching production xray during tests.

On VPS, store the subscription URL in /etc/vibe-proxy/sub_url, then run:
  sudo ./vibe-pick-proxy-isolated.py --apply

During tests this starts a temporary xray process with SOCKS on 127.0.0.1:18080.
Only the final winner is written to /usr/local/etc/xray/config.json when --apply is used.
"""
import argparse, base64, json, os, shutil, signal, socket, ssl, struct, subprocess, sys, tempfile, time, urllib.parse, urllib.request

SUB_FILE = '/etc/vibe-proxy/sub_url'
XRAY_CONFIG = '/usr/local/etc/xray/config.json'
STATE_DIR = '/var/lib/vibe-proxy'
XRAY_BIN = '/usr/local/bin/xray'
TEST_HOST = 'proof.ovh.net'
TEST_PATH = '/files/10Mb.dat'
TEST_PORT = 18080


def log(*a): print(*a, flush=True)


def fetch_subscription(url):
    data = urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent':'Mozilla/5.0'}), timeout=30).read()
    text = data.decode('utf-8', 'replace').strip()
    if 'vless://' not in text:
        raw = data.strip() + b'=' * ((4 - len(data.strip()) % 4) % 4)
        text = base64.b64decode(raw).decode('utf-8', 'replace')
    return [x.strip() for x in text.replace('\r', '\n').split('\n') if x.strip().startswith('vless://')]


def vless_to_outbound(link):
    u = urllib.parse.urlsplit(link)
    qs = urllib.parse.parse_qs(u.query)
    q = lambda name, default='': qs.get(name, [default])[0]
    user = urllib.parse.unquote(u.username or '')
    host = u.hostname
    port = u.port or (443 if q('security') in ('tls','reality') else 80)
    name = urllib.parse.unquote(u.fragment or f'{host}:{port}')
    security = q('security', 'none') or 'none'
    network = q('type', 'tcp') or 'tcp'
    user_obj = {'id': user, 'encryption': q('encryption','none') or 'none', 'level': 0}
    if q('flow'): user_obj['flow'] = q('flow')
    outbound = {
        'protocol': 'vless',
        'settings': {'vnext': [{'address': host, 'port': port, 'users': [user_obj]}]},
        'streamSettings': {'network': network, 'security': security},
    }
    ss = outbound['streamSettings']
    if network == 'ws':
        ws = {'path': q('path','/') or '/'}
        if q('host'): ws['headers'] = {'Host': q('host')}
        ss['wsSettings'] = ws
    elif network == 'grpc':
        ss['grpcSettings'] = {'serviceName': q('serviceName') or q('service_name') or ''}
    if security == 'reality':
        ss['realitySettings'] = {
            'serverName': q('sni') or q('serverName') or host,
            'fingerprint': q('fp','chrome') or 'chrome',
            'publicKey': q('pbk') or q('publicKey'),
            'shortId': q('sid') or q('shortId',''),
        }
    elif security == 'tls':
        ss['tlsSettings'] = {'serverName': q('sni') or q('serverName') or host}
        if q('fp'): ss['tlsSettings']['fingerprint'] = q('fp')
    return name, outbound


def temp_config(outbound, port):
    return {
        'log': {'loglevel': 'warning'},
        'inbounds': [{'listen': '127.0.0.1', 'port': port, 'protocol': 'socks', 'settings': {'udp': True}}],
        'outbounds': [outbound],
    }


def wait_port(port, proc, timeout=3.0):
    end = time.time() + timeout
    while time.time() < end:
        if proc.poll() is not None:
            raise RuntimeError('temp xray exited')
        s = socket.socket(); s.settimeout(0.2)
        try:
            s.connect(('127.0.0.1', port)); s.close(); return
        except OSError:
            time.sleep(0.05)
        finally:
            try: s.close()
            except Exception: pass
    raise RuntimeError('temp xray did not open port')


def socks_download(port, limit):
    raw = socket.socket(); raw.settimeout(12)
    t = time.time(); n = 0
    raw.connect(('127.0.0.1', port))
    raw.sendall(b'\x05\x01\x00')
    if raw.recv(2) != b'\x05\x00': raise RuntimeError('socks greeting failed')
    hb = TEST_HOST.encode()
    raw.sendall(b'\x05\x01\x00\x03' + bytes([len(hb)]) + hb + struct.pack('!H',443))
    rep = raw.recv(10)
    if len(rep) < 2 or rep[1] != 0: raise RuntimeError(f'socks connect failed {rep!r}')
    s = ssl.create_default_context().wrap_socket(raw, server_hostname=TEST_HOST); s.settimeout(12)
    s.sendall(f'GET {TEST_PATH} HTTP/1.1\r\nHost: {TEST_HOST}\r\nUser-Agent: Mozilla/5.0\r\nConnection: close\r\n\r\n'.encode())
    buf = b''; hdr = False
    while n < limit:
        b = s.recv(min(65536, limit - n + 4096))
        if not b: break
        if not hdr:
            buf += b; i = buf.find(b'\r\n\r\n')
            if i >= 0: hdr = True; n += len(buf[i+4:])
        else: n += len(b)
    dt = time.time() - t
    return n, dt, n*8/dt/1e6 if dt else 0


def test_node(outbound, limit):
    with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as f:
        json.dump(temp_config(outbound, TEST_PORT), f); path = f.name
    proc = subprocess.Popen([XRAY_BIN, 'run', '-config', path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_port(TEST_PORT, proc)
        return socks_download(TEST_PORT, limit)
    finally:
        proc.terminate()
        try: proc.wait(timeout=1)
        except subprocess.TimeoutExpired: proc.kill()
        os.unlink(path)


def apply_winner(best):
    os.makedirs(STATE_DIR, exist_ok=True)
    backup = f"{XRAY_CONFIG}.bak-isolated-{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(XRAY_CONFIG, backup)
    cfg = json.load(open(XRAY_CONFIG))
    cfg['outbounds'][0] = best['outbound']
    with open(XRAY_CONFIG, 'w') as f: json.dump(cfg, f, indent=2, ensure_ascii=False); f.write('\n')
    subprocess.run(['systemctl','reset-failed','xray'], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['systemctl','restart','xray'], check=True)
    open(os.path.join(STATE_DIR,'current-link.txt'),'w').write(best['link']+'\n')
    json.dump({k:v for k,v in best.items() if k != 'outbound'}, open(os.path.join(STATE_DIR,'current-node.json'),'w'), indent=2, ensure_ascii=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--sub-file', default=SUB_FILE)
    ap.add_argument('--apply', action='store_true', help='apply winner to production xray at the end')
    ap.add_argument('--max', type=int, default=0)
    ap.add_argument('--limit-kib', type=int, default=512)
    args = ap.parse_args()
    links = fetch_subscription(open(args.sub_file).read().strip())
    if args.max: links = links[:args.max]
    log(f'Found {len(links)} VLESS nodes. Testing on temp xray port {TEST_PORT}; production xray is untouched.')
    results=[]; best=None
    for i, link in enumerate(links, 1):
        try:
            name, outbound = vless_to_outbound(link)
            n, dt, mbps = test_node(outbound, args.limit_kib*1024)
            rec = {'i':i, 'name':name, 'mbps':mbps, 'seconds':dt, 'bytes':n, 'link':link, 'outbound':outbound, 'ok': n > 65536}
            results.append(rec)
            log(f'[{i:03d}/{len(links):03d}] {mbps:7.2f} Mbps {dt:5.2f}s {name[:70]}')
            if rec['ok'] and (best is None or mbps > best['mbps']): best = rec
        except Exception as e:
            log(f'[{i:03d}/{len(links):03d}] FAIL {str(e)[:90]}')
            results.append({'i':i, 'ok':False, 'error':str(e), 'link':link})
    os.makedirs(STATE_DIR, exist_ok=True)
    json.dump(results, open(os.path.join(STATE_DIR,'last-results-isolated.json'),'w'), indent=2, ensure_ascii=False)
    if not best:
        log('No working node found.'); return 2
    log('\nBEST:'); log(f"  {best['name']}"); log(f"  {best['mbps']:.2f} Mbps")
    if args.apply:
        apply_winner(best); log('Applied to production xray.')
    else:
        log('Dry run only. Re-run with --apply to switch production xray.')
    return 0

if __name__ == '__main__': sys.exit(main())
