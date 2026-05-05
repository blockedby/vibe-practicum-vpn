package ikev2

import (
	"strings"
	"testing"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
)

func TestEffectiveDefaultsForAbsentConfig(t *testing.T) {
	eff := EffectiveConfig(nil)
	if eff.Configured {
		t.Fatal("absent ikev2 section should not be configured")
	}
	if eff.Enabled {
		t.Fatal("absent ikev2 section should default disabled")
	}
	if eff.VPNSubnet != config.DefaultIKEv2VPNSubnet || eff.GatewayIP != config.DefaultIKEv2GatewayIP || eff.XFRMInterface != config.DefaultIKEv2XFRMInterface {
		t.Fatalf("defaults not applied: %+v", eff.IKEv2Config)
	}
}

func TestStatusOutputIsDryAndStable(t *testing.T) {
	out := Status(nil)
	for _, want := range []string{"ikev2: configured=false enabled=false", "vpn_subnet: 10.88.0.0/24", "xfrm_interface: ipsec0", "runtime checks are not implemented"} {
		if !strings.Contains(out, want) {
			t.Fatalf("status missing %q in\n%s", want, out)
		}
	}
}

func TestDoctorValidatesConfigOnly(t *testing.T) {
	bad := config.DefaultIKEv2Config()
	bad.Enabled = true
	bad.ServerName = ""
	out, err := Doctor(&bad)
	if err == nil {
		t.Fatal("expected validation error")
	}
	if !strings.Contains(out, "ikev2 doctor: FAIL") || !strings.Contains(out, "server_name") {
		t.Fatalf("unexpected doctor output: %q err=%v", out, err)
	}
}
