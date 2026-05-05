package ikev2

import (
	"strings"
	"testing"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
)

func TestRoutingEnablePlanContainsBypassesAndTPROXYActions(t *testing.T) {
	cfg := config.DefaultIKEv2Config()
	cfg.XFRMInterface = "ipsec-canary0"
	cfg.VPNSubnet = "10.99.0.0/24"
	cfg.TProxyPort = 2099
	cfg.TProxyMark = "0x63"
	cfg.TProxyTable = 199

	plan, err := RoutingEnablePlan(cfg)
	if err != nil {
		t.Fatal(err)
	}
	got := plan.String()
	for _, want := range []string{
		"iptables -t mangle -N VIBE_ROUTER_IKEV2",
		"iptables -t mangle -A PREROUTING -i ipsec-canary0 -s 10.99.0.0/24 -j VIBE_ROUTER_IKEV2",
		"-d 10.99.0.0/24 -j RETURN",
		"-d 10.0.0.0/8 -j RETURN",
		"-d 100.64.0.0/10 -j RETURN",
		"-d 127.0.0.0/8 -j RETURN",
		"-d 169.254.0.0/16 -j RETURN",
		"-d 172.16.0.0/12 -j RETURN",
		"-d 192.168.0.0/16 -j RETURN",
		"-d 224.0.0.0/4 -j RETURN",
		"-p tcp -j TPROXY --on-port 2099 --tproxy-mark 0x63",
		"-p udp -j TPROXY --on-port 2099 --tproxy-mark 0x63",
		"ip rule add fwmark 0x63 lookup 199",
		"ip route add local 0.0.0.0/0 dev lo table 199",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("enable plan missing %q in\n%s", want, got)
		}
	}
	if strings.Contains(got, "tailscale0") || strings.Contains(got, "default route") {
		t.Fatalf("enable plan should not mention tailscale0/default route:\n%s", got)
	}
}

func TestRoutingPlansRejectShellUnsafeConfig(t *testing.T) {
	tests := []struct {
		name   string
		mutate func(*config.IKEv2Config)
	}{
		{"interface semicolon slash", func(c *config.IKEv2Config) { c.XFRMInterface = "ipsec0; rm -rf /" }},
		{"interface command substitution", func(c *config.IKEv2Config) { c.XFRMInterface = "ens3$(touch /tmp/pwn)" }},
		{"mark semicolon", func(c *config.IKEv2Config) { c.TProxyMark = "0x1; iptables -F" }},
		{"mark backticks", func(c *config.IKEv2Config) { c.TProxyMark = "0x1`iptables -F`" }},
		{"mark newline", func(c *config.IKEv2Config) { c.TProxyMark = "0x1\niptables -F" }},
		{"table too large", func(c *config.IKEv2Config) { c.TProxyTable = 2147483648 }},
		{"interface newline", func(c *config.IKEv2Config) { c.XFRMInterface = "ipsec0\nrm -rf /" }},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			cfg := config.DefaultIKEv2Config()
			tc.mutate(&cfg)
			if plan, err := RoutingEnablePlan(cfg); err == nil {
				t.Fatalf("expected unsafe routing config rejection, got plan:\n%s", plan.String())
			}
			if plan, err := RoutingDisablePlan(cfg); err == nil {
				t.Fatalf("expected unsafe routing config rejection, got plan:\n%s", plan.String())
			}
		})
	}
}

func TestRoutingDisablePlanOnlyTargetsIKEv2ChainHookAndRules(t *testing.T) {
	cfg := config.DefaultIKEv2Config()
	plan, err := RoutingDisablePlan(cfg)
	if err != nil {
		t.Fatal(err)
	}
	got := plan.String()
	for _, want := range []string{
		"iptables -t mangle -D PREROUTING -i ipsec0 -s 10.88.0.0/24 -j VIBE_ROUTER_IKEV2",
		"iptables -t mangle -F VIBE_ROUTER_IKEV2",
		"iptables -t mangle -X VIBE_ROUTER_IKEV2",
		"ip rule del fwmark 0x1 lookup 100",
		"ip route del local 0.0.0.0/0 dev lo table 100",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("disable plan missing %q in\n%s", want, got)
		}
	}
	lower := strings.ToLower(got)
	for _, bad := range []string{"tailscale", "vibe_router_main", "delete default", "flush prerouting"} {
		if strings.Contains(lower, bad) {
			t.Fatalf("disable plan contains broad/unrelated target %q:\n%s", bad, got)
		}
	}
}
