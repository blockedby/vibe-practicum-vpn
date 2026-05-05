package ikev2

import (
	"strings"
	"testing"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
)

func TestXFRMInstallPlanUsesConfiguredUnderlayAndPrefix(t *testing.T) {
	cfg := config.DefaultIKEv2Config()
	cfg.XFRMInterface = "ipsec-canary0"
	cfg.XFRMIfID = 77
	cfg.UnderlayInterface = "ens3"
	cfg.GatewayIP = "10.88.0.1"
	cfg.VPNSubnet = "10.88.0.0/24"

	plan, err := XFRMInstallPlan(cfg)
	if err != nil {
		t.Fatal(err)
	}
	got := plan.String()
	for _, want := range []string{
		"dry-run: would create route-based XFRM interface",
		"ip link add ipsec-canary0 type xfrm dev ens3 if_id 77",
		"ip addr add 10.88.0.1/24 dev ipsec-canary0",
		"ip link set ipsec-canary0 up",
		"note: commands are not executed by this planner",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("install plan missing %q in\n%s", want, got)
		}
	}
}

func TestXFRMInstallPlanRequiresUnderlayPlaceholder(t *testing.T) {
	cfg := config.DefaultIKEv2Config()
	plan, err := XFRMInstallPlan(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(plan.String(), "underlay_interface: not configured") {
		t.Fatalf("expected missing-underlay placeholder in\n%s", plan.String())
	}
	if strings.Contains(plan.String(), "dev eth0") {
		t.Fatalf("must not hardcode eth0 in\n%s", plan.String())
	}
}

func TestXFRMPlansRejectShellUnsafeInterfaces(t *testing.T) {
	tests := []struct {
		name   string
		mutate func(*config.IKEv2Config)
	}{
		{"xfrm semicolon slash", func(c *config.IKEv2Config) { c.XFRMInterface = "ipsec0; rm -rf /" }},
		{"underlay command substitution", func(c *config.IKEv2Config) { c.UnderlayInterface = "ens3$(touch /tmp/pwn)" }},
		{"xfrm newline", func(c *config.IKEv2Config) { c.XFRMInterface = "ipsec0\nip link delete lo" }},
		{"underlay newline", func(c *config.IKEv2Config) { c.UnderlayInterface = "ens3\nrm -rf /" }},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			cfg := config.DefaultIKEv2Config()
			cfg.UnderlayInterface = "ens3"
			tc.mutate(&cfg)
			if plan, err := XFRMInstallPlan(cfg); err == nil {
				t.Fatalf("expected unsafe interface rejection, got plan:\n%s", plan.String())
			}
		})
	}

	cfg := config.DefaultIKEv2Config()
	cfg.XFRMInterface = "ipsec0; rm -rf /"
	if plan, err := XFRMDisablePlan(cfg); err == nil {
		t.Fatalf("expected unsafe interface rejection, got plan:\n%s", plan.String())
	}
}

func TestXFRMDisablePlanOnlyTargetsIKEv2Interface(t *testing.T) {
	cfg := config.DefaultIKEv2Config()
	cfg.XFRMInterface = "ipsec0"
	plan, err := XFRMDisablePlan(cfg)
	if err != nil {
		t.Fatal(err)
	}
	got := plan.String()
	for _, want := range []string{"ip link set ipsec0 down", "ip link delete ipsec0", "tailscale/default route: untouched"} {
		if !strings.Contains(got, want) {
			t.Fatalf("disable plan missing %q in\n%s", want, got)
		}
	}
	if strings.Contains(strings.ToLower(got), "tailscale0 down") || strings.Contains(strings.ToLower(got), "default route") && strings.Contains(strings.ToLower(got), "delete default") {
		t.Fatalf("disable plan appears too broad:\n%s", got)
	}
}
