package state

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
)

type Current struct {
	Name     string  `json:"name"`
	Host     string  `json:"host"`
	Network  string  `json:"network"`
	Security string  `json:"security"`
	Link     string  `json:"link"`
	TestedAt string  `json:"tested_at"`
	Port     int     `json:"port"`
	Mbps     float64 `json:"mbps"`
}

// ValidateBaseline checks the only current-state value used by performance
// hysteresis. A missing or malformed baseline must never authorize a rotation.
func (c Current) ValidateBaseline() error {
	if math.IsNaN(c.Mbps) || math.IsInf(c.Mbps, 0) {
		return fmt.Errorf("current benchmark speed must be finite")
	}
	if c.Mbps <= 0 {
		return fmt.Errorf("current benchmark speed must be positive")
	}
	return nil
}

func (c Current) HasValidBaseline() bool { return c.ValidateBaseline() == nil }

func SaveJSON(dir, name string, v any) error {
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	b, err := marshalJSON(v)
	if err != nil {
		return err
	}
	return writeFileAtomic(filepath.Join(dir, name), b, 0600)
}

func marshalJSON(v any) ([]byte, error) {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return nil, err
	}
	return append(b, '\n'), nil
}

// FileVersion is an in-memory identity for an atomically replaced state file.
// It combines the exact bytes with the filesystem identity so a writer that
// publishes the same JSON again is still considered newer. The type is opaque
// to callers; use CaptureFileVersion and the methods below.
type FileVersion struct {
	info os.FileInfo
	data []byte
}

// CaptureFileVersion reads one stable open-file instance. Atomic writers may
// replace the path while this runs, but the open descriptor keeps the bytes
// and identity paired.
func CaptureFileVersion(path string) (FileVersion, error) {
	f, err := os.Open(path)
	if os.IsNotExist(err) {
		return FileVersion{}, nil
	}
	if err != nil {
		return FileVersion{}, err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return FileVersion{}, err
	}
	data, err := io.ReadAll(f)
	if err != nil {
		return FileVersion{}, err
	}
	return FileVersion{info: info, data: append([]byte(nil), data...)}, nil
}

func (v FileVersion) Exists() bool { return v.info != nil }

func (v FileVersion) Data() []byte { return append([]byte(nil), v.data...) }

func (v FileVersion) Perm() os.FileMode {
	if v.info == nil {
		return 0600
	}
	if mode := v.info.Mode().Perm(); mode != 0 {
		return mode
	}
	return 0600
}

func (v FileVersion) Equal(other FileVersion) bool {
	if v.info == nil || other.info == nil {
		return v.info == nil && other.info == nil
	}
	return os.SameFile(v.info, other.info) && bytes.Equal(v.data, other.data)
}

