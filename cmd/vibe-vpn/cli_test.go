package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
	"github.com/kcnc/vibe-practicum-vpn/internal/picker"
	"github.com/kcnc/vibe-practicum-vpn/internal/state"
	"github.com/kcnc/vibe-practicum-vpn/internal/vless"
)

func TestCobraHelpMentionsSafetyAndFilters(t *testing.T) {
	cmd := newRootCommand()
	var out bytes.Buffer
	cmd.SetOut(&out)
	cmd.SetErr(&out)
	cmd.SetArgs([]string{"test", "--help"})
	if err := cmd.Execute(); err != nil {
		t.Fatal(err)
	}
	s := out.String()
	for _, want := range []string{"isolated temporary sing-box by default", "--include", "--no-default-exclude", "--min-mbps"} {
		if !strings.Contains(s, want) {
			t.Fatalf("help missing %q in\n%s", want, s)
		}
	}
}

func TestIKEv2HelpAndReadOnlyCommands(t *testing.T) {
	cmd := newRootCommand()
	var out bytes.Buffer
	cmd.SetOut(&out)
	cmd.SetErr(&out)
	cmd.SetArgs([]string{"ikev2", "--help"})
	if err := cmd.Execute(); err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"IKEv2", "status", "doctor", "smoke", "pki", "server", "xfrm", "routing", "client", "write local config/state/output files", "system/network mutations remain dry-run", "Review --config paths"} {
		if !strings.Contains(out.String(), want) {
			t.Fatalf("ikev2 help missing %q in\n%s", want, out.String())
		}
	}

	dir := t.TempDir()
	cfg := writeTestConfig(t, dir)
	for _, args := range [][]string{{"--config", cfg, "ikev2", "status"}, {"--config", cfg, "ikev2", "doctor"}, {"--config", cfg, "ikev2", "smoke"}} {
		cmd := newRootCommand()
		var got bytes.Buffer
		cmd.SetOut(&got)
		cmd.SetErr(&got)
		cmd.SetArgs(args)
		if err := cmd.Execute(); err != nil {
			t.Fatalf("%v failed: %v", args, err)
		}
		if !strings.Contains(got.String(), "ikev2") {
			t.Fatalf("%v output missing ikev2: %q", args, got.String())
		}
	}
}

