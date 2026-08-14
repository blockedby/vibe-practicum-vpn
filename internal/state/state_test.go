package state

import (
	"context"
	"errors"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

func TestCurrentBaselineValidationFailsClosed(t *testing.T) {
	for name, current := range map[string]Current{
		"zero":     {},
		"negative": {Mbps: -1},
		"nan":      {Mbps: math.NaN()},
		"infinity": {Mbps: math.Inf(1)},
	} {
		t.Run(name, func(t *testing.T) {
			if current.ValidateBaseline() == nil || current.HasValidBaseline() {
				t.Fatal("invalid baseline was accepted")
			}
		})
	}
}

func TestSnapshotRestoresMissingAndExistingCurrentState(t *testing.T) {
	dir := t.TempDir()
	if err := SaveCurrent(dir, Current{Name: "old", Link: "old-link", Mbps: 100}); err != nil {
		t.Fatal(err)
	}
	snap, err := Capture(dir)
	if err != nil {
		t.Fatal(err)
	}
	if err := SaveCurrent(dir, Current{Name: "new", Link: "new-link", Mbps: 120}); err != nil {
		t.Fatal(err)
	}
	if err := snap.Restore(dir); err != nil {
		t.Fatal(err)
	}
	got, err := LoadCurrent(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got.Name != "old" || got.Link != "old-link" || got.Mbps != 100 {
		t.Fatalf("restored current=%+v", got)
	}

	missingDir := filepath.Join(dir, "missing")
	missing, err := Capture(missingDir)
	if err != nil {
		t.Fatal(err)
	}
	if err := SaveCurrent(missingDir, Current{Name: "temporary", Link: "temporary", Mbps: 1}); err != nil {
		t.Fatal(err)
	}
	if err := missing.Restore(missingDir); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(missingDir, "current-node.json")); !os.IsNotExist(err) {
		t.Fatalf("current-node.json remains after missing snapshot restore: %v", err)
	}
}

func TestLegacySnapshotsMigrateOutOfRuntimeBackupDirectory(t *testing.T) {
	dir := t.TempDir()
	if err := SaveCurrent(dir, Current{Name: "old", Link: "opaque-link", Mbps: 10}); err != nil {
		t.Fatal(err)
	}
	snap, err := Capture(dir)
	if err != nil {
		t.Fatal(err)
	}
	runtime := filepath.Join(dir, "backups", "sing-box-20240101-000000000.json")
	if err := os.MkdirAll(filepath.Dir(runtime), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(runtime, []byte(`{"outbounds":[]}`), 0600); err != nil {
		t.Fatal(err)
	}
	legacy := filepath.Base(runtime) + ".state.json"
	if err := SaveJSON(filepath.Dir(runtime), legacy, snap.persisted()); err != nil {
		t.Fatal(err)
	}

	paired, err := PairedRuntimeBackups(dir, "sing-box-")
	if err != nil {
		t.Fatal(err)
	}
	if len(paired) != 1 || paired[0] != runtime {
		t.Fatalf("paired backups=%v, want exact runtime backup", paired)
	}
	if _, err := os.Stat(filepath.Join(dir, "backups", legacy)); !os.IsNotExist(err) {
		t.Fatalf("legacy sidecar remains in runtime backup directory: %v", err)
	}
	migrated := filepath.Join(StateSnapshotDir(dir), legacy)
	if _, err := os.Stat(migrated); err != nil {
		t.Fatalf("migrated sidecar missing: %v", err)
	}
	files, err := RuntimeBackupFiles(dir, "sing-box-")
	if err != nil {
		t.Fatal(err)
	}
	if len(files) != 1 || files[0] != runtime {
		t.Fatalf("runtime glob/filter returned %v", files)
	}
}

func TestPairedRuntimeBackupsIgnoreNewestUnpairedRuntimeFile(t *testing.T) {
	dir := t.TempDir()
	for _, name := range []string{"sing-box-20240101-000000000.json", "sing-box-99999999-999999999.json"} {
		path := filepath.Join(dir, "backups", name)
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(name), 0600); err != nil {
			t.Fatal(err)
		}
	}
	if err := SaveSnapshotForBackup(dir, filepath.Join(dir, "backups", "sing-box-20240101-000000000.json"), Snapshot{}); err != nil {
		t.Fatal(err)
	}
	paired, err := PairedRuntimeBackups(dir, "sing-box-")
	if err != nil {
		t.Fatal(err)
	}
	if len(paired) != 1 || filepath.Base(paired[0]) != "sing-box-20240101-000000000.json" {
		t.Fatalf("paired backups=%v, want only the exact paired basename", paired)
	}
}

func TestCrossProcessStateDirLockContract(t *testing.T) {
	if os.Getenv("VIBE_VPN_STATE_LOCK_HELPER") == "1" {
		dir := os.Getenv("VIBE_VPN_STATE_LOCK_DIR")
		wantBlocked := os.Getenv("VIBE_VPN_STATE_LOCK_EXPECT") == "blocked"
		ctx, cancel := context.WithTimeout(context.Background(), 150*time.Millisecond)
		defer cancel()
		lock, err := AcquireLock(ctx, dir)
		if wantBlocked {
			if lock != nil {
				_ = lock.Close()
				t.Fatal("child acquired a lock held by the parent")
			}
			if !errors.Is(err, context.DeadlineExceeded) {
				t.Fatalf("blocked child error=%v, want context deadline", err)
			}
			return
		}
		if err != nil {
			t.Fatal(err)
		}
		if err := lock.Close(); err != nil {
			t.Fatal(err)
		}
		return
	}

	dir := t.TempDir()
	lock, err := AcquireLock(context.Background(), dir)
	if err != nil {
		t.Fatal(err)
	}
	runHelper := func(expect string) error {
		cmd := exec.Command(os.Args[0], "-test.run=TestCrossProcessStateDirLockContract$", "-test.v")
		cmd.Env = append(os.Environ(),
			"VIBE_VPN_STATE_LOCK_HELPER=1",
			"VIBE_VPN_STATE_LOCK_DIR="+dir,
			"VIBE_VPN_STATE_LOCK_EXPECT="+expect,
		)
		return cmd.Run()
	}
	if err := runHelper("blocked"); err != nil {
		_ = lock.Close()
		t.Fatalf("cross-process blocked contract failed: %v", err)
	}
	if err := lock.Close(); err != nil {
		t.Fatal(err)
	}
	if err := runHelper("released"); err != nil {
		t.Fatalf("cross-process release contract failed: %v", err)
	}
}
