package singbox

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"time"
)

var runCommand = func(name string, args ...string) error { return exec.Command(name, args...).Run() }
var runSystemctl = func(args ...string) error { return exec.Command("systemctl", args...).Run() }

func Check(bin, configPath string) error { return runCommand(bin, "check", "-c", configPath) }

func Apply(configPath, stateDir, service string, out map[string]any) (string, error) {
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
	arr[idx] = outboundWithPreservedTag(out, arr[idx])
	cfg["outbounds"] = arr
	nb, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return "", err
	}
	backup := filepath.Join(backupDir, "sing-box-"+time.Now().Format("20060102-150405.000000000")+".json")
	if err := os.WriteFile(backup, b, 0600); err != nil {
		return "", err
	}
	if err := writeFileAtomic(configPath, append(nb, '\n'), 0644); err != nil {
		return "", err
	}
	_ = runSystemctl("reset-failed", service)
	if err := runSystemctl("restart", service); err != nil {
		restoreErr := writeFileAtomic(configPath, b, 0644)
		_ = runSystemctl("reset-failed", service)
		restartOldErr := runSystemctl("restart", service)
		if restoreErr != nil || restartOldErr != nil {
			return backup, fmt.Errorf("restart %s after apply failed: %w; restore failed: %v; restart restored config: %v", service, err, restoreErr, restartOldErr)
		}
		return backup, fmt.Errorf("restart %s after apply failed: %w; restored backup %s", service, err, backup)
	}
	return backup, nil
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

func Rollback(configPath, stateDir, service string) (string, error) {
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
	if err := writeFileAtomic(configPath, b, 0644); err != nil {
		return "", err
	}
	_ = runSystemctl("reset-failed", service)
	return last, runSystemctl("restart", service)
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
