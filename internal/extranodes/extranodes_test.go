package extranodes

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadHysteria2NodeBuildsXrayOutbound(t *testing.T) {
	dir := t.TempDir()
	authFile := filepath.Join(dir, "auth")
	if err := os.WriteFile(authFile, []byte("secret\n"), 0600); err != nil {
		t.Fatal(err)
	}
	cfg := filepath.Join(dir, "extra-nodes.json")
	body := `[
  {
    "name": "lil-sweden hy2",
    "type": "hysteria2",
    "host": "computer.peacedata.company",
    "port": 18443,
    "auth_file": "` + authFile + `",
    "server_name": "computer.peacedata.company",
    "brutal_mbps": 200
  }
]`
	if err := os.WriteFile(cfg, []byte(body), 0600); err != nil {
		t.Fatal(err)
	}
	nodes, err := Load(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if len(nodes) != 1 {
		t.Fatalf("len=%d", len(nodes))
	}
	n := nodes[0]
	if n.Name != "lil-sweden hy2" || n.Host != "computer.peacedata.company" || n.Port != 18443 || n.Network != "hysteria" || n.Security != "tls" {
		t.Fatalf("unexpected node: %+v", n)
	}
	b, _ := json.Marshal(n.Outbound)
	s := string(b)
	for _, want := range []string{`"protocol":"hysteria"`, `"version":2`, `"address":"computer.peacedata.company"`, `"serverName":"computer.peacedata.company"`, `"auth":"secret"`, `"congestion":"force-brutal"`, `"brutalUp":"200 mbps"`} {
		if !strings.Contains(s, want) {
			t.Fatalf("outbound missing %s in %s", want, s)
		}
	}
}

func TestLoadMissingFileIsEmpty(t *testing.T) {
	nodes, err := Load(filepath.Join(t.TempDir(), "missing.json"))
	if err != nil {
		t.Fatal(err)
	}
	if len(nodes) != 0 {
		t.Fatalf("len=%d", len(nodes))
	}
}
