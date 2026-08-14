package failover

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
	"github.com/kcnc/vibe-practicum-vpn/internal/health"
	"github.com/kcnc/vibe-practicum-vpn/internal/picker"
	"github.com/kcnc/vibe-practicum-vpn/internal/state"
)

type ApplyFunc func(context.Context, config.Config, picker.NodeResult) error
type ProbeFunc func(context.Context) health.Result
type RestoreFunc func(context.Context, config.Config) error
type LogFunc func(string, ...any)

type Manager struct {
	Config  config.Config
	Apply   ApplyFunc
	Probe   ProbeFunc
	Restore RestoreFunc
	Logf    LogFunc
}

// RotationManager owns the performance-driven selection policy. It is kept
// separate from Manager so health-triggered failover never consults
// performance hysteresis or cooldown state.
type RotationManager struct {
	Config  config.Config
	Apply   ApplyFunc
	Probe   ProbeFunc
	Restore RestoreFunc
	Logf    LogFunc
	Now     func() time.Time

	mu              sync.Mutex
	lastRotation    time.Time
	hasLastRotation bool
}

func LoadResults(stateDir string) ([]picker.NodeResult, error) {
	var rs []picker.NodeResult
	b, err := os.ReadFile(filepath.Join(stateDir, "last-results.json"))
	if err != nil {
		return nil, err
	}
	return rs, json.Unmarshal(b, &rs)
}

func Fastest(results []picker.NodeResult) (picker.NodeResult, bool) {
	ok := workingBySpeed(results)
	if len(ok) == 0 {
		return picker.NodeResult{}, false
	}
	return ok[0], true
}

func SameCurrent(r picker.NodeResult, c state.Current) bool { return same(r, c) }

// MeetsMinimumImprovement reports whether a scheduled rotation candidate is
// sufficiently faster than the current node. A missing, corrupt, or invalid
// current baseline never authorizes a positive hysteresis rotation.
func MeetsMinimumImprovement(candidate picker.NodeResult, current state.Current, minimumPercent float64) bool {
	if !finitePositive(candidate.Mbps) || math.IsNaN(minimumPercent) || math.IsInf(minimumPercent, 0) || minimumPercent < 0 {
		return false
	}
	if err := current.ValidateBaseline(); err != nil {
		return false
	}
	if minimumPercent == 0 {
		return true
	}
	if candidate.Mbps <= current.Mbps {
		return false
	}
	return improvementPercent(candidate.Mbps, current.Mbps) >= minimumPercent
}

func improvementPercent(candidate, current float64) float64 {
	if !finitePositive(candidate) || !finitePositive(current) {
		return 0
	}
	return (candidate - current) / current * 100
}

func Candidates(results []picker.NodeResult, cur state.Current) []picker.NodeResult {
	ok := workingBySpeed(results)
	if len(ok) < 2 {
		return ok
	}
	pos := -1
	for i, r := range ok {
		if same(r, cur) {
			pos = i
			break
		}
	}
	if pos < 0 {
		return ok
	}
	out := append([]picker.NodeResult{}, ok[pos+1:]...)
	out = append(out, ok[:pos]...)
	return out
}

func workingBySpeed(results []picker.NodeResult) []picker.NodeResult {
	ok := make([]picker.NodeResult, 0, len(results))
	for _, r := range results {
		if r.OK && !r.Excluded && finitePositive(r.Mbps) {
			ok = append(ok, r)
		}
	}
	sort.SliceStable(ok, func(i, j int) bool { return ok[i].Mbps > ok[j].Mbps })
	return ok
}

func finitePositive(v float64) bool { return v > 0 && !math.IsNaN(v) && !math.IsInf(v, 0) }

func restoreIfStateChanged(dir string, snapshot state.Snapshot, restore RestoreFunc, c config.Config) error {
	current, err := state.Capture(dir)
	if err != nil {
		return fmt.Errorf("capture state after failed apply: %w", err)
	}
	if snapshot.Equal(current) {
		return nil
	}
	var restoreErr error
	if restore != nil {
		restoreErr = restore(context.Background(), c)
	}
	stateErr := snapshot.Restore(dir)
	if restoreErr != nil || stateErr != nil {
		return fmt.Errorf("runtime restore: %v; state restore: %v", restoreErr, stateErr)
	}
	return nil
}

func same(r picker.NodeResult, c state.Current) bool {
	if c.Link != "" && r.Link != "" && r.Link == c.Link {
		return true
	}
	return c.Name != "" && c.Host != "" && r.Name == c.Name && r.Host == c.Host && r.Port == c.Port
}

