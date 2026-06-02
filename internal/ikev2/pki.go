package ikev2

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/pem"
	"fmt"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
	"software.sslmate.com/src/go-pkcs12"
)

const (
	caCertRelPath     = "pki/ca/ca-cert.pem"
	caKeyRelPath      = "pki/private/ca-key.pem"
	serverCertRelPath = "pki/server/server-cert.pem"
	serverKeyRelPath  = "pki/private/server-key.pem"
)

func EnsurePKI(c config.IKEv2Config) error {
	c.ApplyDefaults()
	if err := ensurePKIDirs(c); err != nil {
		return err
	}
	caCert, caKey, err := ensureCA(c)
	if err != nil {
		return err
	}
	return ensureServerCertificate(c, caCert, caKey)
}

func EnsureClientCertificate(c config.IKEv2Config, cl Client) error {
	c.ApplyDefaults()
	if err := ValidateClientName(cl.Name); err != nil {
		return err
	}
	if err := ValidateClientIP(c, cl.IP); err != nil {
		return err
	}
	if err := EnsurePKI(c); err != nil {
		return err
	}
	certPath, keyPath := clientCertPath(c, cl.Name), clientKeyPath(c, cl.Name)
	if fileExists(certPath) && fileExists(keyPath) {
		return nil
	}
	caCert, caKey, err := loadCA(c)
	if err != nil {
		return err
	}
	key, err := rsa.GenerateKey(rand.Reader, 3072)
	if err != nil {
		return err
	}
	now := time.Now().UTC()
	serial, err := randomSerial()
	if err != nil {
		return err
	}
	tpl := &x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: cl.Name, Organization: []string{"vibe-vpn IKEv2 clients"}},
		NotBefore:    now.Add(-time.Hour),
		NotAfter:     now.AddDate(2, 0, 0),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth},
		DNSNames:     []string{cl.Name},
	}
	der, err := x509.CreateCertificate(rand.Reader, tpl, caCert, &key.PublicKey, caKey)
	if err != nil {
		return err
	}
	if err := writePEMFile(keyPath, 0600, "RSA PRIVATE KEY", x509.MarshalPKCS1PrivateKey(key)); err != nil {
		return err
	}
	return writePEMFile(certPath, 0644, "CERTIFICATE", der)
}

func BuildClientPKCS12(c config.IKEv2Config, cl Client, password string) ([]byte, error) {
	c.ApplyDefaults()
	if err := EnsureClientCertificate(c, cl); err != nil {
		return nil, err
	}
	cert, err := loadCertificate(clientCertPath(c, cl.Name))
	if err != nil {
		return nil, err
	}
	key, err := loadRSAPrivateKey(clientKeyPath(c, cl.Name))
	if err != nil {
		return nil, err
	}
	ca, _, err := loadCA(c)
	if err != nil {
		return nil, err
	}
	return pkcs12.Legacy.WithRand(rand.Reader).Encode(key, cert, []*x509.Certificate{ca}, password)
}

func RandomProfilePassword() (string, error) {
	buf := make([]byte, 24)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return strings.TrimRight(base64.URLEncoding.EncodeToString(buf), "="), nil
}

func ensurePKIDirs(c config.IKEv2Config) error {
	dirs := []string{
		c.ConfigDir, c.StateDir,
		filepath.Join(c.ConfigDir, "pki"), filepath.Join(c.ConfigDir, "pki", "ca"), filepath.Join(c.ConfigDir, "pki", "server"), filepath.Join(c.ConfigDir, "pki", "clients"), filepath.Join(c.ConfigDir, "pki", "private"),
		filepath.Join(c.StateDir, "clients"),
	}
	for _, d := range dirs {
		if err := ensureSecretDir(d); err != nil {
			return err
		}
	}
	for _, f := range []string{filepath.Join(c.ConfigDir, "pki", "private", ".keep"), filepath.Join(c.StateDir, "clients", ".keep")} {
		if !fileExists(f) {
			if err := writeSecretFile(f, []byte("vibe-vpn pki/state directory marker; secret material is stored next to this file\n")); err != nil {
				return err
			}
		}
	}
	return nil
}

func ensureCA(c config.IKEv2Config) (*x509.Certificate, *rsa.PrivateKey, error) {
	certPath, keyPath := filepath.Join(c.ConfigDir, caCertRelPath), filepath.Join(c.ConfigDir, caKeyRelPath)
	if fileExists(certPath) && fileExists(keyPath) {
		cert, key, err := loadCA(c)
		return cert, key, err
	}
	key, err := rsa.GenerateKey(rand.Reader, 3072)
	if err != nil {
		return nil, nil, err
	}
	now := time.Now().UTC()
	serial, err := randomSerial()
	if err != nil {
		return nil, nil, err
	}
	tpl := &x509.Certificate{
		SerialNumber:          serial,
		Subject:               pkix.Name{CommonName: "vibe-vpn IKEv2 CA", Organization: []string{"vibe-vpn"}},
		NotBefore:             now.Add(-time.Hour),
		NotAfter:              now.AddDate(10, 0, 0),
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign | x509.KeyUsageDigitalSignature,
		BasicConstraintsValid: true,
		IsCA:                  true,
		MaxPathLenZero:        true,
	}
	der, err := x509.CreateCertificate(rand.Reader, tpl, tpl, &key.PublicKey, key)
	if err != nil {
		return nil, nil, err
	}
	if err := writePEMFile(keyPath, 0600, "RSA PRIVATE KEY", x509.MarshalPKCS1PrivateKey(key)); err != nil {
		return nil, nil, err
	}
	if err := writePEMFile(certPath, 0644, "CERTIFICATE", der); err != nil {
		return nil, nil, err
	}
	cert, err := x509.ParseCertificate(der)
	if err != nil {
		return nil, nil, err
	}
	return cert, key, nil
}

