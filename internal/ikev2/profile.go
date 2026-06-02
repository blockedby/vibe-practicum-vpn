package ikev2

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
)

const profileRedactionNotice = "secret_material: not printed; generated iOS profiles embed certificate credentials"

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
		serverName = "vibe"
	}
	remoteAddress := c.PublicEndpoint
	if remoteAddress == "" {
		remoteAddress = serverName
	}
	remoteID := serverName
	if format == "ios" {
		password, err := RandomProfilePassword()
		if err != nil {
			return nil, err
		}
		p12, err := BuildClientPKCS12(c, cl, password)
		if err != nil {
			return nil, err
		}
		caCert, err := loadCertificate(filepath.Join(c.ConfigDir, caCertRelPath))
		if err != nil {
			return nil, err
		}
		content := renderIOSMobileConfig(c, cl, remoteAddress, remoteID, p12, caCert.Raw, password)
		return []RenderedFile{{RelativePath: cl.Name + ".mobileconfig", Content: content}}, nil
	}
	content := fmt.Sprintf("vibe-vpn IKEv2 generic client profile (preview; no secrets)\nclient_name: %s\nclient_ip: %s\nclient_os: %s\nserver_name: %s\nremote_identifier: %s\nvpn_subnet: %s\ngateway_ip: %s\nauthentication: certificate placeholders only\nclient_certificate_reference: PLACEHOLDER_CLIENT_CERT_REFERENCE_NO_PRIVATE_MATERIAL\nserver_certificate_reference: PLACEHOLDER_SERVER_CERT_TRUST_REFERENCE\nsecret_material: not printed\n", cl.Name, cl.IP, cl.OS, serverName, remoteID, c.VPNSubnet, c.GatewayIP)
	return []RenderedFile{{RelativePath: cl.Name + "-ikev2-profile.txt", Content: content}}, nil
}

