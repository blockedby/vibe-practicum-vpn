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
	// IKEv2 is optional and kept as a pointer so an absent section is
	// distinguishable from an explicitly configured-but-disabled section.
	IKEv2 *IKEv2Config `json:"ikev2,omitempty"`
}

type IKEv2Config struct {
	Enabled           bool   `json:"enabled"`
	ServerName        string `json:"server_name"`
	PublicEndpoint    string `json:"public_endpoint,omitempty"`
	VPNSubnet         string `json:"vpn_subnet"`
	GatewayIP         string `json:"gateway_ip"`
	XFRMInterface     string `json:"xfrm_interface"`
	XFRMIfID          int    `json:"xfrm_if_id"`
	UnderlayInterface string `json:"underlay_interface,omitempty"`
	ConfigDir         string `json:"config_dir"`
	StateDir          string `json:"state_dir"`
	SwanctlDir        string `json:"swanctl_dir"`
	StrongSwanService string `json:"strongswan_service"`
	TProxyPort        int    `json:"tproxy_port"`
	TProxyMark        string `json:"tproxy_mark"`
	TProxyTable       int    `json:"tproxy_table"`
	TailnetInterface  string `json:"tailnet_interface,omitempty"`
	TailnetSubnet     string `json:"tailnet_subnet,omitempty"`
}

const (
	DefaultIKEv2VPNSubnet         = "10.88.0.0/24"
	DefaultIKEv2GatewayIP         = "10.88.0.1"
	DefaultIKEv2XFRMInterface     = "ipsec0"
	DefaultIKEv2XFRMIfID          = 42
	DefaultIKEv2ConfigDir         = "/etc/vibe-vpn/ikev2"
	DefaultIKEv2StateDir          = "/var/lib/vibe-vpn/ikev2"
	DefaultIKEv2SwanctlDir        = "/etc/swanctl"
	DefaultIKEv2StrongSwanService = "strongswan"
	DefaultIKEv2TProxyPort        = 2082
	DefaultIKEv2TProxyMark        = "0x88"
	DefaultIKEv2TProxyTable       = 188
	DefaultIKEv2TailnetInterface  = "tailscale0"
	DefaultIKEv2TailnetSubnet     = "100.64.0.0/10"
)

func Default() Config {
	return Config{SubscriptionFile: "/etc/vibe-vpn/sub_url", XrayBin: "/usr/local/bin/xray", XrayConfig: "/usr/local/etc/xray/config.json", StateDir: "/var/lib/vibe-vpn", ProductionSocks: "127.0.0.1:10808", TestSocks: "127.0.0.1:18080", TestURL: "https://proof.ovh.net/files/10Mb.dat", TestLimitKiB: 512, TimeoutSeconds: 12}
}

func DefaultIKEv2Config() IKEv2Config {
	return IKEv2Config{VPNSubnet: DefaultIKEv2VPNSubnet, GatewayIP: DefaultIKEv2GatewayIP, XFRMInterface: DefaultIKEv2XFRMInterface, XFRMIfID: DefaultIKEv2XFRMIfID, ConfigDir: DefaultIKEv2ConfigDir, StateDir: DefaultIKEv2StateDir, SwanctlDir: DefaultIKEv2SwanctlDir, StrongSwanService: DefaultIKEv2StrongSwanService, TProxyPort: DefaultIKEv2TProxyPort, TProxyMark: DefaultIKEv2TProxyMark, TProxyTable: DefaultIKEv2TProxyTable, TailnetInterface: DefaultIKEv2TailnetInterface, TailnetSubnet: DefaultIKEv2TailnetSubnet}
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
	if c.IKEv2 != nil {
		c.IKEv2.ApplyDefaults()
	}
	return c, c.Validate()
}

func (c *IKEv2Config) ApplyDefaults() {
	if c.PublicEndpoint == "" {
		c.PublicEndpoint = c.ServerName
	}
	if c.VPNSubnet == "" {
		c.VPNSubnet = DefaultIKEv2VPNSubnet
	}
	if c.GatewayIP == "" {
		c.GatewayIP = DefaultIKEv2GatewayIP
	}
	if c.XFRMInterface == "" {
		c.XFRMInterface = DefaultIKEv2XFRMInterface
	}
	if c.XFRMIfID == 0 {
		c.XFRMIfID = DefaultIKEv2XFRMIfID
	}
	if c.ConfigDir == "" {
		c.ConfigDir = DefaultIKEv2ConfigDir
	}
	if c.StateDir == "" {
		c.StateDir = DefaultIKEv2StateDir
	}
	if c.SwanctlDir == "" {
		c.SwanctlDir = DefaultIKEv2SwanctlDir
	}
	if c.StrongSwanService == "" {
		c.StrongSwanService = DefaultIKEv2StrongSwanService
	}
	if c.TProxyPort == 0 {
		c.TProxyPort = DefaultIKEv2TProxyPort
	}
	if c.TProxyMark == "" {
		c.TProxyMark = DefaultIKEv2TProxyMark
	}
	if c.TProxyTable == 0 {
		c.TProxyTable = DefaultIKEv2TProxyTable
	}
	if c.TailnetInterface == "" {
		c.TailnetInterface = DefaultIKEv2TailnetInterface
	}
	if c.TailnetSubnet == "" {
		c.TailnetSubnet = DefaultIKEv2TailnetSubnet
	}
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
	if c.IKEv2 != nil {
		return c.IKEv2.Validate()
	}
	return nil
}

func (c IKEv2Config) Validate() error {
	if c.Enabled && c.ServerName == "" {
		return fmt.Errorf("ikev2.server_name is required when ikev2 is enabled")
	}
	if c.VPNSubnet == "" {
		return fmt.Errorf("ikev2.vpn_subnet is empty")
	}
	if c.GatewayIP == "" {
		return fmt.Errorf("ikev2.gateway_ip is empty")
	}
	if c.XFRMInterface == "" {
		return fmt.Errorf("ikev2.xfrm_interface is empty")
	}
	if c.XFRMIfID <= 0 {
		return fmt.Errorf("ikev2.xfrm_if_id must be positive")
	}
	if c.ConfigDir == "" || c.StateDir == "" || c.SwanctlDir == "" {
		return fmt.Errorf("ikev2 directories must be non-empty")
	}
	if c.StrongSwanService == "" {
		return fmt.Errorf("ikev2.strongswan_service is empty")
	}
	if c.TProxyPort <= 0 {
		return fmt.Errorf("ikev2.tproxy_port must be positive")
	}
	if c.TProxyMark == "" {
		return fmt.Errorf("ikev2.tproxy_mark is empty")
	}
	if c.TProxyTable <= 0 {
		return fmt.Errorf("ikev2.tproxy_table must be positive")
	}
	if c.TailnetInterface == "" {
		return fmt.Errorf("ikev2.tailnet_interface is empty")
	}
	if c.TailnetSubnet == "" {
		return fmt.Errorf("ikev2.tailnet_subnet is empty")
	}
	return nil
}
