package xray

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"time"

	"github.com/kcnc/vibe-practicum-vpn/internal/state"
)

var runSystemctl = func(args ...string) error {
	return exec.Command("systemctl", args...).Run()
}

func TempConfig(out map[string]any, socks string) ([]byte, error) {
	host, port, err := split(socks)
	if err != nil {
		return nil, err
	}
	c := map[string]any{"log": map[string]any{"loglevel": "warning"}, "inbounds": []any{map[string]any{"listen": host, "port": port, "protocol": "socks", "settings": map[string]any{"udp": true}}}, "outbounds": []any{out}}
	return json.MarshalIndent(c, "", "  ")
}

func split(s string) (string, int, error) {
	h, ps, err := net.SplitHostPort(s)
	if err != nil {
		return "", 0, err
	}
	p, err := strconv.Atoi(ps)
	if err != nil || p <= 0 || p > 65535 {
		return "", 0, fmt.Errorf("invalid socks address %q", s)
	}
	if h == "" {
		h = "127.0.0.1"
	}
	return h, p, nil
}

func Apply(configPath, stateDir string, out map[string]any) (string, error) {
	return ApplyContext(context.Background(), configPath, stateDir, out)
}

func ApplyContext(ctx context.Context, configPath, stateDir string, out map[string]any) (string, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	lock, err := state.AcquireLock(ctx, stateDir)
	if err != nil {
		return "", err
	}
	defer lock.Close()
	return ApplyLockedContext(ctx, configPath, stateDir, out)
}

func ApplyLocked(configPath, stateDir string, out map[string]any) (string, error) {
	return ApplyLockedContext(context.Background(), configPath, stateDir, out)
}

func ApplyLockedContext(ctx context.Context, configPath, stateDir string, out map[string]any) (string, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	if err := state.MigrateLegacySnapshots(stateDir); err != nil {
		return "", err
	}
	backupDir := filepath.Join(stateDir, "backups")
	if err := os.MkdirAll(backupDir, 0700); err != nil {
		return "", err
	}
	snapshot, err := state.Capture(stateDir)
	if err != nil {
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
	arr[0] = outboundWithPreservedTag(out, arr[0])
	cfg["outbounds"] = arr
	nb, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return "", err
	}
	backup := filepath.Join(backupDir, "xray-"+time.Now().Format("20060102-150405.000000000")+".json")
	if err := os.WriteFile(backup, b, 0600); err != nil {
		return "", err
	}
	cleanupUncommitted := func() {
		_ = os.Remove(backup)
		_ = state.RemoveSnapshotForBackup(stateDir, backup)
	}
	if err := state.SaveSnapshotForBackup(stateDir, backup, snapshot); err != nil {
		cleanupUncommitted()
		return "", err
	}
	if err := ctx.Err(); err != nil {
		cleanupUncommitted()
		return "", err
	}
	if err := writeFileAtomic(configPath, append(nb, '\n'), 0644); err != nil {
		cleanupUncommitted()
		return "", err
	}
	_ = runSystemctl("reset-failed", "xray")
	if err := runSystemctl("restart", "xray"); err != nil {
		restoreErr := writeFileAtomic(configPath, b, 0644)
		_ = runSystemctl("reset-failed", "xray")
		restartOldErr := runSystemctl("restart", "xray")
		if restoreErr != nil || restartOldErr != nil {
			return backup, fmt.Errorf("restart xray after apply failed: %w; restore failed: %v; restart restored config: %v", err, restoreErr, restartOldErr)
		}
		return backup, fmt.Errorf("restart xray after apply failed: %w; restored backup", err)
	}
	return backup, nil
}

func outboundWithPreservedTag(out map[string]any, old any) map[string]any {
	next := make(map[string]any, len(out)+1)
	for k, v := range out {
		next[k] = v
	}
	if _, hasTag := next["tag"]; hasTag {
		return next
	}
	oldMap, ok := old.(map[string]any)
	if !ok {
		return next
	}
	tag, ok := oldMap["tag"].(string)
	if ok && tag != "" {
		next["tag"] = tag
	}
	return next
}

func Rollback(configPath, stateDir string) (string, error) {
	return RollbackContext(context.Background(), configPath, stateDir)
}

func RollbackContext(ctx context.Context, configPath, stateDir string) (string, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	lock, err := state.AcquireLock(ctx, stateDir)
	if err != nil {
		return "", err
	}
	defer lock.Close()
	return RollbackLockedContext(ctx, configPath, stateDir)
}

func RollbackLocked(configPath, stateDir string) (string, error) {
	return RollbackLockedContext(context.Background(), configPath, stateDir)
}

func RollbackLockedContext(ctx context.Context, configPath, stateDir string) (string, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := state.MigrateLegacySnapshots(stateDir); err != nil {
		return "", err
	}
	files, err := state.PairedRuntimeBackups(stateDir, "xray-")
	if err != nil {
		return "", err
	}
	if len(files) == 0 {
		return "", fmt.Errorf("no paired backups")
	}
	sort.Strings(files)
	last := files[len(files)-1]
	// Parse the exact sidecar before changing the runtime. A corrupt state
	// sidecar must fail closed rather than leaving runtime and state mismatched.
	snap, err := state.LoadSnapshotForBackup(stateDir, last)
	if err != nil {
		return "", err
	}
	if err := RestoreBackupLockedContext(ctx, configPath, last); err != nil {
		return "", err
	}
	if err := snap.Restore(stateDir); err != nil {
		return "", fmt.Errorf("runtime rollback succeeded but state restore failed: %w", err)
	}
	return last, nil
}

// RestoreBackup restores one exact runtime backup. It is used by transaction
// rollback so a newer unrelated backup can never be selected accidentally.
func RestoreBackup(configPath, stateDir, backupPath string) error {
	return RestoreBackupContext(context.Background(), configPath, stateDir, backupPath)
}

func RestoreBackupContext(ctx context.Context, configPath, stateDir, backupPath string) error {
	if ctx == nil {
		ctx = context.Background()
	}
	lock, err := state.AcquireLock(ctx, stateDir)
	if err != nil {
		return err
	}
	defer lock.Close()
	return RestoreBackupLockedContext(ctx, configPath, backupPath)
}

func RestoreBackupLocked(configPath, stateDir, backupPath string) error {
	return RestoreBackupLockedContext(context.Background(), configPath, backupPath)
}

func RestoreBackupLockedContext(ctx context.Context, configPath, backupPath string) error {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	current, err := os.ReadFile(configPath)
	if err != nil {
		return err
	}
	b, err := os.ReadFile(backupPath)
	if err != nil {
		return err
	}
	if err := writeFileAtomic(configPath, b, 0644); err != nil {
		return err
	}
	_ = runSystemctl("reset-failed", "xray")
	if err := runSystemctl("restart", "xray"); err != nil {
		restoreErr := writeFileAtomic(configPath, current, 0644)
		_ = runSystemctl("reset-failed", "xray")
		restartOldErr := runSystemctl("restart", "xray")
		if restoreErr != nil || restartOldErr != nil {
			return fmt.Errorf("restart xray after rollback failed: %w; restore failed: %v; restart restored config: %v", err, restoreErr, restartOldErr)
		}
		return fmt.Errorf("restart xray after rollback failed: %w; restored prior config", err)
	}
	return nil
}

func writeFileAtomic(path string, b []byte, perm os.FileMode) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	f, err := os.CreateTemp(dir, "."+filepath.Base(path)+".*.tmp")
	if err != nil {
		return err
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if _, err := f.Write(b); err != nil {
		_ = f.Close()
		return err
	}
	if err := f.Chmod(perm); err != nil {
		_ = f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}
