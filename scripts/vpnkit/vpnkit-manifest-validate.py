#!/usr/bin/env python3
"""Validate vpnkit manifest and optionally emit sanitized resolved pair JSON."""
import argparse, importlib, json, re, sys
from pathlib import Path

DEFAULT_SCHEMA = Path('config/vpnkit-manifest.schema.json')

SENSITIVE_KEYS = re.compile(r'(key|cert|ca|tls|endpoint|host|target|password|secret|token|auth)', re.I)


def load_deps():
    missing=[]
    try:
        import yaml  # type: ignore
    except Exception:
        yaml=None; missing.append('PyYAML (pip install PyYAML)')
    try:
        jsonschema = importlib.import_module('jsonschema')  # type: ignore
        origin = Path(getattr(jsonschema, '__file__', '')).resolve()
        repo_local_shadow = (Path(__file__).resolve().parent / 'jsonschema.py').resolve()
        if origin == repo_local_shadow:
            raise ImportError(f'local shadow module is not allowed: {origin}')
    except Exception:
        jsonschema=None; missing.append('jsonschema (python3 -m pip install jsonschema)')
    if missing:
        print('Missing Python dependency for manifest validation: ' + ', '.join(missing), file=sys.stderr)
        print('Install the missing public packages in your local/CI Python environment; do not store secrets in manifests or install from private endpoints.', file=sys.stderr)
        return None, None
    return yaml, jsonschema


def die(msg, code=1):
    print(f'ERROR: {msg}', file=sys.stderr); sys.exit(code)


def read_yaml(path):
    yaml, jsonschema = load_deps()
    if not yaml or not jsonschema: sys.exit(2)
    try:
        data = yaml.safe_load(Path(path).read_text())
        schema = json.loads(DEFAULT_SCHEMA.read_text())
        jsonschema.Draft202012Validator(schema).validate(data)
        return data
    except FileNotFoundError as e: die(f'file not found: {e.filename}')
    except Exception as e: die(f'validation failed: {e}')


def semantic_validate(data):
    errors=[]
    caps=set(data.get('capabilities', []))
    for section in ('servers','clients'):
        for name, obj in data.get(section, {}).items():
            if name != safe_id(name): errors.append(f'{section}.{name}: id must be already sanitized')
            if section == 'clients' and obj.get('id') != name: errors.append(f'{section}.{name}: id field must match manifest key')
            for cap in obj.get('capabilities', []):
                if cap not in caps: errors.append(f'{section}.{name}: unknown capability {cap}')
    pair_intents={}
    for pname, pair in data.get('pairs', {}).items():
        s=pair.get('server'); c=pair.get('client')
        intent=pair.get('profile', {}).get('intent')
        key=(s, c, intent)
        if key in pair_intents: errors.append(f'pairs.{pname}: duplicate profile intent {intent} for server/client already defined by {pair_intents[key]}')
        else: pair_intents[key]=pname
        if s not in data.get('servers', {}): errors.append(f'pairs.{pname}: unknown server {s}')
        if c not in data.get('clients', {}): errors.append(f'pairs.{pname}: unknown client {c}')
        have=set()
        if s in data.get('servers', {}): have |= set(data['servers'][s].get('capabilities', []))
        if c in data.get('clients', {}): have |= set(data['clients'][c].get('capabilities', []))
        for cap in pair.get('requires_capabilities', []):
            if cap not in caps: errors.append(f'pairs.{pname}: requires unknown capability {cap}')
            if cap not in have: errors.append(f'pairs.{pname}: required capability {cap} absent from selected server/client')
        refs={}
        if s in data.get('servers', {}): refs.update(data['servers'][s].get('profile_inputs', {}))
        if c in data.get('clients', {}): refs.update(data['clients'][c].get('profile_inputs', {}))
        for key in pair.get('profile', {}).get('required_bindings', []):
            if key not in refs: errors.append(f'pairs.{pname}: required binding key {key} not provided by server/client profile_inputs')
        remote=pair.get('profile', {}).get('remote')
        if remote and remote not in refs.values(): errors.append(f'pairs.{pname}: profile.remote binding reference is not declared by selected inputs')
    if errors: die('semantic validation failed:\n- ' + '\n- '.join(errors))


def safe_id(value):
    return re.sub(r'[^a-z0-9_.-]+','-', str(value).lower()).strip('-')


def sanitize_bindings(bindings):
    out={}
    for k,v in sorted(bindings.items()):
        out[k]={'ref': v, 'value': '[local-only]' if SENSITIVE_KEYS.search(k) else '[not-resolved]'}
    return out


def resolve_pair(data, server, client, profile_intent):
    pairs=[(n,p) for n,p in data['pairs'].items() if p['server']==server and p['client']==client and p.get('profile', {}).get('intent')==profile_intent]
    if not pairs: die(f'no pair found for --server {server} --client {client} --profile-intent {profile_intent}')
    if len(pairs) > 1: die(f'ambiguous pair for --server {server} --client {client} --profile-intent {profile_intent}')
    name,pair=pairs[0]
    srv=data['servers'][server]; cli=data['clients'][client]
    bindings={}; bindings.update(srv.get('profile_inputs', {})); bindings.update(cli.get('profile_inputs', {}))
    return {
        'pair': safe_id(name), 'server': safe_id(server), 'client': safe_id(client), 'profileIntent': profile_intent,
        'serverMetadata': {'id': safe_id(server), 'displayName': srv.get('displayName', server)},
        'clientMetadata': {'id': cli.get('id', safe_id(client)), 'displayName': cli.get('displayName', client), 'profileCommonName': cli.get('profileCommonName', safe_id(client)), 'clientCertIdentity': cli.get('clientCertIdentity', cli.get('profileCommonName', safe_id(client)))},
        'profile': {'intent': profile_intent, 'mode': pair['profile']['mode'], 'proto': pair['profile']['proto'], 'port': pair['profile']['port'], 'remote_ref': pair['profile']['remote'], 'required_bindings': pair['profile']['required_bindings']},
        'bindings': sanitize_bindings(bindings),
        'capabilities': {'server': srv.get('capabilities', []), 'client': cli.get('capabilities', []), 'required': pair.get('requires_capabilities', [])}
    }


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--manifest', default='config/vpnkit-manifest.example.yaml')
    ap.add_argument('--server'); ap.add_argument('--client')
    ap.add_argument('--profile-intent', choices=('test', 'production'), default='test', help='Profile intent to resolve for the selected server/client pair (default: test)')
    args=ap.parse_args()
    data=read_yaml(args.manifest); semantic_validate(data)
    if args.server or args.client:
        if not (args.server and args.client): die('--server and --client must be provided together')
        print(json.dumps(resolve_pair(data, args.server, args.client, args.profile_intent), indent=2, sort_keys=True))
    else:
        print('manifest_valid=true')

if __name__ == '__main__': main()
