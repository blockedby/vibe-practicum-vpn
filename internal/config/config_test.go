package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadSnakeCaseOverridesDefaults(t *testing.T) {
	p := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(p, []byte(`{"subscription_file":"/tmp/sub","test_limit_kib":128,"timeout_seconds":5}`), 0600); err != nil {
		t.Fatal(err)
	}
	c, err := Load(p)
	if err != nil {
		t.Fatal(err)
	}
	if c.SubscriptionFile != "/tmp/sub" || c.TestLimitKiB != 128 || c.TimeoutSeconds != 5 {
		t.Fatalf("unexpected overrides: %+v", c)
	}
	if c.XrayConfig == "" || c.TestSocks == "" {
		t.Fatalf("defaults not preserved: %+v", c)
	}
}

func TestLoadRejectsUnsafeEmptyPath(t *testing.T) {
	p := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(p, []byte(`{"xray_config":""}`), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(p); err == nil {
		t.Fatal("expected validation error")
	}
}
