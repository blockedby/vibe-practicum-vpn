package main

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
	"github.com/kcnc/vibe-practicum-vpn/internal/picker"
	"github.com/kcnc/vibe-practicum-vpn/internal/state"
)

func TestSingboxRestartConfigWaitsForLegacyLocalRequestSupervisor(t *testing.T) {
	t.Setenv("SINGBOX_GENERATION_FILE", "")
	t.Setenv("VPNKIT_SINGBOX_GENERATION_FILE", "")
	c := config.Default()
	c.SingBoxRestartMode = "request-file"
	c.SingBoxRestartFile = "/run/vpnkit/restart-sing-box"
	got := singboxRestartConfig(c)
	if got.AckGenerationFile != "/run/vpnkit/sing-box-generation" || got.AckTimeout <= 0 {
		t.Fatalf("legacy local request config = %+v, want supervised acknowledgement", got)
	}

	c.SingBoxRestartFile = filepath.Join(t.TempDir(), "request")
	got = singboxRestartConfig(c)
	if got.AckGenerationFile != "" {
		t.Fatalf("arbitrary request-file config unexpectedly inferred ack=%q", got.AckGenerationFile)
	}
}

func TestPruneNonDryRunUsesCrossProcessStateDirLock(t *testing.T) {
	if os.Getenv("VIBE_VPN_PRUNE_LOCK_HELPER") == "1" {
		ctx, cancel := context.WithTimeout(context.Background(), 120*time.Millisecond)
		defer cancel()
		err := cmdPruneContext(ctx, &cliOptions{configPath: os.Getenv("VIBE_VPN_PRUNE_CONFIG")}, false, 0)
		if !errors.Is(err, context.DeadlineExceeded) {
			t.Fatalf("prune helper error=%v, want lock timeout", err)
		}
		return
	}

	dir := t.TempDir()
	configPath := filepath.Join(dir, "config.json")
	if err := os.WriteFile(configPath, []byte(`{"state_dir":"`+dir+`"}`), 0600); err != nil {
		t.Fatal(err)
	}
	lock, err := state.AcquireLock(context.Background(), dir)
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(os.Args[0], "-test.run=TestPruneNonDryRunUsesCrossProcessStateDirLock$", "-test.v")
	cmd.Env = append(os.Environ(), "VIBE_VPN_PRUNE_LOCK_HELPER=1", "VIBE_VPN_PRUNE_CONFIG="+configPath)
	if err := cmd.Run(); err != nil {
		_ = lock.Close()
		t.Fatalf("prune helper did not observe lock contention: %v", err)
	}
	if err := lock.Close(); err != nil {
		t.Fatal(err)
	}
	if err := cmdPruneContext(context.Background(), &cliOptions{configPath: configPath}, false, 0); err != nil {
		t.Fatal(err)
	}
}

func TestPruneRemovesRuntimeBackupsAndExactStateSidecars(t *testing.T) {
	dir := t.TempDir()
	configPath := filepath.Join(dir, "config.json")
	if err := os.WriteFile(configPath, []byte(`{"state_dir":"`+dir+`"}`), 0600); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"sing-box-20240101-000000000.json", "xray-20240101-000000000.json"} {
		path := filepath.Join(dir, "backups", name)
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(`{"runtime":"opaque"}`), 0600); err != nil {
			t.Fatal(err)
		}
		if err := state.SaveSnapshotForBackup(dir, path, state.Snapshot{}); err != nil {
			t.Fatal(err)
		}
	}
	if err := cmdPrune(&cliOptions{configPath: configPath}, false, 0); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"sing-box-20240101-000000000.json", "xray-20240101-000000000.json"} {
		path := filepath.Join(dir, "backups", name)
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Fatalf("runtime backup remains at %s: %v", path, err)
		}
		if _, err := os.Stat(state.SnapshotPath(dir, path)); !os.IsNotExist(err) {
			t.Fatalf("state sidecar remains for %s: %v", name, err)
		}
	}
}