// SaveJSONVersioned serializes a short result publication under the shared
// state-dir lock and returns the exact published file version. Callers must
// not already hold dir's lock.
func SaveJSONVersioned(ctx context.Context, dir, name string, v any) (FileVersion, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	b, err := marshalJSON(v)
	if err != nil {
		return FileVersion{}, err
	}
	var version FileVersion
	err = WithLock(ctx, dir, func() error {
		if err := ctx.Err(); err != nil {
			return err
		}
		path := filepath.Join(dir, name)
		before, err := CaptureFileVersion(path)
		if err != nil {
			return err
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		// Keep this check immediately adjacent to the atomic publication. A
		// caller canceled while waiting for the shared lock must never publish.
		saveErr := writeFileAtomicContext(ctx, path, b, 0600)
		if saveErr != nil {
			// writeFileAtomic may have renamed the new file before a directory
			// fsync error is returned. Report the observed published version so a
			// caller can still make a safe conditional compensation attempt.
			if after, captureErr := CaptureFileVersion(path); captureErr == nil && !after.Equal(before) {
				version = after
			}
			return saveErr
		}
		version, err = CaptureFileVersion(path)
		return err
	})
	return version, err
}

// SaveJSONIfVersion publishes v only if name still has expected's exact
// inode/content version. It is used by long-running scheduled work so a
// manual result writer wins without the benchmark holding the state lock.
// committed can be true alongside an error when rename succeeded but durable
// directory synchronization could not be confirmed.
func SaveJSONIfVersion(ctx context.Context, dir, name string, v any, expected FileVersion) (FileVersion, bool, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	b, err := marshalJSON(v)
	if err != nil {
		return FileVersion{}, false, err
	}
	var version FileVersion
	committed := false
	err = WithLock(ctx, dir, func() error {
		if err := ctx.Err(); err != nil {
			return err
		}
		path := filepath.Join(dir, name)
		current, err := CaptureFileVersion(path)
		if err != nil {
			return err
		}
		if !current.Equal(expected) {
			return nil
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		// Do not move this check above the version comparison: cancellation
		// after lock acquisition and before publication must be observed even
		// when the expected version still matches.
		saveErr := writeFileAtomicContext(ctx, path, b, 0600)
		if saveErr != nil {
			// A directory-sync failure can happen after rename. Distinguish that
			// visible candidate from a write that never replaced the path; the
			// returned error still tells the caller durability was not confirmed.
			if after, captureErr := CaptureFileVersion(path); captureErr == nil && !after.Equal(current) {
				version = after
				committed = true
			}
			return saveErr
		}
		version, err = CaptureFileVersion(path)
		if err == nil {
			committed = true
		}
		return err
	})
	return version, committed, err
}

// RestoreFileIfVersion atomically restores replacement only while path still
// has expected's exact version. The shared lock makes this compare-and-write
// safe against all state writers in this process and other vibe-vpn processes.
func RestoreFileIfVersion(ctx context.Context, dir, name string, expected FileVersion, replacement []byte, perm os.FileMode) (bool, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	restored := false
	err := WithLock(ctx, dir, func() error {
		if err := ctx.Err(); err != nil {
			return err
		}
		path := filepath.Join(dir, name)
		current, err := CaptureFileVersion(path)
		if err != nil {
			return err
		}
		if !current.Equal(expected) {
			return nil
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		// This is the last cancellation check before the rename performed by
		// writeFileAtomic; a canceled compensation must not start a new write.
		if perm == 0 {
			perm = 0600
		}
		writeErr := writeFileAtomicContext(ctx, path, replacement, perm)
		if writeErr != nil {
			// Rename is atomic, so a later directory-fsync error can still leave
			// the replacement visible. Report that fact to callers while keeping
			// the durability error for retry/reporting.
			if after, captureErr := CaptureFileVersion(path); captureErr == nil && !after.Equal(current) {
				restored = true
			}
			return writeErr
		}
		restored = true
		return nil
	})
	return restored, err
}

// DeleteFileIfVersion removes name only while it still has expected's exact
// version. The unlink and containing-directory fsync are performed while the
// shared state lock is held, so a newer cooperative writer is never removed.
func DeleteFileIfVersion(ctx context.Context, dir, name string, expected FileVersion) (bool, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	deleted := false
	err := WithLock(ctx, dir, func() error {
		if err := ctx.Err(); err != nil {
			return err
		}
		path := filepath.Join(dir, name)
		current, err := CaptureFileVersion(path)
		if err != nil {
			return err
		}
		if !current.Equal(expected) {
			return nil
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		if err := os.Remove(path); err != nil {
			if os.IsNotExist(err) {
				return nil
			}
			return err
		}
		deleted = true
		// An unlink is visible immediately; sync the directory before claiming
		// the conditional delete is durable.
		return atomicSyncDir(filepath.Dir(path))
	})
	return deleted, err
}

// RestoreIfVersion and DeleteIfVersion are concise aliases for callers that
// treat the state file rather than its path as the primary abstraction.
func RestoreIfVersion(ctx context.Context, dir, name string, expected FileVersion, replacement []byte, perm os.FileMode) (bool, error) {
	return RestoreFileIfVersion(ctx, dir, name, expected, replacement, perm)
}

func DeleteIfVersion(ctx context.Context, dir, name string, expected FileVersion) (bool, error) {
	return DeleteFileIfVersion(ctx, dir, name, expected)
}

func LoadCurrent(dir string) (Current, error) {
	var c Current
	b, err := os.ReadFile(filepath.Join(dir, "current-node.json"))
	if err != nil {
		return c, err
	}
	return c, json.Unmarshal(b, &c)
}

// SaveCurrent writes the selected node and its private link as one state
// update. If either write fails, the exact previous state is restored.
func SaveCurrent(dir string, c Current) error {
	snap, err := Capture(dir)
	if err != nil {
		return err
	}
	if err := SaveJSON(dir, "current-node.json", c); err != nil {
		return err
	}
	if err := writeFileAtomic(filepath.Join(dir, "current-link.txt"), []byte(c.Link+"\n"), 0600); err != nil {
		restoreErr := snap.Restore(dir)
		if restoreErr != nil {
			return fmt.Errorf("save current link: %w; restore previous state: %v", err, restoreErr)
		}
		return err
	}
	return nil
}

// SnapshotForCurrent creates the exact two-file selected-state representation
// that SaveCurrent would publish, without touching the live state directory.
// The link remains opaque bytes in the snapshot and is never included in an
// error or log message.
func SnapshotForCurrent(c Current) (Snapshot, error) {
	b, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return Snapshot{}, err
	}
	return Snapshot{
		CurrentNode: fileSnapshot{Exists: true, Data: append(b, '\n'), Mode: 0600},
		CurrentLink: fileSnapshot{Exists: true, Data: []byte(c.Link + "\n"), Mode: 0600},
	}, nil
}

type fileSnapshot struct {
	Exists bool
	Data   []byte
	Mode   os.FileMode
}

// Snapshot is an in-memory copy of the selected-node state. It intentionally
// contains opaque bytes so callers cannot accidentally log a node link.
type Snapshot struct {
	CurrentNode fileSnapshot
	CurrentLink fileSnapshot
}

func Capture(dir string) (Snapshot, error) {
	var snap Snapshot
	var err error
	if snap.CurrentNode, err = captureFile(filepath.Join(dir, "current-node.json")); err != nil {
		return Snapshot{}, err
	}
	if snap.CurrentLink, err = captureFile(filepath.Join(dir, "current-link.txt")); err != nil {
		return Snapshot{}, err
	}
	return snap, nil
}

func captureFile(path string) (fileSnapshot, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return fileSnapshot{}, nil
		}
		return fileSnapshot{}, err
	}
	st, err := os.Stat(path)
	if err != nil {
		return fileSnapshot{}, err
	}
	return fileSnapshot{Exists: true, Data: append([]byte(nil), b...), Mode: st.Mode().Perm()}, nil
}

func (s Snapshot) Equal(other Snapshot) bool {
	return equalFileSnapshot(s.CurrentNode, other.CurrentNode) && equalFileSnapshot(s.CurrentLink, other.CurrentLink)
}

func equalFileSnapshot(a, b fileSnapshot) bool {
	return a.Exists == b.Exists && a.Mode == b.Mode && bytes.Equal(a.Data, b.Data)
}

func (s Snapshot) Restore(dir string) error {
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	if err := restoreFile(filepath.Join(dir, "current-node.json"), s.CurrentNode); err != nil {
		return err
	}
	return restoreFile(filepath.Join(dir, "current-link.txt"), s.CurrentLink)
}

func restoreFile(path string, f fileSnapshot) error {
	if !f.Exists {
		if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
			return err
		}
		return nil
	}
	mode := f.Mode
	if mode == 0 {
		mode = 0600
	}
	return writeFileAtomic(path, f.Data, mode)
}

