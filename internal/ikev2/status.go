package ikev2

import (
	"fmt"
	"strings"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
)

func Status(c *config.IKEv2Config) string {
	eff := EffectiveConfig(c)
	var b strings.Builder
	fmt.Fprintf(&b, "ikev2: configured=%t enabled=%t\n", eff.Configured, eff.Enabled)
	fmt.Fprintf(&b, "server_name: %s\n", eff.ServerName)
	fmt.Fprintf(&b, "vpn_subnet: %s\n", eff.VPNSubnet)
	fmt.Fprintf(&b, "gateway_ip: %s\n", eff.GatewayIP)
	fmt.Fprintf(&b, "xfrm_interface: %s\n", eff.XFRMInterface)
	fmt.Fprintf(&b, "xfrm_if_id: %d\n", eff.XFRMIfID)
	fmt.Fprintf(&b, "config_dir: %s\n", eff.ConfigDir)
	fmt.Fprintf(&b, "state_dir: %s\n", eff.StateDir)
	fmt.Fprintf(&b, "swanctl_dir: %s\n", eff.SwanctlDir)
	fmt.Fprintf(&b, "strongswan_service: %s\n", eff.StrongSwanService)
	fmt.Fprintf(&b, "tproxy_port: %d\n", eff.TProxyPort)
	fmt.Fprintf(&b, "tproxy_mark: %s\n", eff.TProxyMark)
	fmt.Fprintf(&b, "tproxy_table: %d\n", eff.TProxyTable)
	b.WriteString("note: runtime checks are not implemented in this milestone\n")
	return b.String()
}

func Doctor(c *config.IKEv2Config) (string, error) {
	eff := EffectiveConfig(c)
	if err := eff.IKEv2Config.Validate(); err != nil {
		return fmt.Sprintf("ikev2 doctor: FAIL\n%s\n", err), err
	}
	return "ikev2 doctor: OK\nnote: system/runtime checks are not implemented in this milestone\n", nil
}
