package ikev2

import (
	"fmt"
	"strings"
	"unicode/utf8"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
)

func Status(c *config.IKEv2Config) string {
	eff := EffectiveConfig(c)
	var b strings.Builder
	fmt.Fprintf(&b, "ikev2: configured=%t enabled=%t\n", eff.Configured, eff.Enabled)
	fmt.Fprintf(&b, "server_name: %s\n", escapeStatusValue(eff.ServerName))
	fmt.Fprintf(&b, "vpn_subnet: %s\n", escapeStatusValue(eff.VPNSubnet))
	fmt.Fprintf(&b, "gateway_ip: %s\n", escapeStatusValue(eff.GatewayIP))
	fmt.Fprintf(&b, "xfrm_interface: %s\n", escapeStatusValue(eff.XFRMInterface))
	fmt.Fprintf(&b, "xfrm_if_id: %d\n", eff.XFRMIfID)
	fmt.Fprintf(&b, "config_dir: %s\n", escapeStatusValue(eff.ConfigDir))
	fmt.Fprintf(&b, "state_dir: %s\n", escapeStatusValue(eff.StateDir))
	fmt.Fprintf(&b, "swanctl_dir: %s\n", escapeStatusValue(eff.SwanctlDir))
	fmt.Fprintf(&b, "strongswan_service: %s\n", escapeStatusValue(eff.StrongSwanService))
	fmt.Fprintf(&b, "tproxy_port: %d\n", eff.TProxyPort)
	fmt.Fprintf(&b, "tproxy_mark: %s\n", escapeStatusValue(eff.TProxyMark))
	fmt.Fprintf(&b, "tproxy_table: %d\n", eff.TProxyTable)
	b.WriteString("note: runtime checks are not implemented in this milestone\n")
	return b.String()
}

func escapeStatusValue(s string) string {
	var b strings.Builder
	for len(s) > 0 {
		r, size := utf8.DecodeRuneInString(s)
		if r == utf8.RuneError && size == 1 {
			b.WriteString(`\ufffd`)
			s = s[size:]
			continue
		}
		s = s[size:]
		switch r {
		case '\n':
			b.WriteString(`\n`)
		case '\r':
			b.WriteString(`\r`)
		case '\t':
			b.WriteString(`\t`)
		default:
			if r < 0x20 || r == 0x7f {
				fmt.Fprintf(&b, `\x%02x`, r)
			} else {
				b.WriteRune(r)
			}
		}
	}
	return b.String()
}

func Doctor(c *config.IKEv2Config) (string, error) {
	eff := EffectiveConfig(c)
	if err := eff.IKEv2Config.Validate(); err != nil {
		return fmt.Sprintf("ikev2 doctor: FAIL\n%s\n", err), err
	}
	return "ikev2 doctor: OK\nnote: system/runtime checks are not implemented in this milestone\n", nil
}