// The persisted state snapshot is paired with one runtime backup. []byte
// fields are base64 encoded by encoding/json; the contents never enter logs or
// error strings.
type persistedSnapshot struct {
	CurrentNode fileSnapshotJSON `json:"current_node"`
	CurrentLink fileSnapshotJSON `json:"current_link"`
}

type fileSnapshotJSON struct {
	Exists bool        `json:"exists"`
	Data   []byte      `json:"data,omitempty"`
	Mode   os.FileMode `json:"mode,omitempty"`
}

func (s Snapshot) persisted() persistedSnapshot {
	return persistedSnapshot{
		CurrentNode: fileSnapshotJSON{Exists: s.CurrentNode.Exists, Data: s.CurrentNode.Data, Mode: s.CurrentNode.Mode},
		CurrentLink: fileSnapshotJSON{Exists: s.CurrentLink.Exists, Data: s.CurrentLink.Data, Mode: s.CurrentLink.Mode},
	}
}

func (p persistedSnapshot) snapshot() Snapshot {
	return Snapshot{
		CurrentNode: fileSnapshot{Exists: p.CurrentNode.Exists, Data: p.CurrentNode.Data, Mode: p.CurrentNode.Mode},
		CurrentLink: fileSnapshot{Exists: p.CurrentLink.Exists, Data: p.CurrentLink.Data, Mode: p.CurrentLink.Mode},
	}
}

