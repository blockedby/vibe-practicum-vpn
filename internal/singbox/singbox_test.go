package singbox

import (
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestDockerTemplateRoutingInvariants(t *testing.T) {
	b, err := os.ReadFile(filepath.Join("..", "..", "config", "sing-box", "config.json.template"))
	if err != nil {
		t.Fatal(err)
	}
	selectedOutbound := `{"type":"vless","tag":"selected-native-out","server":"203.0.113.10","server_port":443}`
	text := strings.ReplaceAll(string(b), "{{SELECTED_NATIVE_OUT_JSON}}", selectedOutbound)
	if strings.Contains(text, "{{SELECTED_NATIVE_OUT_JSON}}") {
		t.Fatal("template placeholder was not replaced")
	}

	var cfg map[string]any
	if err := json.Unmarshal([]byte(text), &cfg); err != nil {
		t.Fatalf("template is not valid JSON after placeholder substitution: %v", err)
	}

	route := cfg["route"].(map[string]any)
	if route["final"] != "selected-native-out" {
		t.Fatalf("route.final = %#v, want selected-native-out", route["final"])
	}

	rules := route["rules"].([]any)
	if len(rules) < 4 {
		t.Fatalf("route.rules length = %d, want DNS hijack rules plus RU direct rules", len(rules))
	}
	assertDNSHijackRule(t, rules[0].(map[string]any), "inbound", "vpnkit-dns-in")
	assertDNSHijackRule(t, rules[1].(map[string]any), "protocol", "dns")

	if idx := findDirectRuleSetRule(rules, "geoip-ru"); idx < 2 {
		t.Fatalf("geoip-ru direct rule index = %d, want after DNS hijack rules", idx)
	}
	if idx := findDirectRuleSetRule(rules, "geosite-category-ru"); idx < 2 {
		t.Fatalf("geosite-category-ru direct rule index = %d, want after DNS hijack rules", idx)
	}

	ruleSets := route["rule_set"].([]any)
	assertRemoteRuleSet(t, ruleSets, "geoip-ru", "rule-set-geoip/geoip-ru.srs")
	assertRemoteRuleSet(t, ruleSets, "geosite-category-ru", "rule-set-geosite/geosite-category-ru.srs")
}

func assertDNSHijackRule(t *testing.T, rule map[string]any, matchKey, matchValue string) {
	t.Helper()
	if rule[matchKey] != matchValue || rule["action"] != "hijack-dns" {
		t.Fatalf("DNS hijack rule = %#v, want %s=%q action=hijack-dns", rule, matchKey, matchValue)
	}
}

func findDirectRuleSetRule(rules []any, tag string) int {
	for i, raw := range rules {
		rule := raw.(map[string]any)
		if rule["rule_set"] == tag && rule["outbound"] == "direct-out" {
			return i
		}
	}
	return -1
}

func assertRemoteRuleSet(t *testing.T, ruleSets []any, tag, urlPart string) {
	t.Helper()
	for _, raw := range ruleSets {
		ruleSet := raw.(map[string]any)
		if ruleSet["tag"] != tag {
			continue
		}
		if ruleSet["type"] != "remote" || ruleSet["format"] != "binary" || ruleSet["download_detour"] != "direct-out" {
			t.Fatalf("rule set %s = %#v, want remote binary downloaded via direct-out", tag, ruleSet)
		}
		if !strings.Contains(ruleSet["url"].(string), urlPart) {
			t.Fatalf("rule set %s url = %q, want to contain %q", tag, ruleSet["url"], urlPart)
		}
		return
	}
	t.Fatalf("missing route.rule_set entry for %s", tag)
}

func TestApplyUsesSingBoxServiceAndPreservesOutboundTag(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.json")
	if err := os.WriteFile(cfg, []byte(`{"outbounds":[{"tag":"proxy","type":"direct"}]}`), 0600); err != nil {
		t.Fatal(err)
	}
	var calls [][]string
	oldSystemctl := runSystemctl
	runSystemctl = func(args ...string) error { calls = append(calls, append([]string(nil), args...)); return nil }
	t.Cleanup(func() { runSystemctl = oldSystemctl })
	backup, err := Apply(cfg, dir, "sing-box-vibe-router", map[string]any{"type": "vless", "server": "example.com"})
	if err != nil {
		t.Fatal(err)
	}
	if backup == "" {
		t.Fatal("backup path empty")
	}
	wantCalls := [][]string{{"reset-failed", "sing-box-vibe-router"}, {"restart", "sing-box-vibe-router"}}
	if !reflect.DeepEqual(calls, wantCalls) {
		t.Fatalf("calls = %#v", calls)
	}
	b, err := os.ReadFile(cfg)
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatal(err)
	}
	out := got["outbounds"].([]any)[0].(map[string]any)
	if out["tag"] != "proxy" || out["type"] != "vless" {
		t.Fatalf("outbound = %#v", out)
	}
}

func TestApplyReplacesSelectedNativeOutboundNotDirect(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.json")
	if err := os.WriteFile(cfg, []byte(`{"outbounds":[{"tag":"direct-out","type":"direct"},{"tag":"selected-native-out","type":"vless","server":"old.example"}]}`), 0600); err != nil {
		t.Fatal(err)
	}
	oldSystemctl := runSystemctl
	runSystemctl = func(args ...string) error { return nil }
	t.Cleanup(func() { runSystemctl = oldSystemctl })
	_, err := Apply(cfg, dir, "sing-box-vibe-router", map[string]any{"type": "vless", "server": "new.example"})
	if err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(cfg)
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatal(err)
	}
	outbounds := got["outbounds"].([]any)
	direct := outbounds[0].(map[string]any)
	selected := outbounds[1].(map[string]any)
	if direct["tag"] != "direct-out" || direct["type"] != "direct" {
		t.Fatalf("direct outbound was changed: %#v", direct)
	}
	if selected["tag"] != "selected-native-out" || selected["type"] != "vless" || selected["server"] != "new.example" {
		t.Fatalf("selected outbound = %#v", selected)
	}
}

