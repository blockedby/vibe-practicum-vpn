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
	for _, want := range []string{"IKEv2", "status", "doctor", "pki", "server", "xfrm", "routing", "client"} {
		if !strings.Contains(out.String(), want) {
			t.Fatalf("ikev2 help missing %q in\n%s", want, out.String())
		}
	}

	dir := t.TempDir()
	cfg := writeTestConfig(t, dir)
	for _, args := range [][]string{{"--config", cfg, "ikev2", "status"}, {"--config", cfg, "ikev2", "doctor"}} {
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

	for _, args := range [][]string{{"--config", cfg, "ikev2", "xfrm", "install"}, {"--config", cfg, "ikev2", "xfrm", "disable"}} {
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