const stateSnapshotDirectory = "state-snapshots"

// StateSnapshotDir is deliberately outside the runtime backup directory.
// Runtime code may safely enumerate backups with sing-box-*.json or
// xray-*.json without ever seeing a state sidecar.
func StateSnapshotDir(stateDir string) string {
	return filepath.Join(stateDir, stateSnapshotDirectory)
}

// SnapshotPath returns the sidecar path for exactly one runtime backup. The
// basename, rather than a glob, is the pairing key for rollback.
func SnapshotPath(stateDir, runtimeBackup string) string {
	return filepath.Join(StateSnapshotDir(stateDir), filepath.Base(runtimeBackup)+".state.json")
}

func legacySnapshotPath(stateDir, runtimeBackup string) string {
	return filepath.Join(stateDir, "backups", filepath.Base(runtimeBackup)+".state.json")
}

// MigrateLegacySnapshots moves sidecars written by the pre-REV-009 layout out
// of backups/. It never overwrites a different destination sidecar: equal
// copies are deduplicated, while conflicting copies fail closed and remain
// available for operator inspection.
func MigrateLegacySnapshots(stateDir string) error {
	// Transaction artifacts share the same state-dir lifecycle. Migrate their
	// legacy namespace before any runtime backup listing so a locked caller can
	// recover or prune both artifact families consistently.
	if err := MigrateLegacyTransactionArtifacts(stateDir); err != nil {
		return err
	}
	files, err := filepath.Glob(filepath.Join(stateDir, "backups", "*.state.json"))
	if err != nil {
		return err
	}
	if len(files) == 0 {
		return nil
	}
	if err := os.MkdirAll(StateSnapshotDir(stateDir), 0700); err != nil {
		return err
	}
	for _, src := range files {
		base := strings.TrimSuffix(filepath.Base(src), ".state.json")
		if !isKnownRuntimeBackup(base) {
			// Do not move unrelated operator files merely because they happen to
			// end in .state.json.
			continue
		}
		dst := filepath.Join(StateSnapshotDir(stateDir), filepath.Base(src))
		if existing, readErr := os.ReadFile(dst); readErr == nil {
			incoming, incomingErr := os.ReadFile(src)
			if incomingErr != nil {
				return incomingErr
			}
			if !bytes.Equal(existing, incoming) {
				return fmt.Errorf("state snapshot migration conflict")
			}
			if err := os.Remove(src); err != nil {
				return err
			}
			continue
		} else if !os.IsNotExist(readErr) {
			return readErr
		}
		if err := os.Rename(src, dst); err != nil {
			return err
		}
	}
	return nil
}

func isKnownRuntimeBackup(base string) bool {
	return strings.HasPrefix(base, "sing-box-") || strings.HasPrefix(base, "xray-")
}

