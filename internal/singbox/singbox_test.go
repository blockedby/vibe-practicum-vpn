package singbox

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestDockerTemplateRoutingInvariants(t *testing.T) {
	b, err := os.ReadFile(filepath.Join("..", "..", "config", "sing-box", "config.json.template"))
	if err != nil {
		t.Fatal(err)
	}
	selectedOutbound := `{"type":"vless","tag":"selected-native-out","server":"203.0.113.10","server_port":443}`
	ruRuleSets := `{"type":"remote","tag":"geoip-ru","format":"binary","url":"https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geoip/geoip-ru.srs","download_detour":"direct-out"},{"type":"remote","tag":"geosite-category-ru","format":"binary","url":"https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geosite/geosite-category-ru.srs","download_detour":"direct-out"}`
	text := strings.ReplaceAll(string(b), "{{SELECTED_NATIVE_OUT_JSON}}", selectedOutbound)
	text = strings.ReplaceAll(text, "{{RU_RULE_SETS_JSON}}", ruRuleSets)
	if strings.Contains(text, "{{SELECTED_NATIVE_OUT_JSON}}") || strings.Contains(text, "{{RU_RULE_SETS_JSON}}") {
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
	if len(rules) < 5 {
		t.Fatalf("route.rules length = %d, want DNS hijack rules, sniff rule, plus RU direct rules", len(rules))
	}
	assertDNSHijackRule(t, rules[0].(map[string]any), "inbound", "vpnkit-dns-in")
	assertDNSHijackRule(t, rules[1].(map[string]any), "protocol", "dns")
	sniffIdx := assertRouteSniffRule(t, rules, []string{"vpnkit-redirect-in", "vpnkit-socks-in"})
	if sniffIdx != 2 {
		t.Fatalf("sniff rule index = %d, want immediately after DNS hijack rules", sniffIdx)
	}

	geoIPIdx := findDirectRuleSetRule(rules, "geoip-ru")
	if geoIPIdx <= sniffIdx {
		t.Fatalf("geoip-ru direct rule index = %d, want after sniff rule index %d", geoIPIdx, sniffIdx)
	}
	geositeIdx := findDirectRuleSetRule(rules, "geosite-category-ru")
	if geositeIdx <= sniffIdx {
		t.Fatalf("geosite-category-ru direct rule index = %d, want after sniff rule index %d", geositeIdx, sniffIdx)
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

func assertRouteSniffRule(t *testing.T, rules []any, wantInbounds []string) int {
	t.Helper()
	for i, raw := range rules {
		rule := raw.(map[string]any)
		if rule["action"] != "sniff" {
			if _, ok := rule["sniff"]; ok {
				t.Fatalf("rule %d uses deprecated sniff field instead of route action syntax: %#v", i, rule)
			}
			continue
		}
		if rule["timeout"] != "1s" {
			t.Fatalf("sniff rule timeout = %#v, want 1s", rule["timeout"])
		}
		gotRaw, ok := rule["inbound"].([]any)
		if !ok {
			t.Fatalf("sniff rule inbound = %#v, want array", rule["inbound"])
		}
		got := make([]string, 0, len(gotRaw))
		for _, v := range gotRaw {
			got = append(got, v.(string))
		}
		if !reflect.DeepEqual(got, wantInbounds) {
			t.Fatalf("sniff rule inbounds = %#v, want %#v", got, wantInbounds)
		}
		return i
	}
	t.Fatal("missing route action sniff rule")
	return -1
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

func installHealthySingBoxSystemd(t *testing.T, configPath string, calls *[][]string) {
	t.Helper()
	oldSystemctl := runSystemctl
	oldCommand := runCommand
	oldCmdline := readProcessCmdline
	oldStartTime := readProcessStartTime
	runSystemctl = func(ctx context.Context, args ...string) (string, error) {
		if calls != nil {
			*calls = append(*calls, append([]string(nil), args...))
		}
		if len(args) > 0 && args[0] == "show" {
			for _, arg := range args {
				if strings.Contains(arg, "MainPID") {
					return strconv.Itoa(os.Getpid()), nil
				}
			}
			return fmt.Sprintf("{ path=sing-box ; argv[]=sing-box run -c %s ; ignore_errors=no ; }", configPath), nil
		}
		return "", nil
	}
	runCommand = func(context.Context, string, ...string) error { return nil }
	readProcessCmdline = func(pid int) ([]string, error) {
		if pid != os.Getpid() {
			t.Fatalf("unexpected MainPID %d", pid)
		}
		return []string{"sing-box", "run", "-c", configPath}, nil
	}
	readProcessStartTime = func(int) (string, error) { return "test-start", nil }
	t.Cleanup(func() {
		runSystemctl = oldSystemctl
		runCommand = oldCommand
		readProcessCmdline = oldCmdline
		readProcessStartTime = oldStartTime
	})
}

func TestApplyUsesSingBoxServiceAndPreservesOutboundTag(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.json")
	if err := os.WriteFile(cfg, []byte(`{"outbounds":[{"tag":"proxy","type":"direct"}]}`), 0600); err != nil {
		t.Fatal(err)
	}
	var calls [][]string
	installHealthySingBoxSystemd(t, cfg, &calls)
	backup, err := Apply(cfg, dir, "sing-box-vibe-router", map[string]any{"type": "vless", "server": "example.com"})
	if err != nil {
		t.Fatal(err)
	}
	if backup == "" {
		t.Fatal("backup path empty")
	}
	wantCalls := [][]string{{"reset-failed", "sing-box-vibe-router"}, {"restart", "sing-box-vibe-router"}, {"is-active", "--quiet", "sing-box-vibe-router"}, {"show", "--no-pager", "--property=MainPID", "--value", "sing-box-vibe-router"}, {"show", "--no-pager", "--property=ExecStart", "--value", "sing-box-vibe-router"}, {"is-active", "--quiet", "sing-box-vibe-router"}, {"show", "--no-pager", "--property=MainPID", "--value", "sing-box-vibe-router"}}
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
	installHealthySingBoxSystemd(t, cfg, nil)
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

func acknowledgeRequestInTest(req, generation, next string) {
	go func() {
		deadline := time.Now().Add(time.Second)
		for time.Now().Before(deadline) {
			if b, err := os.ReadFile(req); err == nil && strings.TrimSpace(string(b)) != "" {
				token := strings.TrimSpace(string(b))
				_ = os.WriteFile(generation, []byte(next+"\n"), 0600)
				_ = os.WriteFile(generation+".ack", []byte("token="+token+"\ngeneration="+next+"\nhealth=healthy\n"), 0600)
				_ = os.Remove(req)
				return
			}
			time.Sleep(time.Millisecond)
		}
	}()
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
	runCommand = func(_ context.Context, name string, args ...string) error {
		checked = append(checked, append([]string{name}, args...)...)
		return nil
	}
	oldLookup := lookupIP
	lookupIP = func(host string) ([]net.IP, error) { return []net.IP{net.ParseIP("203.0.113.20")}, nil }
	t.Cleanup(func() { runCommand = oldRun; lookupIP = oldLookup })
	req := filepath.Join(dir, "run", "restart-sing-box")
	generation := filepath.Join(dir, "run", "generation")
	if err := os.MkdirAll(filepath.Dir(generation), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(generation, []byte("1\n"), 0600); err != nil {
		t.Fatal(err)
	}
	acknowledgeRequestInTest(req, generation, "2")
	_, err := ApplyWithRestart(cfg, dir, map[string]any{"type": "vless", "server": "new.example"}, RestartConfig{Mode: RestartModeRequestFile, RequestFile: req, AckGenerationFile: generation, SingBoxBin: "sing-box", AckTimeout: time.Second})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(req); !os.IsNotExist(err) {
		t.Fatalf("restart request was not consumed: %v", err)
	}
	if len(checked) == 0 {
		t.Fatal("candidate was not checked")
	}
	b, _ := os.ReadFile(cfg)
	if string(b) == string(old) {
		t.Fatal("config was not replaced after valid check")
	}
}

func TestRequestFileRequiresGenerationHealthProtocol(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.json")
	old := []byte(`{"outbounds":[{"tag":"selected-native-out","type":"direct"}]}`)
	if err := os.WriteFile(cfg, old, 0600); err != nil {
		t.Fatal(err)
	}
	oldRun := runCommand
	runCommand = func(context.Context, string, ...string) error { return nil }
	oldLookup := lookupIP
	lookupIP = func(string) ([]net.IP, error) { return nil, nil }
	t.Cleanup(func() { runCommand = oldRun; lookupIP = oldLookup })
	_, err := ApplyWithRestart(cfg, dir, map[string]any{"type": "vless", "server": "203.0.113.21"}, RestartConfig{Mode: RestartModeRequestFile, RequestFile: filepath.Join(dir, "run", "restart")})
	if err == nil || !strings.Contains(err.Error(), "generation acknowledgement is required") {
		t.Fatalf("expected request-file protocol validation failure, got %v", err)
	}
	if got, readErr := os.ReadFile(cfg); readErr != nil || string(got) != string(old) {
		t.Fatalf("config changed without health protocol: %q err=%v", got, readErr)
	}
}

func TestApplyRequestFilePreResolvesDomainServerAndPreservesTLSName(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.json")
	if err := os.WriteFile(cfg, []byte(`{"outbounds":[{"tag":"selected-native-out","type":"direct"}]}`), 0600); err != nil {
		t.Fatal(err)
	}
	oldRun := runCommand
	runCommand = func(context.Context, string, ...string) error { return nil }
	oldLookup := lookupIP
	lookupIP = func(host string) ([]net.IP, error) {
		if host != "node.example" {
			t.Fatalf("lookup host = %q", host)
		}
		return []net.IP{net.ParseIP("203.0.113.10")}, nil
	}
	t.Cleanup(func() { runCommand = oldRun; lookupIP = oldLookup })
	req := filepath.Join(dir, "run", "restart-sing-box")
	generation := filepath.Join(dir, "run", "generation")
	if err := os.MkdirAll(filepath.Dir(generation), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(generation, []byte("1\n"), 0600); err != nil {
		t.Fatal(err)
	}
	acknowledgeRequestInTest(req, generation, "2")
	_, err := ApplyWithRestart(cfg, dir, map[string]any{"type": "vless", "server": "node.example", "server_port": 443, "tls": map[string]any{"enabled": true, "server_name": "node.example"}}, RestartConfig{Mode: RestartModeRequestFile, RequestFile: req, AckGenerationFile: generation, SingBoxBin: "sing-box", AckTimeout: time.Second})
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

func TestSystemdRestartSuccessButInactiveFailsClosed(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.json")
	old := []byte(`{"outbounds":[{"tag":"selected-native-out","type":"direct"}]}`)
	if err := os.WriteFile(cfg, old, 0600); err != nil {
		t.Fatal(err)
	}
	oldSystemctl := runSystemctl
	oldCommand := runCommand
	runSystemctl = func(_ context.Context, args ...string) (string, error) {
		if len(args) >= 1 && args[0] == "is-active" {
			return "", os.ErrProcessDone
		}
		return "", nil
	}
	runCommand = func(context.Context, string, ...string) error { return nil }
	t.Cleanup(func() { runSystemctl = oldSystemctl; runCommand = oldCommand })
	start := time.Now()
	_, err := ApplyWithRestartContext(context.Background(), cfg, dir, map[string]any{"type": "vless", "server": "new.example"}, RestartConfig{
		Mode:          RestartModeSystemd,
		Service:       "sing-box-test",
		HealthTimeout: 50 * time.Millisecond,
	})
	if err == nil || !strings.Contains(err.Error(), "not active") {
		t.Fatalf("expected inactive systemd health failure, got %v", err)
	}
	if time.Since(start) > time.Second {
		t.Fatalf("inactive health failure was not bounded: %v", time.Since(start))
	}
	got, readErr := os.ReadFile(cfg)
	if readErr != nil || string(got) != string(old) {
		t.Fatalf("candidate config was not compensated: %q err=%v", got, readErr)
	}
}

func TestSystemdIdentityRejectsWrongCmdlineConfigEvenWithValidOfflineCheck(t *testing.T) {
	dir := t.TempDir()
	configured := filepath.Join(dir, "configured.json")
	wrong := filepath.Join(dir, "wrong.json")
	for _, path := range []string{configured, wrong} {
		if err := os.WriteFile(path, []byte(`{"outbounds":[]}`), 0600); err != nil {
			t.Fatal(err)
		}
	}
	oldSystemctl := runSystemctl
	oldCommand := runCommand
	oldCmdline := readProcessCmdline
	oldStartTime := readProcessStartTime
	readProcessStartTime = func(int) (string, error) { return "test-start", nil }
	runSystemctl = func(_ context.Context, args ...string) (string, error) {
		if len(args) > 0 && args[0] == "show" {
			for _, arg := range args {
				if strings.Contains(arg, "MainPID") {
					return "4242", nil
				}
			}
			return fmt.Sprintf("{ path=sing-box ; argv[]=sing-box run --config %s ; }", configured), nil
		}
		return "", nil
	}
	runCommand = func(context.Context, string, ...string) error { return nil }
	readProcessCmdline = func(int) ([]string, error) {
		return []string{"sing-box", "run", "-c", wrong}, nil
	}
	t.Cleanup(func() {
		runSystemctl = oldSystemctl
		runCommand = oldCommand
		readProcessCmdline = oldCmdline
		readProcessStartTime = oldStartTime
	})
	if err := restartSingBoxSystemdContext(context.Background(), RestartConfig{
		Service: "sing-box-test", ConfigPath: configured, SingBoxBin: "sing-box", HealthTimeout: time.Second,
	}); err == nil || !strings.Contains(err.Error(), "does not match configured path") {
		t.Fatalf("wrong MainPID config was accepted: %v", err)
	}
}

func TestSystemdIdentityRejectsWrongExecStartConfigWithStaleSocks(t *testing.T) {
	dir := t.TempDir()
	configured := filepath.Join(dir, "configured.json")
	wrong := filepath.Join(dir, "wrong.json")
	for _, path := range []string{configured, wrong} {
		if err := os.WriteFile(path, []byte(`{"outbounds":[]}`), 0600); err != nil {
			t.Fatal(err)
		}
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	go func() {
		conn, acceptErr := listener.Accept()
		if acceptErr != nil {
			return
		}
		defer conn.Close()
		buf := make([]byte, 3)
		_, _ = conn.Read(buf)
		_, _ = conn.Write([]byte{5, 0})
	}()
	oldSystemctl := runSystemctl
	oldCommand := runCommand
	oldCmdline := readProcessCmdline
	oldStartTime := readProcessStartTime
	readProcessStartTime = func(int) (string, error) { return "test-start", nil }
	runSystemctl = func(_ context.Context, args ...string) (string, error) {
		if len(args) > 0 && args[0] == "show" {
			for _, arg := range args {
				if strings.Contains(arg, "MainPID") {
					return "4242", nil
				}
			}
			return fmt.Sprintf("{ path=sing-box ; argv[]=sing-box run -c %s ; }", wrong), nil
		}
		return "", nil
	}
	runCommand = func(context.Context, string, ...string) error { return nil }
	readProcessCmdline = func(int) ([]string, error) {
		return []string{"sing-box", "run", "-c", wrong}, nil
	}
	t.Cleanup(func() {
		runSystemctl = oldSystemctl
		runCommand = oldCommand
		readProcessCmdline = oldCmdline
		readProcessStartTime = oldStartTime
	})
	if err := restartSingBoxSystemdContext(context.Background(), RestartConfig{
		Service: "sing-box-test", ConfigPath: configured, SingBoxBin: "sing-box", ProbeAddress: listener.Addr().String(), HealthTimeout: time.Second,
	}); err == nil || !strings.Contains(err.Error(), "does not match configured path") {
		t.Fatalf("wrong config with a healthy stale SOCKS listener was accepted: %v", err)
	}
}

func TestSingBoxConfigFlagFormsAreStrictlyRecognized(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "config.json")
	if err := os.WriteFile(path, []byte(`{}`), 0600); err != nil {
		t.Fatal(err)
	}
	wantFile, err := canonicalConfigPath(path)
	if err != nil {
		t.Fatal(err)
	}
	for _, args := range [][]string{
		{"sing-box", "run", "-c", path},
		{"sing-box", "run", "--config", path},
		{"sing-box", "run", "-c=" + path},
		{"sing-box", "run", "--config=" + path},
	} {
		if err := validateSingBoxInvocation(args, wantFile, "sing-box"); err != nil {
			t.Errorf("args %v rejected: %v", args, err)
		}
	}

	configDir := filepath.Join(root, "configs")
	if err := os.Mkdir(configDir, 0700); err != nil {
		t.Fatal(err)
	}
	wantDir, err := canonicalConfigPath(configDir)
	if err != nil {
		t.Fatal(err)
	}
	for _, args := range [][]string{
		{"sing-box", "run", "-C", configDir},
		{"sing-box", "run", "--config-directory", configDir},
		{"sing-box", "run", "-C=" + configDir},
		{"sing-box", "run", "--config-directory=" + configDir},
	} {
		if err := validateSingBoxInvocation(args, wantDir, "sing-box"); err != nil {
			t.Errorf("directory args %v rejected: %v", args, err)
		}
	}
	for _, args := range [][]string{
		{"sing-box", "run", "-c", path, "-C", configDir},
		{"sing-box", "run", "-C", configDir, "--config", path},
		{"sing-box", "run", "--config-dir", configDir},
	} {
		if err := validateSingBoxInvocation(args, wantFile, "sing-box"); err == nil {
			t.Errorf("ambiguous or unsupported args were accepted: %v", args)
		}
	}
}

func TestSingBoxCheckUsesDirectoryFlag(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "configs")
	if err := os.Mkdir(dir, 0700); err != nil {
		t.Fatal(err)
	}
	old := runCommand
	var got []string
	runCommand = func(_ context.Context, _ string, args ...string) error {
		got = append([]string(nil), args...)
		return nil
	}
	t.Cleanup(func() { runCommand = old })
	if err := CheckContext(context.Background(), "sing-box", dir); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, []string{"check", "-C", dir}) {
		t.Fatalf("check args=%v, want check -C %s", got, dir)
	}
}

func TestSingBoxEscapedExecStartConfigPath(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "config dir")
	if err := os.Mkdir(dir, 0700); err != nil {
		t.Fatal(err)
	}
	want, err := canonicalConfigPath(dir)
	if err != nil {
		t.Fatal(err)
	}
	raw := fmt.Sprintf("{ path=sing-box ; argv[]=sing-box run --config-directory %s ; ignore_errors=no ; }", strings.ReplaceAll(dir, " ", `\x20`))
	args, err := parseExecStartArgs(raw)
	if err != nil {
		t.Fatal(err)
	}
	if err := validateSingBoxInvocation(args, want, "sing-box"); err != nil {
		t.Fatalf("escaped ExecStart args=%v rejected: %v", args, err)
	}
}

func TestApplySystemdDoesNotPreResolveDomainServer(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.json")
	if err := os.WriteFile(cfg, []byte(`{"outbounds":[{"tag":"selected-native-out","type":"direct"}]}`), 0600); err != nil {
		t.Fatal(err)
	}
	installHealthySingBoxSystemd(t, cfg, nil)
	oldLookup := lookupIP
	lookupIP = func(host string) ([]net.IP, error) { t.Fatalf("unexpected lookup for systemd mode"); return nil, nil }
	t.Cleanup(func() { lookupIP = oldLookup })
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

func TestRequestFileWaitsForGenerationAcknowledgement(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.json")
	if err := os.WriteFile(cfg, []byte(`{"outbounds":[{"tag":"selected-native-out","type":"direct"}]}`), 0600); err != nil {
		t.Fatal(err)
	}
	req := filepath.Join(dir, "run", "restart")
	generation := filepath.Join(dir, "run", "generation")
	if err := os.MkdirAll(filepath.Dir(generation), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(generation, []byte("7\n"), 0600); err != nil {
		t.Fatal(err)
	}
	oldLookup := lookupIP
	lookupIP = func(string) ([]net.IP, error) { return nil, nil }
	t.Cleanup(func() { lookupIP = oldLookup })
	go func() {
		deadline := time.Now().Add(time.Second)
		for time.Now().Before(deadline) {
			if b, err := os.ReadFile(req); err == nil && len(strings.TrimSpace(string(b))) > 0 {
				token := strings.TrimSpace(string(b))
				_ = os.WriteFile(generation, []byte("8\n"), 0600)
				_ = os.WriteFile(generation+".ack", []byte("token="+token+"\ngeneration=8\nhealth=healthy\n"), 0600)
				_ = os.Remove(req)
				return
			}
			time.Sleep(time.Millisecond)
		}
	}()
	if _, err := ApplyWithRestartContext(context.Background(), cfg, dir, map[string]any{"type": "vless", "server": "203.0.113.10"}, RestartConfig{
		Mode:              RestartModeRequestFile,
		RequestFile:       req,
		AckGenerationFile: generation,
		AckTimeout:        time.Second,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(req); !os.IsNotExist(err) {
		t.Fatalf("request file was not consumed: %v", err)
	}
	got, err := os.ReadFile(generation)
	if err != nil || strings.TrimSpace(string(got)) != "8" {
		t.Fatalf("generation=%q err=%v, want 8", got, err)
	}
	ack, err := os.ReadFile(generation + ".ack")
	if err != nil || !strings.Contains(string(ack), "health=healthy") {
		t.Fatalf("health acknowledgement=%q err=%v", ack, err)
	}
}

func TestRequestFileConsumedAndGenerationChangedWithoutHealthAckFails(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.json")
	old := []byte(`{"outbounds":[{"tag":"selected-native-out","type":"direct"}]}`)
	if err := os.WriteFile(cfg, old, 0600); err != nil {
		t.Fatal(err)
	}
	generation := filepath.Join(dir, "run", "generation")
	req := filepath.Join(dir, "run", "restart")
	if err := os.MkdirAll(filepath.Dir(generation), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(generation, []byte("1\n"), 0600); err != nil {
		t.Fatal(err)
	}
	go func() {
		deadline := time.Now().Add(time.Second)
		for time.Now().Before(deadline) {
			if b, err := os.ReadFile(req); err == nil && strings.TrimSpace(string(b)) != "" {
				_ = os.WriteFile(generation, []byte("2\n"), 0600)
				_ = os.Remove(req)
				return
			}
			time.Sleep(time.Millisecond)
		}
	}()
	_, err := ApplyWithRestartContext(context.Background(), cfg, dir, map[string]any{"type": "vless", "server": "203.0.113.12"}, RestartConfig{
		Mode:              RestartModeRequestFile,
		RequestFile:       req,
		AckGenerationFile: generation,
		AckTimeout:        30 * time.Millisecond,
	})
	if err == nil || !strings.Contains(err.Error(), "acknowledgement timed out") {
		t.Fatalf("expected health-ack timeout, got %v", err)
	}
	got, readErr := os.ReadFile(cfg)
	if readErr != nil || string(got) != string(old) {
		t.Fatalf("config was not restored after missing health ack: %q err=%v", got, readErr)
	}
}

func TestRequestFileStaleHealthAckCannotSatisfyNewToken(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.json")
	if err := os.WriteFile(cfg, []byte(`{"outbounds":[{"tag":"selected-native-out","type":"direct"}]}`), 0600); err != nil {
		t.Fatal(err)
	}
	generation := filepath.Join(dir, "run", "generation")
	req := filepath.Join(dir, "run", "restart")
	if err := os.MkdirAll(filepath.Dir(generation), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(generation, []byte("4\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(generation+".ack", []byte("token=old-token\ngeneration=5\nhealth=healthy\n"), 0600); err != nil {
		t.Fatal(err)
	}
	go func() {
		deadline := time.Now().Add(time.Second)
		for time.Now().Before(deadline) {
			if b, err := os.ReadFile(req); err == nil && strings.TrimSpace(string(b)) != "" {
				_ = os.WriteFile(generation, []byte("5\n"), 0600)
				_ = os.Remove(req)
				return
			}
			time.Sleep(time.Millisecond)
		}
	}()
	_, err := ApplyWithRestartContext(context.Background(), cfg, dir, map[string]any{"type": "vless", "server": "203.0.113.13"}, RestartConfig{
		Mode:              RestartModeRequestFile,
		RequestFile:       req,
		AckGenerationFile: generation,
		AckTimeout:        30 * time.Millisecond,
	})
	if err == nil || !strings.Contains(err.Error(), "acknowledgement timed out") {
		t.Fatalf("expected stale health-ack timeout, got %v", err)
	}
}

func TestRequestFileAckTimeoutRestoresConfigAndLeavesAsyncRollbackRequest(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.json")
	old := []byte(`{"outbounds":[{"tag":"selected-native-out","type":"direct"}]}`)
	if err := os.WriteFile(cfg, old, 0600); err != nil {
		t.Fatal(err)
	}
	req := filepath.Join(dir, "run", "restart")
	generation := filepath.Join(dir, "run", "generation")
	if err := os.MkdirAll(filepath.Dir(generation), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(generation, []byte("1\n"), 0600); err != nil {
		t.Fatal(err)
	}
	start := time.Now()
	_, err := ApplyWithRestartContext(context.Background(), cfg, dir, map[string]any{"type": "vless", "server": "203.0.113.11"}, RestartConfig{
		Mode:              RestartModeRequestFile,
		RequestFile:       req,
		AckGenerationFile: generation,
		AckTimeout:        20 * time.Millisecond,
	})
	if err == nil || !strings.Contains(err.Error(), "acknowledgement timed out") {
		t.Fatalf("expected bounded acknowledgement failure, got %v", err)
	}
	if time.Since(start) > 500*time.Millisecond {
		t.Fatalf("acknowledgement wait was not bounded: %v", time.Since(start))
	}
	got, readErr := os.ReadFile(cfg)
	if readErr != nil || string(got) != string(old) {
		t.Fatalf("config was not restored: %q err=%v", got, readErr)
	}
	request, readErr := os.ReadFile(req)
	if readErr != nil || strings.TrimSpace(string(request)) == "" {
		t.Fatalf("rollback request is missing or empty: %q err=%v", request, readErr)
	}
}

func TestRollbackUsesExactPairedBackupInsteadOfUnpairedRuntimeFile(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.json")
	if err := os.WriteFile(cfg, []byte(`{"outbounds":[{"tag":"selected-native-out","marker":"old"}]}`), 0600); err != nil {
		t.Fatal(err)
	}
	installHealthySingBoxSystemd(t, cfg, nil)
	if _, err := Apply(cfg, dir, "sing-box", map[string]any{"type": "direct", "marker": "one"}); err != nil {
		t.Fatal(err)
	}
	if _, err := Apply(cfg, dir, "sing-box", map[string]any{"type": "direct", "marker": "two"}); err != nil {
		t.Fatal(err)
	}
	unpaired := filepath.Join(dir, "backups", "sing-box-99999999-999999999.json")
	if err := os.WriteFile(unpaired, []byte(`{"outbounds":[{"marker":"unpaired"}]}`), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := Rollback(cfg, dir, "unused"); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(got), `"marker": "one"`) || strings.Contains(string(got), "unpaired") {
		t.Fatalf("rollback selected wrong runtime backup: %s", got)
	}
}

func TestCanceledSystemdRestartStopsOnlyConfiguredUnit(t *testing.T) {
	configPath := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(configPath, []byte(`{"outbounds":[]}`), 0600); err != nil {
		t.Fatal(err)
	}
	oldSystemctl := runSystemctl
	oldCommand := runCommand
	var calls [][]string
	runSystemctl = func(ctx context.Context, args ...string) (string, error) {
		calls = append(calls, append([]string(nil), args...))
		if len(args) > 0 && args[0] == "restart" {
			<-ctx.Done()
			return "", ctx.Err()
		}
		return "", nil
	}
	runCommand = func(context.Context, string, ...string) error { return nil }
	t.Cleanup(func() { runSystemctl = oldSystemctl; runCommand = oldCommand })
	if err := restartSingBoxSystemdContext(context.Background(), RestartConfig{Service: "sing-box-test", ConfigPath: configPath, SingBoxBin: "sing-box", HealthTimeout: 30 * time.Millisecond}); err == nil {
		t.Fatal("blocking restart unexpectedly succeeded")
	}
	want := [][]string{{"reset-failed", "sing-box-test"}, {"restart", "sing-box-test"}, {"stop", "sing-box-test"}}
	if !reflect.DeepEqual(calls, want) {
		t.Fatalf("systemd cancellation calls=%#v, want only configured unit stop", calls)
	}
}

func TestRunExternalTerminatesBlockingSystemctlDescendant(t *testing.T) {
	dir := t.TempDir()
	marker := filepath.Join(dir, "late-restart")
	fake := filepath.Join(dir, "systemctl")
	script := "#!/bin/sh\n( trap '' TERM; sleep 0.2; printf late > \"$1\" ) &\nwhile :; do sleep 1; done\n"
	if err := os.WriteFile(fake, []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	start := time.Now()
	if err := runExternal(ctx, fake, marker); err == nil {
		t.Fatal("blocking fake systemctl unexpectedly succeeded")
	}
	if elapsed := time.Since(start); elapsed > time.Second {
		t.Fatalf("context cancellation did not terminate systemctl process group: %v", elapsed)
	}
	time.Sleep(350 * time.Millisecond)
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Fatalf("systemctl descendant performed a late restart side effect: %v", err)
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
	runCommand = func(context.Context, string, ...string) error { return os.ErrInvalid }
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

func TestParseProcStatStartTimeHandlesSpacesAndParentheses(t *testing.T) {
	fields := make([]string, 20)
	for i := range fields {
		fields[i] = strconv.Itoa(i)
	}
	fields[0] = "S"
	fields[19] = "987654321"
	got, err := parseProcStatStartTime("123 (sing-box worker (blue) unit) " + strings.Join(fields, " "))
	if err != nil {
		t.Fatal(err)
	}
	if got != "987654321" {
		t.Fatalf("start time=%q, want 987654321", got)
	}
}

func TestSingBoxIdentityMustRemainStableAfterProbe(t *testing.T) {
	for _, mode := range []string{"exit", "reuse", "switch"} {
		t.Run(mode, func(t *testing.T) {
			configPath := filepath.Join(t.TempDir(), "config.json")
			if err := os.WriteFile(configPath, []byte(`{"outbounds":[]}`), 0600); err != nil {
				t.Fatal(err)
			}
			var phase atomic.Int32
			oldSystemctl := runSystemctl
			oldCommand := runCommand
			oldCmdline := readProcessCmdline
			oldStartTime := readProcessStartTime
			runSystemctl = func(_ context.Context, args ...string) (string, error) {
				if len(args) == 0 {
					return "", nil
				}
				switch args[0] {
				case "is-active":
					if mode == "exit" && phase.Load() == 1 {
						return "", fmt.Errorf("unit exited")
					}
					return "", nil
				case "show":
					for _, arg := range args {
						if strings.Contains(arg, "MainPID") {
							if mode == "switch" && phase.Load() == 1 {
								return "200", nil
							}
							return "100", nil
						}
					}
					return fmt.Sprintf("{ path=sing-box ; argv[]=sing-box run -c %s ; }", configPath), nil
				}
				return "", nil
			}
			runCommand = func(context.Context, string, ...string) error { return nil }
			readProcessCmdline = func(int) ([]string, error) {
				return []string{"sing-box", "run", "-c", configPath}, nil
			}
			readProcessStartTime = func(int) (string, error) {
				if mode == "reuse" && phase.Load() == 1 {
					return "new-start", nil
				}
				return "old-start", nil
			}
			probeServer := startSingBoxIdentityProbeServer(t, func() { phase.Store(1) })
			defer probeServer.stop()
			t.Cleanup(func() {
				runSystemctl = oldSystemctl
				runCommand = oldCommand
				readProcessCmdline = oldCmdline
				readProcessStartTime = oldStartTime
			})
			restart := RestartConfig{Service: "sing-box-test", ConfigPath: configPath, SingBoxBin: "sing-box", ProbeAddress: probeServer.address, HealthTimeout: time.Second}
			if err := verifySingBoxSystemdHealth(context.Background(), restart, runSystemctl, runCommand); err == nil {
				t.Fatalf("identity mutation %q was accepted", mode)
			}
		})
	}
}

type singBoxIdentityProbeServer struct {
	address string
	stop    func()
}

func startSingBoxIdentityProbeServer(t *testing.T, mutate func()) singBoxIdentityProbeServer {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		buf := make([]byte, 3)
		if _, err := io.ReadFull(conn, buf); err != nil {
			return
		}
		mutate()
		_, _ = conn.Write([]byte{5, 0})
	}()
	return singBoxIdentityProbeServer{address: listener.Addr().String(), stop: func() {
		_ = listener.Close()
		select {
		case <-done:
		case <-time.After(time.Second):
			t.Error("identity probe server did not stop")
		}
	}}
}