func requestRecoveryConfig(t *testing.T, dir, runtimePath string) (config.Config, func()) {
	t.Helper()
	runDir := filepath.Join(dir, "run")
	if err := os.MkdirAll(runDir, 0700); err != nil {
		t.Fatal(err)
	}
	req := filepath.Join(runDir, "restart")
	generation := filepath.Join(runDir, "generation")
	ack := filepath.Join(runDir, "generation.ack")
	if err := os.WriteFile(generation, []byte("1\n"), 0600); err != nil {
		t.Fatal(err)
	}
	c := config.Default()
	c.Runtime = "singbox"
	c.SingBoxConfig = runtimePath
	c.SingBoxBin = filepath.Join(dir, "sing-box-not-installed")
	c.SingBoxRestartMode = "request-file"
	c.SingBoxRestartFile = req
	c.SingBoxRestartAckGenerationFile = generation
	c.SingBoxRestartAckFile = ack
	c.SingBoxRestartAckTimeout = config.NewDuration(200 * time.Millisecond)
	c.StateDir = dir

	stop := make(chan struct{})
	done := make(chan struct{})
	var once sync.Once
	go func() {
		defer close(done)
		generationNumber := 1
		for {
			select {
			case <-stop:
				return
			default:
			}
			if b, err := os.ReadFile(req); err == nil {
				token := strings.TrimSpace(string(b))
				if token != "" {
					generationNumber++
					next := fmt.Sprintf("%d", generationNumber)
					_ = os.WriteFile(generation, []byte(next+"\n"), 0600)
					_ = os.WriteFile(ack, []byte("token="+token+"\ngeneration="+next+"\nhealth=healthy\n"), 0600)
					_ = os.Remove(req)
				}
			}
			time.Sleep(time.Millisecond)
		}
	}()
	return c, func() {
		once.Do(func() {
			close(stop)
			<-done
		})
	}
}

func TestRecoveryAfterRuntimeAcknowledgementCompletesExactCandidatePair(t *testing.T) {
	dir := t.TempDir()
	runtimePath := filepath.Join(dir, "runtime.json")
	oldRuntime := []byte(`{"runtime":"old"}\n`)
	candidateRuntime := []byte(`{"runtime":"candidate"}\n`)
	if err := os.WriteFile(runtimePath, candidateRuntime, 0600); err != nil {
		t.Fatal(err)
	}
	if err := state.SaveCurrent(dir, state.Current{Name: "old", Link: "old-link", Mbps: 1}); err != nil {
		t.Fatal(err)
	}
	oldState, err := state.Capture(dir)
	if err != nil {
		t.Fatal(err)
	}
	candidate, err := state.SnapshotForCurrent(state.Current{Name: "candidate", Link: "candidate-link", Mbps: 2})
	if err != nil {
		t.Fatal(err)
	}
	if err := state.BeginTransactionWithMetadata(dir, "apply-crash", state.TransactionApply, "singbox", runtimePath, oldRuntime, nil, oldState, candidate); err != nil {
		t.Fatal(err)
	}
	if err := state.AcknowledgeTransaction(dir, "apply-crash", candidateRuntime); err != nil {
		t.Fatal(err)
	}
	c, stop := requestRecoveryConfig(t, dir, runtimePath)
	defer stop()
	if err := recoverTransactionsLocked(context.Background(), c); err != nil {
		t.Fatal(err)
	}
	got, err := state.LoadCurrent(dir)
	if err != nil || got.Name != "candidate" || got.Link != "candidate-link" {
		t.Fatalf("recovered selected state=%+v err=%v", got, err)
	}
	if b, err := os.ReadFile(runtimePath); err != nil || string(b) != string(candidateRuntime) {
		t.Fatalf("recovered runtime=%q err=%v", b, err)
	}
	if pending, err := state.PendingTransactions(dir); err != nil || len(pending) != 0 {
		t.Fatalf("pending transactions=%v err=%v", pending, err)
	}
}

