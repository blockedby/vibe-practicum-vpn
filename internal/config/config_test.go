package config

import (
	"os"
	"path/filepath"
	"testing"
	"time"
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

func TestLoadServiceFoundationDefaults(t *testing.T) {
	c := Default()
	if !c.Service.Enabled || !c.Service.StartupTest || c.Service.Mode != ServiceModeFailoverOnly {
		t.Fatalf("service defaults wrong: %+v", c.Service)
	}
	if c.Test.Interval.Duration != 30*time.Minute {
		t.Fatalf("test interval default wrong: %v", c.Test.Interval)
	}
	if c.Health.NormalInterval.Duration != 5*time.Second || c.Health.ProbeTimeout.Duration != 5*time.Second {
		t.Fatalf("health defaults wrong: %+v", c.Health)
	}
	if got := c.Health.FailureRetryDelays; len(got) != 3 || got[0].Duration != time.Second || got[1].Duration != 2*time.Second || got[2].Duration != 3*time.Second {
		t.Fatalf("retry defaults wrong: %+v", got)
	}
	if len(c.Health.RequiredURLs) != 2 || c.Health.RequiredURLs[0] != "https://x.com/" || c.Health.RequiredURLs[1] != "https://www.linkedin.com/" {
		t.Fatalf("required defaults wrong: %+v", c.Health.RequiredURLs)
	}
	if len(c.Health.DiagnosticURLs) != 1 || c.Health.DiagnosticURLs[0] != "https://ya.ru/" {
		t.Fatalf("diagnostic defaults wrong: %+v", c.Health.DiagnosticURLs)
	}
	if c.Logging.Path != "/var/log/vibe-vpn/" || c.Logging.Retention.Duration != 12*time.Hour || !c.Logging.AlsoJournal {
		t.Fatalf("logging defaults wrong: %+v", c.Logging)
	}
}

func TestLoadYAMLFailoverServiceExample(t *testing.T) {
	p := filepath.Join(t.TempDir(), "config.yaml")
	body := []byte(`service:
  enabled: true
  startup_test: true
test:
  interval: 30m
health:
  normal_interval: 5s
  failure_retry_delays:
    - 1s
    - 2s
    - 3s
  probe_timeout: 5s
  required_urls:
    - https://x.com/
    - https://www.linkedin.com/
  diagnostic_urls:
    - https://ya.ru/
logging:
  path: /var/log/vibe-vpn/
  retention: 12h
  also_journal: true
`)
	if err := os.WriteFile(p, body, 0600); err != nil {
		t.Fatal(err)
	}
	c, err := Load(p)
	if err != nil {
		t.Fatal(err)
	}
	if c.Test.Interval.Duration != 30*time.Minute || c.Logging.Retention.Duration != 12*time.Hour {
		t.Fatalf("duration parse failed: %+v", c)
	}
}

func TestLoadJSONFailoverServiceExample(t *testing.T) {
	p := filepath.Join(t.TempDir(), "config.json")
	body := `{"service":{"enabled":true,"startup_test":true},"test":{"interval":"30m"},"health":{"normal_interval":"5s","failure_retry_delays":["1s","2s","3s"],"probe_timeout":"5s","required_urls":["https://x.com/","https://www.linkedin.com/"],"diagnostic_urls":["https://ya.ru/"]},"logging":{"path":"/var/log/vibe-vpn/","retention":"12h","also_journal":true}}`
	if err := os.WriteFile(p, []byte(body), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(p); err != nil {
		t.Fatal(err)
	}
}

func TestLoadRejectsInvalidServiceFoundation(t *testing.T) {
	cases := map[string]string{
		"bad interval":        `{"test":{"interval":"nope"}}`,
		"bad service mode":    `{"service":{"mode":"rotate-maybe"}}`,
		"empty required":      `{"health":{"required_urls":[]}}`,
		"empty required item": `{"health":{"required_urls":[""]}}`,
		"bad retention":       `{"logging":{"retention":"0s"}}`,
	}
	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			p := filepath.Join(t.TempDir(), "config.json")
			if err := os.WriteFile(p, []byte(body), 0600); err != nil {
				t.Fatal(err)
			}
			if _, err := Load(p); err == nil {
				t.Fatal("expected validation/load error")
			}
		})
	}
}

func TestLoadRejectsUnsafeEmptyPath(t *testing.T) {
	p := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(p, []byte(`{"runtime":"xray","xray_config":""}`), 0600); err != nil {
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
