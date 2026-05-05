package ikev2

import (
	"fmt"
	"net"
	"regexp"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
)

var (
	linuxInterfaceNameRE = regexp.MustCompile(`^[A-Za-z0-9_.:-]{1,15}$`)
	tproxyMarkRE         = regexp.MustCompile(`^(0[xX][0-9A-Fa-f]+|[0-9]+)$`)
)

func validateLinuxInterfaceName(field, value string) error {
	if !linuxInterfaceNameRE.MatchString(value) {
		return fmt.Errorf("%s must be a Linux interface name matching [A-Za-z0-9_.:-]{1,15}", field)
	}
	return nil
}

func validateOptionalUnderlayInterface(value string) error {
	if value == "" {
		return nil
	}
	return validateLinuxInterfaceName("ikev2.underlay_interface", value)
}

func validateTProxyMark(value string) error {
	if !tproxyMarkRE.MatchString(value) {
		return fmt.Errorf("ikev2.tproxy_mark must be a decimal or hex mark such as 1 or 0x1")
	}
	return nil
}

func validateRoutingTableID(value int) error {
	if value <= 0 || value > 2147483647 {
		return fmt.Errorf("ikev2.tproxy_table must be in range 1..2147483647")
	}
	return nil
}

func validateTProxyPort(value int) error {
	if value <= 0 || value > 65535 {
		return fmt.Errorf("ikev2.tproxy_port must be in range 1..65535")
	}
	return nil
}

func validateCommandRenderedNetworkFields(c config.IKEv2Config, includeUnderlay bool) error {
	if err := validateLinuxInterfaceName("ikev2.xfrm_interface", c.XFRMInterface); err != nil {
		return err
	}
	if includeUnderlay {
		if err := validateOptionalUnderlayInterface(c.UnderlayInterface); err != nil {
			return err
		}
	}
	if c.VPNSubnet != "" {
		if _, _, err := net.ParseCIDR(c.VPNSubnet); err != nil {
			return fmt.Errorf("invalid ikev2.vpn_subnet %q", c.VPNSubnet)
		}
	}
	if c.GatewayIP != "" && net.ParseIP(c.GatewayIP) == nil {
		return fmt.Errorf("invalid ikev2.gateway_ip %q", c.GatewayIP)
	}
	if err := validateTProxyMark(c.TProxyMark); err != nil {
		return err
	}
	if err := validateRoutingTableID(c.TProxyTable); err != nil {
		return err
	}
	return validateTProxyPort(c.TProxyPort)
}