func TestRecoveryAfterRollbackAcknowledgementCompletesExactTargetPair(t *testing.T) {
	dir := t.TempDir()
	runtimePath := filepath.Join(dir, "runtime.json")
	oldRuntime := []byte(`{"runtime":"candidate"}\n`)
	targetRuntime := []byte(`{"runtime":"old"}\n`)
	if err := os.WriteFile(runtimePath, targetRuntime, 0600); err != nil {
		t.Fatal(err)
	}
	if err := state.SaveCurrent(dir, state.Current{Name: "candidate", Link: "candidate-link", Mbps: 2}); err != nil {
		t.Fatal(err)
	}
	oldState, err := state.Capture(dir)
	if err != nil {
		t.Fatal(err)
	}
	targetState, err := state.SnapshotForCurrent(state.Current{Name: "old", Link: "old-link", Mbps: 1})
	if err != nil {
		t.Fatal(err)
	}
	if err := state.BeginTransactionWithMetadata(dir, "rollback-crash", state.TransactionRollback, "singbox", runtimePath, oldRuntime, nil, oldState, targetState); err != nil {
		t.Fatal(err)
	}
	if err := state.AcknowledgeTransaction(dir, "rollback-crash", targetRuntime); err != nil {
		t.Fatal(err)
	}
	c, stop := requestRecoveryConfig(t, dir, runtimePath)
	defer stop()
	if err := recoverTransactionsLocked(context.Background(), c); err != nil {
		t.Fatal(err)
	}
	got, err := state.LoadCurrent(dir)
	if err != nil || got.Name != "old" || got.Link != "old-link" {
		t.Fatalf("recovered rollback state=%+v err=%v", got, err)
	}
	if b, err := os.ReadFile(runtimePath); err != nil || string(b) != string(targetRuntime) {
		t.Fatalf("recovered rollback runtime=%q err=%v", b, err)
	}
}

func TestRecoveryPreparedTransactionRestoresOldPair(t *testing.T) {
	dir := t.TempDir()
	runtimePath := filepath.Join(dir, "runtime.json")
	oldRuntime := []byte(`{"runtime":"old"}\n`)
	if err := os.WriteFile(runtimePath, oldRuntime, 0600); err != nil {
		t.Fatal(err)
	}
	if err := state.SaveCurrent(dir, state.Current{Name: "old", Link: "old-link", Mbps: 1}); err != nil {
		t.Fatal(err)
	}
	oldState, err := state.Capture(dir)
	if err != nil {
		t.Fatal(err)
	}
	candidate, err := state.SnapshotForCurrent(state.Current{Name: "candidate", Link: "candidate-link", Mbps: 2})
	if err != nil {
		t.Fatal(err)
	}
	if err := state.BeginTransactionWithMetadata(dir, "prepared-crash", state.TransactionApply, "singbox", runtimePath, oldRuntime, nil, oldState, candidate); err != nil {
		t.Fatal(err)
	}
	c, stop := requestRecoveryConfig(t, dir, runtimePath)
	defer stop()
	if err := recoverTransactionsLocked(context.Background(), c); err != nil {
		t.Fatal(err)
	}
	got, err := state.LoadCurrent(dir)
	if err != nil || got.Name != "old" || got.Link != "old-link" {
		t.Fatalf("prepared recovery changed state=%+v err=%v", got, err)
	}
	generation, err := os.ReadFile(filepath.Join(dir, "run", "generation"))
	if err != nil || strings.TrimSpace(string(generation)) == "1" {
		t.Fatalf("prepared recovery did not obtain a fresh request acknowledgement: %q err=%v", generation, err)
	}
}

