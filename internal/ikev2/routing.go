package ikev2

import (
	"fmt"
	"strings"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
)

const (
	ikev2RoutingChain            = "VIBE_ROUTER_IKEV2"
	ikev2TailnetBridgeName       = "ipad-ikev2-tailnet"
	ikev2TailnetBridgeComment    = "vibe-vpn-ikev2-tailnet-bridge"
	bridgeForwardToTailnetRule   = "ipsec-to-tailnet"
	bridgeForwardFromTailnetRule = "tailnet-established-to-ipsec"
	bridgeNATRule                = "masquerade-ipsec-to-tailnet"
	bridgeBypassVPNRule          = "bypass-vpn-subnet"
	bridgeBypassTailnetRule      = "bypass-tailnet-subnet"
)

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
	fmt.Fprintf(&b, "routing_tailnet_interface: %s\n", eff.TailnetInterface)
	fmt.Fprintf(&b, "routing_tailnet_subnet: %s\n", eff.TailnetSubnet)
	fmt.Fprintf(&b, "routing_chain: %s\n", ikev2RoutingChain)
	fmt.Fprintf(&b, "routing_bridge: %s\n", ikev2TailnetBridgeName)
	b.WriteString("live_inspection: not implemented; no system commands executed\n")
	return b.String()
}

func RoutingEnablePlan(c config.IKEv2Config) (RoutingPlan, error) {
	c.ApplyDefaults()
	if err := c.Validate(); err != nil {
		return RoutingPlan{}, err
	}
	if err := validateCommandRenderedNetworkFields(c, false); err != nil {
		return RoutingPlan{}, err
	}
	p := RoutingPlan{Title: "dry-run: would add IKEv2-only TPROXY routing plan"}
	p.Actions = append(p.Actions,
		fmt.Sprintf("iptables -t mangle -N %s", ikev2RoutingChain),
		fmt.Sprintf("iptables -t mangle -A PREROUTING -i %s -s %s -j %s", c.XFRMInterface, c.VPNSubnet, ikev2RoutingChain),
	)
	for _, cidr := range routingBypassCIDRs(c.VPNSubnet, c.TailnetSubnet) {
		p.Actions = append(p.Actions, fmt.Sprintf("iptables -t mangle -A %s -d %s -j RETURN", ikev2RoutingChain, cidr))
	}
	p.Actions = append(p.Actions,
		fmt.Sprintf("iptables -t mangle -A %s -p tcp -j TPROXY --on-port %d --tproxy-mark %s", ikev2RoutingChain, c.TProxyPort, c.TProxyMark),
		fmt.Sprintf("iptables -t mangle -A %s -p udp -j TPROXY --on-port %d --tproxy-mark %s", ikev2RoutingChain, c.TProxyPort, c.TProxyMark),
		fmt.Sprintf("ip rule add fwmark %s lookup %d", c.TProxyMark, c.TProxyTable),
		fmt.Sprintf("ip route add local 0.0.0.0/0 dev lo table %d", c.TProxyTable),
	)
	p.Notes = append(p.Notes, "commands are not executed by this planner", "scoped to the dedicated IKEv2 ingress chain and policy table only", "private/tailnet destinations return before TPROXY capture", "real enable is not implemented in this slice; use --dry-run only")
	return p, nil
}

