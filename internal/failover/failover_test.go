package failover

import (
	"context"
	"encoding/json"
	"math"
	"path/filepath"
	"testing"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
	"github.com/kcnc/vibe-practicum-vpn/internal/health"
	"github.com/kcnc/vibe-practicum-vpn/internal/picker"
	"github.com/kcnc/vibe-practicum-vpn/internal/state"
)

func TestMeetsMinimumImprovementUsesStrictPercentageThreshold(t *testing.T) {
	current := state.Current{Mbps: 100}
	if MeetsMinimumImprovement(picker.NodeResult{Mbps: 109}, current, 10) {
		t.Fatal("9% improvement should not satisfy 10% hysteresis")
	}
	if !MeetsMinimumImprovement(picker.NodeResult{Mbps: 110}, current, 10) {
		t.Fatal("10% improvement should satisfy 10% hysteresis")
	}
	if !MeetsMinimumImprovement(picker.NodeResult{Mbps: 90}, current, 0) {
		t.Fatal("zero threshold should preserve explicit disabled-control behavior")
	}
	for name, current := range map[string]state.Current{
		"missing speed":  {},
		"zero speed":     {Mbps: 0},
		"nan speed":      {Mbps: math.NaN()},
		"infinite speed": {Mbps: math.Inf(1)},
		"negative speed": {Mbps: -1},
	} {
		t.Run(name, func(t *testing.T) {
			if MeetsMinimumImprovement(picker.NodeResult{Mbps: 1}, current, 10) {
				t.Fatal("invalid current baseline must fail closed")
			}
		})
	}
}

func TestCandidatesStartAfterCurrentBySpeed(t *testing.T) {
	rs := []picker.NodeResult{{Index: 1, OK: true, Name: "slow", Host: "s", Port: 1, Mbps: 10}, {Index: 2, OK: true, Name: "fast", Host: "f", Port: 1, Mbps: 30}, {Index: 3, OK: true, Name: "cur", Host: "c", Port: 1, Mbps: 20}, {Index: 4, OK: true, Excluded: true, Mbps: 40}}
	got := Candidates(rs, state.Current{Name: "cur", Host: "c", Port: 1})
	if len(got) != 2 || got[0].Name != "slow" || got[1].Name != "fast" {
		t.Fatalf("order=%v", got)
	}
}

