package ikev2

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
)

func testConfig(dir string) config.IKEv2Config {
	c := config.DefaultIKEv2Config()
	c.ConfigDir = filepath.Join(dir, "etc")
	c.StateDir = filepath.Join(dir, "state")
	return c
}

func TestValidateClientName(t *testing.T) {
	for _, name := range []string{"phone", "ios-1", "Pixel_8"} {
		if err := ValidateClientName(name); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
	}
	for _, name := range []string{"", ".bad", "bad/thing", "two words", "secret.pem", "a"} {
		if err := ValidateClientName(name); err == nil {
			t.Fatalf("%s accepted", name)
		}
	}
}

func TestValidateClientIP(t *testing.T) {
	c := testConfig(t.TempDir())
	if err := ValidateClientIP(c, "10.88.0.2"); err != nil {
		t.Fatal(err)
	}
	for _, ip := range []string{"10.88.0.0", "10.88.0.1", "10.88.0.255", "10.89.0.2", "bad"} {
		if err := ValidateClientIP(c, ip); err == nil {
			t.Fatalf("%s accepted", ip)
		}
	}
}

func TestRegistryCreateListRevokeRoundTrip(t *testing.T) {
	c := testConfig(t.TempDir())
	if err := InitPKI(c); err != nil {
		t.Fatal(err)
	}
	reg := NewRegistry(c)
	cl, err := reg.Create("phone", "10.88.0.2", "ios")
	if err != nil {
		t.Fatal(err)
	}
	if cl.Name != "phone" || cl.Revoked {
		t.Fatalf("bad client: %+v", cl)
	}
	if _, err := reg.Create("phone", "10.88.0.3", "ios"); err == nil {
		t.Fatal("duplicate name accepted")
	}
	if _, err := reg.Create("tablet", "10.88.0.2", "android"); err == nil {
		t.Fatal("duplicate ip accepted")
	}
	list, err := reg.List()
	if err != nil || len(list) != 1 {
		t.Fatalf("list=%+v err=%v", list, err)
	}
	if err := reg.Revoke("phone"); err != nil {
		t.Fatal(err)
	}
	list, _ = reg.List()
	if !list[0].Revoked {
		t.Fatalf("not revoked: %+v", list[0])
	}
}

func TestInitPKICreatesSafeModes(t *testing.T) {
	c := testConfig(t.TempDir())
	if err := InitPKI(c); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{c.ConfigDir, c.StateDir, filepath.Join(c.ConfigDir, "pki", "private"), filepath.Join(c.StateDir, "clients")} {
		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm() != 0700 {
			t.Fatalf("%s mode=%o", path, info.Mode().Perm())
		}
	}
	for _, path := range []string{filepath.Join(c.ConfigDir, "pki", "private", ".keep"), filepath.Join(c.StateDir, "clients", ".keep")} {
		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm() != 0600 {
			t.Fatalf("%s mode=%o", path, info.Mode().Perm())
		}
	}
}
