package singbox

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/kcnc/vibe-practicum-vpn/internal/state"
)

type commandRunner func(context.Context, string, ...string) error
type systemctlRunner func(context.Context, ...string) (string, error)

var runCommand commandRunner = func(ctx context.Context, name string, args ...string) error {
	return runExternal(ctx, name, args...)
}
var runSystemctl systemctlRunner = func(ctx context.Context, args ...string) (string, error) {
	return runExternalOutput(ctx, "systemctl", args...)
}
var readProcessCmdline = readProcessCmdlineFile
var readProcessStartTime = readProcessStartTimeFile
var lookupIP = net.LookupIP

var restartSequence uint64

const (
	// These bounds keep a misconfigured local supervisor from making a manual
	// apply or rollback wait forever. Normal request-file operations require the
	// token, generation, and health acknowledgement path.
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
	// AckFile is the supervisor's health acknowledgement file. Its content
	// binds the request token to the exact generation and a healthy predicate.
	AckFile string
	// HealthAckFile is an explicit-name alias retained for callers that prefer
	// to distinguish the health acknowledgement from the generation marker.
	HealthAckFile string
	// ConfigPath, ProbeAddress, and HealthTimeout define the host-systemd
	// verification contract. Container/request-file supervision has its own
	// token/generation/health acknowledgement contract.
	ConfigPath    string
	ProbeAddress  string
	HealthTimeout time.Duration
	AckTimeout    time.Duration
	SingBoxBin    string
}

const (
	DefaultHealthTimeout = 30 * time.Second
	MaxHealthTimeout     = 5 * time.Minute
)

func (r RestartConfig) normalized() RestartConfig {
	if r.Mode == "" {
		r.Mode = RestartModeSystemd
	}
	r.AckGenerationFile = strings.TrimSpace(r.AckGenerationFile)
	if r.AckFile == "" {
		r.AckFile = r.HealthAckFile
	}
	r.AckFile = strings.TrimSpace(r.AckFile)
	if r.Mode == RestartModeSystemd && strings.TrimSpace(r.SingBoxBin) == "" {
		r.SingBoxBin = "sing-box"
	}
	if r.HealthTimeout <= 0 {
		r.HealthTimeout = r.AckTimeout
	}
	if r.HealthTimeout <= 0 {
		r.HealthTimeout = DefaultHealthTimeout
	}
	if r.HealthTimeout > MaxHealthTimeout {
		r.HealthTimeout = MaxHealthTimeout
	}
	if r.AckGenerationFile != "" {
		if r.AckFile == "" {
			r.AckFile = r.AckGenerationFile + ".ack"
		}
		if r.AckTimeout == 0 {
			r.AckTimeout = DefaultAckTimeout
		}
		if r.AckTimeout > MaxAckTimeout {
			r.AckTimeout = MaxAckTimeout
		}
	}
	return r
}

func Check(bin, configPath string) error {
	return CheckContext(context.Background(), bin, configPath)
}

func CheckContext(ctx context.Context, bin, configPath string) error {
	if ctx == nil {
		ctx = context.Background()
	}
	args, err := singBoxCheckArgs(configPath)
	if err != nil {
		return err
	}
	return runCommand(ctx, bin, args...)
}

func singBoxCheckArgs(configPath string) ([]string, error) {
	if canonical, err := canonicalConfigPath(configPath); err == nil {
		configPath = canonical
	}
	info, err := os.Stat(configPath)
	if err != nil {
		// Preserve the external command's historical error handling for a
		// missing path; the systemd identity gate separately requires an
		// existing canonical path.
		return []string{"check", "-c", configPath}, nil
	}
	if info.IsDir() {
		return []string{"check", "-C", configPath}, nil
	}
	if !info.Mode().IsRegular() {
		return nil, fmt.Errorf("sing-box config path is not a regular file or directory")
	}
	return []string{"check", "-c", configPath}, nil
}

// RestartWithAckContext re-runs the supervised restart/health handshake
// without changing the config file. Transaction recovery uses it to ensure a
// child that died after an earlier acknowledgement cannot turn a stale
// runtime file into a newly committed selected state.
func RestartWithAckContext(ctx context.Context, restart RestartConfig) error {
	return restartSingBoxContext(ctx, restart)
}

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
	return ApplyWithRestart(configPath, stateDir, out, RestartConfig{Mode: RestartModeSystemd, Service: service, ConfigPath: configPath, SingBoxBin: "sing-box"})
}

