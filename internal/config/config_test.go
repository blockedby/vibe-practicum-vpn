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

func TestLoadWithoutIKEv2SectionKeepsLegacyDefaults(t *testing.T) {
	p := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(p, []byte(`{"subscription_file":"/tmp/sub"}`), 0600); err != nil {
		t.Fatal(err)
	}
	c, err := Load(p)
	if err != nil {
		t.Fatal(err)
	}
	if c.IKEv2 != nil {
		t.Fatalf("absent ikev2 section should stay nil, got %+v", c.IKEv2)
	}
	if c.SubscriptionFile != "/tmp/sub" || c.XrayConfig == "" {
		t.Fatalf("legacy defaults not preserved: %+v", c)
	}
}

func TestLoadIKEv2AppliesDefaultsAndOverrides(t *testing.T) {
	p := filepath.Join(t.TempDir(), "config.json")
	body := `{"ikev2":{"enabled":true,"server_name":"vpn.example.com","xfrm_if_id":77}}`
	if err := os.WriteFile(p, []byte(body), 0600); err != nil {
		t.Fatal(err)
	}
	c, err := Load(p)
	if err != nil {
		t.Fatal(err)
	}
	if c.IKEv2 == nil {
		t.Fatal("expected ikev2 config")
	}
	if !c.IKEv2.Enabled || c.IKEv2.ServerName != "vpn.example.com" || c.IKEv2.XFRMIfID != 77 {
		t.Fatalf("overrides not applied: %+v", c.IKEv2)
	}
	if c.IKEv2.VPNSubnet != DefaultIKEv2VPNSubnet || c.IKEv2.GatewayIP != DefaultIKEv2GatewayIP || c.IKEv2.TProxyPort != DefaultIKEv2TProxyPort || c.IKEv2.TailnetInterface != DefaultIKEv2TailnetInterface || c.IKEv2.TailnetSubnet != DefaultIKEv2TailnetSubnet {
		t.Fatalf("defaults not applied: %+v", c.IKEv2)
	}
}

func TestIKEv2EnabledRequiresServerName(t *testing.T) {
	p := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(p, []byte(`{"ikev2":{"enabled":true}}`), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(p); err == nil {
		t.Fatal("expected ikev2 validation error")
	}
}
