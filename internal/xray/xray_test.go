package xray

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func installHealthyXraySystemd(t *testing.T, configPath string, failFirstRestart bool) {
	t.Helper()
	oldSystemctl := runSystemctl
	oldCommand := runCommand
	oldCmdline := readProcessCmdline
	oldStartTime := readProcessStartTime
	restartFailures := 0
	runSystemctl = func(_ context.Context, args ...string) (string, error) {
		if len(args) > 0 && args[0] == "show" {
			for _, arg := range args {
				if strings.Contains(arg, "MainPID") {
					return strconv.Itoa(os.Getpid()), nil
				}
			}
			return fmt.Sprintf("{ path=xray ; argv[]=xray run -config %s ; ignore_errors=no ; }", configPath), nil
		}
		if failFirstRestart && len(args) == 2 && args[0] == "restart" && restartFailures == 0 {
			restartFailures++
			return "", errors.New("boom")
		}
		return "", nil
	}
	runCommand = func(context.Context, string, ...string) error { return nil }
	readProcessCmdline = func(pid int) ([]string, error) {
		if pid != os.Getpid() {
			t.Fatalf("unexpected MainPID %d", pid)
		}
		return []string{"xray", "run", "-config", configPath}, nil
	}
	readProcessStartTime = func(int) (string, error) { return "test-start", nil }
	t.Cleanup(func() {
		runSystemctl = oldSystemctl
		runCommand = oldCommand
		readProcessCmdline = oldCmdline
		readProcessStartTime = oldStartTime
	})
}

func TestTempConfigUsesTestPort(t *testing.T) {
	b, err := TempConfig(map[string]any{"protocol": "freedom"}, "127.0.0.1:18080")
	if err != nil {
		t.Fatal(err)
	}
	s := string(b)
	if !strings.Contains(s, "18080") || strings.Contains(s, "10808") {
		t.Fatal(s)
	}
}

func TestApplyRestoresConfigWhenRestartFails(t *testing.T) {
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "config.json")
	orig := []byte(`{"outbounds":[{"protocol":"freedom"}],"inbounds":[]}`)
	if err := os.WriteFile(cfgPath, orig, 0644); err != nil {
		t.Fatal(err)
	}
	installHealthyXraySystemd(t, cfgPath, true)
	backup, err := Apply(cfgPath, dir, map[string]any{"protocol": "blackhole"})
	if err == nil || !strings.Contains(err.Error(), "restored backup") {
		t.Fatalf("expected restored-backup error, got backup=%q err=%v", backup, err)
	}
	got, readErr := os.ReadFile(cfgPath)
	if readErr != nil {
		t.Fatal(readErr)
	}
	if string(got) != string(orig) {
		t.Fatalf("config was not restored: %s", got)
	}
	if _, statErr := os.Stat(backup); statErr != nil {
		t.Fatalf("backup missing: %v", statErr)
	}
}

func TestRollbackUsesExactPairedBackupInsteadOfUnpairedRuntimeFile(t *testing.T) {
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "config.json")
	if err := os.WriteFile(cfgPath, []byte(`{"outbounds":[{"protocol":"freedom","marker":"old"}]}`), 0644); err != nil {
		t.Fatal(err)
	}
	installHealthyXraySystemd(t, cfgPath, false)
	if _, err := Apply(cfgPath, dir, map[string]any{"protocol": "blackhole", "marker": "one"}); err != nil {
		t.Fatal(err)
	}
	if _, err := Apply(cfgPath, dir, map[string]any{"protocol": "blackhole", "marker": "two"}); err != nil {
		t.Fatal(err)
	}
	unpaired := filepath.Join(dir, "backups", "xray-99999999-999999999.json")
	if err := os.WriteFile(unpaired, []byte(`{"outbounds":[{"marker":"unpaired"}]}`), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := Rollback(cfgPath, dir); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(cfgPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(got), `"marker": "one"`) || strings.Contains(string(got), "unpaired") {
		t.Fatalf("rollback selected wrong runtime backup: %s", got)
	}
}