func TestRunTriesNextUntilProbeSucceeds(t *testing.T) {
	dir := t.TempDir()
	rs := []picker.NodeResult{{Index: 1, OK: true, Name: "a", Host: "a", Port: 1, Mbps: 30}, {Index: 2, OK: true, Name: "b", Host: "b", Port: 1, Mbps: 20}}
	b, _ := json.Marshal(rs)
	if err := state.SaveJSON(dir, "last-results.json", json.RawMessage(b)); err != nil {
		t.Fatal(err)
	}
	c := config.Default()
	c.StateDir = dir
	applied := []string{}
	probes := 0
	m := Manager{Config: c, Apply: func(ctx context.Context, c config.Config, r picker.NodeResult) error {
		applied = append(applied, r.Name)
		return nil
	}, Probe: func(ctx context.Context) health.Result { probes++; return health.Result{FailoverNeeded: probes == 1} }}
	if err := m.Run(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(applied) != 2 || applied[0] != "a" || applied[1] != "b" {
		t.Fatalf("applied=%v", applied)
	}
}

func TestLoadResultsMissingErrors(t *testing.T) {
	if _, err := LoadResults(filepath.Join(t.TempDir(), "missing")); err == nil {
		t.Fatal("expected error")
	}
}

func TestHealthFailoverIgnoresPerformanceHysteresis(t *testing.T) {
	dir := t.TempDir()
	results := []picker.NodeResult{{Index: 1, OK: true, Name: "fallback", Host: "fallback", Port: 443, Mbps: 10}}
	b, _ := json.Marshal(results)
	if err := state.SaveJSON(dir, "last-results.json", json.RawMessage(b)); err != nil {
		t.Fatal(err)
	}
	if err := state.SaveJSON(dir, "current-node.json", state.Current{Name: "current", Host: "current", Port: 443, Mbps: 100}); err != nil {
		t.Fatal(err)
	}
	c := config.Default()
	c.StateDir = dir
	c.Service.FastestRotation.MinImprovementPercent = 1000
	applied := 0
	m := Manager{
		Config: c,
		Apply: func(context.Context, config.Config, picker.NodeResult) error {
			applied++
			return nil
		},
		Probe: func(context.Context) health.Result { return health.Result{} },
	}
	if err := m.Run(context.Background()); err != nil {
		t.Fatal(err)
	}
	if applied != 1 {
		t.Fatalf("applied=%d, want health failover to apply fallback despite performance threshold", applied)
	}
}

func TestScheduledRotationStopsOnFailedPreHealth(t *testing.T) {
	dir := t.TempDir()
	c := config.Default()
	c.StateDir = dir
	if err := state.SaveJSON(dir, "current-node.json", state.Current{Name: "old", Host: "old", Port: 443, Mbps: 100}); err != nil {
		t.Fatal(err)
	}
	results := []picker.NodeResult{{Index: 1, OK: true, Name: "new", Host: "new", Port: 443, Mbps: 120}}
	if err := state.SaveJSON(dir, "last-results.json", results); err != nil {
		t.Fatal(err)
	}
	applies, probes := 0, 0
	m := RotationManager{
		Config: c,
		Apply:  func(context.Context, config.Config, picker.NodeResult) error { applies++; return nil },
		Probe:  func(context.Context) health.Result { probes++; return health.Result{FailoverNeeded: true} },
	}
	if err := m.Run(context.Background()); err != nil {
		t.Fatal(err)
	}
	if applies != 0 || probes != 1 {
		t.Fatalf("applies=%d probes=%d, want no apply after failed pre-health", applies, probes)
	}
}

func TestScheduledRotationMissingBaselineFailsClosed(t *testing.T) {
	dir := t.TempDir()
	c := config.Default()
	c.StateDir = dir
	if err := state.SaveJSON(dir, "last-results.json", []picker.NodeResult{{Index: 1, OK: true, Name: "new", Host: "new", Port: 443, Mbps: 120}}); err != nil {
		t.Fatal(err)
	}
	applies := 0
	m := RotationManager{
		Config: c,
		Apply:  func(context.Context, config.Config, picker.NodeResult) error { applies++; return nil },
		Probe:  func(context.Context) health.Result { return health.Result{} },
	}
	if err := m.Run(context.Background()); err != nil {
		t.Fatal(err)
	}
	if applies != 0 {
		t.Fatalf("applies=%d, want no rotation without a valid current baseline", applies)
	}
}

func TestScheduledRotationPostHealthRestoresRuntimeAndState(t *testing.T) {
	dir := t.TempDir()
	c := config.Default()
	c.StateDir = dir
	old := state.Current{Name: "old", Host: "old", Port: 443, Link: "old-link", Mbps: 100}
	candidate := state.Current{Name: "new", Host: "new", Port: 443, Link: "new-link", Mbps: 120}
	if err := state.SaveCurrent(dir, old); err != nil {
		t.Fatal(err)
	}
	if err := state.SaveJSON(dir, "last-results.json", []picker.NodeResult{{Index: 1, OK: true, Name: candidate.Name, Host: candidate.Host, Port: candidate.Port, Link: candidate.Link, Mbps: candidate.Mbps}}); err != nil {
		t.Fatal(err)
	}
	runtime := "old-runtime"
	probes := 0
	restored := 0
	m := RotationManager{
		Config: c,
		Apply: func(_ context.Context, _ config.Config, _ picker.NodeResult) error {
			runtime = "new-runtime"
			return state.SaveCurrent(dir, candidate)
		},
		Restore: func(context.Context, config.Config) error { restored++; runtime = "old-runtime"; return nil },
		Probe: func(context.Context) health.Result {
			probes++
			return health.Result{FailoverNeeded: probes == 2}
		},
	}
	if err := m.Run(context.Background()); err == nil {
		t.Fatal("expected post-apply health failure")
	}
	got, err := state.LoadCurrent(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got != old || runtime != "old-runtime" || restored != 1 {
		t.Fatalf("state=%+v runtime=%q restored=%d, want old transaction", got, runtime, restored)
	}
}

func TestExhaustedFailoverRestoresPriorWorkingState(t *testing.T) {
	dir := t.TempDir()
	c := config.Default()
	c.StateDir = dir
	old := state.Current{Name: "old", Host: "old", Port: 443, Link: "old-link", Mbps: 100}
	if err := state.SaveCurrent(dir, old); err != nil {
		t.Fatal(err)
	}
	results := []picker.NodeResult{
		{Index: 1, OK: true, Name: "a", Host: "a", Port: 443, Link: "a-link", Mbps: 90},
		{Index: 2, OK: true, Name: "b", Host: "b", Port: 443, Link: "b-link", Mbps: 80},
	}
	if err := state.SaveJSON(dir, "last-results.json", results); err != nil {
		t.Fatal(err)
	}
	runtime := "old-runtime"
	restored := 0
	m := Manager{
		Config: c,
		Apply: func(_ context.Context, _ config.Config, r picker.NodeResult) error {
			runtime = r.Name + "-runtime"
			return state.SaveCurrent(dir, state.Current{Name: r.Name, Host: r.Host, Port: r.Port, Link: r.Link, Mbps: r.Mbps})
		},
		Restore: func(context.Context, config.Config) error { restored++; runtime = "old-runtime"; return nil },
		Probe:   func(context.Context) health.Result { return health.Result{FailoverNeeded: true} },
	}
	if err := m.Run(context.Background()); err == nil {
		t.Fatal("expected exhausted failover error")
	}
	got, err := state.LoadCurrent(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got != old || runtime != "old-runtime" || restored != 2 {
		t.Fatalf("state=%+v runtime=%q restored=%d, want prior working transaction", got, runtime, restored)
	}
}
