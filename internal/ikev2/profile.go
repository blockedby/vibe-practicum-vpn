package ikev2

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
)

const profileRedactionNotice = "secret_material: not printed; profile contains placeholders only"

func ProfileRedactionNotice() string { return profileRedactionNotice }

func (r Registry) Get(name string) (Client, error) {
	if err := ValidateClientName(name); err != nil {
		return Client{}, err
	}
	b, err := os.ReadFile(r.path(name))
	if err != nil {
		if os.IsNotExist(err) {
			return Client{}, fmt.Errorf("client %q not found", name)
		}
		return Client{}, err
	}
	var c Client
	if err := json.Unmarshal(b, &c); err != nil {
		return Client{}, err
	}
	return c, nil
}

func RenderClientProfile(c config.IKEv2Config, cl Client, format string) ([]RenderedFile, error) {
	c.ApplyDefaults()
	if format == "" {
		format = "ios"
	}
	if format != "ios" && format != "generic" {
		return nil, fmt.Errorf("unsupported profile format %q", format)
	}
	if cl.Revoked {
		return nil, fmt.Errorf("client %q is revoked", cl.Name)
	}
	if err := ValidateClientIP(c, cl.IP); err != nil {
		return nil, err
	}
	serverName := c.ServerName
	if serverName == "" {
		serverName = "IKEV2_SERVER_NAME_NOT_CONFIGURED"
	}
	remoteID := serverName
	if format == "ios" {
		content := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadDescription</key><string>vibe-vpn IKEv2 canary preview; no private keys or credentials embedded</string>
  <key>PayloadDisplayName</key><string>vibe-vpn IKEv2 %s</string>
  <key>PayloadIdentifier</key><string>com.vibe-vpn.ikev2.preview.%s</string>
  <key>PayloadType</key><string>Configuration</string>
  <key>PayloadVersion</key><integer>1</integer>
  <key>VPN</key>
  <dict>
    <key>VPNType</key><string>IKEv2</string>
    <key>RemoteAddress</key><string>%s</string>
    <key>RemoteIdentifier</key><string>%s</string>
    <key>LocalIdentifier</key><string>%s</string>
    <key>ClientVPNAddress</key><string>%s</string>
    <key>VPNSubnet</key><string>%s</string>
    <key>AuthenticationMethod</key><string>Certificate</string>
    <key>CertificateReference</key><string>PLACEHOLDER_CLIENT_CERT_REFERENCE_NO_PRIVATE_MATERIAL</string>
    <key>ServerCertificate</key><string>PLACEHOLDER_SERVER_CERT_TRUST_REFERENCE</string>
  </dict>
</dict>
</plist>
`, xmlEscape(cl.Name), xmlEscape(cl.Name), xmlEscape(serverName), xmlEscape(remoteID), xmlEscape(cl.Name), xmlEscape(cl.IP), xmlEscape(c.VPNSubnet))
		return []RenderedFile{{RelativePath: cl.Name + ".mobileconfig", Content: content}}, nil
	}
	content := fmt.Sprintf("vibe-vpn IKEv2 generic client profile (preview; no secrets)\nclient_name: %s\nclient_ip: %s\nclient_os: %s\nserver_name: %s\nremote_identifier: %s\nvpn_subnet: %s\ngateway_ip: %s\nauthentication: certificate placeholders only\nclient_certificate_reference: PLACEHOLDER_CLIENT_CERT_REFERENCE_NO_PRIVATE_MATERIAL\nserver_certificate_reference: PLACEHOLDER_SERVER_CERT_TRUST_REFERENCE\nsecret_material: not printed\n", cl.Name, cl.IP, cl.OS, serverName, remoteID, c.VPNSubnet, c.GatewayIP)
	return []RenderedFile{{RelativePath: cl.Name + "-ikev2-profile.txt", Content: content}}, nil
}

func WriteRenderedClientProfile(outputDir string, files []RenderedFile) ([]string, error) {
	return WriteRenderedServerConfig(outputDir, files)
}

func AuditClientProfile(c config.IKEv2Config, cl Client) string {
	c.ApplyDefaults()
	var b strings.Builder
	fmt.Fprintf(&b, "PASS client exists: %s\n", cl.Name)
	if cl.Revoked {
		b.WriteString("WARN client not revoked: revoked=true\n")
	} else {
		b.WriteString("PASS client not revoked\n")
	}
	if err := ValidateClientIP(c, cl.IP); err != nil {
		fmt.Fprintf(&b, "WARN client ip in subnet: %v\n", err)
	} else {
		fmt.Fprintf(&b, "PASS client ip in subnet: %s in %s\n", cl.IP, c.VPNSubnet)
	}
	if c.ServerName == "" {
		b.WriteString("WARN server name configured: missing ikev2.server_name\n")
	} else {
		fmt.Fprintf(&b, "PASS server name configured: %s\n", c.ServerName)
	}
	pki := filepath.Join(c.ConfigDir, "pki")
	if _, err := os.Stat(pki); err != nil {
		fmt.Fprintf(&b, "WARN pki placeholder/layout present: %s missing\n", pki)
	} else {
		fmt.Fprintf(&b, "PASS pki placeholder/layout present: %s\n", pki)
	}
	b.WriteString(profileRedactionNotice + "\n")
	return b.String()
}

func xmlEscape(s string) string {
	r := strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", "\"", "&quot;", "'", "&apos;")
	return r.Replace(s)
}

func IPInSubnet(c config.IKEv2Config, ip string) bool {
	_, n, err := net.ParseCIDR(c.VPNSubnet)
	return err == nil && n.Contains(net.ParseIP(ip))
}
