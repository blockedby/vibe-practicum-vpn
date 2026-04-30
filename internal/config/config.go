package config

import (
	"encoding/json"
	"fmt"
	"os"
)

type Config struct {
	SubscriptionFile string `json:"subscription_file"`
	XrayBin          string `json:"xray_bin"`
	XrayConfig       string `json:"xray_config"`
	StateDir         string `json:"state_dir"`
	ProductionSocks  string `json:"production_socks"`
	TestSocks        string `json:"test_socks"`
	TestURL          string `json:"test_url"`
	TestLimitKiB     int    `json:"test_limit_kib"`
	TimeoutSeconds   int    `json:"timeout_seconds"`
}

func Default() Config {
	return Config{"/etc/vibe-vpn/sub_url", "/usr/local/bin/xray", "/usr/local/etc/xray/config.json", "/var/lib/vibe-vpn", "127.0.0.1:10808", "127.0.0.1:18080", "https://proof.ovh.net/files/10Mb.dat", 512, 12}
}

func Load(path string) (Config, error) {
	c := Default()
	if path == "" {
		return c, nil
	}
	b, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return c, nil
		}
		return c, err
	}
	if err := json.Unmarshal(b, &c); err != nil {
		return c, err
	}
	return c, c.Validate()
}

func (c Config) Validate() error {
	if c.SubscriptionFile == "" {
		return fmt.Errorf("subscription_file is empty")
	}
	if c.XrayBin == "" {
		return fmt.Errorf("xray_bin is empty")
	}
	if c.XrayConfig == "" {
		return fmt.Errorf("xray_config is empty")
	}
	if c.StateDir == "" {
		return fmt.Errorf("state_dir is empty")
	}
	if c.ProductionSocks == "" {
		return fmt.Errorf("production_socks is empty")
	}
	if c.TestSocks == "" {
		return fmt.Errorf("test_socks is empty")
	}
	if c.TestURL == "" {
		return fmt.Errorf("test_url is empty")
	}
	if c.TestLimitKiB <= 0 {
		return fmt.Errorf("test_limit_kib must be positive")
	}
	if c.TimeoutSeconds <= 0 {
		return fmt.Errorf("timeout_seconds must be positive")
	}
	return nil
}
