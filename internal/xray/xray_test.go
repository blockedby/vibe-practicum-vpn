package xray

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestTempConfigUsesTestPort(t *testing.T) {
	b, err := TempConfig(map[string]any{"protocol": "freedom"}, "127.0.0.1:18080")
	if err != nil {
		t.Fatal(err)
	}
	s := string(b)
	if !strings.Contains(s, "18080") || strings.Contains(s, "10808") {
		t.Fatal(s)
	}
}

func TestApplyRestoresConfigWhenRestartFails(t *testing.T) {
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "config.json")
	orig := []byte(`{"outbounds":[{"protocol":"freedom"}],"inbounds":[]}`)
	if err := os.WriteFile(cfgPath, orig, 0644); err != nil {
		t.Fatal(err)
	}
	old := runSystemctl
	defer func() { runSystemctl = old }()
	calls := 0
	runSystemctl = func(args ...string) error {
		if len(args) == 2 && args[0] == "restart" && args[1] == "xray" {
			calls++
			if calls == 1 {
				return errors.New("boom")
			}
		}
		return nil
	}
	backup, err := Apply(cfgPath, dir, map[string]any{"protocol": "blackhole"})
	if err == nil || !strings.Contains(err.Error(), "restored backup") {
		t.Fatalf("expected restored-backup error, got backup=%q err=%v", backup, err)
	}
	got, readErr := os.ReadFile(cfgPath)
	if readErr != nil {
		t.Fatal(readErr)
	}
	if string(got) != string(orig) {
		t.Fatalf("config was not restored: %s", got)
	}
	if _, statErr := os.Stat(backup); statErr != nil {
		t.Fatalf("backup missing: %v", statErr)
	}
}

func TestRollbackUsesExactPairedBackupInsteadOfUnpairedRuntimeFile(t *testing.T) {
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "config.json")
	if err := os.WriteFile(cfgPath, []byte(`{"outbounds":[{"protocol":"freedom","marker":"old"}]}`), 0644); err != nil {
		t.Fatal(err)
	}
	old := runSystemctl
	runSystemctl = func(args ...string) error { return nil }
	t.Cleanup(func() { runSystemctl = old })
	if _, err := Apply(cfgPath, dir, map[string]any{"protocol": "blackhole", "marker": "one"}); err != nil {
		t.Fatal(err)
	}
	if _, err := Apply(cfgPath, dir, map[string]any{"protocol": "blackhole", "marker": "two"}); err != nil {
		t.Fatal(err)
	}
	unpaired := filepath.Join(dir, "backups", "xray-99999999-999999999.json")
	if err := os.WriteFile(unpaired, []byte(`{"outbounds":[{"marker":"unpaired"}]}`), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := Rollback(cfgPath, dir); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(cfgPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(got), `"marker": "one"`) || strings.Contains(string(got), "unpaired") {
		t.Fatalf("rollback selected wrong runtime backup: %s", got)
	}
}

func TestApplyWritesWinnerOnRestartSuccess(t *testing.T) {
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "config.json")
	if err := os.WriteFile(cfgPath, []byte(`{"outbounds":[{"protocol":"freedom"}]}`), 0644); err != nil {
		t.Fatal(err)
	}
	old := runSystemctl
	defer func() { runSystemctl = old }()
	runSystemctl = func(args ...string) error { return nil }
	if _, err := Apply(cfgPath, dir, map[string]any{"protocol": "blackhole"}); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(cfgPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(got), `"protocol": "blackhole"`) {
		t.Fatalf("winner not written: %s", got)
	}
}

func TestApplyPreservesFirstOutboundTag(t *testing.T) {
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "config.json")
	if err := os.WriteFile(cfgPath, []byte(`{"outbounds":[{"protocol":"freedom","tag":"proxy"}],"routing":{"rules":[{"outboundTag":"proxy"}]}}`), 0644); err != nil {
		t.Fatal(err)
	}
	old := runSystemctl
	defer func() { runSystemctl = old }()
	runSystemctl = func(args ...string) error { return nil }
	if _, err := Apply(cfgPath, dir, map[string]any{"protocol": "blackhole"}); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(cfgPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(got), `"tag": "proxy"`) {
		t.Fatalf("outbound tag not preserved: %s", got)
	}
}
