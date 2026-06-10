#!/usr/bin/env python3
"""Deterministic proof for vpnkit sing-box smart-routing templates.

This is a repo-local config/fixture proof, not a live sing-box runtime test.
It parses tracked templates after replacing the selected-native placeholder with
safe dummy JSON and simulates domain rule-set matching for sample hostnames.
"""
from __future__ import annotations

import json
import pathlib
import sys
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[1]
DUMMY_OUTBOUND = {
    "type": "vless",
    "tag": "selected-native-out",
    "server": "example.invalid",
    "server_port": 443,
    "uuid": "00000000-0000-0000-0000-000000000000",
}
REMOTE_RU_RULE_SETS = [
    {
        "type": "remote",
        "tag": "geoip-ru",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geoip/geoip-ru.srs",
        "download_detour": "direct-out",
    },
    {
        "type": "remote",
        "tag": "geosite-category-ru",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geosite/geosite-category-ru.srs",
        "download_detour": "direct-out",
    },
]
LOCAL_FIXTURE_RU_RULE_SETS = [
    {
        "type": "local",
        "tag": "geoip-ru",
        "format": "source",
        "path": "/etc/sing-box/rule-sets/geoip-ru.json",
    },
    {
        "type": "local",
        "tag": "geosite-category-ru",
        "format": "source",
        "path": "/etc/sing-box/rule-sets/geosite-category-ru.json",
    },
]
TEMPLATES = [
    ROOT / "config/sing-box/config.json.template",
    ROOT / "config/sing-box/config.tun.json.template",
]
LOCAL_RULESETS = {
    "vpnkit-adblock": ROOT / "config/sing-box/rule-sets/vpnkit-adblock.json",
    "vpnkit-dev-direct": ROOT / "config/sing-box/rule-sets/vpnkit-dev-direct.json",
}
SAMPLES = {
    "ads.doubleclick.net": "block-out",
    "pagead2.googlesyndication.com": "block-out",
    "github.com": "direct-out",
    "codeload.github.com": "direct-out",
    "registry.npmjs.org": "direct-out",
    "npmjs.com": "direct-out",
    "files.pythonhosted.org": "direct-out",
    "auth.docker.io": "direct-out",
    "proxy.golang.org": "direct-out",
    "pypi.org": "direct-out",
    "example.ru": "direct-out",
    "foreign-news.example.com": "selected-native-out",
}


def load_template(path: pathlib.Path, ru_rule_sets: list[dict[str, Any]]) -> dict[str, Any]:
    text = (
        path.read_text()
        .replace("{{SELECTED_NATIVE_OUT_JSON}}", json.dumps(DUMMY_OUTBOUND))
        .replace("{{RU_RULE_SETS_JSON}}", ",".join(json.dumps(rule_set) for rule_set in ru_rule_sets))
    )
    return json.loads(text)


def load_suffixes(path: pathlib.Path) -> list[str]:
    data = json.loads(path.read_text())
    assert data.get("version") == 1, f"{path}: source rule-set version must be 1"
    suffixes: list[str] = []
    for rule in data.get("rules", []):
        suffixes.extend(rule.get("domain_suffix", []))
    assert suffixes, f"{path}: expected non-empty domain_suffix list"
    return suffixes


def matches_suffix(domain: str, suffix: str) -> bool:
    return domain == suffix or domain.endswith(f".{suffix}")


def simulated_decision(domain: str, route: dict[str, Any], suffixes: dict[str, list[str]]) -> str:
    for rule in route["rules"]:
        tag = rule.get("rule_set")
        if tag == "geosite-category-ru" and matches_suffix(domain, "ru"):
            return rule["outbound"]
        if tag in suffixes and any(matches_suffix(domain, suffix) for suffix in suffixes[tag]):
            return rule["outbound"]
    return route["final"]


def assert_template(path: pathlib.Path, *, local_fixture: bool = False) -> None:
    config = load_template(path, LOCAL_FIXTURE_RU_RULE_SETS if local_fixture else REMOTE_RU_RULE_SETS)
    outbounds = {outbound["tag"] for outbound in config["outbounds"]}
    assert {"selected-native-out", "direct-out", "block-out"} <= outbounds

    route = config["route"]
    rules = route["rules"]
    assert route["final"] == "selected-native-out"

    # Preserve DNS hijack/sniff order before policy rules.
    if path.name == "config.json.template":
        assert rules[0].get("action") == "hijack-dns" and rules[0].get("inbound") == "vpnkit-dns-in"
        assert rules[1].get("protocol") == "dns" and rules[1].get("action") == "hijack-dns"
        assert rules[2].get("action") == "sniff"
        policy_start = 3
    else:
        assert rules[0].get("protocol") == "dns" and rules[0].get("action") == "hijack-dns"
        assert rules[1].get("action") == "sniff"
        policy_start = 2

    assert rules[policy_start] == {"rule_set": "vpnkit-adblock", "outbound": "block-out"}
    assert rules[policy_start + 1] == {"rule_set": "vpnkit-dev-direct", "outbound": "direct-out"}
    assert rules[policy_start + 2] == {"rule_set": "geoip-ru", "outbound": "direct-out"}
    assert rules[policy_start + 3] == {"rule_set": "geosite-category-ru", "outbound": "direct-out"}

    rule_sets = {rule_set["tag"]: rule_set for rule_set in route["rule_set"]}
    for tag, rule_path in LOCAL_RULESETS.items():
        entry = rule_sets[tag]
        assert entry["type"] == "local"
        assert entry["format"] == "source"
        assert entry["path"] == f"/etc/sing-box/rule-sets/{rule_path.name}"

    for tag in ("geoip-ru", "geosite-category-ru"):
        entry = rule_sets[tag]
        if local_fixture:
            assert entry["type"] == "local"
            assert entry["format"] == "source"
            assert entry["path"] == f"/etc/sing-box/rule-sets/{tag}.json"
            assert "url" not in entry
        else:
            assert entry["type"] == "remote"
            assert entry["format"] == "binary"
            assert entry["download_detour"] == "direct-out"
            assert entry["url"].startswith("https://")

    suffixes = {tag: load_suffixes(path) for tag, path in LOCAL_RULESETS.items()}
    for domain, expected in SAMPLES.items():
        actual = simulated_decision(domain, route, suffixes)
        assert actual == expected, f"{path}: {domain}: expected {expected}, got {actual}"


def assert_openvpn_preserved() -> None:
    server = (ROOT / "config/openvpn/server.tpl").read_text()
    for line in ("push \"redirect-gateway def1 bypass-dhcp\"", "tun-mtu 1400", "mssfix 1360"):
        assert line in server, f"OpenVPN server template missing preserved line: {line}"


def main() -> int:
    for template in TEMPLATES:
        assert_template(template)
        assert_template(template, local_fixture=True)
    assert_openvpn_preserved()
    print("PASS sing-box smart routing proof: adblock/dev-direct/RU/default decisions and remote/local-fixture template invariants")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        raise SystemExit(1)