func TestIKEv2PKIAndClientCommands(t *testing.T) {
	dir := t.TempDir()
	cfg := writeTestConfigWithIKEv2(t, dir)

	for _, tc := range []struct {
		args []string
		want string
	}{
		{[]string{"--config", cfg, "ikev2", "pki", "init"}, "secret_material: not printed"},
		{[]string{"--config", cfg, "ikev2", "client", "create", "phone", "--ip", "10.88.0.2", "--os", "ios"}, "created ikev2 client"},
		{[]string{"--config", cfg, "ikev2", "client", "list"}, "phone\t10.88.0.2\tios\trevoked=false"},
		{[]string{"--config", cfg, "ikev2", "client", "revoke", "phone"}, "revoked ikev2 client"},
		{[]string{"--config", cfg, "ikev2", "client", "list"}, "phone\t10.88.0.2\tios\trevoked=true"},
		{[]string{"--config", cfg, "ikev2", "server", "render", "--output-dir", filepath.Join(dir, "rendered")}, "wrote " + filepath.Join(dir, "rendered", "swanctl.conf")},
		{[]string{"--config", cfg, "ikev2", "server", "install", "--dry-run"}, "dry-run: would install " + filepath.Join(dir, "ikev2-etc", "swanctl.conf") + " to " + filepath.Join(dir, "swanctl", "swanctl.conf")},
		{[]string{"--config", cfg, "ikev2", "server", "install", "--dry-run", "--output-dir", filepath.Join(dir, "staged")}, "dry-run: staged " + filepath.Join(dir, "staged", "swanctl.conf")},
		{[]string{"--config", cfg, "ikev2", "xfrm", "status"}, "xfrm_underlay_interface: ens3"},
		{[]string{"--config", cfg, "ikev2", "xfrm", "install", "--dry-run"}, "ip link add ipsec0 type xfrm dev ens3 if_id 42"},
		{[]string{"--config", cfg, "ikev2", "xfrm", "disable", "--dry-run"}, "ip link delete ipsec0"},
		{[]string{"--config", cfg, "ikev2", "routing", "status"}, "routing_interface: ipsec0"},
		{[]string{"--config", cfg, "ikev2", "routing", "enable", "--dry-run"}, "iptables -t mangle -A VIBE_ROUTER_IKEV2 -p tcp -j TPROXY --on-port 2082 --tproxy-mark 0x88"},
		{[]string{"--config", cfg, "ikev2", "routing", "disable", "--dry-run"}, "iptables -t mangle -X VIBE_ROUTER_IKEV2"},
		{[]string{"--config", cfg, "ikev2", "routing", "bridge", "status"}, "bridge: ipad-ikev2-tailnet"},
		{[]string{"--config", cfg, "ikev2", "routing", "bridge", "enable", "--dry-run"}, "vibe-vpn-ikev2-tailnet-bridge:ipsec-to-tailnet"},
		{[]string{"--config", cfg, "ikev2", "routing", "bridge", "disable", "--dry-run"}, "while iptables -w -t filter -C FORWARD -i ipsec0 -o tailscale0"},
	} {
		cmd := newRootCommand()
		var out bytes.Buffer
		cmd.SetOut(&out)
		cmd.SetErr(&out)
		cmd.SetArgs(tc.args)
		if err := cmd.Execute(); err != nil {
			t.Fatalf("%v failed: %v\n%s", tc.args, err, out.String())
		}
		if !strings.Contains(out.String(), tc.want) {
			t.Fatalf("%v output missing %q in %q", tc.args, tc.want, out.String())
		}
	}

	for _, args := range [][]string{{"--config", cfg, "ikev2", "xfrm", "install"}, {"--config", cfg, "ikev2", "xfrm", "disable"}, {"--config", cfg, "ikev2", "routing", "enable"}, {"--config", cfg, "ikev2", "routing", "disable"}, {"--config", cfg, "ikev2", "routing", "bridge", "enable"}, {"--config", cfg, "ikev2", "routing", "bridge", "disable"}} {
		cmd := newRootCommand()
		cmd.SetArgs(args)
		if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "without --dry-run") {
			t.Fatalf("%v expected safety dry-run error, got %v", args, err)
		}
	}

	secretish := []string{
		filepath.Join(dir, "ikev2-etc", "pki", "private", ".keep"),
		filepath.Join(dir, "ikev2-state", "clients", "phone.json"),
	}
	for _, path := range secretish {
		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm() != 0600 {
			t.Fatalf("%s mode=%o", path, info.Mode().Perm())
		}
	}
}

