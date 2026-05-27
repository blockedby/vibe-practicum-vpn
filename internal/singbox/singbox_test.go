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