func RoutingDisablePlan(c config.IKEv2Config) (RoutingPlan, error) {
	c.ApplyDefaults()
	if err := c.Validate(); err != nil {
		return RoutingPlan{}, err
	}
	if err := validateCommandRenderedNetworkFields(c, false); err != nil {
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

func RoutingBridgeStatus(c *config.IKEv2Config) (string, error) {
	eff := EffectiveConfig(c)
	if err := validateTailnetBridgeFields(eff.IKEv2Config); err != nil {
		return "", err
	}
	var b strings.Builder
	fmt.Fprintf(&b, "bridge: %s\n", ikev2TailnetBridgeName)
	fmt.Fprintf(&b, "bridge_ingress_interface: %s\n", eff.XFRMInterface)
	fmt.Fprintf(&b, "bridge_ingress_subnet: %s\n", eff.VPNSubnet)
	fmt.Fprintf(&b, "bridge_tailnet_interface: %s\n", eff.TailnetInterface)
	fmt.Fprintf(&b, "bridge_tailnet_subnet: %s\n", eff.TailnetSubnet)
	fmt.Fprintf(&b, "bridge_routing_chain: %s\n", ikev2RoutingChain)
	fmt.Fprintf(&b, "bridge_rule_comment_prefix: %s\n", ikev2TailnetBridgeComment)
	b.WriteString("live_inspection: not implemented; no system commands executed\n")
	b.WriteString("audit_commands:\n")
	for _, cmd := range bridgeAuditCommands(eff.IKEv2Config) {
		fmt.Fprintf(&b, "%s\n", cmd)
	}
	return b.String(), nil
}

func RoutingBridgeEnablePlan(c config.IKEv2Config) (RoutingPlan, error) {
	c.ApplyDefaults()
	if err := c.Validate(); err != nil {
		return RoutingPlan{}, err
	}
	if err := validateTailnetBridgeFields(c); err != nil {
		return RoutingPlan{}, err
	}
	p := RoutingPlan{Title: "dry-run: would add IKEv2-to-tailnet bridge rules"}
	p.Actions = append(p.Actions,
		checkThenInsertCommand("filter", "FORWARD", bridgeForwardToTailnetSpec(c), "1"),
		checkThenInsertCommand("filter", "FORWARD", bridgeForwardFromTailnetSpec(c), "1"),
		checkThenAppendCommand("nat", "POSTROUTING", bridgeNATSpec(c)),
		checkThenInsertIfChainExistsCommand("mangle", ikev2RoutingChain, bridgeBypassVPNSpec(c), "1"),
		checkThenInsertIfChainExistsCommand("mangle", ikev2RoutingChain, bridgeBypassTailnetSpec(c), "1"),
	)
	p.Notes = append(p.Notes,
		"commands are not executed by this planner",
		"FORWARD rules allow only ipsec-to-tailnet and established/related tailnet return traffic",
		"NAT rule masquerades only IKEv2 subnet traffic destined to the tailnet out the tailnet interface so PC/Deck routes need no change",
		"TPROXY bypass rules are inserted only into the dedicated IKEv2 chain if that chain already exists",
		"all added bridge rules are comment-scoped and idempotent check-before-add commands",
		"does not change the VPS default route and does not restart tailscaled, strongSwan, xray, sing-box, or Docker",
	)
	return p, nil
}

func RoutingBridgeDisablePlan(c config.IKEv2Config) (RoutingPlan, error) {
	c.ApplyDefaults()
	if err := c.Validate(); err != nil {
		return RoutingPlan{}, err
	}
	if err := validateTailnetBridgeFields(c); err != nil {
		return RoutingPlan{}, err
	}
	return RoutingPlan{
		Title: "dry-run: would remove IKEv2-to-tailnet bridge rules",
		Actions: []string{
			deleteExactRuleLoopCommand("mangle", ikev2RoutingChain, bridgeBypassTailnetSpec(c)),
			deleteExactRuleLoopCommand("mangle", ikev2RoutingChain, bridgeBypassVPNSpec(c)),
			deleteExactRuleLoopCommand("nat", "POSTROUTING", bridgeNATSpec(c)),
			deleteExactRuleLoopCommand("filter", "FORWARD", bridgeForwardFromTailnetSpec(c)),
			deleteExactRuleLoopCommand("filter", "FORWARD", bridgeForwardToTailnetSpec(c)),
		},
		Notes: []string{
			"commands are not executed by this planner",
			"deletes only exact comment-scoped bridge rules and leaves existing Tailscale/Hysteria/IKEv2 rules intact",
			"does not flush chains, delete default routes, or restart services",
		},
	}, nil
}

func bridgeAuditCommands(c config.IKEv2Config) []string {
	return []string{
		presentCommand("filter", "FORWARD", bridgeForwardToTailnetSpec(c), bridgeForwardToTailnetRule),
		presentCommand("filter", "FORWARD", bridgeForwardFromTailnetSpec(c), bridgeForwardFromTailnetRule),
		presentCommand("nat", "POSTROUTING", bridgeNATSpec(c), bridgeNATRule),
		presentCommand("mangle", ikev2RoutingChain, bridgeBypassVPNSpec(c), bridgeBypassVPNRule),
		presentCommand("mangle", ikev2RoutingChain, bridgeBypassTailnetSpec(c), bridgeBypassTailnetRule),
	}
}

func bridgeForwardToTailnetSpec(c config.IKEv2Config) string {
	return fmt.Sprintf("-i %s -o %s -s %s -d %s -m comment --comment %s:%s -j ACCEPT", c.XFRMInterface, c.TailnetInterface, c.VPNSubnet, c.TailnetSubnet, ikev2TailnetBridgeComment, bridgeForwardToTailnetRule)
}

func bridgeForwardFromTailnetSpec(c config.IKEv2Config) string {
	return fmt.Sprintf("-i %s -o %s -s %s -d %s -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment %s:%s -j ACCEPT", c.TailnetInterface, c.XFRMInterface, c.TailnetSubnet, c.VPNSubnet, ikev2TailnetBridgeComment, bridgeForwardFromTailnetRule)
}

func bridgeNATSpec(c config.IKEv2Config) string {
	return fmt.Sprintf("-o %s -s %s -d %s -m comment --comment %s:%s -j MASQUERADE", c.TailnetInterface, c.VPNSubnet, c.TailnetSubnet, ikev2TailnetBridgeComment, bridgeNATRule)
}

func bridgeBypassVPNSpec(c config.IKEv2Config) string {
	return fmt.Sprintf("-d %s -m comment --comment %s:%s -j RETURN", c.VPNSubnet, ikev2TailnetBridgeComment, bridgeBypassVPNRule)
}

func bridgeBypassTailnetSpec(c config.IKEv2Config) string {
	return fmt.Sprintf("-d %s -m comment --comment %s:%s -j RETURN", c.TailnetSubnet, ikev2TailnetBridgeComment, bridgeBypassTailnetRule)
}

func checkThenAppendCommand(table, chain, spec string) string {
	return fmt.Sprintf("iptables -w -t %s -C %s %s || iptables -w -t %s -A %s %s", table, chain, spec, table, chain, spec)
}

func checkThenInsertCommand(table, chain, spec, position string) string {
	return fmt.Sprintf("iptables -w -t %s -C %s %s || iptables -w -t %s -I %s %s %s", table, chain, spec, table, chain, position, spec)
}

func checkThenInsertIfChainExistsCommand(table, chain, spec, position string) string {
	return fmt.Sprintf("if iptables -w -t %s -nL %s >/dev/null 2>&1; then iptables -w -t %s -C %s %s || iptables -w -t %s -I %s %s %s; else echo skip: %s missing; fi", table, chain, table, chain, spec, table, chain, position, spec, chain)
}

func deleteExactRuleLoopCommand(table, chain, spec string) string {
	return fmt.Sprintf("while iptables -w -t %s -C %s %s 2>/dev/null; do iptables -w -t %s -D %s %s; done", table, chain, spec, table, chain, spec)
}

func presentCommand(table, chain, spec, name string) string {
	return fmt.Sprintf("iptables -w -t %s -C %s %s >/dev/null 2>&1 && echo present:%s || echo missing:%s", table, chain, spec, name, name)
}

func routingBypassCIDRs(vpnSubnet, tailnetSubnet string) []string {
	return []string{
		vpnSubnet,
		"0.0.0.0/8",
		"10.0.0.0/8",
		tailnetSubnet,
		"127.0.0.0/8",
		"169.254.0.0/16",
		"172.16.0.0/12",
		"192.168.0.0/16",
		"224.0.0.0/4",
		"240.0.0.0/4",
	}
}