func TestIKEv2ClientRenderAndAuditCommands(t *testing.T) {
	dir := t.TempDir()
	cfg := writeTestConfigWithIKEv2(t, dir)

	cmd := newRootCommand()
	cmd.SetArgs([]string{"--config", cfg, "ikev2", "client", "create", "phone", "--ip", "10.88.0.2", "--os", "ios"})
	if err := cmd.Execute(); err != nil {
		t.Fatal(err)
	}

	outDir := filepath.Join(dir, "profiles")
	cmd = newRootCommand()
	var out bytes.Buffer
	cmd.SetOut(&out)
	cmd.SetErr(&out)
	cmd.SetArgs([]string{"--config", cfg, "ikev2", "client", "render", "phone", "--output-dir", outDir})
	if err := cmd.Execute(); err != nil {
		t.Fatalf("render ios failed: %v\n%s", err, out.String())
	}
	mobileconfig := filepath.Join(outDir, "phone.mobileconfig")
	if !strings.Contains(out.String(), "wrote "+mobileconfig) || !strings.Contains(out.String(), "secret_material: not printed") {
		t.Fatalf("render output missing safe write notice: %q", out.String())
	}
	body, err := os.ReadFile(mobileconfig)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"PayloadType", "com.apple.security.pkcs12", "com.apple.vpn.managed", "IKEv2", "AuthenticationMethod</key><string>Certificate", "RemoteIdentifier</key><string>vibe"} {
		if !strings.Contains(string(body), want) {
			t.Fatalf("mobileconfig missing %q", want)
		}
	}
	if info, err := os.Stat(mobileconfig); err != nil {
		t.Fatal(err)
	} else if info.Mode().Perm() != 0600 {
		t.Fatalf("mobileconfig mode=%o", info.Mode().Perm())
	}
	if err := os.Chmod(mobileconfig, 0644); err != nil {
		t.Fatal(err)
	}
	cmd = newRootCommand()
	out.Reset()
	cmd.SetOut(&out)
	cmd.SetErr(&out)
	cmd.SetArgs([]string{"--config", cfg, "ikev2", "client", "render", "phone", "--output-dir", outDir})
	if err := cmd.Execute(); err != nil {
		t.Fatalf("re-render ios failed: %v\n%s", err, out.String())
	}
	if info, err := os.Stat(mobileconfig); err != nil {
		t.Fatal(err)
	} else if info.Mode().Perm() != 0600 {
		t.Fatalf("re-rendered mobileconfig mode=%o", info.Mode().Perm())
	}
	for _, forbidden := range []string{"PRIVATE KEY", "BEGIN CERTIFICATE", "vless://"} {
		if strings.Contains(string(body), forbidden) {
			t.Fatalf("mobileconfig contains forbidden material %q", forbidden)
		}
	}

	cmd = newRootCommand()
	out.Reset()
	cmd.SetOut(&out)
	cmd.SetErr(&out)
	cmd.SetArgs([]string{"--config", cfg, "ikev2", "client", "render", "phone", "--output-dir", outDir, "--format", "generic"})
	if err := cmd.Execute(); err != nil {
		t.Fatalf("render generic failed: %v\n%s", err, out.String())
	}
	generic, err := os.ReadFile(filepath.Join(outDir, "phone-ikev2-profile.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(generic), "authentication: certificate placeholders only") || !strings.Contains(string(generic), "secret_material: not printed") {
		t.Fatalf("generic profile missing safe placeholder text:\n%s", string(generic))
	}

	cmd = newRootCommand()
	out.Reset()
	cmd.SetOut(&out)
	cmd.SetErr(&out)
	cmd.SetArgs([]string{"--config", cfg, "ikev2", "client", "audit", "phone"})
	if err := cmd.Execute(); err != nil {
		t.Fatalf("audit failed: %v\n%s", err, out.String())
	}
	for _, want := range []string{"PASS client exists: phone", "PASS client not revoked", "PASS client ip in subnet", "WARN server name configured", "secret_material: not printed"} {
		if !strings.Contains(out.String(), want) {
			t.Fatalf("audit missing %q in\n%s", want, out.String())
		}
	}

	cmd = newRootCommand()
	cmd.SetArgs([]string{"--config", cfg, "ikev2", "client", "audit", "missing"})
	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "not found") {
		t.Fatalf("expected missing client audit error, got %v", err)
	}

	cmd = newRootCommand()
	cmd.SetArgs([]string{"--config", cfg, "ikev2", "client", "revoke", "phone"})
	if err := cmd.Execute(); err != nil {
		t.Fatal(err)
	}
	cmd = newRootCommand()
	cmd.SetArgs([]string{"--config", cfg, "ikev2", "client", "render", "phone", "--output-dir", outDir})
	if err := cmd.Execute(); err == nil || !strings.Contains(err.Error(), "revoked") {
		t.Fatalf("expected revoked client render error, got %v", err)
	}
}

func TestCurrentLink(t *testing.T) {
	dir := t.TempDir()
	cfg := writeTestConfig(t, dir)
	if err := state.SaveJSON(dir, "current-node.json", state.Current{Name: "n", Link: "vless://example"}); err != nil {
		t.Fatal(err)
	}
	cmd := newRootCommand()
	var out bytes.Buffer
	cmd.SetOut(&out)
	old := os.Stdout
	r, w, _ := os.Pipe()
	os.Stdout = w
	cmd.SetArgs([]string{"--config", cfg, "current", "--link"})
	err := cmd.Execute()
	w.Close()
	os.Stdout = old
	buf := new(bytes.Buffer)
	_, _ = buf.ReadFrom(r)
	if err != nil {
		t.Fatal(err)
	}
	if strings.TrimSpace(buf.String()) != "vless://example" {
		t.Fatalf("got %q", buf.String())
	}
}