// SaveSnapshotForBackup stores a state snapshot in the dedicated sidecar
// directory. Callers should create the runtime backup first and remove it if
// this operation fails; a crash-created unpaired file is ignored by paired
// rollback and can be cleaned by prune.
func SaveSnapshotForBackup(stateDir, runtimeBackup string, snap Snapshot) error {
	if strings.TrimSpace(runtimeBackup) == "" {
		return fmt.Errorf("runtime backup path is empty")
	}
	path := SnapshotPath(stateDir, runtimeBackup)
	return SaveJSON(filepath.Dir(path), filepath.Base(path), snap.persisted())
}

func LoadSnapshotForBackup(stateDir, runtimeBackup string) (Snapshot, error) {
	if strings.TrimSpace(runtimeBackup) == "" {
		return Snapshot{}, fmt.Errorf("runtime backup path is empty")
	}
	if err := MigrateLegacySnapshots(stateDir); err != nil {
		return Snapshot{}, err
	}
	b, err := os.ReadFile(SnapshotPath(stateDir, runtimeBackup))
	if err != nil {
		return Snapshot{}, err
	}
	var p persistedSnapshot
	if err := json.Unmarshal(b, &p); err != nil {
		return Snapshot{}, err
	}
	return p.snapshot(), nil
}

// RemoveSnapshotForBackup removes both the current and pre-REV-009 locations.
// It is used by prune so an old sidecar cannot be left behind as an orphan.
func RemoveSnapshotForBackup(stateDir, runtimeBackup string) error {
	var first error
	for _, path := range []string{SnapshotPath(stateDir, runtimeBackup), legacySnapshotPath(stateDir, runtimeBackup)} {
		if err := os.Remove(path); err != nil && !os.IsNotExist(err) && first == nil {
			first = err
		}
	}
	return first
}

// RuntimeBackupFiles returns only real runtime JSON backups. In particular,
// legacy *.state.json files are filtered even before migration is run, so a
// read-only prune or rollback listing can never treat a sidecar as runtime.
func RuntimeBackupFiles(stateDir, prefix string) ([]string, error) {
	files, err := filepath.Glob(filepath.Join(stateDir, "backups", prefix+"*.json"))
	if err != nil {
		return nil, err
	}
	out := make([]string, 0, len(files))
	for _, path := range files {
		base := filepath.Base(path)
		if strings.HasSuffix(base, ".state.json") || !strings.HasPrefix(base, prefix) {
			continue
		}
		st, statErr := os.Stat(path)
		if statErr != nil {
			if os.IsNotExist(statErr) {
				continue
			}
			return nil, statErr
		}
		if !st.Mode().IsRegular() {
			continue
		}
		out = append(out, path)
	}
	sort.Strings(out)
	return out, nil
}

// PairedRuntimeBackups lists only runtime backups that have the exact
// basename-matched state sidecar. It is the only listing used by rollback.
func PairedRuntimeBackups(stateDir, prefix string) ([]string, error) {
	if err := MigrateLegacySnapshots(stateDir); err != nil {
		return nil, err
	}
	files, err := RuntimeBackupFiles(stateDir, prefix)
	if err != nil {
		return nil, err
	}
	paired := make([]string, 0, len(files))
	for _, runtimeBackup := range files {
		if _, err := os.Stat(SnapshotPath(stateDir, runtimeBackup)); err == nil {
			paired = append(paired, runtimeBackup)
		} else if !os.IsNotExist(err) {
			return nil, err
		}
	}
	return paired, nil
}

// SnapshotFiles returns sidecars in the dedicated directory for orphan
// cleanup. It does not migrate legacy files and is therefore safe for dry-run
// inspection.
func SnapshotFiles(stateDir string) ([]string, error) {
	files, err := filepath.Glob(filepath.Join(StateSnapshotDir(stateDir), "*.state.json"))
	if err != nil {
		return nil, err
	}
	sort.Strings(files)
	return files, nil
}