func Rollback(configPath, stateDir, service string) (string, error) {
	return RollbackWithRestart(configPath, stateDir, RestartConfig{Mode: RestartModeSystemd, Service: service, ConfigPath: configPath, SingBoxBin: "sing-box"})
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
	if strings.TrimSpace(restart.ConfigPath) == "" {
		restart.ConfigPath = configPath
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
	if err := validateCandidateContext(ctx, configPath, stateDir, nb, restart); err != nil {
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
		// A failed acknowledgement must not leave the candidate selected.
		// Compensation uses the same supervised protocol; a bare request is
		// not proof that the old runtime is serving.
		restoreErr := writeFileAtomic(configPath, b, 0644)
		restartOldErr := error(nil)
		if restoreErr == nil {
			restartOldErr = restartSingBoxContext(context.Background(), restart)
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
	if strings.TrimSpace(restart.ConfigPath) == "" {
		restart.ConfigPath = configPath
	}
	restart = restart.normalized()
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
	if strings.TrimSpace(restart.ConfigPath) == "" {
		restart.ConfigPath = configPath
	}
	restart = restart.normalized()
	current, err := os.ReadFile(configPath)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	if os.IsNotExist(err) {
		current = nil
	}
	b, err := os.ReadFile(backupPath)
	if err != nil {
		return err
	}
	if err := validateCandidateContext(ctx, configPath, stateDir, b, restart); err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if err := writeFileAtomic(configPath, b, 0644); err != nil {
		return err
	}
	if err := restartSingBoxContext(ctx, restart); err != nil {
		restoreErr := restoreRuntimeFile(configPath, current)
		restartOldErr := error(nil)
		if restoreErr == nil {
			// A compensation restart is supervised by the same token,
			// generation, and health-ack protocol. An unacknowledged request
			// cannot be used to close a transaction journal.
			restartOldErr = restartSingBoxContext(context.Background(), restart)
		}
		if restoreErr != nil || restartOldErr != nil {
			return fmt.Errorf("restart after rollback failed: %w; restore failed: %v; restart restored config: %v", err, restoreErr, restartOldErr)
		}
		return fmt.Errorf("restart after rollback failed: %w; restored prior config", err)
	}
	return nil
}

func restoreRuntimeFile(path string, b []byte) error {
	if b == nil {
		err := os.Remove(path)
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	return writeFileAtomic(path, b, 0644)
}

func validateCandidate(configPath, stateDir string, b []byte, restart RestartConfig) error {
	return validateCandidateContext(context.Background(), configPath, stateDir, b, restart)
}

func validateCandidateContext(ctx context.Context, configPath, stateDir string, b []byte, restart RestartConfig) error {
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
	if err := CheckContext(ctx, restart.SingBoxBin, tmp); err != nil {
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
		return restartSingBoxSystemdContext(ctx, restart)
	case RestartModeRequestFile:
		if restart.RequestFile == "" {
			return fmt.Errorf("restart request file is empty")
		}
		// Request-file mode is always supervised. A generation bump without a
		// matching token-bound healthy acknowledgement is not proof of a live
		// runtime and can never close a transaction.
		if restart.AckGenerationFile == "" {
			return fmt.Errorf("restart generation acknowledgement is required")
		}
		if restart.AckTimeout < 0 {
			return fmt.Errorf("restart acknowledgement timeout is negative")
		}
		before, err := readGeneration(restart.AckGenerationFile)
		if err != nil {
			return err
		}
		if restart.AckFile == "" {
			return fmt.Errorf("restart health acknowledgement file is empty")
		}
		if err := os.MkdirAll(filepath.Dir(restart.RequestFile), 0755); err != nil {
			return err
		}
		// The request body is deliberately nonempty and unique so two quick
		// applies cannot collapse into one supervisor observation.
		token := fmt.Sprintf("restart-%d-%d-%d", os.Getpid(), time.Now().UnixNano(), atomic.AddUint64(&restartSequence, 1))
		if err := writeFileAtomic(restart.RequestFile, []byte(token+"\n"), 0600); err != nil {
			return err
		}
		return waitForRestartAck(ctx, restart.RequestFile, restart.AckFile, restart.AckGenerationFile, token, before, restart.AckTimeout)
	default:
		return fmt.Errorf("unsupported restart mode %q", restart.Mode)
	}
}

// restartSingBoxSystemdContext is the explicit host-systemd contract. It does
// not inspect Docker/container health: after restart the unit must be active,
// sing-box must accept its config with `check`, and (when configured) the
// production SOCKS listener must complete a SOCKS5 greeting. Every observation
// and the restart operation are bounded by HealthTimeout; a failed predicate
// fails closed rather than treating systemctl success as health.
func restartSingBoxSystemdContext(ctx context.Context, restart RestartConfig) error {
	if ctx == nil {
		ctx = context.Background()
	}
	if strings.TrimSpace(restart.Service) == "" {
		return fmt.Errorf("sing-box systemd service is empty")
	}
	if strings.TrimSpace(restart.ConfigPath) == "" {
		return fmt.Errorf("sing-box systemd config path is empty")
	}
	if strings.TrimSpace(restart.SingBoxBin) == "" {
		return fmt.Errorf("sing-box systemd binary is empty")
	}
	timeout := restart.HealthTimeout
	if timeout <= 0 {
		timeout = DefaultHealthTimeout
	}
	if timeout > MaxHealthTimeout {
		timeout = MaxHealthTimeout
	}
	operationCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	systemctl := runSystemctl
	command := runCommand

	if _, err := systemctl(operationCtx, "reset-failed", restart.Service); err != nil && operationCtx.Err() != nil {
		return fmt.Errorf("reset sing-box service failure state failed: %w", err)
	}
	if _, err := systemctl(operationCtx, "restart", restart.Service); err != nil {
		// systemctl may have submitted a unit job before its client was
		// canceled. Stop only this unit, using an independent bounded context,
		// so a late restart cannot surprise a later transaction.
		bestEffortStopSystemdUnit(systemctl, restart.Service)
		return fmt.Errorf("restart sing-box service failed: %w", err)
	}

	err := verifySingBoxSystemdHealth(operationCtx, restart, systemctl, command)
	if err != nil {
		bestEffortStopSystemdUnit(systemctl, restart.Service)
	}
	return err
}

func verifySingBoxSystemdHealth(ctx context.Context, restart RestartConfig, systemctl systemctlRunner, command commandRunner) error {
	return runSystemdHealth(ctx, restart, func(healthCtx context.Context) error {
		// Capture the unit state and process identity before any predicate that
		// could be satisfied by a stale listener or file. The final proof closes
		// the race window around the offline check and optional SOCKS probe.
		identity, err := captureSingBoxProcess(healthCtx, restart, systemctl)
		if err != nil {
			return err
		}
		checkArgs, err := singBoxCheckArgs(identity.configPath)
		if err != nil {
			return err
		}
		if err := command(healthCtx, restart.SingBoxBin, checkArgs...); err != nil {
			return fmt.Errorf("sing-box config check failed: %w", err)
		}
		if strings.TrimSpace(restart.ProbeAddress) != "" {
			if err := probeSocks(healthCtx, restart.ProbeAddress); err != nil {
				return fmt.Errorf("sing-box SOCKS probe failed: %w", err)
			}
		}
		if err := verifySingBoxProcessUnchanged(healthCtx, restart, identity, systemctl); err != nil {
			return err
		}
		return nil
	})
}

func runSystemdHealth(ctx context.Context, restart RestartConfig, check func(context.Context) error) error {
	if ctx == nil {
		ctx = context.Background()
	}
	timeout := restart.HealthTimeout
	if timeout <= 0 {
		timeout = DefaultHealthTimeout
	}
	if timeout > MaxHealthTimeout {
		timeout = MaxHealthTimeout
	}
	healthCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	if err := check(healthCtx); err != nil {
		if healthCtx.Err() != nil {
			return fmt.Errorf("sing-box post-restart health verification timed out: %w", healthCtx.Err())
		}
		return fmt.Errorf("sing-box post-restart health verification failed: %w", err)
	}
	return nil
}

// runExternal runs one command in its own process group. A context timeout
// kills the group, not just the systemctl/sing-box parent, so a blocking fake
// or wrapper cannot perform a late unit mutation after the caller has failed.
func runExternal(ctx context.Context, name string, args ...string) error {
	_, err := runExternalOutput(ctx, name, args...)
	return err
}

func runExternalOutput(ctx context.Context, name string, args ...string) (string, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	cmd := exec.Command(name, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	var out strings.Builder
	cmd.Stdout = &out
	cmd.Stderr = io.Discard
	if err := cmd.Start(); err != nil {
		return "", err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err := <-done:
		return out.String(), err
	case <-ctx.Done():
		terminateExternalProcessGroup(cmd, done)
		return out.String(), ctx.Err()
	}
}

func terminateExternalProcessGroup(cmd *exec.Cmd, done <-chan error) {
	if cmd.Process != nil {
		pid := cmd.Process.Pid
		_ = syscall.Kill(-pid, syscall.SIGTERM)
		timer := time.NewTimer(100 * time.Millisecond)
		select {
		case <-done:
			timer.Stop()
		case <-timer.C:
		}
		// The parent may have exited on SIGTERM while a descendant ignored it;
		// always issue the group SIGKILL before declaring cancellation complete.
		_ = syscall.Kill(-pid, syscall.SIGKILL)
		_ = cmd.Process.Kill()
	}
	select {
	case <-done:
	case <-time.After(time.Second):
	}
}

func bestEffortStopSystemdUnit(systemctl systemctlRunner, service string) {
	if strings.TrimSpace(service) == "" {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_, _ = systemctl(ctx, "stop", service)
}

type singBoxProcessIdentity struct {
	pid        int
	startTime  string
	cmdline    string
	configPath string
}

func captureSingBoxProcess(ctx context.Context, restart RestartConfig, systemctl systemctlRunner) (singBoxProcessIdentity, error) {
	var identity singBoxProcessIdentity
	if _, err := systemctl(ctx, "is-active", "--quiet", restart.Service); err != nil {
		return identity, fmt.Errorf("sing-box service is not active: %w", err)
	}
	want, err := canonicalConfigPath(restart.ConfigPath)
	if err != nil {
		return identity, fmt.Errorf("sing-box config path: %w", err)
	}
	mainPID, execStart, err := singBoxProcessMetadataWithRunner(ctx, restart.Service, systemctl)
	if err != nil {
		return identity, fmt.Errorf("sing-box systemd metadata: %w", err)
	}
	execArgs, err := parseExecStartArgs(execStart)
	if err != nil {
		return identity, fmt.Errorf("sing-box effective ExecStart: %w", err)
	}
	if err := validateSingBoxInvocation(execArgs, want, restart.SingBoxBin); err != nil {
		return identity, fmt.Errorf("sing-box effective ExecStart: %w", err)
	}
	cmdArgs, err := readProcessCmdline(mainPID)
	if err != nil {
		return identity, fmt.Errorf("sing-box MainPID cmdline: %w", err)
	}
	cmdline, err := singBoxCmdlineIdentity(cmdArgs, want, restart.SingBoxBin)
	if err != nil {
		return identity, fmt.Errorf("sing-box MainPID cmdline: %w", err)
	}
	// Read stat after cmdline validation so an exit or PID reuse between the
	// two /proc reads cannot produce a mixed-process proof.
	startTime, err := readProcessStartTime(mainPID)
	if err != nil {
		return identity, fmt.Errorf("sing-box MainPID start time: %w", err)
	}
	if strings.TrimSpace(startTime) == "" {
		return identity, fmt.Errorf("sing-box MainPID start time is empty")
	}
	return singBoxProcessIdentity{pid: mainPID, startTime: startTime, cmdline: cmdline, configPath: want}, nil
}

// verifySingBoxProcess retains the package-local initial-proof helper used by
// older callers and tests. The health gate uses captureSingBoxProcess so it
// can compare the identity again after all probes complete.
func verifySingBoxProcess(ctx context.Context, restart RestartConfig) error {
	_, err := captureSingBoxProcess(ctx, restart, runSystemctl)
	return err
}

func verifySingBoxProcessUnchanged(ctx context.Context, restart RestartConfig, expected singBoxProcessIdentity, systemctl systemctlRunner) error {
	if _, err := systemctl(ctx, "is-active", "--quiet", restart.Service); err != nil {
		return fmt.Errorf("sing-box service is not active after health probe: %w", err)
	}
	mainPID, err := singBoxMainPIDWithRunner(ctx, restart.Service, systemctl)
	if err != nil {
		return fmt.Errorf("sing-box MainPID after health probe: %w", err)
	}
	if mainPID != expected.pid {
		return fmt.Errorf("sing-box MainPID changed after health probe: was %d, now %d", expected.pid, mainPID)
	}
	cmdArgs, err := readProcessCmdline(mainPID)
	if err != nil {
		return fmt.Errorf("sing-box MainPID cmdline after health probe: %w", err)
	}
	cmdline, err := singBoxCmdlineIdentity(cmdArgs, expected.configPath, restart.SingBoxBin)
	if err != nil {
		return fmt.Errorf("sing-box MainPID cmdline after health probe: %w", err)
	}
	if cmdline != expected.cmdline {
		return fmt.Errorf("sing-box MainPID cmdline identity changed after health probe")
	}
	// Keep the immutable token as the last /proc observation. If the process
	// exited and the PID was reused while reading cmdline, this catches it.
	startTime, err := readProcessStartTime(mainPID)
	if err != nil {
		return fmt.Errorf("sing-box MainPID start time after health probe: %w", err)
	}
	if strings.TrimSpace(startTime) == "" {
		return fmt.Errorf("sing-box MainPID start time after health probe is empty")
	}
	if startTime != expected.startTime {
		return fmt.Errorf("sing-box process start time changed after health probe: was %q, now %q", expected.startTime, startTime)
	}
	return nil
}

func singBoxCmdlineIdentity(args []string, want, configuredBinary string) (string, error) {
	// systemd's effective ExecStart proves the configured executable. The
	// MainPID cmdline is compared byte-for-byte across the health window, but
	// test/supervisor wrappers may legitimately use a different argv[0].
	if err := validateSingBoxInvocation(args, want, ""); err != nil {
		return "", err
	}
	return strings.Join(args, "\x00"), nil
}

func canonicalConfigPath(path string) (string, error) {
	path = strings.TrimSpace(path)
	if path == "" {
		return "", fmt.Errorf("path is empty")
	}
	if !filepath.IsAbs(path) {
		return "", fmt.Errorf("path is not absolute")
	}
	p, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	// EvalSymlinks deliberately returns the no-symlink identity used for both
	// file and directory invocations. A lexical path and a symlink alias must
	// not be treated as two different runtime configurations.
	p, err = filepath.EvalSymlinks(p)
	if err != nil {
		return "", err
	}
	info, err := os.Stat(p)
	if err != nil {
		return "", err
	}
	if !info.Mode().IsRegular() && !info.IsDir() {
		return "", fmt.Errorf("path is not a regular file or directory")
	}
	return filepath.Clean(p), nil
}

func canonicalExecutablePath(path string) (string, error) {
	path = strings.TrimSpace(path)
	if path == "" {
		return "", fmt.Errorf("binary is empty")
	}
	if !filepath.IsAbs(path) {
		var err error
		path, err = exec.LookPath(path)
		if err != nil {
			return "", err
		}
	}
	path, err := filepath.EvalSymlinks(path)
	if err != nil {
		return "", err
	}
	info, err := os.Stat(path)
	if err != nil {
		return "", err
	}
	if !info.Mode().IsRegular() {
		return "", fmt.Errorf("binary path is not a regular file")
	}
	return filepath.Clean(path), nil
}

func binaryInvocationMatches(got, configured string) bool {
	got = strings.TrimSpace(got)
	configured = strings.TrimSpace(configured)
	if got == "" || configured == "" {
		return false
	}
	if filepath.IsAbs(configured) {
		wantPath, wantErr := canonicalExecutablePath(configured)
		gotPath, gotErr := canonicalExecutablePath(got)
		return wantErr == nil && gotErr == nil && wantPath == gotPath
	}
	// Resolve a known bare name through PATH so an unrelated executable with
	// the same basename cannot satisfy the proof. If the binary is not
	// installed in a unit-test/supervisor environment, retain basename
	// compatibility for the existing fake-runtime contract.
	if wantPath, wantErr := canonicalExecutablePath(configured); wantErr == nil {
		gotPath, gotErr := canonicalExecutablePath(got)
		return gotErr == nil && wantPath == gotPath
	}
	return filepath.Base(got) == filepath.Base(configured)
}

func systemdProcessMetadata(ctx context.Context, service string) (int, string, error) {
	return singBoxProcessMetadataWithRunner(ctx, service, runSystemctl)
}

func singBoxProcessMetadataWithRunner(ctx context.Context, service string, systemctl systemctlRunner) (int, string, error) {
	pid, err := singBoxMainPIDWithRunner(ctx, service, systemctl)
	if err != nil {
		return 0, "", err
	}
	execStart, err := systemctl(ctx, "show", "--no-pager", "--property=ExecStart", "--value", service)
	if err != nil {
		return 0, "", err
	}
	return pid, execStart, nil
}

func singBoxMainPIDWithRunner(ctx context.Context, service string, systemctl systemctlRunner) (int, error) {
	pidText, err := systemctl(ctx, "show", "--no-pager", "--property=MainPID", "--value", service)
	if err != nil {
		return 0, err
	}
	rawPID := ""
	for _, line := range strings.Split(pidText, "\n") {
		line = strings.TrimSpace(strings.TrimPrefix(line, "MainPID="))
		if line != "" {
			rawPID = line
			break
		}
	}
	pid, err := strconv.Atoi(rawPID)
	if err != nil || pid <= 0 {
		return 0, fmt.Errorf("invalid MainPID %q", strings.TrimSpace(pidText))
	}
	return pid, nil
}

func readProcessStartTimeFile(pid int) (string, error) {
	if pid <= 0 {
		return "", fmt.Errorf("invalid pid %d", pid)
	}
	b, err := os.ReadFile(filepath.Join("/proc", strconv.Itoa(pid), "stat"))
	if err != nil {
		return "", err
	}
	return parseProcStatStartTime(string(b))
}

// parseProcStatStartTime parses Linux /proc/<pid>/stat without assuming that
// comm contains neither whitespace nor parentheses. The field after comm is
// state (field 3), and starttime is field 22, hence offset 19 in the fields
// following the closing comm parenthesis.
func parseProcStatStartTime(stat string) (string, error) {
	open := strings.IndexByte(stat, '(')
	close := strings.LastIndex(stat, ") ")
	if open < 0 || close <= open {
		return "", fmt.Errorf("malformed /proc stat comm field")
	}
	fields := strings.Fields(stat[close+2:])
	const startTimeIndex = 22 - 3
	if len(fields) <= startTimeIndex {
		return "", fmt.Errorf("malformed /proc stat fields")
	}
	startTime := fields[startTimeIndex]
	if startTime == "" {
		return "", fmt.Errorf("empty /proc stat start time")
	}
	return startTime, nil
}

func readProcessCmdlineFile(pid int) ([]string, error) {
	if pid <= 0 {
		return nil, fmt.Errorf("invalid pid %d", pid)
	}
	b, err := os.ReadFile(filepath.Join("/proc", strconv.Itoa(pid), "cmdline"))
	if err != nil {
		return nil, err
	}
	parts := strings.Split(string(b), "\x00")
	if len(parts) > 0 && parts[len(parts)-1] == "" {
		parts = parts[:len(parts)-1]
	}
	if len(parts) == 0 || strings.TrimSpace(parts[0]) == "" {
		return nil, fmt.Errorf("empty cmdline")
	}
	return parts, nil
}

func parseExecStartArgs(raw string) ([]string, error) {
	raw = strings.TrimSpace(raw)
	if strings.HasPrefix(raw, "ExecStart=") {
		raw = strings.TrimPrefix(raw, "ExecStart=")
	}
	if idx := strings.Index(raw, "argv[]="); idx >= 0 {
		raw = raw[idx+len("argv[]="):]
	}
	// systemctl show renders ExecStart as a struct whose argv[] value ends at
	// the next unquoted semicolon. Do not split escaped/quoted semicolons in a
	// path or argument.
	raw = trimExecStartMetadata(raw)
	return splitCommandArgs(raw)
}

func trimExecStartMetadata(raw string) string {
	var quote byte
	for i := 0; i < len(raw); i++ {
		switch raw[i] {
		case '\'', '"':
			if quote == 0 {
				quote = raw[i]
			} else if quote == raw[i] {
				quote = 0
			}
		case '\\':
			if i+1 < len(raw) {
				i++
			}
		case ';':
			if quote == 0 {
				return strings.TrimSpace(raw[:i])
			}
		}
	}
	return strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(raw), "}"))
}

func splitCommandArgs(raw string) ([]string, error) {
	var args []string
	var token strings.Builder
	var quote byte
	flush := func() {
		if token.Len() != 0 {
			args = append(args, token.String())
			token.Reset()
		}
	}
	for i := 0; i < len(raw); i++ {
		switch raw[i] {
		case '\'', '"':
			if quote == 0 {
				quote = raw[i]
			} else if quote == raw[i] {
				quote = 0
			} else {
				token.WriteByte(raw[i])
			}
		case '\\':
			if i+3 < len(raw) && raw[i+1] == 'x' {
				if value, ok := parseHexByte(raw[i+2 : i+4]); ok {
					token.WriteByte(value)
					i += 3
					continue
				}
			}
			if i+1 >= len(raw) {
				return nil, fmt.Errorf("dangling escape")
			}
			i++
			token.WriteByte(raw[i])
		default:
			if quote == 0 && (raw[i] == ' ' || raw[i] == '\t' || raw[i] == '\n' || raw[i] == '\r') {
				flush()
				continue
			}
			token.WriteByte(raw[i])
		}
	}
	if quote != 0 {
		return nil, fmt.Errorf("unterminated quote")
	}
	flush()
	if len(args) == 0 {
		return nil, fmt.Errorf("empty command")
	}
	return args, nil
}

func parseHexByte(s string) (byte, bool) {
	if len(s) != 2 {
		return 0, false
	}
	value := byte(0)
	for i := range s {
		value <<= 4
		switch c := s[i]; {
		case c >= '0' && c <= '9':
			value += c - '0'
		case c >= 'a' && c <= 'f':
			value += c - 'a' + 10
		case c >= 'A' && c <= 'F':
			value += c - 'A' + 10
		default:
			return 0, false
		}
	}
	return value, true
}

type singBoxConfigArgument struct {
	path      string
	directory bool
}

func singBoxConfigArguments(args []string) ([]singBoxConfigArgument, error) {
	if len(args) == 0 {
		return nil, fmt.Errorf("empty process invocation")
	}
	var out []singBoxConfigArgument
	add := func(path string, directory bool) error {
		if strings.TrimSpace(path) == "" {
			return fmt.Errorf("config argument has no path")
		}
		out = append(out, singBoxConfigArgument{path: path, directory: directory})
		return nil
	}
	for i := 1; i < len(args); i++ {
		arg := args[i]
		switch {
		case arg == "-c" || arg == "--config":
			if i+1 >= len(args) {
				return nil, fmt.Errorf("%s has no path", arg)
			}
			if err := add(args[i+1], false); err != nil {
				return nil, err
			}
			i++
		case strings.HasPrefix(arg, "--config="):
			if err := add(strings.TrimPrefix(arg, "--config="), false); err != nil {
				return nil, err
			}
		case strings.HasPrefix(arg, "-c="):
			if err := add(strings.TrimPrefix(arg, "-c="), false); err != nil {
				return nil, err
			}
		case arg == "-C" || arg == "--config-directory":
			if i+1 >= len(args) {
				return nil, fmt.Errorf("%s has no path", arg)
			}
			if err := add(args[i+1], true); err != nil {
				return nil, err
			}
			i++
		case strings.HasPrefix(arg, "-C="):
			if err := add(strings.TrimPrefix(arg, "-C="), true); err != nil {
				return nil, err
			}
		case strings.HasPrefix(arg, "--config-directory="):
			if err := add(strings.TrimPrefix(arg, "--config-directory="), true); err != nil {
				return nil, err
			}
		case arg == "-config-dir" || arg == "--config-dir" || arg == "-configdir" || arg == "--configdir":
			return nil, fmt.Errorf("unsupported sing-box config flag %q", arg)
		case strings.HasPrefix(arg, "-config-dir=") || strings.HasPrefix(arg, "--config-dir=") || strings.HasPrefix(arg, "-configdir=") || strings.HasPrefix(arg, "--configdir="):
			return nil, fmt.Errorf("unsupported sing-box config flag %q", arg)
		}
	}
	if len(out) != 1 {
		return nil, fmt.Errorf("expected exactly one sing-box config path, got %d", len(out))
	}
	return out, nil
}

func validateSingBoxInvocation(args []string, want, configuredBinary string) error {
	if len(args) == 0 {
		return fmt.Errorf("empty process invocation")
	}
	if strings.TrimSpace(configuredBinary) != "" && !binaryInvocationMatches(args[0], configuredBinary) {
		return fmt.Errorf("running binary does not match configured binary")
	}
	configs, err := singBoxConfigArguments(args)
	if err != nil {
		return err
	}
	selected := configs[0]
	got, err := canonicalConfigPath(selected.path)
	if err != nil {
		return fmt.Errorf("config path: %w", err)
	}
	if got != want {
		if selected.directory {
			return fmt.Errorf("config directory %q does not match configured path", selected.path)
		}
		return fmt.Errorf("config path %q does not match configured path", selected.path)
	}
	info, err := os.Stat(got)
	if err != nil {
		return fmt.Errorf("config path: %w", err)
	}
	if selected.directory && !info.IsDir() {
		return fmt.Errorf("config-directory form requires configured path to be a directory")
	}
	if !selected.directory && !info.Mode().IsRegular() {
		return fmt.Errorf("-c/--config form requires configured path to be a regular file")
	}
	return nil
}

// These small predicates retain package-local testability while using the
// strict parser above for the actual health gate.
func commandConfigArgs(raw string, binary string) []string {
	args, _ := parseExecStartArgs(raw)
	return args
}

func configArgMatches(args []string, want string, binary string) bool {
	return validateSingBoxInvocation(args, want, binary) == nil
}

func execStartConfigMatches(raw, want, binary string) bool {
	return configArgMatches(commandConfigArgs(raw, binary), want, binary)
}

func cmdlineConfigMatches(raw []byte, want, binary string) bool {
	return configArgMatches(strings.Split(strings.TrimSuffix(string(raw), "\x00"), "\x00"), want, binary)
}

func probeSocks(ctx context.Context, address string) error {
	dialer := net.Dialer{}
	conn, err := dialer.DialContext(ctx, "tcp", address)
	if err != nil {
		return err
	}
	defer conn.Close()
	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}
	if _, err := conn.Write([]byte{5, 1, 0}); err != nil {
		return err
	}
	response := make([]byte, 2)
	if _, err := io.ReadFull(conn, response); err != nil {
		return err
	}
	if response[0] != 5 || response[1] != 0 {
		return fmt.Errorf("unexpected SOCKS5 greeting response")
	}
	return nil
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

type restartHealthAck struct {
	Token      string `json:"token"`
	Generation string `json:"generation"`
	Health     string `json:"health"`
}

func readRestartHealthAck(path string) (restartHealthAck, error) {
	var ack restartHealthAck
	b, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return ack, nil
		}
		return ack, err
	}
	if err := json.Unmarshal(b, &ack); err == nil {
		return ack, nil
	}
	// The minimal container supervisor uses key=value lines so it does not
	// need jq or Python. Accept only the three expected fields.
	for _, line := range strings.Split(string(b), "\n") {
		key, value, ok := strings.Cut(strings.TrimSpace(line), "=")
		if !ok {
			continue
		}
		switch key {
		case "token":
			ack.Token = value
		case "generation":
			ack.Generation = value
		case "health":
			ack.Health = value
		}
	}
	return ack, nil
}

func waitForRestartAck(ctx context.Context, requestFile, ackFile, generationFile, token, before string, timeout time.Duration) error {
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
		if !consumed {
			request, readErr := os.ReadFile(requestFile)
			if readErr != nil && !os.IsNotExist(readErr) {
				return readErr
			}
			if readErr == nil && strings.TrimSpace(string(request)) != token {
				return fmt.Errorf("restart request token changed")
			}
		}
		current, err := readGeneration(generationFile)
		if err != nil {
			return err
		}
		ack, err := readRestartHealthAck(ackFile)
		if err != nil {
			return err
		}
		// All four observations are required. In particular, a stale ack file,
		// a generation bump without a health predicate, or a status-only legacy
		// marker cannot satisfy a new request.
		if consumed && current != "" && current != before && ack.Token == token && ack.Generation == current && ack.Health == "healthy" {
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
	if err := f.Sync(); err != nil {
		_ = f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmp, path); err != nil {
		return err
	}
	d, err := os.Open(dir)
	if err != nil {
		return err
	}
	defer d.Close()
	return d.Sync()
}