func TestSystemdRestartSuccessButInactiveFailsClosed(t *testing.T) {
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "config.json")
	old := []byte(`{"outbounds":[{"protocol":"freedom"}]}`)
	if err := os.WriteFile(cfgPath, old, 0644); err != nil {
		t.Fatal(err)
	}
	oldSystemctl := runSystemctl
	oldCommand := runCommand
	runSystemctl = func(_ context.Context, args ...string) (string, error) {
		if len(args) >= 1 && args[0] == "is-active" {
			return "", os.ErrProcessDone
		}
		return "", nil
	}
	runCommand = func(context.Context, string, ...string) error { return nil }
	t.Cleanup(func() { runSystemctl = oldSystemctl; runCommand = oldCommand })
	start := time.Now()
	_, err := ApplyWithHealthContext(context.Background(), cfgPath, dir, map[string]any{"protocol": "blackhole"}, HealthConfig{
		Service: "xray", Binary: "xray", Timeout: 50 * time.Millisecond,
	})
	if err == nil || !strings.Contains(err.Error(), "not active") {
		t.Fatalf("expected inactive systemd health failure, got %v", err)
	}
	if time.Since(start) > time.Second {
		t.Fatalf("inactive health failure was not bounded: %v", time.Since(start))
	}
	got, readErr := os.ReadFile(cfgPath)
	if readErr != nil || string(got) != string(old) {
		t.Fatalf("candidate config was not compensated: %q err=%v", got, readErr)
	}
}

func TestXraySystemdIdentityRejectsWrongConfigDespiteOfflineCheck(t *testing.T) {
	dir := t.TempDir()
	configured := filepath.Join(dir, "configured.json")
	wrong := filepath.Join(dir, "wrong.json")
	for _, path := range []string{configured, wrong} {
		if err := os.WriteFile(path, []byte(`{"outbounds":[]}`), 0600); err != nil {
			t.Fatal(err)
		}
	}
	oldSystemctl := runSystemctl
	oldCommand := runCommand
	oldCmdline := readProcessCmdline
	oldStartTime := readProcessStartTime
	readProcessStartTime = func(int) (string, error) { return "test-start", nil }
	runSystemctl = func(_ context.Context, args ...string) (string, error) {
		if len(args) > 0 && args[0] == "show" {
			for _, arg := range args {
				if strings.Contains(arg, "MainPID") {
					return "4242", nil
				}
			}
			return fmt.Sprintf("{ path=xray ; argv[]=xray run -config %s ; }", configured), nil
		}
		return "", nil
	}
	runCommand = func(context.Context, string, ...string) error { return nil }
	readProcessCmdline = func(int) ([]string, error) {
		return []string{"xray", "run", "-config", wrong}, nil
	}
	t.Cleanup(func() {
		runSystemctl = oldSystemctl
		runCommand = oldCommand
		readProcessCmdline = oldCmdline
		readProcessStartTime = oldStartTime
	})
	if err := restartXrayAndVerify(context.Background(), configured, HealthConfig{Service: "xray", Binary: "xray", Timeout: time.Second}); err == nil || !strings.Contains(err.Error(), "does not match configured path") {
		t.Fatalf("wrong xray MainPID config was accepted: %v", err)
	}
}

