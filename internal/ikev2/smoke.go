package ikev2

import (
	"fmt"
	"strings"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
)

func SmokePlan(c *config.IKEv2Config) string {
	eff := EffectiveConfig(c)
	var b strings.Builder
	b.WriteString("IKEv2 canary smoke plan\n")
	b.WriteString("NO REAL MUTATION: review all dry-run output before any production change.\n")
	fmt.Fprintf(&b, "config_dir: %s\n", eff.ConfigDir)
	fmt.Fprintf(&b, "state_dir: %s\n", eff.StateDir)
	fmt.Fprintf(&b, "vpn_subnet: %s\n", eff.VPNSubnet)
	fmt.Fprintf(&b, "xfrm_interface: %s\n", eff.XFRMInterface)
	b.WriteString("\nRun in order:\n")
	b.WriteString("1. vibe-vpn ikev2 status\n")
	b.WriteString("2. vibe-vpn ikev2 doctor\n")
	b.WriteString("3. vibe-vpn ikev2 pki init\n")
	b.WriteString("4. vibe-vpn ikev2 client create <canary-name> --ip <10.88.0.x> --os ios\n")
	b.WriteString("5. vibe-vpn ikev2 client list\n")
	b.WriteString("6. vibe-vpn ikev2 client audit <canary-name>\n")
	b.WriteString("7. vibe-vpn ikev2 client render <canary-name> --output-dir <staging-dir> --format ios\n")
	b.WriteString("8. vibe-vpn ikev2 server render --output-dir <staging-dir>\n")
	b.WriteString("9. vibe-vpn ikev2 server install --dry-run --output-dir <staging-dir>\n")
	b.WriteString("10. vibe-vpn ikev2 xfrm status\n")
	b.WriteString("11. vibe-vpn ikev2 xfrm install --dry-run\n")
	b.WriteString("12. vibe-vpn ikev2 routing status\n")
	b.WriteString("13. vibe-vpn ikev2 routing enable --dry-run\n")
	b.WriteString("14. Verify Tailscale, xray, sing-box, and vibe-vpn status remain healthy.\n")
	b.WriteString("\nSafety gates:\n")
	b.WriteString("- server/xfrm/routing install or enable must be dry-run only in this slice.\n")
	b.WriteString("- output must not contain private keys, credentials, VLESS links, subscription URLs, or tokens.\n")
	b.WriteString("- plans must not change tailscale0 or the VPS default route.\n")
	return b.String()
}
