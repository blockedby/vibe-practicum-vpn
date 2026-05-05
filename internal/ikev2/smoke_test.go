package ikev2

import (
	"strings"
	"testing"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
)

func TestSmokePlanIsReadOnlyAndListsDryRunGates(t *testing.T) {
	cfg := config.DefaultIKEv2Config()
	cfg.ConfigDir = "/tmp/ikev2/etc"
	cfg.StateDir = "/tmp/ikev2/state"
	out := SmokePlan(&cfg)
	for _, want := range []string{
		"IKEv2 canary smoke plan",
		"NO REAL MUTATION",
		"config_dir: /tmp/ikev2/etc",
		"vibe-vpn ikev2 server install --dry-run",
		"vibe-vpn ikev2 xfrm install --dry-run",
		"vibe-vpn ikev2 routing enable --dry-run",
		"output must not contain private keys",
		"must not change tailscale0 or the VPS default route",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("smoke plan missing %q in\n%s", want, out)
		}
	}
	for _, forbidden := range []string{"vless://", "BEGIN PRIVATE KEY"} {
		if strings.Contains(out, forbidden) {
			t.Fatalf("smoke plan contains forbidden material %q", forbidden)
		}
	}
}