func TestApplyRequestFileValidatesBeforeReplace(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.json")
	old := []byte(`{"outbounds":[{"tag":"selected-native-out","type":"direct"}]}`)
	if err := os.WriteFile(cfg, old, 0600); err != nil {
		t.Fatal(err)
	}
	var checked []string
	oldRun := runCommand
	runCommand = func(name string, args ...string) error {
		checked = append(checked, append([]string{name}, args...)...)
		return nil
	}
	oldLookup := lookupIP
	lookupIP = func(host string) ([]net.IP, error) { return []net.IP{net.ParseIP("203.0.113.20")}, nil }
	t.Cleanup(func() { runCommand = oldRun; lookupIP = oldLookup })
	req := filepath.Join(dir, "run", "restart-sing-box")
	_, err := ApplyWithRestart(cfg, dir, map[string]any{"type": "vless", "server": "new.example"}, RestartConfig{Mode: RestartModeRequestFile, RequestFile: req, SingBoxBin: "sing-box"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(req); err != nil {
		t.Fatalf("restart request not written: %v", err)
	}
	if len(checked) == 0 {
		t.Fatal("candidate was not checked")
	}
	b, _ := os.ReadFile(cfg)
	if string(b) == string(old) {
		t.Fatal("config was not replaced after valid check")
	}
}

func TestApplyRequestFilePreResolvesDomainServerAndPreservesTLSName(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.json")
	if err := os.WriteFile(cfg, []byte(`{"outbounds":[{"tag":"selected-native-out","type":"direct"}]}`), 0600); err != nil {
		t.Fatal(err)
	}
	oldRun := runCommand
	runCommand = func(name string, args ...string) error { return nil }
	oldLookup := lookupIP
	lookupIP = func(host string) ([]net.IP, error) {
		if host != "node.example" {
			t.Fatalf("lookup host = %q", host)
		}
		return []net.IP{net.ParseIP("203.0.113.10")}, nil
	}
	t.Cleanup(func() { runCommand = oldRun; lookupIP = oldLookup })
	req := filepath.Join(dir, "run", "restart-sing-box")
	_, err := ApplyWithRestart(cfg, dir, map[string]any{"type": "vless", "server": "node.example", "server_port": 443, "tls": map[string]any{"enabled": true, "server_name": "node.example"}}, RestartConfig{Mode: RestartModeRequestFile, RequestFile: req, SingBoxBin: "sing-box"})
	if err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(cfg)
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatal(err)
	}
	out := got["outbounds"].([]any)[0].(map[string]any)
	if out["server"] != "203.0.113.10" {
		t.Fatalf("server was not pre-resolved: %#v", out)
	}
	tls := out["tls"].(map[string]any)
	if tls["server_name"] != "node.example" {
		t.Fatalf("tls server_name changed: %#v", tls)
	}
}

func TestApplySystemdDoesNotPreResolveDomainServer(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.json")
	if err := os.WriteFile(cfg, []byte(`{"outbounds":[{"tag":"selected-native-out","type":"direct"}]}`), 0600); err != nil {
		t.Fatal(err)
	}
	oldSystemctl := runSystemctl
	runSystemctl = func(args ...string) error { return nil }
	oldLookup := lookupIP
	lookupIP = func(host string) ([]net.IP, error) { t.Fatalf("unexpected lookup for systemd mode"); return nil, nil }
	t.Cleanup(func() { runSystemctl = oldSystemctl; lookupIP = oldLookup })
	_, err := ApplyWithRestart(cfg, dir, map[string]any{"type": "vless", "server": "node.example"}, RestartConfig{Mode: RestartModeSystemd, Service: "sing-box-vibe-router"})
	if err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(cfg)
	var got map[string]any
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatal(err)
	}
	out := got["outbounds"].([]any)[0].(map[string]any)
	if out["server"] != "node.example" {
		t.Fatalf("systemd apply changed server: %#v", out)
	}
}

func TestApplyValidationFailureLeavesConfigAndNoRequest(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.json")
	old := []byte(`{"outbounds":[{"tag":"selected-native-out","type":"direct"}]}`)
	if err := os.WriteFile(cfg, old, 0600); err != nil {
		t.Fatal(err)
	}
	oldRun := runCommand
	runCommand = func(name string, args ...string) error { return os.ErrInvalid }
	oldLookup := lookupIP
	lookupIP = func(host string) ([]net.IP, error) { return []net.IP{net.ParseIP("203.0.113.30")}, nil }
	t.Cleanup(func() { runCommand = oldRun; lookupIP = oldLookup })
	req := filepath.Join(dir, "restart")
	_, err := ApplyWithRestart(cfg, dir, map[string]any{"type": "vless"}, RestartConfig{Mode: RestartModeRequestFile, RequestFile: req, SingBoxBin: "sing-box"})
	if err == nil {
		t.Fatal("expected validation error")
	}
	b, _ := os.ReadFile(cfg)
	if string(b) != string(old) {
		t.Fatalf("config changed on validation failure: %s", b)
	}
	if _, statErr := os.Stat(req); !os.IsNotExist(statErr) {
		t.Fatalf("request file exists after validation failure: %v", statErr)
	}
}
