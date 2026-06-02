package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestOpenVPNServerTemplateIncludesMTUMSSFix(t *testing.T) {
	path := filepath.Join("..", "..", "config", "openvpn", "server.tpl")
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	text := string(b)
	for _, want := range []string{"tun-mtu 1400", "mssfix 1360"} {
		if !strings.Contains(text, want) {
			t.Fatalf("OpenVPN server template missing %q", want)
		}
	}
}
