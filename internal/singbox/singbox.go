package singbox

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync/atomic"
	"time"

	"github.com/kcnc/vibe-practicum-vpn/internal/state"
)

var runCommand = func(name string, args ...string) error { return exec.Command(name, args...).Run() }
var runSystemctl = func(args ...string) error { return exec.Command("systemctl", args...).Run() }
var lookupIP = net.LookupIP

var restartSequence uint64

const (
	// These bounds keep a misconfigured local supervisor from making a manual
	// apply or rollback wait forever. An unset acknowledgement path remains
	// intentionally asynchronous for backwards compatibility.
	DefaultAckTimeout = 30 * time.Second
	MaxAckTimeout     = 5 * time.Minute
)

type RestartMode string

const (
	RestartModeSystemd     RestartMode = "systemd"
	RestartModeRequestFile RestartMode = "request-file"
)

type RestartConfig struct {
	Mode              RestartMode
	Service           string
	RequestFile       string
	AckGenerationFile string
	// AckFile is a compatibility alias for AckGenerationFile.
	AckFile    string
	AckTimeout time.Duration
	SingBoxBin string
}

func (r RestartConfig) normalized() RestartConfig {
	if r.Mode == "" {
		r.Mode = RestartModeSystemd
	}
	if r.AckGenerationFile == "" {
		r.AckGenerationFile = r.AckFile
	}
	r.AckGenerationFile = strings.TrimSpace(r.AckGenerationFile)
	if r.AckGenerationFile != "" {
		if r.AckTimeout == 0 {
			r.AckTimeout = DefaultAckTimeout
		}
		if r.AckTimeout > MaxAckTimeout {
			r.AckTimeout = MaxAckTimeout
		}
	}
	return r
}

func Check(bin, configPath string) error { return runCommand(bin, "check", "-c", configPath) }

// SyncFromSourcePreserveSelected refreshes a persisted runtime config from the
// rendered source config while preserving the runtime selected-native-out
// outbound. This pure wrapper is retained for callers that only need the file
// transformation. The CLI uses SyncFromSourcePreserveSelectedWithLock so sync
// participates in the same state-dir transaction lock as apply/rollback/prune.
func SyncFromSourcePreserveSelected(sourcePath, runtimePath string) error {
	return syncFromSourcePreserveSelected(sourcePath, runtimePath)
}

// SyncFromSourcePreserveSelectedWithLock is the process-safe sync entrypoint.
func SyncFromSourcePreserveSelectedWithLock(ctx context.Context, sourcePath, runtimePath, stateDir string) error {
	if ctx == nil {
		ctx = context.Background()
	}
	lock, err := state.AcquireLock(ctx, stateDir)
	if err != nil {
		return err
	}
	defer lock.Close()
	return syncFromSourcePreserveSelected(sourcePath, runtimePath)
}

// SyncFromSourcePreserveSelectedLocked performs the transformation for a
// caller that already owns stateDir's lock.
func SyncFromSourcePreserveSelectedLocked(sourcePath, runtimePath string) error {
	return syncFromSourcePreserveSelected(sourcePath, runtimePath)
}

func syncFromSourcePreserveSelected(sourcePath, runtimePath string) error {
	b, err := os.ReadFile(sourcePath)
	if err != nil {
		return err
	}
	var source map[string]any
	if err := json.Unmarshal(b, &source); err != nil {
		return fmt.Errorf("read source sing-box config: %w", err)
	}

	if rb, err := os.ReadFile(runtimePath); err == nil {
		var runtime map[string]any
		if err := json.Unmarshal(rb, &runtime); err != nil {
			return fmt.Errorf("read runtime sing-box config: %w", err)
		}
		if selected, ok := findOutbound(runtime, "selected-native-out"); ok {
			if err := replaceOutbound(source, "selected-native-out", selected); err != nil {
				return err
			}
		}
	} else if !os.IsNotExist(err) {
		return err
	}

	nb, err := json.MarshalIndent(source, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(runtimePath), 0755); err != nil {
		return err
	}
	return writeFileAtomic(runtimePath, append(nb, '\n'), 0644)
}

func findOutbound(cfg map[string]any, tag string) (map[string]any, bool) {
	arr, ok := cfg["outbounds"].([]any)
	if !ok {
		return nil, false
	}
	for _, v := range arr {
		m, ok := v.(map[string]any)
		if !ok {
			continue
		}
		if got, _ := m["tag"].(string); got == tag {
			return m, true
		}
	}
	return nil, false
}

func replaceOutbound(cfg map[string]any, tag string, outbound map[string]any) error {
	arr, ok := cfg["outbounds"].([]any)
	if !ok {
		return fmt.Errorf("source sing-box config has no outbounds")
	}
	for i, v := range arr {
		m, ok := v.(map[string]any)
		if !ok {
			continue
		}
		if got, _ := m["tag"].(string); got == tag {
			arr[i] = outbound
			cfg["outbounds"] = arr
			return nil
		}
	}
	return fmt.Errorf("source sing-box config missing outbound tag %q", tag)
}

