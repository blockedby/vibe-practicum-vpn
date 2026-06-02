package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

type Duration struct{ time.Duration }

func NewDuration(d time.Duration) Duration      { return Duration{Duration: d} }
func (d Duration) String() string               { return d.Duration.String() }
func (d Duration) MarshalJSON() ([]byte, error) { return json.Marshal(d.String()) }
func (d *Duration) UnmarshalJSON(b []byte) error {
	var s string
	if err := json.Unmarshal(b, &s); err == nil {
		return d.parse(s)
	}
	var n int64
	if err := json.Unmarshal(b, &n); err != nil {
		return fmt.Errorf("duration must be a string duration")
	}
	d.Duration = time.Duration(n)
	return nil
}
func (d *Duration) UnmarshalYAML(value *yaml.Node) error { return d.parse(value.Value) }
func (d *Duration) parse(s string) error {
	parsed, err := time.ParseDuration(strings.TrimSpace(s))
	if err != nil {
		return err
	}
	d.Duration = parsed
	return nil
}

type Config struct {
	SubscriptionFile    string        `json:"subscription_file" yaml:"subscription_file"`
	ExtraNodesFile      string        `json:"extra_nodes_file" yaml:"extra_nodes_file"`
	Runtime             string        `json:"runtime" yaml:"runtime"`
	XrayBin             string        `json:"xray_bin" yaml:"xray_bin"`
	XrayConfig          string        `json:"xray_config" yaml:"xray_config"`
	SingBoxBin          string        `json:"sing_box_bin" yaml:"sing_box_bin"`
	SingBoxConfig       string        `json:"sing_box_config" yaml:"sing_box_config"`
	SingBoxService      string        `json:"sing_box_service" yaml:"sing_box_service"`
	SingBoxRestartMode  string        `json:"sing_box_restart_mode" yaml:"sing_box_restart_mode"`
	SingBoxRestartFile  string        `json:"sing_box_restart_file" yaml:"sing_box_restart_file"`
	StateDir            string        `json:"state_dir" yaml:"state_dir"`
	ProductionSocks     string        `json:"production_socks" yaml:"production_socks"`
	TestSocks           string        `json:"test_socks" yaml:"test_socks"`
	TestURL             string        `json:"test_url" yaml:"test_url"`
	TestLimitKiB        int           `json:"test_limit_kib" yaml:"test_limit_kib"`
	TestDurationSeconds int           `json:"test_duration_seconds" yaml:"test_duration_seconds"`
	TimeoutSeconds      int           `json:"timeout_seconds" yaml:"timeout_seconds"`
	Service             ServiceConfig `json:"service" yaml:"service"`
	Test                TestConfig    `json:"test" yaml:"test"`
	Health              HealthConfig  `json:"health" yaml:"health"`
	Logging             LoggingConfig `json:"logging" yaml:"logging"`
	// IKEv2 is optional and kept as a pointer so an absent section is
	// distinguishable from an explicitly configured-but-disabled section.
	IKEv2 *IKEv2Config `json:"ikev2,omitempty" yaml:"ikev2,omitempty"`
}

type ServiceMode string

const (
	ServiceModeFailoverOnly    ServiceMode = "failover-only"
	ServiceModeFastestRotation ServiceMode = "fastest-rotation"
	DefaultServiceMode                     = ServiceModeFastestRotation
)

type ServiceConfig struct {
	Enabled     bool        `json:"enabled" yaml:"enabled"`
	StartupTest bool        `json:"startup_test" yaml:"startup_test"`
	Mode        ServiceMode `json:"mode" yaml:"mode"`
}
type TestConfig struct {
	Interval Duration `json:"interval" yaml:"interval"`
}
type HealthConfig struct {
	NormalInterval     Duration   `json:"normal_interval" yaml:"normal_interval"`
	FailureRetryDelays []Duration `json:"failure_retry_delays" yaml:"failure_retry_delays"`
	ProbeTimeout       Duration   `json:"probe_timeout" yaml:"probe_timeout"`
	RequiredURLs       []string   `json:"required_urls" yaml:"required_urls"`
	DiagnosticURLs     []string   `json:"diagnostic_urls" yaml:"diagnostic_urls"`
}
type LoggingConfig struct {
	Path        string   `json:"path" yaml:"path"`
	Retention   Duration `json:"retention" yaml:"retention"`
	AlsoJournal bool     `json:"also_journal" yaml:"also_journal"`
}