func WriteRenderedClientProfile(outputDir string, files []RenderedFile) ([]string, error) {
	if outputDir == "" {
		return nil, fmt.Errorf("output dir is required")
	}
	var written []string
	for _, f := range files {
		if f.RelativePath == "" || filepath.IsAbs(f.RelativePath) || strings.Contains(f.RelativePath, "..") {
			return nil, fmt.Errorf("unsafe render path %q", f.RelativePath)
		}
		p := filepath.Join(outputDir, f.RelativePath)
		if err := os.MkdirAll(filepath.Dir(p), 0700); err != nil {
			return nil, err
		}
		if err := os.Chmod(filepath.Dir(p), 0700); err != nil {
			return nil, err
		}
		if err := writeFileWithMode(p, []byte(f.Content), 0600); err != nil {
			return nil, err
		}
		written = append(written, p)
	}
	return written, nil
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

func renderIOSMobileConfig(c config.IKEv2Config, cl Client, remoteAddress, remoteID string, p12, caDER []byte, password string) string {
	profileUUID := deterministicUUID("profile", cl.Name, cl.IP, remoteAddress, remoteID)
	vpnUUID := deterministicUUID("vpn", cl.Name, cl.IP, remoteAddress, remoteID)
	p12UUID := deterministicUUID("p12", cl.Name, cl.IP, remoteAddress, remoteID)
	caUUID := deterministicUUID("ca", cl.Name, cl.IP, remoteAddress, remoteID)
	identifierBase := "com.vibe-vpn.ikev2." + strings.ToLower(cl.Name)
	return fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadType</key><string>com.apple.security.root</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>PayloadIdentifier</key><string>%s.ca</string>
      <key>PayloadUUID</key><string>%s</string>
      <key>PayloadDisplayName</key><string>vibe-vpn IKEv2 CA</string>
      <key>PayloadContent</key><data>%s</data>
    </dict>
    <dict>
      <key>PayloadType</key><string>com.apple.security.pkcs12</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>PayloadIdentifier</key><string>%s.identity</string>
      <key>PayloadUUID</key><string>%s</string>
      <key>PayloadDisplayName</key><string>vibe-vpn IKEv2 %s identity</string>
      <key>Password</key><string>%s</string>
      <key>PayloadContent</key><data>%s</data>
    </dict>
    <dict>
      <key>PayloadType</key><string>com.apple.vpn.managed</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>PayloadIdentifier</key><string>%s.vpn</string>
      <key>PayloadUUID</key><string>%s</string>
      <key>PayloadDisplayName</key><string>vibe-vpn IKEv2</string>
      <key>UserDefinedName</key><string>vibe-vpn IKEv2</string>
      <key>VPNType</key><string>IKEv2</string>
      <key>IKEv2</key>
      <dict>
        <key>RemoteAddress</key><string>%s</string>
        <key>RemoteIdentifier</key><string>%s</string>
        <key>LocalIdentifier</key><string>%s</string>
        <key>AuthenticationMethod</key><string>Certificate</string>
        <key>PayloadCertificateUUID</key><string>%s</string>
        <key>UseConfigurationAttributeInternalIPSubnet</key><integer>0</integer>
        <key>EnablePFS</key><integer>1</integer>
        <key>IKESecurityAssociationParameters</key>
        <dict>
          <key>EncryptionAlgorithm</key><string>AES-256</string>
          <key>IntegrityAlgorithm</key><string>SHA2-256</string>
          <key>DiffieHellmanGroup</key><integer>14</integer>
          <key>LifeTimeInMinutes</key><integer>1440</integer>
        </dict>
        <key>ChildSecurityAssociationParameters</key>
        <dict>
          <key>EncryptionAlgorithm</key><string>AES-256</string>
          <key>IntegrityAlgorithm</key><string>SHA2-256</string>
          <key>DiffieHellmanGroup</key><integer>14</integer>
          <key>LifeTimeInMinutes</key><integer>1440</integer>
        </dict>
      </dict>
    </dict>
  </array>
  <key>PayloadDescription</key><string>vibe-vpn IKEv2 profile; contains certificate credentials for this client</string>
  <key>PayloadDisplayName</key><string>vibe-vpn IKEv2 %s</string>
  <key>PayloadIdentifier</key><string>%s.profile</string>
  <key>PayloadOrganization</key><string>vibe-vpn</string>
  <key>PayloadRemovalDisallowed</key><false/>
  <key>PayloadType</key><string>Configuration</string>
  <key>PayloadUUID</key><string>%s</string>
  <key>PayloadVersion</key><integer>1</integer>
</dict>
</plist>
`, xmlEscape(identifierBase), caUUID, xmlEscape(base64.StdEncoding.EncodeToString(caDER)), xmlEscape(identifierBase), p12UUID, xmlEscape(cl.Name), xmlEscape(password), xmlEscape(base64.StdEncoding.EncodeToString(p12)), xmlEscape(identifierBase), vpnUUID, xmlEscape(remoteAddress), xmlEscape(remoteID), xmlEscape(cl.Name), p12UUID, xmlEscape(cl.Name), xmlEscape(identifierBase), profileUUID)
}

func deterministicUUID(parts ...string) string {
	sum32 := sha256.Sum256([]byte("vibe-vpn|" + strings.Join(parts, "|")))
	sum := append([]byte(nil), sum32[:16]...)
	sum[6] = (sum[6] & 0x0f) | 0x50
	sum[8] = (sum[8] & 0x3f) | 0x80
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x", sum[0:4], sum[4:6], sum[6:8], sum[8:10], sum[10:16])
}

func xmlEscape(s string) string {
	r := strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", "\"", "&quot;", "'", "&apos;")
	return r.Replace(s)
}

func IPInSubnet(c config.IKEv2Config, ip string) bool {
	_, n, err := net.ParseCIDR(c.VPNSubnet)
	return err == nil && n.Contains(net.ParseIP(ip))
}
