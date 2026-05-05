package ikev2

import (
	"fmt"
	"strings"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
)

const ikev2RoutingChain = "VIBE_ROUTER_IKEV2"

type RoutingPlan struct {
	Title   string
	Actions []string
	Notes   []string
}

func (p RoutingPlan) String() string {
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

func RoutingStatus(c *config.IKEv2Config) string {
	eff := EffectiveConfig(c)
	var b strings.Builder
	fmt.Fprintf(&b, "routing_interface: %s\n", eff.XFRMInterface)
	fmt.Fprintf(&b, "routing_subnet: %s\n", eff.VPNSubnet)
	fmt.Fprintf(&b, "routing_tproxy_port: %d\n", eff.TProxyPort)
	fmt.Fprintf(&b, "routing_tproxy_mark: %s\n", eff.TProxyMark)
	fmt.Fprintf(&b, "routing_tproxy_table: %d\n", eff.TProxyTable)
	fmt.Fprintf(&b, "routing_chain: %s\n", ikev2RoutingChain)
	b.WriteString("live_inspection: not implemented; no system commands executed\n")
	return b.String()
}

func RoutingEnablePlan(c config.IKEv2Config) (RoutingPlan, error) {
	c.ApplyDefaults()
	if err := c.Validate(); err != nil {
		return RoutingPlan{}, err
	}
	p := RoutingPlan{Title: "dry-run: would add IKEv2-only TPROXY routing plan"}
	p.Actions = append(p.Actions,
		fmt.Sprintf("iptables -t mangle -N %s", ikev2RoutingChain),
		fmt.Sprintf("iptables -t mangle -A PREROUTING -i %s -s %s -j %s", c.XFRMInterface, c.VPNSubnet, ikev2RoutingChain),
	)
	for _, cidr := range routingBypassCIDRs(c.VPNSubnet) {
		p.Actions = append(p.Actions, fmt.Sprintf("iptables -t mangle -A %s -d %s -j RETURN", ikev2RoutingChain, cidr))
	}
	p.Actions = append(p.Actions,
		fmt.Sprintf("iptables -t mangle -A %s -p tcp -j TPROXY --on-port %d --tproxy-mark %s", ikev2RoutingChain, c.TProxyPort, c.TProxyMark),
		fmt.Sprintf("iptables -t mangle -A %s -p udp -j TPROXY --on-port %d --tproxy-mark %s", ikev2RoutingChain, c.TProxyPort, c.TProxyMark),
		fmt.Sprintf("ip rule add fwmark %s lookup %d", c.TProxyMark, c.TProxyTable),
		fmt.Sprintf("ip route add local 0.0.0.0/0 dev lo table %d", c.TProxyTable),
	)
	p.Notes = append(p.Notes, "commands are not executed by this planner", "scoped to the dedicated IKEv2 ingress chain and policy table only", "real enable is not implemented in this slice; use --dry-run only")
	return p, nil
}

func RoutingDisablePlan(c config.IKEv2Config) (RoutingPlan, error) {
	c.ApplyDefaults()
	if err := c.Validate(); err != nil {
		return RoutingPlan{}, err
	}
	return RoutingPlan{
		Title: "dry-run: would remove IKEv2-only TPROXY routing plan",
		Actions: []string{
			fmt.Sprintf("iptables -t mangle -D PREROUTING -i %s -s %s -j %s", c.XFRMInterface, c.VPNSubnet, ikev2RoutingChain),
			fmt.Sprintf("iptables -t mangle -F %s", ikev2RoutingChain),
			fmt.Sprintf("iptables -t mangle -X %s", ikev2RoutingChain),
			fmt.Sprintf("ip rule del fwmark %s lookup %d", c.TProxyMark, c.TProxyTable),
			fmt.Sprintf("ip route del local 0.0.0.0/0 dev lo table %d", c.TProxyTable),
		},
		Notes: []string{"commands are not executed by this planner", "removes only the dedicated IKEv2 chain, hook, fwmark rule, and table route", "real disable is not implemented in this slice; use --dry-run only"},
	}, nil
}

func routingBypassCIDRs(vpnSubnet string) []string {
	return []string{
		vpnSubnet,
		"0.0.0.0/8",
		"10.0.0.0/8",
		"100.64.0.0/10",
		"127.0.0.0/8",
		"169.254.0.0/16",
		"172.16.0.0/12",
		"192.168.0.0/16",
		"224.0.0.0/4",
		"240.0.0.0/4",
	}
}
