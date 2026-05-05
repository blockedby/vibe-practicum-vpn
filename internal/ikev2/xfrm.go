package ikev2

import (
	"fmt"
	"net"
	"strings"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
)

type XFRMPlan struct {
	Title   string
	Actions []string
	Notes   []string
}

func (p XFRMPlan) String() string {
	var b strings.Builder
	if p.Title != "" {
		fmt.Fprintf(&b, "%s\n", p.Title)
	}
	for _, a := range p.Actions {
		fmt.Fprintf(&b, "%s\n", a)
	}
	for _, n := range p.Notes {
		fmt.Fprintf(&b, "note: %s\n", n)
	}
	return b.String()
}

func XFRMStatus(c *config.IKEv2Config) string {
	eff := EffectiveConfig(c)
	var b strings.Builder
	fmt.Fprintf(&b, "xfrm_interface: %s\n", eff.XFRMInterface)
	fmt.Fprintf(&b, "xfrm_if_id: %d\n", eff.XFRMIfID)
	if eff.UnderlayInterface == "" {
		b.WriteString("xfrm_underlay_interface: not configured\n")
	} else {
		fmt.Fprintf(&b, "xfrm_underlay_interface: %s\n", eff.UnderlayInterface)
	}
	fmt.Fprintf(&b, "gateway_ip: %s\n", eff.GatewayIP)
	fmt.Fprintf(&b, "vpn_subnet: %s\n", eff.VPNSubnet)
	b.WriteString("live_inspection: not implemented; no system commands executed\n")
	return b.String()
}

func XFRMInstallPlan(c config.IKEv2Config) (XFRMPlan, error) {
	c.ApplyDefaults()
	if err := c.Validate(); err != nil {
		return XFRMPlan{}, err
	}
	if err := validateCommandRenderedNetworkFields(c, true); err != nil {
		return XFRMPlan{}, err
	}
	prefix, err := gatewayPrefix(c)
	if err != nil {
		return XFRMPlan{}, err
	}
	p := XFRMPlan{Title: "dry-run: would create route-based XFRM interface"}
	if c.UnderlayInterface == "" {
		p.Actions = append(p.Actions, fmt.Sprintf("underlay_interface: not configured; set ikev2.underlay_interface before real install planning for %s", c.XFRMInterface))
	} else {
		p.Actions = append(p.Actions, fmt.Sprintf("ip link add %s type xfrm dev %s if_id %d", c.XFRMInterface, c.UnderlayInterface, c.XFRMIfID))
	}
	p.Actions = append(p.Actions,
		fmt.Sprintf("ip addr add %s/%d dev %s", c.GatewayIP, prefix, c.XFRMInterface),
		fmt.Sprintf("ip link set %s up", c.XFRMInterface),
	)
	p.Notes = append(p.Notes, "commands are not executed by this planner", "real install is not implemented in this slice; use --dry-run only")
	return p, nil
}

func XFRMDisablePlan(c config.IKEv2Config) (XFRMPlan, error) {
	c.ApplyDefaults()
	if err := validateLinuxInterfaceName("ikev2.xfrm_interface", c.XFRMInterface); err != nil {
		return XFRMPlan{}, err
	}
	return XFRMPlan{
		Title: "dry-run: would remove IKEv2 XFRM interface setup only",
		Actions: []string{
			fmt.Sprintf("ip link set %s down", c.XFRMInterface),
			fmt.Sprintf("ip link delete %s", c.XFRMInterface),
		},
		Notes: []string{"commands are not executed by this planner", "tailscale/default route: untouched", "real disable is not implemented in this slice; use --dry-run only"},
	}, nil
}

func gatewayPrefix(c config.IKEv2Config) (int, error) {
	ip := net.ParseIP(c.GatewayIP)
	if ip == nil {
		return 0, fmt.Errorf("invalid ikev2.gateway_ip %q", c.GatewayIP)
	}
	_, n, err := net.ParseCIDR(c.VPNSubnet)
	if err != nil {
		return 0, err
	}
	if !n.Contains(ip) {
		return 0, fmt.Errorf("gateway ip %s is outside vpn subnet %s", c.GatewayIP, c.VPNSubnet)
	}
	ones, _ := n.Mask.Size()
	return ones, nil
}