func systemdRecoveryFixture(t *testing.T, runtime string) (config.Config, string) {
	t.Helper()
	dir := t.TempDir()
	binDir := filepath.Join(dir, "bin")
	if err := os.MkdirAll(binDir, 0700); err != nil {
		t.Fatal(err)
	}
	systemctl := filepath.Join(binDir, "systemctl")
	if err := os.WriteFile(systemctl, []byte("#!/bin/sh\ncase \"$1\" in\n  is-active) exit 1 ;;\n  *) exit 0 ;;\nesac\n"), 0700); err != nil {
		t.Fatal(err)
	}
	backend := filepath.Join(binDir, "backend")
	if err := os.WriteFile(backend, []byte("#!/bin/sh\nexit 0\n"), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", binDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	runtimePath := filepath.Join(dir, "runtime.json")
	oldRuntime := []byte(`{"runtime":"old"}\n`)
	if err := os.WriteFile(runtimePath, oldRuntime, 0600); err != nil {
		t.Fatal(err)
	}
	if err := state.SaveCurrent(dir, state.Current{Name: "old", Link: "old-link", Mbps: 1}); err != nil {
		t.Fatal(err)
	}
	oldState, err := state.Capture(dir)
	if err != nil {
		t.Fatal(err)
	}
	candidate, err := state.SnapshotForCurrent(state.Current{Name: "candidate", Link: "candidate-link", Mbps: 2})
	if err != nil {
		t.Fatal(err)
	}
	c := config.Default()
	c.Runtime = runtime
	c.StateDir = dir
	c.XrayBin = backend
	c.SingBoxBin = backend
	c.SingBoxRestartMode = "systemd"
	c.SingBoxService = "sing-box-test"
	c.SingBoxRestartAckTimeout = config.NewDuration(50 * time.Millisecond)
	c.ProductionSocks = ""
	if runtime == "xray" {
		c.XrayConfig = runtimePath
	} else {
		c.SingBoxConfig = runtimePath
	}
	if err := state.BeginTransactionWithMetadata(dir, "systemd-unhealthy", state.TransactionApply, runtime, runtimePath, oldRuntime, nil, oldState, candidate); err != nil {
		t.Fatal(err)
	}
	return c, runtimePath
}

func assertSystemdRecoveryFailsClosed(t *testing.T, runtime string) {
	t.Helper()
	c, runtimePath := systemdRecoveryFixture(t, runtime)
	if err := recoverTransactionsLocked(context.Background(), c); err == nil {
		t.Fatalf("%s recovery unexpectedly accepted inactive service", runtime)
	}
	if pending, err := state.PendingTransactions(c.StateDir); err != nil || len(pending) != 1 {
		t.Fatalf("%s journal pending=%v err=%v, want retained journal", runtime, pending, err)
	}
	cur, err := state.LoadCurrent(c.StateDir)
	if err != nil || cur.Name != "old" || cur.Link != "old-link" {
		t.Fatalf("%s candidate state committed during failed recovery: %+v err=%v", runtime, cur, err)
	}
	got, err := os.ReadFile(runtimePath)
	if err != nil || !strings.Contains(string(got), `"old"`) {
		t.Fatalf("%s runtime after failed recovery=%q err=%v", runtime, got, err)
	}
}

func TestSystemdXrayRecoveryInactiveRetainsJournal(t *testing.T) {
	assertSystemdRecoveryFailsClosed(t, "xray")
}

func TestSystemdSingBoxRecoveryInactiveRetainsJournal(t *testing.T) {
	assertSystemdRecoveryFailsClosed(t, "singbox")
}

func TestTransactionFailpointIsDeterministicSIGKILL(t *testing.T) {
	if os.Getenv("VIBE_VPN_FAILPOINT_HELPER") == "1" {
		transactionFailpoint("after-runtime-ack")
		return
	}
	cmd := exec.Command(os.Args[0], "-test.run=TestTransactionFailpointIsDeterministicSIGKILL$", "-test.v")
	cmd.Env = append(os.Environ(), "VIBE_VPN_FAILPOINT_HELPER=1", "VIBE_VPN_TX_FAILPOINT=after-runtime-ack")
	err := cmd.Run()
	if err == nil || !strings.Contains(err.Error(), "signal: killed") {
		t.Fatalf("failpoint subprocess error=%v, want SIGKILL", err)
	}
}

func TestXrayFailedRestartCrashBeforeCompensationRecoversOldRuntime(t *testing.T) {
	if os.Getenv("VIBE_VPN_XRAY_CRASH_HELPER") == "1" {
		dir := os.Getenv("VIBE_VPN_XRAY_CRASH_DIR")
		runtimePath := filepath.Join(dir, "runtime.json")
		c := config.Default()
		c.Runtime = "xray"
		c.StateDir = dir
		c.XrayConfig = runtimePath
		c.XrayBin = os.Getenv("VIBE_VPN_XRAY_BIN")
		c.ProductionSocks = ""
		result := picker.NodeResult{Name: "candidate", Link: "candidate-link", Mbps: 2, Outbound: map[string]any{"protocol": "blackhole"}}
		if err := applyResult(c, result); err == nil {
			os.Exit(3)
		}
		return
	}

	dir := t.TempDir()
	runtimePath := filepath.Join(dir, "runtime.json")
	oldRuntime := []byte(`{"outbounds":[{"protocol":"freedom"}]}\n`)
	if err := os.WriteFile(runtimePath, oldRuntime, 0600); err != nil {
		t.Fatal(err)
	}
	if err := state.SaveCurrent(dir, state.Current{Name: "old", Link: "old-link", Mbps: 1}); err != nil {
		t.Fatal(err)
	}
	binDir := filepath.Join(dir, "bin")
	if err := os.MkdirAll(binDir, 0700); err != nil {
		t.Fatal(err)
	}
	xrayBin := filepath.Join(dir, "systemd-runtime")
	installFakeSystemdRuntime(t, dir, runtimePath, xrayBin, "-config")
	t.Setenv("PATH", binDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("VIBE_VPN_XRAY_FAIL_RESTART", "1")
	cmd := exec.Command(os.Args[0], "-test.run=TestXrayFailedRestartCrashBeforeCompensationRecoversOldRuntime$", "-test.v")
	cmd.Env = append(os.Environ(),
		"VIBE_VPN_XRAY_CRASH_HELPER=1",
		"VIBE_VPN_XRAY_CRASH_DIR="+dir,
		"VIBE_VPN_XRAY_BIN="+xrayBin,
		"VIBE_VPN_XRAY_FAILPOINT=after-old-runtime-write-before-compensation",
	)
	if err := cmd.Run(); err == nil || !strings.Contains(err.Error(), "signal: killed") {
		t.Fatalf("crash helper error=%v, want SIGKILL", err)
	}
	pending, err := state.PendingTransactions(dir)
	if err != nil || len(pending) != 1 {
		t.Fatalf("pending journal after crash=%v err=%v", pending, err)
	}
	if got, err := os.ReadFile(runtimePath); err != nil || string(got) != string(oldRuntime) {
		t.Fatalf("runtime after crash=%q err=%v, want old bytes", got, err)
	}
	if got, err := state.LoadCurrent(dir); err != nil || got.Name != "old" {
		t.Fatalf("selected state after crash=%+v err=%v", got, err)
	}

	t.Setenv("VIBE_VPN_XRAY_FAIL_RESTART", "0")
	c := config.Default()
	c.Runtime = "xray"
	c.StateDir = dir
	c.XrayConfig = runtimePath
	c.XrayBin = xrayBin
	c.ProductionSocks = ""
	if err := recoverTransactionsLocked(context.Background(), c); err != nil {
		t.Fatal(err)
	}
	if pending, err := state.PendingTransactions(dir); err != nil || len(pending) != 0 {
		t.Fatalf("pending journal after recovery=%v err=%v", pending, err)
	}
	if got, err := os.ReadFile(runtimePath); err != nil || string(got) != string(oldRuntime) {
		t.Fatalf("runtime after recovery=%q err=%v", got, err)
	}
}

func TestRequestFileAckConfigCarriesDistinctHealthAck(t *testing.T) {
	c := config.Default()
	c.SingBoxRestartMode = "request-file"
	c.SingBoxRestartFile = "/run/vpnkit/restart-sing-box"
	c.SingBoxRestartAckGenerationFile = "/run/vpnkit/sing-box-generation"
	c.SingBoxRestartAckFile = "/run/vpnkit/sing-box-generation.ack"
	got := singboxRestartConfig(c)
	if got.AckGenerationFile == got.AckFile || !strings.HasSuffix(got.AckFile, ".ack") {
		t.Fatalf("request ack config=%+v, want distinct generation and health ack", got)
	}
}

func TestScheduledFailureWithoutBaselineDeletesExactCandidate(t *testing.T) {
	dir := t.TempDir()
	c := config.Default()
	c.StateDir = dir
	run := func(_ context.Context, _ *cliOptions, _ config.Config, baseline *state.FileVersion) (state.FileVersion, error) {
		candidate, committed, err := state.SaveJSONIfVersion(context.Background(), dir, "last-results.json", []picker.NodeResult{{Index: 1, Name: "failed", Host: "failed.example", Port: 443, OK: false}}, *baseline)
		if err != nil {
			t.Fatal(err)
		}
		if !committed || !candidate.Exists() {
			t.Fatal("failed scheduled candidate did not publish")
		}
		return candidate, errors.New("scheduled benchmark failed")
	}
	if err := runScheduledTestContextWithRunner(context.Background(), &cliOptions{}, c, run); err == nil {
		t.Fatal("scheduled failure unexpectedly returned nil")
	}
	if _, err := os.Stat(filepath.Join(dir, "last-results.json")); !os.IsNotExist(err) {
		t.Fatalf("failed candidate remains after absent-baseline compensation: %v", err)
	}
}

func TestScheduledFailureWithoutBaselinePreservesNewerWriter(t *testing.T) {
	dir := t.TempDir()
	c := config.Default()
	c.StateDir = dir
	run := func(_ context.Context, _ *cliOptions, _ config.Config, baseline *state.FileVersion) (state.FileVersion, error) {
		candidate, committed, err := state.SaveJSONIfVersion(context.Background(), dir, "last-results.json", []picker.NodeResult{{Index: 1, Name: "failed", Host: "failed.example", Port: 443, OK: false}}, *baseline)
		if err != nil {
			t.Fatal(err)
		}
		if !committed || !candidate.Exists() {
			t.Fatal("failed scheduled candidate did not publish")
		}
		if _, err := state.SaveJSONVersioned(context.Background(), dir, "last-results.json", []picker.NodeResult{{Index: 2, Name: "manual", Host: "manual.example", Port: 443, OK: true, Mbps: 200}}); err != nil {
			t.Fatal(err)
		}
		return candidate, errors.New("scheduled benchmark failed")
	}
	if err := runScheduledTestContextWithRunner(context.Background(), &cliOptions{}, c, run); err == nil {
		t.Fatal("scheduled failure unexpectedly returned nil")
	}
	got, err := os.ReadFile(filepath.Join(dir, "last-results.json"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(got), "manual.example") || strings.Contains(string(got), "failed.example") {
		t.Fatalf("newer manual result was not preserved: %s", got)
	}
}

func TestScheduledSupersededOutcomeIsDistinctNonSuccess(t *testing.T) {
	dir := t.TempDir()
	c := config.Default()
	c.StateDir = dir
	err := runScheduledTestContextWithRunner(context.Background(), &cliOptions{}, c, func(context.Context, *cliOptions, config.Config, *state.FileVersion) (state.FileVersion, error) {
		return state.FileVersion{}, ErrScheduledResultsSuperseded
	})
	if !errors.Is(err, ErrScheduledResultsSuperseded) {
		t.Fatalf("superseded scheduled outcome=%v, want sentinel", err)
	}
}

func TestScheduledFailureDoesNotRestoreNewerCrossProcessResult(t *testing.T) {
	if os.Getenv("VIBE_VPN_SCHEDULED_RESULT_HELPER") == "1" {
		dir := os.Getenv("VIBE_VPN_SCHEDULED_RESULT_DIR")
		_, err := state.SaveJSONVersioned(context.Background(), dir, "last-results.json", []picker.NodeResult{{Index: 2, Name: "manual", Host: "manual.example", Port: 443, OK: true, Mbps: 200}})
		if err != nil {
			t.Fatal(err)
		}
		return
	}

	dir := t.TempDir()
	if _, err := state.SaveJSONVersioned(context.Background(), dir, "last-results.json", []picker.NodeResult{{Index: 1, Name: "old", Host: "old.example", Port: 443, OK: true, Mbps: 100}}); err != nil {
		t.Fatal(err)
	}
	c := config.Default()
	c.StateDir = dir
	started := make(chan struct{})
	run := func(_ context.Context, _ *cliOptions, _ config.Config, baseline *state.FileVersion) (state.FileVersion, error) {
		if !baseline.Exists() {
			t.Fatal("scheduled baseline unexpectedly missing")
		}
		close(started)
		cmd := exec.Command(os.Args[0], "-test.run=TestScheduledFailureDoesNotRestoreNewerCrossProcessResult$", "-test.v")
		cmd.Env = append(os.Environ(), "VIBE_VPN_SCHEDULED_RESULT_HELPER=1", "VIBE_VPN_SCHEDULED_RESULT_DIR="+dir)
		if err := cmd.Run(); err != nil {
			t.Fatalf("manual writer subprocess failed: %v", err)
		}
		return state.FileVersion{}, errors.New("scheduled benchmark failed")
	}

	done := make(chan error, 1)
	go func() { done <- runScheduledTestContextWithRunner(context.Background(), &cliOptions{}, c, run) }()
	select {
	case <-started:
	case <-time.After(2 * time.Second):
		t.Fatal("scheduled runner did not reach the pending point")
	}
	select {
	case err := <-done:
		if err == nil || err.Error() != "scheduled benchmark failed" {
			t.Fatalf("scheduled result error=%v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("scheduled runner did not finish")
	}
	got, err := os.ReadFile(filepath.Join(dir, "last-results.json"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(got), "manual.example") || strings.Contains(string(got), "old.example") {
		t.Fatalf("scheduled failure replaced newer manual results: %s", got)
	}
}

func TestScheduledFailureRestoreUsesExactPublishedVersion(t *testing.T) {
	dir := t.TempDir()
	if _, err := state.SaveJSONVersioned(context.Background(), dir, "last-results.json", []picker.NodeResult{{Index: 1, Name: "old", Host: "old.example", Port: 443, OK: true, Mbps: 100}}); err != nil {
		t.Fatal(err)
	}
	c := config.Default()
	c.StateDir = dir
	run := func(_ context.Context, _ *cliOptions, _ config.Config, baseline *state.FileVersion) (state.FileVersion, error) {
		candidate, committed, err := state.SaveJSONIfVersion(context.Background(), dir, "last-results.json", []picker.NodeResult{{Index: 3, Name: "scheduled", Host: "scheduled.example", Port: 443, OK: false}}, *baseline)
		if err != nil {
			t.Fatal(err)
		}
		if !committed {
			t.Fatal("scheduled candidate did not publish")
		}
		if _, err := state.SaveJSONVersioned(context.Background(), dir, "last-results.json", []picker.NodeResult{{Index: 2, Name: "manual", Host: "manual.example", Port: 443, OK: true, Mbps: 200}}); err != nil {
			t.Fatal(err)
		}
		return candidate, errors.New("scheduled benchmark failed")
	}
	if err := runScheduledTestContextWithRunner(context.Background(), &cliOptions{}, c, run); err == nil {
		t.Fatal("scheduled failure unexpectedly returned nil")
	}
	got, err := os.ReadFile(filepath.Join(dir, "last-results.json"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(got), "manual.example") || strings.Contains(string(got), "scheduled.example") || strings.Contains(string(got), "old.example") {
		t.Fatalf("conditional restore changed newer manual results: %s", got)
	}
}

func TestSuccessThresholdAdaptsToSmallLimits(t *testing.T) {
	if got := successThreshold(32 * 1024); got != 32*1024 {
		t.Fatalf("small limit threshold = %d", got)
	}
	if got := successThreshold(512 * 1024); got != 64*1024 {
		t.Fatalf("large limit threshold = %d", got)
	}
}

func TestTCPOpen(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	if !tcpOpen(ln.Addr().String(), time.Second) {
		t.Fatal("expected listener to be detected")
	}
}

func TestRedactedNodeResultsDoNotExposeLinksOrOutbounds(t *testing.T) {
	results := []picker.NodeResult{{Name: "node", Link: "vless://private", Outbound: map[string]any{"server": "private"}}}
	redacted := redactedNodeResults(results)
	if redacted[0].Link != "" || redacted[0].Outbound != nil {
		t.Fatalf("redacted result still contains sensitive fields: %+v", redacted[0])
	}
	if results[0].Link == "" || results[0].Outbound == nil {
		t.Fatal("redaction mutated source results")
	}
}
