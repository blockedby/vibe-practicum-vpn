package singbox

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"time"
)

var runCommand = func(name string, args ...string) error { return exec.Command(name, args...).Run() }
var runSystemctl = func(args ...string) error { return exec.Command("systemctl", args...).Run() }
var lookupIP = net.LookupIP

type RestartMode string

const (
	RestartModeSystemd     RestartMode = "systemd"
	RestartModeRequestFile RestartMode = "request-file"
)

type RestartConfig struct {
	Mode        RestartMode
	Service     string
	RequestFile string
	SingBoxBin  string
}

func (r RestartConfig) normalized() RestartConfig {
	if r.Mode == "" {
		r.Mode = RestartModeSystemd
	}
	return r
}

func Check(bin, configPath string) error { return runCommand(bin, "check", "-c", configPath) }

func Apply(configPath, stateDir, service string, out map[string]any) (string, error) {
	return ApplyWithRestart(configPath, stateDir, out, RestartConfig{Mode: RestartModeSystemd, Service: service})
}

func Rollback(configPath, stateDir, service string) (string, error) {
	return RollbackWithRestart(configPath, stateDir, RestartConfig{Mode: RestartModeSystemd, Service: service})
}

func ApplyWithRestart(configPath, stateDir string, out map[string]any, restart RestartConfig) (string, error) {
	restart = restart.normalized()
	backupDir := filepath.Join(stateDir, "backups")
	if err := os.MkdirAll(backupDir, 0700); err != nil {
		return "", err
	}
	b, err := os.ReadFile(configPath)
	if err != nil {
		return "", err
	}
	var cfg map[string]any
	if err := json.Unmarshal(b, &cfg); err != nil {
		return "", err
	}
	arr, ok := cfg["outbounds"].([]any)
	if !ok || len(arr) == 0 {
		return "", fmt.Errorf("no outbounds")
	}
	idx := firstProxyOutbound(arr)
	nextOut, err := outboundForApply(out, arr[idx], restart)
	if err != nil {
		return "", err
	}
	arr[idx] = nextOut
	cfg["outbounds"] = arr
	nb, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return "", err
	}
	if err := validateCandidate(configPath, stateDir, nb, restart); err != nil {
		return "", err
	}
	backup := filepath.Join(backupDir, "sing-box-"+time.Now().Format("20060102-150405.000000000")+".json")
	if err := os.WriteFile(backup, b, 0600); err != nil {
		return "", err
	}
	if err := writeFileAtomic(configPath, append(nb, '\n'), 0644); err != nil {
		return "", err
	}
	if err := restartSingBox(restart); err != nil {
		restoreErr := writeFileAtomic(configPath, b, 0644)
		restartOldErr := restartSingBox(restart)
		if restoreErr != nil || restartOldErr != nil {
			return backup, fmt.Errorf("restart after apply failed: %w; restore failed: %v; restart restored config: %v", err, restoreErr, restartOldErr)
		}
		return backup, fmt.Errorf("restart after apply failed: %w; restored backup %s", err, backup)
	}
	return backup, nil
}

func RollbackWithRestart(configPath, stateDir string, restart RestartConfig) (string, error) {
	restart = restart.normalized()
	files, _ := filepath.Glob(filepath.Join(stateDir, "backups", "sing-box-*.json"))
	if len(files) == 0 {
		return "", fmt.Errorf("no backups")
	}
	sort.Strings(files)
	last := files[len(files)-1]
	b, err := os.ReadFile(last)
	if err != nil {
		return "", err
	}
	if err := validateCandidate(configPath, stateDir, b, restart); err != nil {
		return "", err
	}
	if err := writeFileAtomic(configPath, append(bytesTrimFinalNewline(b), '\n'), 0644); err != nil {
		return "", err
	}
	return last, restartSingBox(restart)
}

func validateCandidate(configPath, stateDir string, b []byte, restart RestartConfig) error {
	if restart.Mode != RestartModeRequestFile || restart.SingBoxBin == "" {
		return nil
	}
	if _, err := exec.LookPath(restart.SingBoxBin); err != nil {
		return nil
	}
	dir := filepath.Dir(configPath)
	if dir == "" || dir == "." {
		dir = stateDir
	}
	f, err := os.CreateTemp(dir, ".vibe-vpn-check-*.json")
	if err != nil {
		return err
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if _, err := f.Write(append(bytesTrimFinalNewline(b), '\n')); err != nil {
		f.Close()
		return err
	}
	if err := f.Chmod(0644); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	if err := Check(restart.SingBoxBin, tmp); err != nil {
		return fmt.Errorf("sing-box check candidate: %w", err)
	}
	return nil
}

func restartSingBox(restart RestartConfig) error {
	switch restart.Mode {
	case "", RestartModeSystemd:
		_ = runSystemctl("reset-failed", restart.Service)
		return runSystemctl("restart", restart.Service)
	case RestartModeRequestFile:
		if restart.RequestFile == "" {
			return fmt.Errorf("restart request file is empty")
		}
		if err := os.MkdirAll(filepath.Dir(restart.RequestFile), 0755); err != nil {
			return err
		}
		return os.WriteFile(restart.RequestFile, []byte(time.Now().Format(time.RFC3339Nano)+"\n"), 0644)
	default:
		return fmt.Errorf("unsupported restart mode %q", restart.Mode)
	}
}

func bytesTrimFinalNewline(b []byte) []byte {
	for len(b) > 0 && (b[len(b)-1] == '\n' || b[len(b)-1] == '\r') {
		b = b[:len(b)-1]
	}
	return b
}

func firstProxyOutbound(arr []any) int {
	for i, v := range arr {
		if m, ok := v.(map[string]any); ok {
			tag, _ := m["tag"].(string)
			if tag == "selected-native-out" || tag == "proxy" || tag == "xray-socks-out" {
				return i
			}
		}
	}
	return 0
}
func outboundForApply(out map[string]any, old any, restart RestartConfig) (map[string]any, error) {
	next := outboundWithPreservedTag(out, old)
	if restart.Mode != RestartModeRequestFile {
		return next, nil
	}
	return preResolveOutboundServer(next)
}

func outboundWithPreservedTag(out map[string]any, old any) map[string]any {
	next := make(map[string]any, len(out)+1)
	for k, v := range out {
		next[k] = v
	}
	if _, ok := next["tag"]; ok {
		return next
	}
	if m, ok := old.(map[string]any); ok {
		if tag, ok := m["tag"].(string); ok && tag != "" {
			next["tag"] = tag
		}
	}
	return next
}

func preResolveOutboundServer(out map[string]any) (map[string]any, error) {
	server, _ := out["server"].(string)
	if server == "" {
		return out, nil
	}
	if net.ParseIP(server) != nil {
		return out, nil
	}
	ips, err := lookupIP(server)
	if err != nil {
		return nil, fmt.Errorf("resolve selected outbound server for container apply: %w", err)
	}
	for _, ip := range ips {
		if v4 := ip.To4(); v4 != nil {
			out["server"] = v4.String()
			return out, nil
		}
	}
	if len(ips) > 0 {
		out["server"] = ips[0].String()
		return out, nil
	}
	return nil, fmt.Errorf("resolve selected outbound server for container apply: no addresses for %s", server)
}

func writeFileAtomic(path string, b []byte, perm os.FileMode) error {
	dir := filepath.Dir(path)
	f, err := os.CreateTemp(dir, "."+filepath.Base(path)+".*.tmp")
	if err != nil {
		return err
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if _, err := f.Write(b); err != nil {
		f.Close()
		return err
	}
	if err := f.Chmod(perm); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}
