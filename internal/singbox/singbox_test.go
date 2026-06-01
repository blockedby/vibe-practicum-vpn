package singbox

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

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
	t.Cleanup(func() { runCommand = oldRun })
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

func TestApplyValidationFailureLeavesConfigAndNoRequest(t *testing.T) {
	dir := t.TempDir()
	cfg := filepath.Join(dir, "config.json")
	old := []byte(`{"outbounds":[{"tag":"selected-native-out","type":"direct"}]}`)
	if err := os.WriteFile(cfg, old, 0600); err != nil {
		t.Fatal(err)
	}
	oldRun := runCommand
	runCommand = func(name string, args ...string) error { return os.ErrInvalid }
	t.Cleanup(func() { runCommand = oldRun })
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
