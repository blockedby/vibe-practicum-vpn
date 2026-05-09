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
	ServerName string         `json:"server_name,omitempty"`
	SNI        string         `json:"sni,omitempty"`
	ALPN       []string       `json:"alpn,omitempty"`
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
	auth, err := d.auth()
	if err != nil {
		return vless.Node{}, err
	}
	if auth == "" {
		return vless.Node{}, fmt.Errorf("hysteria2 node missing auth/auth_file")
	}
	serverName := first(d.ServerName, d.SNI, host)
	alpn := d.ALPN
	if len(alpn) == 0 {
		alpn = []string{"h3"}
	}
	name := strings.TrimSpace(d.Name)
	if name == "" {
		name = fmt.Sprintf("%s:%d", host, d.Port)
	}
	stream := map[string]any{
		"network":  "hysteria",
		"security": "tls",
		"tlsSettings": map[string]any{
			"serverName": serverName,
			"alpn":       alpn,
		},
		"hysteriaSettings": map[string]any{
			"version": 2,
			"auth":    auth,
		},
	}
	if d.BrutalMbps > 0 {
		rate := fmt.Sprintf("%d mbps", d.BrutalMbps)
		stream["finalmask"] = map[string]any{"quicParams": map[string]any{"congestion": "force-brutal", "brutalUp": rate, "brutalDown": rate}}
	}
	outbound := map[string]any{
		"protocol": "hysteria",
		"settings": map[string]any{
			"version": 2,
			"address": host,
			"port":    d.Port,
		},
		"streamSettings": stream,
	}
	return vless.Node{Link: first(d.Link, "static://"+slug(name)), Name: name, Host: host, Port: d.Port, Network: "hysteria", Security: "tls", Outbound: outbound}, nil
}

func (d Node) auth() (string, error) {
	if d.AuthFile == "" {
		return strings.TrimSpace(d.Auth), nil
	}
	b, err := os.ReadFile(d.AuthFile)
	if err != nil {
		return "", fmt.Errorf("read auth_file %s: %w", d.AuthFile, err)
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