func testSocksProbeListener(t *testing.T) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	t.Cleanup(func() {
		_ = ln.Close()
		close(done)
	})
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				greeting := make([]byte, 3)
				if _, err := io.ReadFull(conn, greeting); err == nil && greeting[0] == 5 {
					_, _ = conn.Write([]byte{5, 0})
				}
			}()
		}
	}()
	return ln.Addr().String()
}

func installFakeSystemdRuntime(t *testing.T, dir, configPath, effectiveBinary, configFlag string) string {
	t.Helper()
	runtime := filepath.Join(dir, "systemd-runtime")
	if err := os.WriteFile(runtime, []byte("#!/bin/sh\nfor arg in \"$@\"; do\n  [ \"$arg\" = check ] && exit 0\n  [ \"$arg\" = -test ] && exit 0\ndone\nwhile :; do sleep 1; done\n"), 0700); err != nil {
		t.Fatal(err)
	}
	pidFile := filepath.Join(dir, "systemd-runtime.pid")
	systemctl := filepath.Join(dir, "bin", "systemctl")
	script := fmt.Sprintf(`#!/bin/sh
pidfile=%q
runtime=%q
config=%q
binary=%q
flag=%q
case "${1:-}" in
  restart)
    if [ "${VIBE_VPN_XRAY_FAIL_RESTART:-0}" = 1 ]; then exit 42; fi
    if [ -s "$pidfile" ]; then kill "$(cat "$pidfile")" 2>/dev/null || true; fi
    "$runtime" run "$flag" "$config" >/dev/null 2>&1 &
    echo $! >"$pidfile"
    ;;
  stop)
    if [ -s "$pidfile" ]; then kill "$(cat "$pidfile")" 2>/dev/null || true; rm -f "$pidfile"; fi
    ;;
  is-active)
    [ -s "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null
    ;;
  show)
    case " $* " in
      *MainPID*) [ -s "$pidfile" ] && cat "$pidfile" ;;
      *ExecStart*) printf '%%s\n' "{ path=$binary ; argv[]=$binary run $flag $config ; }" ;;
      *) exit 1 ;;
    esac
    ;;
esac
exit 0
`, pidFile, runtime, configPath, effectiveBinary, configFlag)
	if err := os.WriteFile(systemctl, []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if b, err := os.ReadFile(pidFile); err == nil {
			if pid := strings.TrimSpace(string(b)); pid != "" {
				_ = exec.Command("kill", pid).Run()
			}
		}
		_ = os.Remove(pidFile)
	})
	return runtime
}

func TestApplyBestRespectsFilters(t *testing.T) {
	dir := t.TempDir()
	bin := filepath.Join(dir, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "systemctl"), []byte("#!/bin/sh\nexit 0\n"), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	cfg := writeTestConfig(t, dir)
	results := []picker.NodeResult{
		{Index: 1, Name: "fast ws", Network: "ws", Security: "tls", Mbps: 100, OK: true, Outbound: map[string]any{"tag": "proxy"}},
		{Index: 2, Name: "slower tcp", Network: "tcp", Security: "tls", Mbps: 50, OK: true, Outbound: map[string]any{"tag": "proxy"}},
	}
	b, _ := json.Marshal(results)
	if err := os.WriteFile(filepath.Join(dir, "last-results.json"), b, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "xray.json"), []byte(`{"outbounds":[{"tag":"proxy"}]}`), 0600); err != nil {
		t.Fatal(err)
	}
	installFakeSystemdRuntime(t, dir, filepath.Join(dir, "xray.json"), "/bin/echo", "-config")
	probe := testSocksProbeListener(t)
	configBytes, err := os.ReadFile(cfg)
	if err != nil {
		t.Fatal(err)
	}
	configBytes = []byte(strings.Replace(string(configBytes), "127.0.0.1:1", probe, 1))
	if err := os.WriteFile(cfg, configBytes, 0600); err != nil {
		t.Fatal(err)
	}
	cmd := newRootCommand()
	cmd.SetArgs([]string{"--config", cfg, "apply", "best", "--transport", "tcp"})
	if err := cmd.Execute(); err != nil {
		t.Fatal(err)
	}
	cur, err := state.LoadCurrent(dir)
	if err != nil {
		t.Fatal(err)
	}
	if cur.Name != "slower tcp" {
		t.Fatalf("applied %q", cur.Name)
	}
}