func Apply(configPath, stateDir, service string, out map[string]any) (string, error) {
	return ApplyWithRestart(configPath, stateDir, out, RestartConfig{Mode: RestartModeSystemd, Service: service})
}

func Rollback(configPath, stateDir, service string) (string, error) {
	return RollbackWithRestart(configPath, stateDir, RestartConfig{Mode: RestartModeSystemd, Service: service})
}

// ApplyWithRestart takes the state-dir process lock for callers that do not
// already own the transaction boundary.
func ApplyWithRestart(configPath, stateDir string, out map[string]any, restart RestartConfig) (string, error) {
	return ApplyWithRestartContext(context.Background(), configPath, stateDir, out, restart)
}

func ApplyWithRestartContext(ctx context.Context, configPath, stateDir string, out map[string]any, restart RestartConfig) (string, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	lock, err := state.AcquireLock(ctx, stateDir)
	if err != nil {
		return "", err
	}
	defer lock.Close()
	return ApplyWithRestartLockedContext(ctx, configPath, stateDir, out, restart)
}

// ApplyWithRestartLocked performs the runtime mutation for a caller that
// already owns state-dir's lock (daemon transaction paths use this form).
func ApplyWithRestartLocked(configPath, stateDir string, out map[string]any, restart RestartConfig) (string, error) {
	return ApplyWithRestartLockedContext(context.Background(), configPath, stateDir, out, restart)
}

func ApplyWithRestartLockedContext(ctx context.Context, configPath, stateDir string, out map[string]any, restart RestartConfig) (string, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	restart = restart.normalized()
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
	cleanupUncommitted := func() {
		_ = os.Remove(backup)
		_ = state.RemoveSnapshotForBackup(stateDir, backup)
	}
	// The sidecar is written before the runtime file is changed, so a failure
	// here cannot leave a new runtime active without its exact prior state.
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
	if err := restartSingBoxContext(ctx, restart); err != nil {
		// A failed request-file acknowledgement must not leave the candidate
		// config selected. Send the old config back asynchronously during the
		// error path; waiting again could turn one bounded failure into two.
		restoreErr := writeFileAtomic(configPath, b, 0644)
		restartOldErr := error(nil)
		if restoreErr == nil {
			restartOldErr = restartSingBoxContext(context.Background(), withoutAck(restart))
		}
		if restoreErr != nil || restartOldErr != nil {
			return backup, fmt.Errorf("restart after apply failed: %w; restore failed: %v; restart restored config: %v", err, restoreErr, restartOldErr)
		}
		return backup, fmt.Errorf("restart after apply failed: %w; restored backup", err)
	}
	return backup, nil
}

func RollbackWithRestart(configPath, stateDir string, restart RestartConfig) (string, error) {
	return RollbackWithRestartContext(context.Background(), configPath, stateDir, restart)
}

func RollbackWithRestartContext(ctx context.Context, configPath, stateDir string, restart RestartConfig) (string, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	lock, err := state.AcquireLock(ctx, stateDir)
	if err != nil {
		return "", err
	}
	defer lock.Close()
	return RollbackWithRestartLockedContext(ctx, configPath, stateDir, restart)
}

func RollbackWithRestartLocked(configPath, stateDir string, restart RestartConfig) (string, error) {
	return RollbackWithRestartLockedContext(context.Background(), configPath, stateDir, restart)
}

func RollbackWithRestartLockedContext(ctx context.Context, configPath, stateDir string, restart RestartConfig) (string, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := state.MigrateLegacySnapshots(stateDir); err != nil {
		return "", err
	}
	files, err := state.PairedRuntimeBackups(stateDir, "sing-box-")
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
	if err := RestoreBackupWithRestartLockedContext(ctx, configPath, stateDir, last, restart); err != nil {
		return "", err
	}
	if err := snap.Restore(stateDir); err != nil {
		return "", fmt.Errorf("runtime rollback succeeded but state restore failed: %w", err)
	}
	return last, nil
}

// RestoreBackupWithRestart restores one exact runtime backup and uses the same
// restart/request-file supervision path as a normal apply. It is intentionally
// separate from selecting the latest backup so a transaction can restore the
// backup it just created without exposing node material in logs.
func RestoreBackupWithRestart(configPath, stateDir, backupPath string, restart RestartConfig) error {
	return RestoreBackupWithRestartContext(context.Background(), configPath, stateDir, backupPath, restart)
}

func RestoreBackupWithRestartContext(ctx context.Context, configPath, stateDir, backupPath string, restart RestartConfig) error {
	if ctx == nil {
		ctx = context.Background()
	}
	lock, err := state.AcquireLock(ctx, stateDir)
	if err != nil {
		return err
	}
	defer lock.Close()
	return RestoreBackupWithRestartLockedContext(ctx, configPath, stateDir, backupPath, restart)
}