func TestXrayConfigDirAndStaleSocksCannotBypassIdentity(t *testing.T) {
	dir := t.TempDir()
	configDir := filepath.Join(dir, "configs")
	if err := os.Mkdir(configDir, 0700); err != nil {
		t.Fatal(err)
	}
	configured := filepath.Join(configDir, "config.json")
	if err := os.WriteFile(configured, []byte(`{"outbounds":[]}`), 0600); err != nil {
		t.Fatal(err)
	}
	want, err := canonicalRuntimePath(configDir)
	if err != nil {
		t.Fatal(err)
	}
	for _, flag := range []string{"-confdir", "--confdir", "-config-dir", "--config-dir"} {
		if err := validateXrayInvocation([]string{"xray", "run", flag, configDir}, want, "xray"); err != nil {
			t.Errorf("config-dir flag %s rejected: %v", flag, err)
		}
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	go func() {
		conn, acceptErr := listener.Accept()
		if acceptErr != nil {
			return
		}
		defer conn.Close()
		buf := make([]byte, 3)
		_, _ = conn.Read(buf)
		_, _ = conn.Write([]byte{5, 0})
	}()
	wrong := filepath.Join(dir, "wrong.json")
	if err := os.WriteFile(wrong, []byte(`{"outbounds":[]}`), 0600); err != nil {
		t.Fatal(err)
	}
	oldSystemctl := runSystemctl
	oldCommand := runCommand
	oldCmdline := readProcessCmdline
	oldStartTime := readProcessStartTime
	readProcessStartTime = func(int) (string, error) { return "test-start", nil }
	runSystemctl = func(_ context.Context, args ...string) (string, error) {
		if len(args) > 0 && args[0] == "show" {
			for _, arg := range args {
				if strings.Contains(arg, "MainPID") {
					return "4242", nil
				}
			}
			return fmt.Sprintf("{ path=xray ; argv[]=xray run -config %s ; }", wrong), nil
		}
		return "", nil
	}
	runCommand = func(context.Context, string, ...string) error { return nil }
	readProcessCmdline = func(int) ([]string, error) {
		return []string{"xray", "run", "-config", wrong}, nil
	}
	t.Cleanup(func() {
		runSystemctl = oldSystemctl
		runCommand = oldCommand
		readProcessCmdline = oldCmdline
		readProcessStartTime = oldStartTime
	})
	if err := restartXrayAndVerify(context.Background(), configured, HealthConfig{Service: "xray", Binary: "xray", ProbeAddress: listener.Addr().String(), Timeout: time.Second}); err == nil || !strings.Contains(err.Error(), "does not match configured path") {
		t.Fatalf("wrong xray config with a healthy stale SOCKS listener was accepted: %v", err)
	}
}

func TestApplyWritesWinnerOnRestartSuccess(t *testing.T) {
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "config.json")
	if err := os.WriteFile(cfgPath, []byte(`{"outbounds":[{"protocol":"freedom"}]}`), 0644); err != nil {
		t.Fatal(err)
	}
	installHealthyXraySystemd(t, cfgPath, false)
	if _, err := Apply(cfgPath, dir, map[string]any{"protocol": "blackhole"}); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(cfgPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(got), `"protocol": "blackhole"`) {
		t.Fatalf("winner not written: %s", got)
	}
}

func TestCanceledSystemdRestartStopsOnlyConfiguredUnit(t *testing.T) {
	configPath := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(configPath, []byte(`{"outbounds":[]}`), 0600); err != nil {
		t.Fatal(err)
	}
	oldSystemctl := runSystemctl
	oldCommand := runCommand
	var calls [][]string
	runSystemctl = func(ctx context.Context, args ...string) (string, error) {
		calls = append(calls, append([]string(nil), args...))
		if len(args) > 0 && args[0] == "restart" {
			<-ctx.Done()
			return "", ctx.Err()
		}
		return "", nil
	}
	runCommand = func(context.Context, string, ...string) error { return nil }
	t.Cleanup(func() { runSystemctl = oldSystemctl; runCommand = oldCommand })
	if err := restartXrayAndVerify(context.Background(), configPath, HealthConfig{Service: "xray-test", Binary: "xray", Timeout: 30 * time.Millisecond}); err == nil {
		t.Fatal("blocking restart unexpectedly succeeded")
	}
	want := [][]string{{"reset-failed", "xray-test"}, {"restart", "xray-test"}, {"stop", "xray-test"}}
	if !reflect.DeepEqual(calls, want) {
		t.Fatalf("systemd cancellation calls=%#v, want only configured unit stop", calls)
	}
}

func TestRunExternalTerminatesBlockingSystemctlDescendant(t *testing.T) {
	dir := t.TempDir()
	marker := filepath.Join(dir, "late-restart")
	fake := filepath.Join(dir, "systemctl")
	script := "#!/bin/sh\n( trap '' TERM; sleep 0.2; printf late > \"$1\" ) &\nwhile :; do sleep 1; done\n"
	if err := os.WriteFile(fake, []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	start := time.Now()
	if err := runExternal(ctx, fake, marker); err == nil {
		t.Fatal("blocking fake systemctl unexpectedly succeeded")
	}
	if elapsed := time.Since(start); elapsed > time.Second {
		t.Fatalf("context cancellation did not terminate systemctl process group: %v", elapsed)
	}
	time.Sleep(350 * time.Millisecond)
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Fatalf("systemctl descendant performed a late restart side effect: %v", err)
	}
}