func writeTestConfig(t *testing.T, dir string) string {
	t.Helper()
	cfg := filepath.Join(dir, "config.json")
	body := `{"subscription_file":"` + filepath.Join(dir, "sub") + `","runtime":"xray","xray_bin":"/bin/echo","xray_config":"` + filepath.Join(dir, "xray.json") + `","state_dir":"` + dir + `","production_socks":"127.0.0.1:1","test_socks":"127.0.0.1:2","test_url":"http://example.invalid","test_limit_kib":1,"timeout_seconds":1}`
	if err := os.WriteFile(cfg, []byte(body), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "sub"), []byte("http://example.invalid"), 0600); err != nil {
		t.Fatal(err)
	}
	return cfg
}

func writeTestConfigWithIKEv2(t *testing.T, dir string) string {
	t.Helper()
	cfg := filepath.Join(dir, "config-ikev2.json")
	body := `{"subscription_file":"` + filepath.Join(dir, "sub") + `","runtime":"xray","xray_bin":"/bin/echo","xray_config":"` + filepath.Join(dir, "xray.json") + `","state_dir":"` + dir + `","production_socks":"127.0.0.1:1","test_socks":"127.0.0.1:2","test_url":"http://example.invalid","test_limit_kib":1,"timeout_seconds":1,"ikev2":{"config_dir":"` + filepath.Join(dir, "ikev2-etc") + `","state_dir":"` + filepath.Join(dir, "ikev2-state") + `","swanctl_dir":"` + filepath.Join(dir, "swanctl") + `","underlay_interface":"ens3"}}`
	if err := os.WriteFile(cfg, []byte(body), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "sub"), []byte("http://example.invalid"), 0600); err != nil {
		t.Fatal(err)
	}
	return cfg
}

func TestApplyResultSingBoxDerivesOutboundFromLink(t *testing.T) {
	dir := t.TempDir()
	bin := filepath.Join(dir, "bin")
	if err := os.Mkdir(bin, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "systemctl"), []byte("#!/bin/sh\nexit 0\n"), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	cfgPath := filepath.Join(dir, "sing-box.json")
	if err := os.WriteFile(cfgPath, []byte(`{"outbounds":[{"type":"direct","tag":"direct"},{"type":"socks","tag":"xray-socks-out","server":"127.0.0.1","server_port":10808}]}`), 0600); err != nil {
		t.Fatal(err)
	}
	c := config.Default()
	c.Runtime = "singbox"
	c.SingBoxConfig = cfgPath
	c.SingBoxService = "sing-box-test"
	c.SingBoxBin = filepath.Join(dir, "systemd-runtime")
	installFakeSystemdRuntime(t, dir, cfgPath, c.SingBoxBin, "-c")
	c.ProductionSocks = testSocksProbeListener(t)
	c.StateDir = dir
	res := picker.NodeResult{
		Name: "reality", Host: "example.com", Port: 443, Network: "tcp", Security: "reality", Mbps: 42,
		Link:     "vless://user-id@example.com:443?type=tcp&security=reality&sni=github.com&fp=chrome&pbk=public-key&sid=abcd&flow=xtls-rprx-vision#r",
		Outbound: map[string]any{"protocol": "vless", "settings": map[string]any{}, "streamSettings": map[string]any{}},
	}
	if err := applyResult(c, res); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(cfgPath)
	if err != nil {
		t.Fatal(err)
	}
	var cfg map[string]any
	if err := json.Unmarshal(b, &cfg); err != nil {
		t.Fatal(err)
	}
	out := cfg["outbounds"].([]any)[1].(map[string]any)
	if out["tag"] != "xray-socks-out" || out["type"] != "vless" || out["server"] != "example.com" || out["uuid"] != "user-id" {
		t.Fatalf("unexpected sing-box outbound: %#v", out)
	}
	if _, ok := out["protocol"]; ok {
		t.Fatalf("xray protocol key leaked into sing-box config: %#v", out)
	}
	if _, ok := out["settings"]; ok {
		t.Fatalf("xray settings key leaked into sing-box config: %#v", out)
	}
	if _, ok := out["streamSettings"]; ok {
		t.Fatalf("xray streamSettings key leaked into sing-box config: %#v", out)
	}
	tls := out["tls"].(map[string]any)
	if tls["enabled"] != true || tls["server_name"] != "github.com" {
		t.Fatalf("unexpected tls: %#v", tls)
	}
	reality := tls["reality"].(map[string]any)
	if reality["public_key"] != "public-key" || reality["short_id"] != "abcd" {
		t.Fatalf("unexpected reality: %#v", reality)
	}
}

