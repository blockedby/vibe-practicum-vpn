package extranodes

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadHysteria2NodeBuildsSingBoxOutbound(t *testing.T) {
	dir := t.TempDir()
	authFile := filepath.Join(dir, "auth")
	if err := os.WriteFile(authFile, []byte("secret\n"), 0600); err != nil {
		t.Fatal(err)
	}
	cfg := filepath.Join(dir, "extra-nodes.json")
	body := `[
  {
    "name": "example-extra-node hy2",
    "type": "hysteria2",
    "host": "203.0.113.20",
    "port": 443,
    "auth_file": "` + authFile + `",
    "server_name": "example-private-node.invalid",
    "up_mbps": 100,
    "down_mbps": 100
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
	if n.Name != "example-extra-node hy2" || n.Host != "203.0.113.20" || n.Port != 443 || n.Network != "hysteria2" || n.Security != "tls" {
		t.Fatalf("unexpected node: %+v", n)
	}
	b, _ := json.Marshal(n.Outbound)
	s := string(b)
	for _, want := range []string{`"type":"hysteria2"`, `"server":"203.0.113.20"`, `"server_port":443`, `"server_name":"example-private-node.invalid"`, `"password":"secret"`, `"up_mbps":100`, `"down_mbps":100`} {
		if !strings.Contains(s, want) {
			t.Fatalf("outbound missing %s in %s", want, s)
		}
	}
}

func TestLoadHysteria2NodeReadsObfsFile(t *testing.T) {
	dir := t.TempDir()
	authFile := filepath.Join(dir, "auth")
	obfsFile := filepath.Join(dir, "obfs")
	if err := os.WriteFile(authFile, []byte("secret\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(obfsFile, []byte("obfs-secret\n"), 0600); err != nil {
		t.Fatal(err)
	}
	cfg := filepath.Join(dir, "extra-nodes.json")
	body := `[{"name":"hy2","type":"hysteria2","host":"192.0.2.1","port":443,"auth_file":"` + authFile + `","obfs_file":"` + obfsFile + `"}]`
	if err := os.WriteFile(cfg, []byte(body), 0600); err != nil {
		t.Fatal(err)
	}
	nodes, err := Load(cfg)
	if err != nil {
		t.Fatal(err)
	}
	obfs, ok := nodes[0].Outbound["obfs"].(map[string]any)
	if !ok || obfs["type"] != "salamander" || obfs["password"] != "obfs-secret" {
		t.Fatalf("unexpected obfs outbound: %#v", nodes[0].Outbound["obfs"])
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