type IKEv2Config struct {
	Enabled           bool   `json:"enabled" yaml:"enabled"`
	ServerName        string `json:"server_name" yaml:"server_name"`
	PublicEndpoint    string `json:"public_endpoint,omitempty" yaml:"public_endpoint,omitempty"`
	VPNSubnet         string `json:"vpn_subnet" yaml:"vpn_subnet"`
	GatewayIP         string `json:"gateway_ip" yaml:"gateway_ip"`
	XFRMInterface     string `json:"xfrm_interface" yaml:"xfrm_interface"`
	XFRMIfID          int    `json:"xfrm_if_id" yaml:"xfrm_if_id"`
	UnderlayInterface string `json:"underlay_interface,omitempty" yaml:"underlay_interface,omitempty"`
	ConfigDir         string `json:"config_dir" yaml:"config_dir"`
	StateDir          string `json:"state_dir" yaml:"state_dir"`
	SwanctlDir        string `json:"swanctl_dir" yaml:"swanctl_dir"`
	StrongSwanService string `json:"strongswan_service" yaml:"strongswan_service"`
	TProxyPort        int    `json:"tproxy_port" yaml:"tproxy_port"`
	TProxyMark        string `json:"tproxy_mark" yaml:"tproxy_mark"`
	TProxyTable       int    `json:"tproxy_table" yaml:"tproxy_table"`
	TailnetInterface  string `json:"tailnet_interface,omitempty" yaml:"tailnet_interface,omitempty"`
	TailnetSubnet     string `json:"tailnet_subnet,omitempty" yaml:"tailnet_subnet,omitempty"`
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
	return Config{
		SubscriptionFile:   "/etc/vibe-vpn/sub_url",
		ExtraNodesFile:     "/etc/vibe-vpn/extra-nodes.json",
		Runtime:            "singbox",
		XrayBin:            "/usr/local/bin/xray",
		XrayConfig:         "/usr/local/etc/xray/config.json",
		SingBoxBin:         "/usr/bin/sing-box",
		SingBoxConfig:      "/etc/sing-box-vibe/tproxy-canary.json",
		SingBoxService:     "sing-box-vibe-router",
		SingBoxRestartMode: "systemd",
		StateDir:           "/var/lib/vibe-vpn",
		ProductionSocks:    "127.0.0.1:2080",
		TestSocks:          "127.0.0.1:18080",
		TestURL:            "https://proof.ovh.net/files/10Mb.dat",
		TestLimitKiB:       512,
		TimeoutSeconds:     12,
		Service:            ServiceConfig{Enabled: true, StartupTest: true, Mode: DefaultServiceMode},
		Test:               TestConfig{Interval: NewDuration(30 * time.Minute)},
		Health: HealthConfig{
			NormalInterval:     NewDuration(5 * time.Second),
			FailureRetryDelays: []Duration{NewDuration(time.Second), NewDuration(2 * time.Second), NewDuration(3 * time.Second)},
			ProbeTimeout:       NewDuration(5 * time.Second),
			RequiredURLs:       []string{"https://x.com/", "https://www.linkedin.com/"},
			DiagnosticURLs:     []string{"https://ya.ru/"},
		},
		Logging: LoggingConfig{Path: "/var/log/vibe-vpn/", Retention: NewDuration(12 * time.Hour), AlsoJournal: true},
	}
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
	if strings.EqualFold(filepath.Ext(path), ".yaml") || strings.EqualFold(filepath.Ext(path), ".yml") {
		err = yaml.Unmarshal(b, &c)
	} else {
		err = json.Unmarshal(b, &c)
	}
	if err != nil {
		return c, err
	}
	if c.Service.Mode == "" {
		c.Service.Mode = DefaultServiceMode
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
	runtime := strings.ToLower(strings.TrimSpace(c.Runtime))
	if runtime == "" {
		runtime = "singbox"
	}
	switch runtime {
	case "singbox", "sing-box":
		if c.SingBoxBin == "" {
			return fmt.Errorf("sing_box_bin is empty")
		}
		if c.SingBoxConfig == "" {
			return fmt.Errorf("sing_box_config is empty")
		}
		if c.SingBoxService == "" {
			return fmt.Errorf("sing_box_service is empty")
		}
	case "xray":
		if c.XrayBin == "" {
			return fmt.Errorf("xray_bin is empty")
		}
		if c.XrayConfig == "" {
			return fmt.Errorf("xray_config is empty")
		}
	default:
		return fmt.Errorf("runtime must be singbox or xray")
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
	if c.TestDurationSeconds < 0 {
		return fmt.Errorf("test_duration_seconds must be non-negative")
	}
	if c.TimeoutSeconds <= 0 {
		return fmt.Errorf("timeout_seconds must be positive")
	}
	if !c.Service.Enabled { /* explicit disabled service is valid */
	}
	if c.Service.Mode == "" {
		c.Service.Mode = DefaultServiceMode
	}
	if c.Service.Mode != ServiceModeFailoverOnly && c.Service.Mode != ServiceModeFastestRotation {
		return fmt.Errorf("service.mode must be %q or %q", ServiceModeFailoverOnly, ServiceModeFastestRotation)
	}
	if c.Test.Interval.Duration <= 0 {
		return fmt.Errorf("test.interval must be positive")
	}
	if c.Health.NormalInterval.Duration <= 0 {
		return fmt.Errorf("health.normal_interval must be positive")
	}
	if c.Health.ProbeTimeout.Duration <= 0 {
		return fmt.Errorf("health.probe_timeout must be positive")
	}
	if len(c.Health.FailureRetryDelays) == 0 {
		return fmt.Errorf("health.failure_retry_delays is empty")
	}
	for i, d := range c.Health.FailureRetryDelays {
		if d.Duration <= 0 {
			return fmt.Errorf("health.failure_retry_delays[%d] must be positive", i)
		}
	}
	if len(c.Health.RequiredURLs) == 0 {
		return fmt.Errorf("health.required_urls is empty")
	}
	for i, u := range c.Health.RequiredURLs {
		if strings.TrimSpace(u) == "" {
			return fmt.Errorf("health.required_urls[%d] is empty", i)
		}
	}
	for i, u := range c.Health.DiagnosticURLs {
		if strings.TrimSpace(u) == "" {
			return fmt.Errorf("health.diagnostic_urls[%d] is empty", i)
		}
	}
	if c.Logging.Path == "" {
		return fmt.Errorf("logging.path is empty")
	}
	if c.Logging.Retention.Duration <= 0 {
		return fmt.Errorf("logging.retention must be positive")
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
