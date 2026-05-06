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
	cfg.TailnetSubnet = "100.100.0.0/16"

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
		"-d 100.100.0.0/16 -j RETURN",
		"-d 127.0.0.0/8 -j RETURN",
		"-d 169.254.0.0/16 -j RETURN",
		"-d 172.16.0.0/12 -j RETURN",
		"-d 192.168.0.0/16 -j RETURN",
		"-d 224.0.0.0/4 -j RETURN",
		"-p tcp -j TPROXY --on-port 2099 --tproxy-mark 0x63",
		"-p udp -j TPROXY --on-port 2099 --tproxy-mark 0x63",
		"ip rule add fwmark 0x63 lookup 199",
		"ip route add local 0.0.0.0/0 dev lo table 199",
		"private/tailnet destinations return before TPROXY capture",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("enable plan missing %q in\n%s", want, got)
		}
	}
	if strings.Contains(got, "tailscale0") || strings.Contains(got, "default route") {
		t.Fatalf("enable plan should not mention tailscale0/default route:\n%s", got)
	}
}

func TestRoutingBridgeEnablePlanContainsScopedForwardNATAndBypasses(t *testing.T) {
	cfg := config.DefaultIKEv2Config()
	cfg.XFRMInterface = "ipsec0"
	cfg.VPNSubnet = "10.88.0.0/24"
	cfg.TailnetInterface = "tailscale0"
	cfg.TailnetSubnet = "100.64.0.0/10"

	plan, err := RoutingBridgeEnablePlan(cfg)
	if err != nil {
		t.Fatal(err)
	}
	got := plan.String()
	for _, want := range []string{
		"dry-run: would add IKEv2-to-tailnet bridge rules",
		"iptables -w -t filter -C FORWARD -i ipsec0 -o tailscale0 -s 10.88.0.0/24 -d 100.64.0.0/10 -m comment --comment vibe-vpn-ikev2-tailnet-bridge:ipsec-to-tailnet -j ACCEPT || iptables -w -t filter -I FORWARD 1",
		"iptables -w -t filter -C FORWARD -i tailscale0 -o ipsec0 -s 100.64.0.0/10 -d 10.88.0.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment vibe-vpn-ikev2-tailnet-bridge:tailnet-established-to-ipsec -j ACCEPT",
		"iptables -w -t nat -C POSTROUTING -o tailscale0 -s 10.88.0.0/24 -d 100.64.0.0/10 -m comment --comment vibe-vpn-ikev2-tailnet-bridge:masquerade-ipsec-to-tailnet -j MASQUERADE || iptables -w -t nat -A POSTROUTING",
		"if iptables -w -t mangle -nL VIBE_ROUTER_IKEV2 >/dev/null 2>&1; then iptables -w -t mangle -C VIBE_ROUTER_IKEV2 -d 10.88.0.0/24 -m comment --comment vibe-vpn-ikev2-tailnet-bridge:bypass-vpn-subnet -j RETURN",
		"if iptables -w -t mangle -nL VIBE_ROUTER_IKEV2 >/dev/null 2>&1; then iptables -w -t mangle -C VIBE_ROUTER_IKEV2 -d 100.64.0.0/10 -m comment --comment vibe-vpn-ikev2-tailnet-bridge:bypass-tailnet-subnet -j RETURN",
		"does not change the VPS default route",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("bridge enable plan missing %q in\n%s", want, got)
		}
	}
	for _, bad := range []string{"iptables -F", "iptables -t filter -F", "iptables -t nat -F", "systemctl restart", "ip route add default"} {
		if strings.Contains(got, bad) {
			t.Fatalf("bridge enable plan contains unsafe broad action %q:\n%s", bad, got)
		}
	}
}

