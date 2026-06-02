package extranodes

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/kcnc/vibe-practicum-vpn/internal/vless"
)

// Node describes one operator-managed node outside the subscription feed.
// The file is expected to be root-only when it contains auth material or points
// at auth files.
type Node struct {
	Name       string         `json:"name"`
	Type       string         `json:"type,omitempty"`
	Host       string         `json:"host,omitempty"`
	Port       int            `json:"port,omitempty"`
	Network    string         `json:"network,omitempty"`
	Security   string         `json:"security,omitempty"`
	Link       string         `json:"link,omitempty"`
	Outbound   map[string]any `json:"outbound,omitempty"`
	Auth       string         `json:"auth,omitempty"`
	AuthFile   string         `json:"auth_file,omitempty"`
	Password   string         `json:"password,omitempty"`
	ServerName string         `json:"server_name,omitempty"`
	SNI        string         `json:"sni,omitempty"`
	ALPN       []string       `json:"alpn,omitempty"`
	Obfs       string         `json:"obfs,omitempty"`
	ObfsFile   string         `json:"obfs_file,omitempty"`
	UpMbps     int            `json:"up_mbps,omitempty"`
	DownMbps   int            `json:"down_mbps,omitempty"`
	BrutalMbps int            `json:"brutal_mbps,omitempty"`
}

// Load reads extra/static nodes. A missing or empty path means no nodes.
func Load(path string) ([]vless.Node, error) {
	if path == "" {
		return nil, nil
	}
	b, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var defs []Node
	if err := json.Unmarshal(b, &defs); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	out := make([]vless.Node, 0, len(defs))
	for i, d := range defs {
		n, err := d.ToNode()
		if err != nil {
			return nil, fmt.Errorf("extra node %d: %w", i+1, err)
		}
		out = append(out, n)
	}
	return out, nil
}

func (d Node) ToNode() (vless.Node, error) {
	typ := strings.ToLower(strings.TrimSpace(d.Type))
	if typ == "" {
		if d.Outbound != nil {
			typ = "xray"
		} else {
			typ = "hysteria2"
		}
	}
	switch typ {
	case "hysteria2", "hy2", "hysteria":
		return d.hysteria2Node()
	case "xray", "raw":
		return d.rawNode()
	default:
		return vless.Node{}, fmt.Errorf("unsupported type %q", d.Type)
	}
}

func (d Node) rawNode() (vless.Node, error) {
	if d.Outbound == nil {
		return vless.Node{}, fmt.Errorf("raw node missing outbound")
	}
	if strings.TrimSpace(d.Name) == "" {
		return vless.Node{}, fmt.Errorf("raw node missing name")
	}
	return vless.Node{Link: first(d.Link, "static://"+slug(d.Name)), Name: d.Name, Host: d.Host, Port: d.Port, Network: first(d.Network, "custom"), Security: first(d.Security, "custom"), Outbound: d.Outbound}, nil
}

func (d Node) hysteria2Node() (vless.Node, error) {
	host := strings.TrimSpace(d.Host)
	if host == "" {
		return vless.Node{}, fmt.Errorf("hysteria2 node missing host")
	}
	if d.Port <= 0 || d.Port > 65535 {
		return vless.Node{}, fmt.Errorf("hysteria2 node has invalid port %d", d.Port)
	}
	password, err := d.password()
	if err != nil {
		return vless.Node{}, err
	}
	if password == "" {
		return vless.Node{}, fmt.Errorf("hysteria2 node missing auth/auth_file/password")
	}
	serverName := first(d.ServerName, d.SNI, host)
	name := strings.TrimSpace(d.Name)
	if name == "" {
		name = fmt.Sprintf("%s:%d", host, d.Port)
	}
	outbound := map[string]any{
		"type":        "hysteria2",
		"server":      host,
		"server_port": d.Port,
		"password":    password,
		"network":     first(d.Network, "tcp"),
		"tls": map[string]any{
			"enabled":     true,
			"server_name": serverName,
		},
	}
	if len(d.ALPN) > 0 {
		outbound["tls"].(map[string]any)["alpn"] = d.ALPN
	}
	obfs, err := d.obfsPassword()
	if err != nil {
		return vless.Node{}, err
	}
	if obfs != "" {
		outbound["obfs"] = map[string]any{"type": "salamander", "password": obfs}
	}
	upMbps := d.UpMbps
	if upMbps == 0 {
		upMbps = d.BrutalMbps
	}
	downMbps := d.DownMbps
	if downMbps == 0 {
		downMbps = d.BrutalMbps
	}
	if upMbps > 0 {
		outbound["up_mbps"] = upMbps
	}
	if downMbps > 0 {
		outbound["down_mbps"] = downMbps
	}
	return vless.Node{Link: first(d.Link, "static://"+slug(name)), Name: name, Host: host, Port: d.Port, Network: "hysteria2", Security: "tls", Outbound: outbound}, nil
}

func (d Node) password() (string, error) {
	if d.AuthFile == "" {
		return strings.TrimSpace(first(d.Password, d.Auth)), nil
	}
	b, err := os.ReadFile(d.AuthFile)
	if err != nil {
		return "", fmt.Errorf("read auth_file %s: %w", d.AuthFile, err)
	}
	return strings.TrimSpace(string(b)), nil
}

func (d Node) obfsPassword() (string, error) {
	if d.ObfsFile == "" {
		return strings.TrimSpace(d.Obfs), nil
	}
	b, err := os.ReadFile(d.ObfsFile)
	if err != nil {
		return "", fmt.Errorf("read obfs_file %s: %w", d.ObfsFile, err)
	}
	return strings.TrimSpace(string(b)), nil
}

func first(xs ...string) string {
	for _, x := range xs {
		if strings.TrimSpace(x) != "" {
			return strings.TrimSpace(x)
		}
	}
	return ""
}

func slug(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	var b strings.Builder
	lastDash := false
	for _, r := range s {
		ok := (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9')
		if ok {
			b.WriteRune(r)
			lastDash = false
			continue
		}
		if !lastDash {
			b.WriteByte('-')
			lastDash = true
		}
	}
	return strings.Trim(b.String(), "-")
}