func TestTempBenchmarkBackendDefaultsToSingBoxAndDoesNotUseProductionConfig(t *testing.T) {
	c := config.Default()
	c.Runtime = "singbox"
	c.SingBoxBin = "/bin/sing-box-test"
	c.SingBoxConfig = filepath.Join(t.TempDir(), "production.json")
	c.TestSocks = "127.0.0.1:18080"
	n, err := vless.Parse("vless://user-id@example.com:443?type=tcp&security=reality&sni=github.com&fp=chrome&pbk=public-key&sid=abcd&flow=xtls-rprx-vision#r")
	if err != nil {
		t.Fatal(err)
	}
	backend, err := tempBenchmarkBackend(c, n)
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(backend.configPath)
	if backend.bin != c.SingBoxBin || strings.Join(backend.args, " ") != "run -c "+backend.configPath {
		t.Fatalf("unexpected backend command: bin=%q args=%v", backend.bin, backend.args)
	}
	if strings.Contains(backend.configPath, c.SingBoxConfig) || !strings.Contains(filepath.Base(backend.configPath), "vibe-vpn-singbox-") {
		t.Fatalf("unexpected temp config path %q production %q", backend.configPath, c.SingBoxConfig)
	}
	b, err := os.ReadFile(backend.configPath)
	if err != nil {
		t.Fatal(err)
	}
	var cfg map[string]any
	if err := json.Unmarshal(b, &cfg); err != nil {
		t.Fatalf("temp sing-box config is not json: %v\n%s", err, b)
	}
	in := cfg["inbounds"].([]any)[0].(map[string]any)
	if in["type"] != "socks" || in["listen"] != "127.0.0.1" || in["listen_port"].(float64) != 18080 {
		t.Fatalf("unexpected inbound: %#v", in)
	}
	out := cfg["outbounds"].([]any)[0].(map[string]any)
	if out["type"] != "vless" || out["tag"] != "benchmark-out" || out["server"] != "example.com" {
		t.Fatalf("unexpected sing-box outbound: %#v", out)
	}
	if _, ok := out["protocol"]; ok {
		t.Fatalf("xray protocol key leaked into sing-box benchmark config: %#v", out)
	}
	if _, ok := out["settings"]; ok {
		t.Fatalf("xray settings key leaked into sing-box benchmark config: %#v", out)
	}
}

func TestTempBenchmarkBackendKeepsExplicitXrayRuntime(t *testing.T) {
	c := config.Default()
	c.Runtime = "xray"
	c.XrayBin = "/bin/xray-test"
	c.TestSocks = "127.0.0.1:18081"
	n, err := vless.Parse("vless://user-id@example.com:443?type=tcp&security=tls&sni=example.com#n")
	if err != nil {
		t.Fatal(err)
	}
	backend, err := tempBenchmarkBackend(c, n)
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(backend.configPath)
	if backend.bin != c.XrayBin || strings.Join(backend.args, " ") != "run -config "+backend.configPath {
		t.Fatalf("unexpected backend command: bin=%q args=%v", backend.bin, backend.args)
	}
	if !strings.Contains(filepath.Base(backend.configPath), "vibe-vpn-xray-") {
		t.Fatalf("unexpected xray temp config path: %q", backend.configPath)
	}
	b, err := os.ReadFile(backend.configPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(b), `"protocol": "vless"`) {
		t.Fatalf("expected legacy xray config, got %s", b)
	}
}
