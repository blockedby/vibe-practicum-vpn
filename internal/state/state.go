package state

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
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
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	return writeFileAtomic(filepath.Join(dir, name), append(b, '\n'), 0600)
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
	lock, err := AcquireLock(ctx, dir)
	if err != nil {
		return err
	}
	defer lock.Close()
	return fn()
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