func RuntimeBackupBaseForSnapshot(path string) string {
	return strings.TrimSuffix(filepath.Base(path), ".state.json")
}

var (
	lockRegistryMu sync.Mutex
	lockRegistry   = map[string]chan struct{}{}

	// afterLockAcquiredHook is a narrow test seam for cancellation tests. It
	// runs only after AcquireLock has returned and before a lock-scoped
	// callback is allowed to publish anything.
	afterLockAcquiredHook func()

	// These seams let package tests model rename/fsync failures that can occur
	// after an atomic replacement became visible. Production uses os.Rename,
	// File.Sync, and syncDir unchanged.
	atomicRename   = os.Rename
	atomicSyncFile = func(f *os.File) error { return f.Sync() }
	atomicSyncDir  = syncDir
)

// Lock combines an in-process gate with an advisory OS file lock. The file
// lock makes daemon and separately invoked pick/apply/rollback/sync/prune
// commands obey the same state-dir transaction boundary.
type Lock struct {
	file *os.File
	gate chan struct{}
	once sync.Once
}

func AcquireLock(ctx context.Context, dir string) (*Lock, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, err
	}
	key, err := filepath.Abs(dir)
	if err != nil {
		return nil, err
	}
	lockRegistryMu.Lock()
	gate := lockRegistry[key]
	if gate == nil {
		gate = make(chan struct{}, 1)
		gate <- struct{}{}
		lockRegistry[key] = gate
	}
	lockRegistryMu.Unlock()

	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-gate:
	}

	f, err := os.OpenFile(filepath.Join(dir, ".vibe-vpn.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		gate <- struct{}{}
		return nil, err
	}
	ticker := time.NewTicker(10 * time.Millisecond)
	defer ticker.Stop()
	for {
		err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
		if err == nil {
			return &Lock{file: f, gate: gate}, nil
		}
		if !errors.Is(err, syscall.EWOULDBLOCK) && !errors.Is(err, syscall.EAGAIN) {
			_ = f.Close()
			gate <- struct{}{}
			return nil, err
		}
		select {
		case <-ctx.Done():
			_ = f.Close()
			gate <- struct{}{}
			return nil, ctx.Err()
		case <-ticker.C:
		}
	}
}

func (l *Lock) Close() error {
	if l == nil {
		return nil
	}
	var ret error
	l.once.Do(func() {
		if l.file != nil {
			if err := syscall.Flock(int(l.file.Fd()), syscall.LOCK_UN); err != nil {
				ret = err
			}
			if err := l.file.Close(); ret == nil && err != nil {
				ret = err
			}
		}
		if l.gate != nil {
			l.gate <- struct{}{}
		}
	})
	return ret
}

func WithLock(ctx context.Context, dir string, fn func() error) error {
	if ctx == nil {
		ctx = context.Background()
	}
	lock, err := AcquireLock(ctx, dir)
	if err != nil {
		return err
	}
	defer lock.Close()
	if afterLockAcquiredHook != nil {
		afterLockAcquiredHook()
	}
	// AcquireLock may win the OS lock at the same instant a caller cancels.
	// Recheck here so lock-held cancellation cannot enter a publishing
	// callback, even when the lock became available after the wait.
	if err := ctx.Err(); err != nil {
		return err
	}
	return fn()
}

func writeFileAtomic(path string, b []byte, perm os.FileMode) error {
	return writeFileAtomicContext(context.Background(), path, b, perm)
}

func writeFileAtomicContext(ctx context.Context, path string, b []byte, perm os.FileMode) error {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return err
	}
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
	if err := atomicSyncFile(f); err != nil {
		_ = f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	// This is the final cancellation check before the atomic rename. A caller
	// canceled while the temporary file was being prepared cannot publish it.
	if err := ctx.Err(); err != nil {
		return err
	}
	if err := atomicRename(tmp, path); err != nil {
		return err
	}
	return atomicSyncDir(dir)
}