func (m *RotationManager) Run(ctx context.Context) error {
	if ctx == nil {
		ctx = context.Background()
	}
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.Apply == nil {
		return fmt.Errorf("scheduled rotation apply adapter is nil")
	}
	lock, err := state.AcquireLock(ctx, m.Config.StateDir)
	if err != nil {
		return fmt.Errorf("scheduled rotation state lock: %w", err)
	}
	defer lock.Close()
	if err := ctx.Err(); err != nil {
		return err
	}
	snapshot, err := state.Capture(m.Config.StateDir)
	if err != nil {
		return fmt.Errorf("capture current state: %w", err)
	}

	now := m.now()
	cooldown := m.Config.Service.FastestRotation.Cooldown.Duration
	if cooldown > 0 && m.hasLastRotation && now.Before(m.lastRotation.Add(cooldown)) {
		m.log("scheduled fastest rotation cooling down; next rotation allowed after %s", m.lastRotation.Add(cooldown).Format(time.RFC3339))
		return nil
	}
	probe := m.probe()
	if res := probe(ctx); res.FailoverNeeded {
		// The health path owns failover. A performance rotation must never
		// replace a node after the old node has already failed health.
		m.log("scheduled fastest rotation stopped: old health reports failover-needed")
		return nil
	}
	if err := ctx.Err(); err != nil {
		return err
	}

	cur, err := state.LoadCurrent(m.Config.StateDir)
	if err != nil {
		m.log("scheduled fastest rotation skipped: current state unavailable")
		return nil
	}
	minimum := m.Config.Service.FastestRotation.MinImprovementPercent
	if err := cur.ValidateBaseline(); err != nil {
		m.log("scheduled fastest rotation skipped: current benchmark baseline unavailable")
		return nil
	}
	results, err := LoadResults(m.Config.StateDir)
	if err != nil {
		return err
	}
	fastest, ok := Fastest(results)
	if !ok {
		return fmt.Errorf("no working non-excluded node available for scheduled rotation")
	}
	if SameCurrent(fastest, cur) {
		m.log("scheduled fastest rotation: fastest node #%03d %s is already current", fastest.Index, fastest.Name)
		return nil
	}
	if !MeetsMinimumImprovement(fastest, cur, minimum) {
		m.log("scheduled fastest rotation: candidate #%03d %s improves speed by %.2f%%, below %.2f%% minimum", fastest.Index, fastest.Name, improvementPercent(fastest.Mbps, cur.Mbps), minimum)
		return nil
	}
	m.log("scheduled fastest rotation applying #%03d %s %.2f Mbps", fastest.Index, fastest.Name, fastest.Mbps)
	if err := m.Apply(ctx, m.Config, fastest); err != nil {
		if restoreErr := restoreIfStateChanged(m.Config.StateDir, snapshot, m.Restore, m.Config); restoreErr != nil {
			return fmt.Errorf("scheduled rotation apply failed: %v; restore failed: %w", err, restoreErr)
		}
		return err
	}
	if err := ctx.Err(); err != nil {
		if restoreErr := m.restoreTransaction(snapshot); restoreErr != nil {
			return fmt.Errorf("scheduled rotation canceled; restore failed: %w", restoreErr)
		}
		return err
	}
	res := probe(ctx)
	if err := ctx.Err(); err != nil {
		if restoreErr := m.restoreTransaction(snapshot); restoreErr != nil {
			return fmt.Errorf("scheduled rotation canceled; restore failed: %w", restoreErr)
		}
		return err
	}
	if res.FailoverNeeded {
		if restoreErr := m.restoreTransaction(snapshot); restoreErr != nil {
			return fmt.Errorf("scheduled rotation post-apply health failed; restore failed: %w", restoreErr)
		}
		return fmt.Errorf("scheduled rotation post-apply health failed")
	}
	m.lastRotation = m.now()
	m.hasLastRotation = true
	return nil
}

func (m *RotationManager) probe() ProbeFunc {
	if m.Probe != nil {
		return m.Probe
	}
	runner := health.NewRunner(m.Config.ProductionSocks, m.Config.Health.RequiredURLs, m.Config.Health.DiagnosticURLs, m.Config.Health.ProbeTimeout.Duration)
	return runner.Run
}

func (m *RotationManager) restoreTransaction(snapshot state.Snapshot) error {
	var restoreErr error
	if m.Restore != nil {
		restoreErr = m.Restore(context.Background(), m.Config)
	}
	if err := snapshot.Restore(m.Config.StateDir); err != nil {
		if restoreErr != nil {
			return fmt.Errorf("runtime restore: %v; state restore: %w", restoreErr, err)
		}
		return fmt.Errorf("state restore: %w", err)
	}
	return restoreErr
}

