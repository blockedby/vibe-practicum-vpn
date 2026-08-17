package xray

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
	"syscall"
	"time"

	"github.com/kcnc/vibe-practicum-vpn/internal/state"
)

type commandRunner func(context.Context, string, ...string) error
type systemctlRunner func(context.Context, ...string) (string, error)

var runSystemctl systemctlRunner = func(ctx context.Context, args ...string) (string, error) {
	return runExternalOutput(ctx, "systemctl", args...)
}
var runCommand commandRunner = func(ctx context.Context, name string, args ...string) error {
	return runExternal(ctx, name, args...)
}
var readProcessCmdline = readProcessCmdlineFile
var readProcessStartTime = readProcessStartTimeFile

const (
	DefaultHealthTimeout = 30 * time.Second
	MaxHealthTimeout     = 5 * time.Minute
)

// HealthConfig is the explicit host-systemd verification contract. It never
// relies on a Docker/container health predicate: the unit must be active, the
// xray config test must pass, and ProbeAddress (when configured) must complete
// a SOCKS5 greeting.
type HealthConfig struct {
	Service      string
	Binary       string
	ProbeAddress string
	Timeout      time.Duration
}

func defaultHealthConfig() HealthConfig {
	return HealthConfig{Service: "xray", Binary: "xray"}
}

func (h HealthConfig) normalized() HealthConfig {
	if strings.TrimSpace(h.Service) == "" {
		h.Service = "xray"
	}
	if strings.TrimSpace(h.Binary) == "" {
		h.Binary = "xray"
	}
	if h.Timeout <= 0 {
		h.Timeout = DefaultHealthTimeout
	}
	if h.Timeout > MaxHealthTimeout {
		h.Timeout = MaxHealthTimeout
	}
	return h
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
	return ApplyWithHealthContext(ctx, configPath, stateDir, out, defaultHealthConfig())
}

// ApplyWithHealthContext is the configured-runtime entrypoint used by
// vibe-vpn. It carries the production SOCKS probe and bounded verification
// settings into both apply and compensation paths.
func ApplyWithHealthContext(ctx context.Context, configPath, stateDir string, out map[string]any, health HealthConfig) (string, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	lock, err := state.AcquireLock(ctx, stateDir)
	if err != nil {
		return "", err
	}
	defer lock.Close()
	return ApplyLockedContextWithHealth(ctx, configPath, stateDir, out, health)
}

func ApplyLocked(configPath, stateDir string, out map[string]any) (string, error) {
	return ApplyLockedContext(context.Background(), configPath, stateDir, out)
}

func ApplyLockedContext(ctx context.Context, configPath, stateDir string, out map[string]any) (string, error) {
	return ApplyLockedContextWithHealth(ctx, configPath, stateDir, out, defaultHealthConfig())
}