func ensureServerCertificate(c config.IKEv2Config, caCert *x509.Certificate, caKey *rsa.PrivateKey) error {
	certPath, keyPath := filepath.Join(c.ConfigDir, serverCertRelPath), filepath.Join(c.ConfigDir, serverKeyRelPath)
	if fileExists(certPath) && fileExists(keyPath) {
		return nil
	}
	serverName := c.ServerName
	if serverName == "" {
		serverName = "vibe"
	}
	key, err := rsa.GenerateKey(rand.Reader, 3072)
	if err != nil {
		return err
	}
	now := time.Now().UTC()
	serial, err := randomSerial()
	if err != nil {
		return err
	}
	tpl := &x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: serverName, Organization: []string{"vibe-vpn"}},
		NotBefore:    now.Add(-time.Hour),
		NotAfter:     now.AddDate(2, 0, 0),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	addNameToCertTemplate(tpl, serverName)
	if c.PublicEndpoint != "" && c.PublicEndpoint != serverName {
		addNameToCertTemplate(tpl, c.PublicEndpoint)
	}
	der, err := x509.CreateCertificate(rand.Reader, tpl, caCert, &key.PublicKey, caKey)
	if err != nil {
		return err
	}
	if err := writePEMFile(keyPath, 0600, "RSA PRIVATE KEY", x509.MarshalPKCS1PrivateKey(key)); err != nil {
		return err
	}
	return writePEMFile(certPath, 0644, "CERTIFICATE", der)
}

func addNameToCertTemplate(tpl *x509.Certificate, name string) {
	if ip := net.ParseIP(name); ip != nil {
		tpl.IPAddresses = append(tpl.IPAddresses, ip)
	} else {
		tpl.DNSNames = append(tpl.DNSNames, name)
	}
}

func loadCA(c config.IKEv2Config) (*x509.Certificate, *rsa.PrivateKey, error) {
	cert, err := loadCertificate(filepath.Join(c.ConfigDir, caCertRelPath))
	if err != nil {
		return nil, nil, err
	}
	key, err := loadRSAPrivateKey(filepath.Join(c.ConfigDir, caKeyRelPath))
	if err != nil {
		return nil, nil, err
	}
	return cert, key, nil
}

func loadCertificate(path string) (*x509.Certificate, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	block, _ := pem.Decode(b)
	if block == nil || block.Type != "CERTIFICATE" {
		return nil, fmt.Errorf("%s does not contain a PEM certificate", path)
	}
	return x509.ParseCertificate(block.Bytes)
}

func loadRSAPrivateKey(path string) (*rsa.PrivateKey, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	block, _ := pem.Decode(b)
	if block == nil {
		return nil, fmt.Errorf("%s does not contain a PEM private key", path)
	}
	switch block.Type {
	case "RSA PRIVATE KEY":
		return x509.ParsePKCS1PrivateKey(block.Bytes)
	case "PRIVATE KEY":
		key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
		if err != nil {
			return nil, err
		}
		rsaKey, ok := key.(*rsa.PrivateKey)
		if !ok {
			return nil, fmt.Errorf("%s contains a non-RSA private key", path)
		}
		return rsaKey, nil
	default:
		return nil, fmt.Errorf("%s contains unsupported PEM block %s", path, block.Type)
	}
}

func writePEMFile(path string, mode os.FileMode, typ string, der []byte) error {
	if err := ensureSecretDir(filepath.Dir(path)); err != nil {
		return err
	}
	return writeFileWithMode(path, pem.EncodeToMemory(&pem.Block{Type: typ, Bytes: der}), mode)
}

func clientCertPath(c config.IKEv2Config, name string) string {
	return filepath.Join(c.ConfigDir, "pki", "clients", name+"-cert.pem")
}

func clientKeyPath(c config.IKEv2Config, name string) string {
	return filepath.Join(c.ConfigDir, "pki", "private", name+"-key.pem")
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func randomSerial() (*big.Int, error) {
	serialLimit := new(big.Int).Lsh(big.NewInt(1), 128)
	serial, err := rand.Int(rand.Reader, serialLimit)
	if err != nil {
		return nil, fmt.Errorf("generate certificate serial: %w", err)
	}
	return serial, nil
}
