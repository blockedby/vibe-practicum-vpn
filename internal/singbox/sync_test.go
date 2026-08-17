package singbox

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"github.com/kcnc/vibe-practicum-vpn/internal/state"
)

func TestSyncFromSourcePreserveSelectedAddsAdblockPolicyAndKeepsRuntimeOutbound(t *testing.T) {
	dir := t.TempDir()
	source := filepath.Join(dir, "source.json")
	runtime := filepath.Join(dir, "runtime", "config.json")

	writeJSON(t, source, map[string]any{
		"outbounds": []any{
			map[string]any{"type": "vless", "tag": "selected-native-out", "server": "source.example", "server_port": float64(443)},
			map[string]any{"type": "direct", "tag": "direct-out"},
			map[string]any{"type": "block", "tag": "block-out"},
		},
		"route": map[string]any{
			"rules": []any{
				map[string]any{"rule_set": "vpnkit-adblock", "outbound": "block-out"},
				map[string]any{"rule_set": "vpnkit-dev-direct", "outbound": "direct-out"},
			},
			"rule_set": []any{
				map[string]any{"type": "local", "tag": "vpnkit-adblock", "format": "source", "path": "/etc/sing-box/rule-sets/vpnkit-adblock.json"},
			},
			"final": "selected-native-out",
		},
	})
	writeJSON(t, runtime, map[string]any{
		"outbounds": []any{
			map[string]any{"type": "vless", "tag": "selected-native-out", "server": "runtime.example", "server_port": float64(8443), "uuid": "00000000-0000-0000-0000-000000000000"},
			map[string]any{"type": "direct", "tag": "direct-out"},
		},
		"route": map[string]any{
			"rules": []any{map[string]any{"rule_set": "geoip-ru", "outbound": "direct-out"}},
			"final": "selected-native-out",
		},
	})

	if err := SyncFromSourcePreserveSelected(source, runtime); err != nil {
		t.Fatalf("SyncFromSourcePreserveSelected() error = %v", err)
	}

	var got map[string]any
	readJSON(t, runtime, &got)
	selected, ok := findOutbound(got, "selected-native-out")
	if !ok {
		t.Fatalf("selected-native-out missing after sync")
	}
	if selected["server"] != "runtime.example" || selected["server_port"] != float64(8443) {
		t.Fatalf("runtime selected outbound was not preserved: %#v", selected)
	}
	route := got["route"].(map[string]any)
	rules := route["rules"].([]any)
	first := rules[0].(map[string]any)
	if first["rule_set"] != "vpnkit-adblock" || first["outbound"] != "block-out" {
		t.Fatalf("adblock policy route missing/wrong after sync: %#v", first)
	}
	ruleSets := route["rule_set"].([]any)
	ruleSet := ruleSets[0].(map[string]any)
	if ruleSet["tag"] != "vpnkit-adblock" {
		t.Fatalf("adblock rule-set registration missing after sync: %#v", ruleSet)
	}
}

func TestSyncFromSourcePreserveSelectedCreatesRuntimeWhenAbsent(t *testing.T) {
	dir := t.TempDir()
	source := filepath.Join(dir, "source.json")
	runtime := filepath.Join(dir, "runtime", "config.json")
	writeJSON(t, source, map[string]any{
		"outbounds": []any{map[string]any{"type": "direct", "tag": "selected-native-out"}},
		"route":     map[string]any{"final": "selected-native-out"},
	})
	if err := SyncFromSourcePreserveSelected(source, runtime); err != nil {
		t.Fatalf("SyncFromSourcePreserveSelected() error = %v", err)
	}
	if _, err := os.Stat(runtime); err != nil {
		t.Fatalf("runtime config was not created: %v", err)
	}
}

func TestSyncUsesCrossProcessStateDirLock(t *testing.T) {
	if os.Getenv("VIBE_VPN_SYNC_LOCK_HELPER") == "1" {
		ctx, cancel := context.WithTimeout(context.Background(), 120*time.Millisecond)
		defer cancel()
		err := SyncFromSourcePreserveSelectedWithLock(ctx, os.Getenv("VIBE_VPN_SYNC_SOURCE"), os.Getenv("VIBE_VPN_SYNC_RUNTIME"), os.Getenv("VIBE_VPN_SYNC_STATE_DIR"))
		if !errors.Is(err, context.DeadlineExceeded) {
			t.Fatalf("sync helper error=%v, want lock timeout", err)
		}
		return
	}

	dir := t.TempDir()
	source := filepath.Join(dir, "source.json")
	runtime := filepath.Join(dir, "runtime", "config.json")
	writeJSON(t, source, map[string]any{"outbounds": []any{map[string]any{"tag": "selected-native-out", "type": "direct"}}})
	lock, err := state.AcquireLock(context.Background(), dir)
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(os.Args[0], "-test.run=TestSyncUsesCrossProcessStateDirLock$", "-test.v")
	cmd.Env = append(os.Environ(),
		"VIBE_VPN_SYNC_LOCK_HELPER=1",
		"VIBE_VPN_SYNC_SOURCE="+source,
		"VIBE_VPN_SYNC_RUNTIME="+runtime,
		"VIBE_VPN_SYNC_STATE_DIR="+dir,
	)
	if err := cmd.Run(); err != nil {
		_ = lock.Close()
		t.Fatalf("sync helper did not observe lock contention: %v", err)
	}
	if err := lock.Close(); err != nil {
		t.Fatal(err)
	}
	if err := SyncFromSourcePreserveSelectedWithLock(context.Background(), source, runtime, dir); err != nil {
		t.Fatalf("sync after lock release failed: %v", err)
	}
}

func writeJSON(t *testing.T, path string, v any) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, append(b, '\n'), 0644); err != nil {
		t.Fatal(err)
	}
}

func readJSON(t *testing.T, path string, v any) {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(b, v); err != nil {
		t.Fatal(err)
	}
}