func ApplyLockedContextWithHealth(ctx context.Context, configPath, stateDir string, out map[string]any, health HealthConfig) (string, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	health = health.normalized()
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
	if err := restartXrayAndVerify(ctx, configPath, health); err != nil {
		restoreErr := writeFileAtomic(configPath, b, 0644)
		if restoreErr == nil {
			xrayFailpoint("after-old-runtime-write-before-compensation")
		}
		restartOldErr := error(nil)
		if restoreErr == nil {
			restartOldErr = restartXrayAndVerify(context.Background(), configPath, health)
		}
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
	return RollbackWithHealthContext(ctx, configPath, stateDir, defaultHealthConfig())
}

func RollbackWithHealthContext(ctx context.Context, configPath, stateDir string, health HealthConfig) (string, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	lock, err := state.AcquireLock(ctx, stateDir)
	if err != nil {
		return "", err
	}
	defer lock.Close()
	return RollbackLockedContextWithHealth(ctx, configPath, stateDir, health)
}

func RollbackLocked(configPath, stateDir string) (string, error) {
	return RollbackLockedContext(context.Background(), configPath, stateDir)
}

func RollbackLockedContext(ctx context.Context, configPath, stateDir string) (string, error) {
	return RollbackLockedContextWithHealth(ctx, configPath, stateDir, defaultHealthConfig())
}

func RollbackLockedContextWithHealth(ctx context.Context, configPath, stateDir string, health HealthConfig) (string, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	health = health.normalized()
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
	if err := RestoreBackupLockedContextWithHealth(ctx, configPath, last, health); err != nil {
		return "", err
	}
	if err := snap.Restore(stateDir); err != nil {
		return "", fmt.Errorf("runtime rollback succeeded but state restore failed: %w", err)
	}
	return last, nil
}

// RestartWithHealthContext revalidates the currently selected xray runtime
// without changing its config. Journal recovery uses it before trusting a
// runtime/state pair that was acknowledged by an earlier process.
func RestartWithHealthContext(ctx context.Context, configPath string, health HealthConfig) error {
	return restartXrayAndVerify(ctx, configPath, health)
}

// RestoreBackup restores one exact runtime backup. It is used by transaction
// rollback so a newer unrelated backup can never be selected accidentally.
func RestoreBackup(configPath, stateDir, backupPath string) error {
	return RestoreBackupContext(context.Background(), configPath, stateDir, backupPath)
}

func RestoreBackupContext(ctx context.Context, configPath, stateDir, backupPath string) error {
	return RestoreBackupWithHealthContext(ctx, configPath, stateDir, backupPath, defaultHealthConfig())
}

func RestoreBackupWithHealthContext(ctx context.Context, configPath, stateDir, backupPath string, health HealthConfig) error {
	if ctx == nil {
		ctx = context.Background()
	}
	lock, err := state.AcquireLock(ctx, stateDir)
	if err != nil {
		return err
	}
	defer lock.Close()
	return RestoreBackupLockedContextWithHealth(ctx, configPath, backupPath, health)
}

func RestoreBackupLocked(configPath, stateDir, backupPath string) error {
	return RestoreBackupLockedContext(context.Background(), configPath, backupPath)
}

func RestoreBackupLockedContext(ctx context.Context, configPath, backupPath string) error {
	return RestoreBackupLockedContextWithHealth(ctx, configPath, backupPath, defaultHealthConfig())
}

func RestoreBackupLockedContextWithHealth(ctx context.Context, configPath, backupPath string, health HealthConfig) error {
	if ctx == nil {
		ctx = context.Background()
	}
	health = health.normalized()
	if err := ctx.Err(); err != nil {
		return err
	}
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
	if err := writeFileAtomic(configPath, b, 0644); err != nil {
		return err
	}
	if err := restartXrayAndVerify(ctx, configPath, health); err != nil {
		restoreErr := restoreRuntimeFile(configPath, current)
		if restoreErr == nil {
			xrayFailpoint("after-old-runtime-write-before-compensation")
		}
		restartOldErr := error(nil)
		if restoreErr == nil {
			restartOldErr = restartXrayAndVerify(context.Background(), configPath, health)
		}
		if restoreErr != nil || restartOldErr != nil {
			return fmt.Errorf("restart xray after rollback failed: %w; restore failed: %v; restart restored config: %v", err, restoreErr, restartOldErr)
		}
		return fmt.Errorf("restart xray after rollback failed: %w; restored prior config", err)
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

func restartXrayAndVerify(ctx context.Context, configPath string, health HealthConfig) error {
	if ctx == nil {
		ctx = context.Background()
	}
	health = health.normalized()
	if strings.TrimSpace(configPath) == "" {
		return fmt.Errorf("xray config path is empty")
	}
	operationCtx, cancel := context.WithTimeout(ctx, health.Timeout)
	defer cancel()
	systemctl := runSystemctl
	command := runCommand
	if _, err := systemctl(operationCtx, "reset-failed", health.Service); err != nil && operationCtx.Err() != nil {
		return fmt.Errorf("reset xray service failure state failed: %w", err)
	}
	if _, err := systemctl(operationCtx, "restart", health.Service); err != nil {
		bestEffortStopSystemdUnit(systemctl, health.Service)
		return fmt.Errorf("restart xray service failed: %w", err)
	}
	err := verifyXraySystemdHealth(operationCtx, configPath, health, systemctl, command)
	if err != nil {
		bestEffortStopSystemdUnit(systemctl, health.Service)
	}
	return err
}

func verifyXraySystemdHealth(ctx context.Context, configPath string, health HealthConfig, systemctl systemctlRunner, command commandRunner) error {
	return runSystemdHealth(ctx, health, func(healthCtx context.Context) error {
		// Capture the unit state and the process identity before any health
		// predicate that could be satisfied by a stale listener or file. The
		// final proof below closes the race window around the offline check and
		// optional SOCKS probe.
		identity, err := captureXrayProcess(healthCtx, health, configPath, systemctl)
		if err != nil {
			return err
		}
		if err := command(healthCtx, health.Binary, "run", "-test", "-config", identity.configPath); err != nil {
			return fmt.Errorf("xray config check failed: %w", err)
		}
		if strings.TrimSpace(health.ProbeAddress) != "" {
			if err := probeSocks(healthCtx, health.ProbeAddress); err != nil {
				return fmt.Errorf("xray SOCKS probe failed: %w", err)
			}
		}
		if err := verifyXrayProcessUnchanged(healthCtx, health, configPath, identity, systemctl); err != nil {
			return err
		}
		return nil
	})
}

func runSystemdHealth(ctx context.Context, health HealthConfig, check func(context.Context) error) error {
	if ctx == nil {
		ctx = context.Background()
	}
	timeout := health.Timeout
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
			return fmt.Errorf("xray post-restart health verification timed out: %w", healthCtx.Err())
		}
		return fmt.Errorf("xray post-restart health verification failed: %w", err)
	}
	return nil
}

// runExternal executes a command in its own process group. Canceling the
// context terminates the group so a child of systemctl cannot apply a late job.
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

type xrayProcessIdentity struct {
	pid        int
	startTime  string
	cmdline    string
	configPath string
}

func captureXrayProcess(ctx context.Context, health HealthConfig, configPath string, systemctl systemctlRunner) (xrayProcessIdentity, error) {
	var identity xrayProcessIdentity
	if _, err := systemctl(ctx, "is-active", "--quiet", health.Service); err != nil {
		return identity, fmt.Errorf("xray service is not active: %w", err)
	}
	want, err := canonicalRuntimePath(configPath)
	if err != nil {
		return identity, fmt.Errorf("xray config path: %w", err)
	}
	pid, execStart, err := xrayProcessMetadataWithRunner(ctx, health.Service, systemctl)
	if err != nil {
		return identity, fmt.Errorf("xray systemd metadata: %w", err)
	}
	execArgs, err := parseExecStartArgs(execStart)
	if err != nil {
		return identity, fmt.Errorf("xray effective ExecStart: %w", err)
	}
	if err := validateXrayInvocation(execArgs, want, health.Binary); err != nil {
		return identity, fmt.Errorf("xray effective ExecStart: %w", err)
	}
	cmdArgs, err := readProcessCmdline(pid)
	if err != nil {
		return identity, fmt.Errorf("xray MainPID cmdline: %w", err)
	}
	cmdline, err := xrayCmdlineIdentity(cmdArgs, want, health.Binary)
	if err != nil {
		return identity, fmt.Errorf("xray MainPID cmdline: %w", err)
	}
	// Read stat after cmdline validation so an exit or PID reuse between the
	// two /proc reads cannot produce a mixed-process proof.
	startTime, err := readProcessStartTime(pid)
	if err != nil {
		return identity, fmt.Errorf("xray MainPID start time: %w", err)
	}
	if strings.TrimSpace(startTime) == "" {
		return identity, fmt.Errorf("xray MainPID start time is empty")
	}
	return xrayProcessIdentity{pid: pid, startTime: startTime, cmdline: cmdline, configPath: want}, nil
}

// verifyXrayProcess retains the package-local initial-proof helper used by
// older callers and tests. The health gate uses captureXrayProcess directly
// so it can compare the identity again after all probes complete.
func verifyXrayProcess(ctx context.Context, health HealthConfig, configPath string) error {
	_, err := captureXrayProcess(ctx, health, configPath, runSystemctl)
	return err
}

func verifyXrayProcessUnchanged(ctx context.Context, health HealthConfig, configPath string, expected xrayProcessIdentity, systemctl systemctlRunner) error {
	if _, err := systemctl(ctx, "is-active", "--quiet", health.Service); err != nil {
		return fmt.Errorf("xray service is not active after health probe: %w", err)
	}
	pid, err := xrayMainPIDWithRunner(ctx, health.Service, systemctl)
	if err != nil {
		return fmt.Errorf("xray MainPID after health probe: %w", err)
	}
	if pid != expected.pid {
		return fmt.Errorf("xray MainPID changed after health probe: was %d, now %d", expected.pid, pid)
	}
	cmdArgs, err := readProcessCmdline(pid)
	if err != nil {
		return fmt.Errorf("xray MainPID cmdline after health probe: %w", err)
	}
	cmdline, err := xrayCmdlineIdentity(cmdArgs, expected.configPath, health.Binary)
	if err != nil {
		return fmt.Errorf("xray MainPID cmdline after health probe: %w", err)
	}
	if cmdline != expected.cmdline {
		return fmt.Errorf("xray MainPID cmdline identity changed after health probe")
	}
	// Keep the immutable token as the last /proc observation. If the process
	// exited and the PID was reused while reading cmdline, this catches it.
	startTime, err := readProcessStartTime(pid)
	if err != nil {
		return fmt.Errorf("xray MainPID start time after health probe: %w", err)
	}
	if strings.TrimSpace(startTime) == "" {
		return fmt.Errorf("xray MainPID start time after health probe is empty")
	}
	if startTime != expected.startTime {
		return fmt.Errorf("xray process start time changed after health probe: was %q, now %q", expected.startTime, startTime)
	}
	return nil
}

func xrayCmdlineIdentity(args []string, want, configuredBinary string) (string, error) {
	// systemd's effective ExecStart proves the configured executable. The
	// MainPID cmdline is compared byte-for-byte across the health window, but
	// test/supervisor wrappers may legitimately use a different argv[0].
	if err := validateXrayInvocation(args, want, ""); err != nil {
		return "", err
	}
	return strings.Join(args, "\x00"), nil
}

func canonicalRuntimePath(path string) (string, error) {
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

func canonicalConfigPath(path string) (string, error) {
	p, err := canonicalRuntimePath(path)
	if err != nil {
		return "", err
	}
	info, err := os.Stat(p)
	if err != nil {
		return "", err
	}
	if !info.Mode().IsRegular() {
		return "", fmt.Errorf("path is not a regular file")
	}
	return p, nil
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

func xrayProcessMetadata(ctx context.Context, service string) (int, string, error) {
	return xrayProcessMetadataWithRunner(ctx, service, runSystemctl)
}

func xrayProcessMetadataWithRunner(ctx context.Context, service string, systemctl systemctlRunner) (int, string, error) {
	pid, err := xrayMainPIDWithRunner(ctx, service, systemctl)
	if err != nil {
		return 0, "", err
	}
	s, err := systemctl(ctx, "show", "--no-pager", "--property=ExecStart", "--value", service)
	return pid, s, err
}

func xrayMainPIDWithRunner(ctx context.Context, service string, systemctl systemctlRunner) (int, error) {
	p, err := systemctl(ctx, "show", "--no-pager", "--property=MainPID", "--value", service)
	if err != nil {
		return 0, err
	}
	rawPID := ""
	for _, line := range strings.Split(p, "\n") {
		line = strings.TrimSpace(strings.TrimPrefix(line, "MainPID="))
		if line != "" {
			rawPID = line
			break
		}
	}
	pid, err := strconv.Atoi(rawPID)
	if err != nil || pid <= 0 {
		return 0, fmt.Errorf("invalid MainPID %q", strings.TrimSpace(p))
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

type xrayConfigArgument struct {
	path      string
	directory bool
}

func xrayConfigArguments(args []string) ([]xrayConfigArgument, error) {
	var out []xrayConfigArgument
	add := func(path string, directory bool) error {
		if strings.TrimSpace(path) == "" {
			return fmt.Errorf("config argument has no path")
		}
		out = append(out, xrayConfigArgument{path: path, directory: directory})
		return nil
	}
	for i := 1; i < len(args); i++ {
		arg := args[i]
		switch {
		case arg == "-config" || arg == "--config":
			if i+1 >= len(args) {
				return nil, fmt.Errorf("%s has no path", arg)
			}
			if err := add(args[i+1], false); err != nil {
				return nil, err
			}
			i++
		case strings.HasPrefix(arg, "-config="):
			if err := add(strings.TrimPrefix(arg, "-config="), false); err != nil {
				return nil, err
			}
		case strings.HasPrefix(arg, "--config="):
			if err := add(strings.TrimPrefix(arg, "--config="), false); err != nil {
				return nil, err
			}
		case arg == "-confdir" || arg == "--confdir" || arg == "-configdir" || arg == "--configdir" || arg == "-config-dir" || arg == "--config-dir":
			if i+1 >= len(args) {
				return nil, fmt.Errorf("%s has no path", arg)
			}
			if err := add(args[i+1], true); err != nil {
				return nil, err
			}
			i++
		case strings.HasPrefix(arg, "-confdir="):
			if err := add(strings.TrimPrefix(arg, "-confdir="), true); err != nil {
				return nil, err
			}
		case strings.HasPrefix(arg, "--confdir="):
			if err := add(strings.TrimPrefix(arg, "--confdir="), true); err != nil {
				return nil, err
			}
		case strings.HasPrefix(arg, "-configdir="):
			if err := add(strings.TrimPrefix(arg, "-configdir="), true); err != nil {
				return nil, err
			}
		case strings.HasPrefix(arg, "--configdir="):
			if err := add(strings.TrimPrefix(arg, "--configdir="), true); err != nil {
				return nil, err
			}
		case strings.HasPrefix(arg, "-config-dir="):
			if err := add(strings.TrimPrefix(arg, "-config-dir="), true); err != nil {
				return nil, err
			}
		case strings.HasPrefix(arg, "--config-dir="):
			if err := add(strings.TrimPrefix(arg, "--config-dir="), true); err != nil {
				return nil, err
			}
		}
	}
	if len(out) != 1 {
		return nil, fmt.Errorf("expected exactly one xray config argument, got %d", len(out))
	}
	return out, nil
}

func validateXrayInvocation(args []string, want, configuredBinary string) error {
	if len(args) == 0 {
		return fmt.Errorf("empty process invocation")
	}
	if strings.TrimSpace(configuredBinary) != "" && !binaryInvocationMatches(args[0], configuredBinary) {
		return fmt.Errorf("running binary does not match configured binary")
	}
	configs, err := xrayConfigArguments(args)
	if err != nil {
		return err
	}
	selected := configs[0]
	got, err := canonicalRuntimePath(selected.path)
	if err != nil {
		return fmt.Errorf("config path: %w", err)
	}
	if selected.directory {
		// A directory invocation is only exact when the configured path is
		// itself that directory. Treating filepath.Dir(file) as equivalent
		// would allow an unrelated file in the same xray config directory to
		// satisfy the health gate.
		if got != want {
			return fmt.Errorf("config directory does not match configured path")
		}
		if info, statErr := os.Stat(want); statErr != nil || !info.IsDir() {
			return fmt.Errorf("config-dir form requires configured path to be a directory")
		}
		return nil
	}
	if got != want {
		return fmt.Errorf("config path does not match configured path")
	}
	if info, statErr := os.Stat(want); statErr != nil || !info.Mode().IsRegular() {
		return fmt.Errorf("-config form requires configured path to be a file")
	}
	return nil
}

func xrayConfigMatches(raw, want string) bool {
	var args []string
	var err error
	if strings.ContainsRune(raw, '\x00') {
		// A /proc cmdline is NUL separated rather than an ExecStart property.
		args = strings.Split(strings.TrimSuffix(raw, "\x00"), "\x00")
	} else {
		args, err = parseExecStartArgs(raw)
	}
	if err != nil {
		return false
	}
	configs, err := xrayConfigArguments(args)
	if err != nil {
		return false
	}
	selected := configs[0]
	got, err := canonicalRuntimePath(selected.path)
	if err != nil || got != want {
		return false
	}
	if selected.directory {
		info, statErr := os.Stat(want)
		return statErr == nil && info.IsDir()
	}
	info, statErr := os.Stat(want)
	return statErr == nil && info.Mode().IsRegular()
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

func xrayFailpoint(name string) {
	point := strings.TrimSpace(os.Getenv("VIBE_VPN_XRAY_FAILPOINT"))
	if point == "" {
		point = strings.TrimSpace(os.Getenv("VIBE_VPN_RUNTIME_FAILPOINT"))
	}
	point = strings.ReplaceAll(point, "_", "-")
	if point != name {
		return
	}
	_ = syscall.Kill(os.Getpid(), syscall.SIGKILL)
	os.Exit(137)
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
