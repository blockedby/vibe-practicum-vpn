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