func RestoreBackupWithRestartLocked(configPath, stateDir, backupPath string, restart RestartConfig) error {
	return RestoreBackupWithRestartLockedContext(context.Background(), configPath, stateDir, backupPath, restart)
}

func RestoreBackupWithRestartLockedContext(ctx context.Context, configPath, stateDir, backupPath string, restart RestartConfig) error {
	if ctx == nil {
		ctx = context.Background()
	}
	restart = restart.normalized()
	current, err := os.ReadFile(configPath)
	if err != nil {
		return err
	}
	b, err := os.ReadFile(backupPath)
	if err != nil {
		return err
	}
	if err := validateCandidate(configPath, stateDir, b, restart); err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if err := writeFileAtomic(configPath, append(bytesTrimFinalNewline(b), '\n'), 0644); err != nil {
		return err
	}
	if err := restartSingBoxContext(ctx, restart); err != nil {
		restoreErr := writeFileAtomic(configPath, current, 0644)
		restartOldErr := error(nil)
		if restoreErr == nil {
			restartOldErr = restartSingBoxContext(context.Background(), withoutAck(restart))
		}
		if restoreErr != nil || restartOldErr != nil {
			return fmt.Errorf("restart after rollback failed: %w; restore failed: %v; restart restored config: %v", err, restoreErr, restartOldErr)
		}
		return fmt.Errorf("restart after rollback failed: %w; restored prior config", err)
	}
	return nil
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
		_ = f.Close()
		return err
	}
	if err := f.Chmod(0644); err != nil {
		_ = f.Close()
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

// restartSingBox preserves the original synchronous helper for package-local
// callers; runtime paths that propagate cancellation use the context variant.
func restartSingBox(restart RestartConfig) error {
	return restartSingBoxContext(context.Background(), restart)
}

func restartSingBoxContext(ctx context.Context, restart RestartConfig) error {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	restart = restart.normalized()
	switch restart.Mode {
	case "", RestartModeSystemd:
		_ = runSystemctl("reset-failed", restart.Service)
		return runSystemctl("restart", restart.Service)
	case RestartModeRequestFile:
		if restart.RequestFile == "" {
			return fmt.Errorf("restart request file is empty")
		}
		if restart.AckTimeout < 0 {
			return fmt.Errorf("restart acknowledgement timeout is negative")
		}
		var before string
		var err error
		if restart.AckGenerationFile != "" {
			before, err = readGeneration(restart.AckGenerationFile)
			if err != nil {
				return err
			}
		}
		if err := os.MkdirAll(filepath.Dir(restart.RequestFile), 0755); err != nil {
			return err
		}
		// The request body is deliberately nonempty and unique so two quick
		// applies cannot collapse into one supervisor observation.
		token := fmt.Sprintf("restart-%d-%d\n", time.Now().UnixNano(), atomic.AddUint64(&restartSequence, 1))
		if err := writeFileAtomic(restart.RequestFile, []byte(token), 0600); err != nil {
			return err
		}
		if restart.AckGenerationFile == "" {
			return nil
		}
		return waitForRestartAck(ctx, restart.RequestFile, restart.AckGenerationFile, before, restart.AckTimeout)
	default:
		return fmt.Errorf("unsupported restart mode %q", restart.Mode)
	}
}

func withoutAck(restart RestartConfig) RestartConfig {
	restart.AckGenerationFile = ""
	restart.AckFile = ""
	restart.AckTimeout = 0
	return restart
}

func readGeneration(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return "", nil
		}
		return "", err
	}
	return strings.TrimSpace(string(b)), nil
}

func requestConsumed(path string) (bool, error) {
	_, err := os.Stat(path)
	if err == nil {
		return false, nil
	}
	if os.IsNotExist(err) {
		return true, nil
	}
	return false, err
}

func waitForRestartAck(ctx context.Context, requestFile, generationFile, before string, timeout time.Duration) error {
	if timeout <= 0 {
		timeout = DefaultAckTimeout
	}
	if timeout > MaxAckTimeout {
		timeout = MaxAckTimeout
	}
	deadline := time.NewTimer(timeout)
	defer deadline.Stop()
	tick := time.NewTicker(10 * time.Millisecond)
	defer tick.Stop()
	for {
		consumed, err := requestConsumed(requestFile)
		if err != nil {
			return err
		}
		current, err := readGeneration(generationFile)
		if err != nil {
			return err
		}
		if consumed && current != "" && current != before {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-deadline.C:
			return fmt.Errorf("restart acknowledgement timed out")
		case <-tick.C:
		}
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
	return nil, fmt.Errorf("resolve selected outbound server for container apply: no addresses")
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
