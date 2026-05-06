package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/kcnc/vibe-practicum-vpn/internal/picker"
	"github.com/kcnc/vibe-practicum-vpn/internal/state"
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
	for _, want := range []string{"isolated temporary xray", "--include", "--no-default-exclude", "--min-mbps"} {
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
	for _, want := range []string{"PayloadType", "IKEv2", "PLACEHOLDER_CLIENT_CERT_REFERENCE_NO_PRIVATE_MATERIAL", "ClientVPNAddress</key><string>10.88.0.2"} {
		if !strings.Contains(string(body), want) {
			t.Fatalf("mobileconfig missing %q in\n%s", want, string(body))
		}
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
	body := `{"subscription_file":"` + filepath.Join(dir, "sub") + `","xray_bin":"/bin/echo","xray_config":"` + filepath.Join(dir, "xray.json") + `","state_dir":"` + dir + `","production_socks":"127.0.0.1:1","test_socks":"127.0.0.1:2","test_url":"http://example.invalid","test_limit_kib":1,"timeout_seconds":1}`
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
	body := `{"subscription_file":"` + filepath.Join(dir, "sub") + `","xray_bin":"/bin/echo","xray_config":"` + filepath.Join(dir, "xray.json") + `","state_dir":"` + dir + `","production_socks":"127.0.0.1:1","test_socks":"127.0.0.1:2","test_url":"http://example.invalid","test_limit_kib":1,"timeout_seconds":1,"ikev2":{"config_dir":"` + filepath.Join(dir, "ikev2-etc") + `","state_dir":"` + filepath.Join(dir, "ikev2-state") + `","swanctl_dir":"` + filepath.Join(dir, "swanctl") + `","underlay_interface":"ens3"}}`
	if err := os.WriteFile(cfg, []byte(body), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "sub"), []byte("http://example.invalid"), 0600); err != nil {
		t.Fatal(err)
	}
	return cfg
}