func (m *RotationManager) now() time.Time {
	if m.Now != nil {
		return m.Now()
	}
	return time.Now()
}

func (m *RotationManager) log(f string, args ...any) {
	if m.Logf != nil {
		m.Logf(f, args...)
	}
}

func (m Manager) Run(ctx context.Context) error {
	if ctx == nil {
		ctx = context.Background()
	}
	if m.Apply == nil {
		return fmt.Errorf("failover apply adapter is nil")
	}
	lock, err := state.AcquireLock(ctx, m.Config.StateDir)
	if err != nil {
		return fmt.Errorf("failover state lock: %w", err)
	}
	defer lock.Close()
	if err := ctx.Err(); err != nil {
		return err
	}
	snapshot, err := state.Capture(m.Config.StateDir)
	if err != nil {
		return fmt.Errorf("capture current state: %w", err)
	}
	probe := m.probe()
	results, err := LoadResults(m.Config.StateDir)
	if err != nil {
		m.log("CRITICAL failover: load results failed: %v", err)
		return err
	}
	cur, _ := state.LoadCurrent(m.Config.StateDir)
	candidates := Candidates(results, cur)
	if len(candidates) == 0 {
		err := fmt.Errorf("no failover candidates available")
		m.log("CRITICAL failover exhausted: %v", err)
		return err
	}

	runtimeDirty := false
	for _, cand := range candidates {
		if err := ctx.Err(); err != nil {
			if runtimeDirty {
				_ = m.restoreTransaction(snapshot)
			}
			return err
		}
		m.log("failover applying candidate #%03d %s %.2f Mbps", cand.Index, cand.Name, cand.Mbps)
		if err := m.Apply(ctx, m.Config, cand); err != nil {
			m.log("failover apply failed for #%03d: %v", cand.Index, err)
			if restoreErr := restoreIfStateChanged(m.Config.StateDir, snapshot, m.Restore, m.Config); restoreErr != nil {
				return fmt.Errorf("failover candidate #%03d apply failed: %v; restore failed: %w", cand.Index, err, restoreErr)
			}
			continue
		}
		runtimeDirty = true
		res := probe(ctx)
		if err := ctx.Err(); err != nil {
			if restoreErr := m.restoreTransaction(snapshot); restoreErr != nil {
				return fmt.Errorf("failover canceled; restore failed: %w", restoreErr)
			}
			return err
		}
		if !res.FailoverNeeded {
			if err := ctx.Err(); err != nil {
				if restoreErr := m.restoreTransaction(snapshot); restoreErr != nil {
					return fmt.Errorf("failover canceled; restore failed: %w", restoreErr)
				}
				return err
			}
			m.log("failover succeeded with #%03d %s", cand.Index, cand.Name)
			return nil
		}
		m.log("failover candidate #%03d applied but health probe failed; restoring before trying next", cand.Index)
		if err := m.restoreTransaction(snapshot); err != nil {
			m.log("CRITICAL failover candidate #%03d restore failed: %v", cand.Index, err)
			return fmt.Errorf("failover candidate #%03d restore failed: %w", cand.Index, err)
		}
		runtimeDirty = false
	}
	if runtimeDirty {
		if err := m.restoreTransaction(snapshot); err != nil {
			return fmt.Errorf("all failover candidates exhausted; restore failed: %w", err)
		}
	}
	if err := snapshot.Restore(m.Config.StateDir); err != nil {
		return fmt.Errorf("all failover candidates exhausted; state restore failed: %w", err)
	}
	err = fmt.Errorf("all failover candidates exhausted")
	m.log("CRITICAL failover exhausted: %v", err)
	return err
}

func (m Manager) probe() ProbeFunc {
	if m.Probe != nil {
		return m.Probe
	}
	runner := health.NewRunner(m.Config.ProductionSocks, m.Config.Health.RequiredURLs, m.Config.Health.DiagnosticURLs, m.Config.Health.ProbeTimeout.Duration)
	return runner.Run
}

func (m Manager) log(f string, args ...any) {
	if m.Logf != nil {
		m.Logf(f, args...)
	}
}

func (m Manager) restoreTransaction(snapshot state.Snapshot) error {
	var restoreErr error
	if m.Restore != nil {
		restoreErr = m.Restore(context.Background(), m.Config)
	}
	if err := snapshot.Restore(m.Config.StateDir); err != nil {
		if restoreErr != nil {
			return fmt.Errorf("runtime restore: %v; state restore: %w", restoreErr, err)
		}
		return fmt.Errorf("state restore: %w", err)
	}
	return restoreErr
}