func TestApplyPreservesFirstOutboundTag(t *testing.T) {
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "config.json")
	if err := os.WriteFile(cfgPath, []byte(`{"outbounds":[{"protocol":"freedom","tag":"proxy"}],"routing":{"rules":[{"outboundTag":"proxy"}]}}`), 0644); err != nil {
		t.Fatal(err)
	}
	installHealthyXraySystemd(t, cfgPath, false)
	if _, err := Apply(cfgPath, dir, map[string]any{"protocol": "blackhole"}); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(cfgPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(got), `"tag": "proxy"`) {
		t.Fatalf("outbound tag not preserved: %s", got)
	}
}

func TestParseProcStatStartTimeHandlesSpacesAndParentheses(t *testing.T) {
	fields := make([]string, 20)
	for i := range fields {
		fields[i] = strconv.Itoa(i)
	}
	fields[0] = "S"
	fields[19] = "987654321"
	got, err := parseProcStatStartTime("123 (xray worker (blue) unit) " + strings.Join(fields, " "))
	if err != nil {
		t.Fatal(err)
	}
	if got != "987654321" {
		t.Fatalf("start time=%q, want 987654321", got)
	}
}

func TestXrayIdentityMustRemainStableAfterProbe(t *testing.T) {
	for _, mode := range []string{"exit", "reuse", "switch"} {
		t.Run(mode, func(t *testing.T) {
			configPath := filepath.Join(t.TempDir(), "config.json")
			if err := os.WriteFile(configPath, []byte(`{"outbounds":[]}`), 0600); err != nil {
				t.Fatal(err)
			}
			var phase atomic.Int32
			oldSystemctl := runSystemctl
			oldCommand := runCommand
			oldCmdline := readProcessCmdline
			oldStartTime := readProcessStartTime
			runSystemctl = func(_ context.Context, args ...string) (string, error) {
				if len(args) == 0 {
					return "", nil
				}
				switch args[0] {
				case "is-active":
					if mode == "exit" && phase.Load() == 1 {
						return "", errors.New("unit exited")
					}
					return "", nil
				case "show":
					for _, arg := range args {
						if strings.Contains(arg, "MainPID") {
							if mode == "switch" && phase.Load() == 1 {
								return "200", nil
							}
							return "100", nil
						}
					}
					return fmt.Sprintf("{ path=xray ; argv[]=xray run -config %s ; }", configPath), nil
				}
				return "", nil
			}
			runCommand = func(context.Context, string, ...string) error { return nil }
			readProcessCmdline = func(int) ([]string, error) {
				return []string{"xray", "run", "-config", configPath}, nil
			}
			readProcessStartTime = func(int) (string, error) {
				if mode == "reuse" && phase.Load() == 1 {
					return "new-start", nil
				}
				return "old-start", nil
			}
			probeServer := startXrayIdentityProbeServer(t, func() { phase.Store(1) })
			defer probeServer.stop()
			t.Cleanup(func() {
				runSystemctl = oldSystemctl
				runCommand = oldCommand
				readProcessCmdline = oldCmdline
				readProcessStartTime = oldStartTime
			})
			health := HealthConfig{Service: "xray", Binary: "xray", ProbeAddress: probeServer.address, Timeout: time.Second}
			if err := verifyXraySystemdHealth(context.Background(), configPath, health, runSystemctl, runCommand); err == nil {
				t.Fatalf("identity mutation %q was accepted", mode)
			}
		})
	}
}

type xrayIdentityProbeServer struct {
	address string
	stop    func()
}

func startXrayIdentityProbeServer(t *testing.T, mutate func()) xrayIdentityProbeServer {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		buf := make([]byte, 3)
		if _, err := io.ReadFull(conn, buf); err != nil {
			return
		}
		mutate()
		_, _ = conn.Write([]byte{5, 0})
	}()
	return xrayIdentityProbeServer{address: listener.Addr().String(), stop: func() {
		_ = listener.Close()
		select {
		case <-done:
		case <-time.After(time.Second):
			t.Error("identity probe server did not stop")
		}
	}}
}
