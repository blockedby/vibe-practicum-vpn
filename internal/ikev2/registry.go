package ikev2

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"time"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
)

var clientNameRE = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_-]{1,62}$`)

type Client struct {
	Name      string `json:"name"`
	IP        string `json:"ip"`
	OS        string `json:"os,omitempty"`
	Revoked   bool   `json:"revoked"`
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
}

type Registry struct{ cfg config.IKEv2Config }

func NewRegistry(c config.IKEv2Config) Registry { c.ApplyDefaults(); return Registry{cfg: c} }

func InitPKI(c config.IKEv2Config) error {
	return EnsurePKI(c)
}

func ValidateClientName(name string) error {
	if !clientNameRE.MatchString(name) {
		return fmt.Errorf("invalid client name %q: use 2-63 letters, digits, '-' or '_'", name)
	}
	return nil
}

func ValidateClientIP(c config.IKEv2Config, s string) error {
	c.ApplyDefaults()
	ip := net.ParseIP(s)
	if ip == nil {
		return fmt.Errorf("invalid client ip %q", s)
	}
	_, n, err := net.ParseCIDR(c.VPNSubnet)
	if err != nil {
		return err
	}
	if !n.Contains(ip) {
		return fmt.Errorf("client ip %s is outside vpn subnet %s", s, c.VPNSubnet)
	}
	if ip.Equal(net.ParseIP(c.GatewayIP)) {
		return fmt.Errorf("client ip %s is gateway ip", s)
	}
	if ip4 := ip.To4(); ip4 != nil {
		ones, bits := n.Mask.Size()
		total := uint32(1) << uint(bits-ones)
		base := n.IP.To4()
		if base != nil {
			last := append(net.IP(nil), base...)
			v := uint32(last[0])<<24 | uint32(last[1])<<16 | uint32(last[2])<<8 | uint32(last[3])
			v += total - 1
			last = net.IPv4(byte(v>>24), byte(v>>16), byte(v>>8), byte(v))
			if ip4.Equal(base) || ip4.Equal(last.To4()) {
				return fmt.Errorf("client ip %s cannot be network or broadcast", s)
			}
		}
	}
	return nil
}

func ValidateClientOS(osName string) error {
	switch osName {
	case "", "ios", "android", "windows", "linux":
		return nil
	default:
		return fmt.Errorf("unsupported client os %q", osName)
	}
}

func (r Registry) Create(name, ip, osName string) (Client, error) {
	if err := ValidateClientName(name); err != nil {
		return Client{}, err
	}
	if err := ValidateClientIP(r.cfg, ip); err != nil {
		return Client{}, err
	}
	if err := ValidateClientOS(osName); err != nil {
		return Client{}, err
	}
	if err := ensureSecretDir(r.dir()); err != nil {
		return Client{}, err
	}
	clients, err := r.List()
	if err != nil {
		return Client{}, err
	}
	for _, c := range clients {
		if c.Name == name {
			return Client{}, fmt.Errorf("client %q already exists", name)
		}
		if c.IP == ip {
			return Client{}, fmt.Errorf("client ip %s already exists", ip)
		}
	}
	now := time.Now().UTC().Format(time.RFC3339)
	c := Client{Name: name, IP: ip, OS: osName, CreatedAt: now, UpdatedAt: now}
	if err := EnsureClientCertificate(r.cfg, c); err != nil {
		return Client{}, err
	}
	return c, r.save(c)
}

func (r Registry) List() ([]Client, error) {
	ents, err := os.ReadDir(r.dir())
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var out []Client
	for _, e := range ents {
		if e.IsDir() || filepath.Ext(e.Name()) != ".json" {
			continue
		}
		var c Client
		b, err := os.ReadFile(filepath.Join(r.dir(), e.Name()))
		if err != nil {
			return nil, err
		}
		if err := json.Unmarshal(b, &c); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

func (r Registry) Revoke(name string) error {
	if err := ValidateClientName(name); err != nil {
		return err
	}
	b, err := os.ReadFile(r.path(name))
	if err != nil {
		if os.IsNotExist(err) {
			return fmt.Errorf("client %q not found", name)
		}
		return err
	}
	var c Client
	if err := json.Unmarshal(b, &c); err != nil {
		return err
	}
	c.Revoked = true
	c.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
	return r.save(c)
}

func (r Registry) dir() string             { return filepath.Join(r.cfg.StateDir, "clients") }
func (r Registry) path(name string) string { return filepath.Join(r.dir(), name+".json") }
func (r Registry) save(c Client) error {
	b, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	return writeSecretFile(r.path(c.Name), append(b, '\n'))
}
func writeSecretFile(path string, b []byte) error {
	if err := ensureSecretDir(filepath.Dir(path)); err != nil {
		return err
	}
	return writeFileWithMode(path, b, 0600)
}

func writeFileWithMode(path string, b []byte, mode os.FileMode) error {
	dir := filepath.Dir(path)
	tmp, err := os.CreateTemp(dir, "."+filepath.Base(path)+".tmp-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if err := tmp.Chmod(mode); err != nil {
		tmp.Close()
		return err
	}
	if _, err := tmp.Write(b); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmpName, path); err != nil {
		return err
	}
	return os.Chmod(path, mode)
}

func ensureSecretDir(path string) error {
	if err := os.MkdirAll(path, 0700); err != nil {
		return err
	}
	return os.Chmod(path, 0700)
}