func TestRoutingBridgeDisablePlanDeletesOnlyExactCommentScopedRules(t *testing.T) {
	cfg := config.DefaultIKEv2Config()
	plan, err := RoutingBridgeDisablePlan(cfg)
	if err != nil {
		t.Fatal(err)
	}
	got := plan.String()
	for _, want := range []string{
		"dry-run: would remove IKEv2-to-tailnet bridge rules",
		"while iptables -w -t mangle -C VIBE_ROUTER_IKEV2 -d 100.64.0.0/10 -m comment --comment vibe-vpn-ikev2-tailnet-bridge:bypass-tailnet-subnet -j RETURN 2>/dev/null; do iptables -w -t mangle -D VIBE_ROUTER_IKEV2",
		"while iptables -w -t mangle -C VIBE_ROUTER_IKEV2 -d 10.88.0.0/24 -m comment --comment vibe-vpn-ikev2-tailnet-bridge:bypass-vpn-subnet -j RETURN 2>/dev/null; do iptables -w -t mangle -D VIBE_ROUTER_IKEV2",
		"while iptables -w -t nat -C POSTROUTING -o tailscale0 -s 10.88.0.0/24 -d 100.64.0.0/10 -m comment --comment vibe-vpn-ikev2-tailnet-bridge:masquerade-ipsec-to-tailnet -j MASQUERADE 2>/dev/null; do iptables -w -t nat -D POSTROUTING",
		"while iptables -w -t filter -C FORWARD -i tailscale0 -o ipsec0 -s 100.64.0.0/10 -d 10.88.0.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment vibe-vpn-ikev2-tailnet-bridge:tailnet-established-to-ipsec -j ACCEPT 2>/dev/null; do iptables -w -t filter -D FORWARD",
		"while iptables -w -t filter -C FORWARD -i ipsec0 -o tailscale0 -s 10.88.0.0/24 -d 100.64.0.0/10 -m comment --comment vibe-vpn-ikev2-tailnet-bridge:ipsec-to-tailnet -j ACCEPT 2>/dev/null; do iptables -w -t filter -D FORWARD",
		"leaves existing Tailscale/Hysteria/IKEv2 rules intact",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("bridge disable plan missing %q in\n%s", want, got)
		}
	}
	lower := strings.ToLower(got)
	for _, bad := range []string{"iptables -f", "iptables -t filter -f", "iptables -t nat -f", "ip route del default", "systemctl", "docker"} {
		if strings.Contains(lower, bad) {
			t.Fatalf("bridge disable plan contains broad/unrelated target %q:\n%s", bad, got)
		}
	}
}

func TestRoutingBridgeStatusPrintsAuditCommands(t *testing.T) {
	cfg := config.DefaultIKEv2Config()
	got, err := RoutingBridgeStatus(&cfg)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"bridge: ipad-ikev2-tailnet",
		"bridge_ingress_interface: ipsec0",
		"bridge_tailnet_interface: tailscale0",
		"bridge_tailnet_subnet: 100.64.0.0/10",
		"audit_commands:",
		"echo present:ipsec-to-tailnet || echo missing:ipsec-to-tailnet",
		"echo present:masquerade-ipsec-to-tailnet || echo missing:masquerade-ipsec-to-tailnet",
		"live_inspection: not implemented; no system commands executed",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("bridge status missing %q in\n%s", want, got)
		}
	}
}

func TestRoutingPlansRejectShellUnsafeConfig(t *testing.T) {
	commonTests := []struct {
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
		{"tailnet subnet command", func(c *config.IKEv2Config) { c.TailnetSubnet = "100.64.0.0/10; iptables -F" }},
	}
	for _, tc := range commonTests {
		t.Run(tc.name, func(t *testing.T) {
			cfg := config.DefaultIKEv2Config()
			tc.mutate(&cfg)
			if plan, err := RoutingEnablePlan(cfg); err == nil {
				t.Fatalf("expected unsafe routing config rejection, got plan:\n%s", plan.String())
			}
			if plan, err := RoutingDisablePlan(cfg); err == nil {
				t.Fatalf("expected unsafe routing config rejection, got plan:\n%s", plan.String())
			}
			if plan, err := RoutingBridgeEnablePlan(cfg); err == nil {
				t.Fatalf("expected unsafe bridge config rejection, got plan:\n%s", plan.String())
			}
			if plan, err := RoutingBridgeDisablePlan(cfg); err == nil {
				t.Fatalf("expected unsafe bridge disable config rejection, got plan:\n%s", plan.String())
			}
		})
	}

	bridgeOnlyTests := []struct {
		name   string
		mutate func(*config.IKEv2Config)
	}{
		{"tailnet interface semicolon", func(c *config.IKEv2Config) { c.TailnetInterface = "tailscale0; iptables -F" }},
		{"tailnet interface newline", func(c *config.IKEv2Config) { c.TailnetInterface = "tailscale0\niptables -F" }},
	}
	for _, tc := range bridgeOnlyTests {
		t.Run(tc.name, func(t *testing.T) {
			cfg := config.DefaultIKEv2Config()
			tc.mutate(&cfg)
			if plan, err := RoutingBridgeEnablePlan(cfg); err == nil {
				t.Fatalf("expected unsafe bridge config rejection, got plan:\n%s", plan.String())
			}
			if plan, err := RoutingBridgeDisablePlan(cfg); err == nil {
				t.Fatalf("expected unsafe bridge disable config rejection, got plan:\n%s", plan.String())
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
