package main

import (
	"context"
	"errors"
	"net"
	"os"
	"os/exec"
	"path/filepath"
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
