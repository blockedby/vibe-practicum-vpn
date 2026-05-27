package service

import (
	"context"
	"encoding/json"
	"sync"
	"testing"
	"time"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
	"github.com/kcnc/vibe-practicum-vpn/internal/health"
	"github.com/kcnc/vibe-practicum-vpn/internal/picker"
	"github.com/kcnc/vibe-practicum-vpn/internal/state"
)

func testConfig() config.Config {
	c := config.Default()
	c.Service.StartupTest = false
	c.Test.Interval = config.NewDuration(time.Hour)
	c.Health.NormalInterval = config.NewDuration(time.Hour)
	c.Health.DiagnosticURLs = nil
	c.Health.FailureRetryDelays = []config.Duration{
		config.NewDuration(time.Millisecond),
		config.NewDuration(time.Millisecond),
		config.NewDuration(time.Millisecond),
	}
	return c
}

func TestCheckHealthProgressiveConfirmationTriggersFailoverAfterPersistentFailure(t *testing.T) {
	c := testConfig()
	var mu sync.Mutex
	probeCalls := 0
	failoverCalls := 0
	s := &Service{Config: c, Health: health.Runner{RequiredURLs: c.Health.RequiredURLs, Probe: func(context.Context, string, string, time.Duration) health.ProbeResult {
		mu.Lock()
		defer mu.Unlock()
		probeCalls++
		return health.ProbeResult{URL: "https://x.com/", OK: false}
	}}, Failover: func(context.Context) error {
		mu.Lock()
		defer mu.Unlock()
		failoverCalls++
		return nil
	}}

	s.checkHealth(context.Background())

	mu.Lock()
	defer mu.Unlock()
	if probeCalls != 8 {
		t.Fatalf("probe calls = %d, want two required URLs across initial + 3 confirmations", probeCalls)
	}
	if failoverCalls != 1 {
		t.Fatalf("failover calls = %d, want 1", failoverCalls)
	}
}

func TestCheckHealthProgressiveConfirmationResetsOnRecovery(t *testing.T) {
	c := testConfig()
	var mu sync.Mutex
	probeCalls := 0
	failoverCalls := 0
	s := &Service{Config: c, Health: health.Runner{RequiredURLs: c.Health.RequiredURLs, Probe: func(context.Context, string, string, time.Duration) health.ProbeResult {
		mu.Lock()
		defer mu.Unlock()
		probeCalls++
		ok := probeCalls >= 3
		return health.ProbeResult{URL: "https://x.com/", OK: ok}
	}}, Failover: func(context.Context) error {
		mu.Lock()
		defer mu.Unlock()
		failoverCalls++
		return nil
	}}

	s.checkHealth(context.Background())

	mu.Lock()
	defer mu.Unlock()
	if probeCalls < 3 || probeCalls > 4 {
		t.Fatalf("probe calls = %d, want initial probe and one confirmation batch until recovery", probeCalls)
	}
	if failoverCalls != 0 {
		t.Fatalf("failover calls = %d, want 0 after recovery", failoverCalls)
	}
}

func TestRunTestDefaultModeDoesNotRotateAfterSuccess(t *testing.T) {
	c := testConfig()
	c.Service.Mode = config.ServiceModeFailoverOnly
	tests := 0
	rotations := 0
	s := &Service{Config: c, Test: func(context.Context) error { tests++; return nil }, ScheduledRotation: func(context.Context) error { rotations++; return nil }}

	s.runTest(context.Background())

	if tests != 1 || rotations != 0 {
		t.Fatalf("tests=%d rotations=%d, want one test and no rotation", tests, rotations)
	}
}

func TestRunTestFastestRotationOnlyAfterSuccessfulTest(t *testing.T) {
	c := testConfig()
	c.Service.Mode = config.ServiceModeFastestRotation
	rotations := 0
	s := &Service{Config: c, Test: func(context.Context) error { return nil }, ScheduledRotation: func(context.Context) error { rotations++; return nil }}

	s.runTest(context.Background())

	if rotations != 1 {
		t.Fatalf("rotations=%d, want 1", rotations)
	}
	s.Test = func(context.Context) error { return context.DeadlineExceeded }
	s.runTest(context.Background())
	if rotations != 1 {
		t.Fatalf("rotation ran after failed test; rotations=%d", rotations)
	}
}

func TestScheduledRotationProbesThenAppliesFastestWorkingNode(t *testing.T) {
	c := testConfig()
	c.StateDir = t.TempDir()
	rs := []picker.NodeResult{
		{Index: 1, OK: true, Name: "slow", Host: "slow", Port: 443, Mbps: 10},
		{Index: 2, OK: true, Name: "fast", Host: "fast", Port: 443, Mbps: 30},
		{Index: 3, OK: true, Excluded: true, Name: "excluded", Host: "excluded", Port: 443, Mbps: 50},
		{Index: 4, OK: false, Name: "failed", Host: "failed", Port: 443, Mbps: 60},
	}
	b, _ := json.Marshal(rs)
	if err := state.SaveJSON(c.StateDir, "last-results.json", json.RawMessage(b)); err != nil {
		t.Fatal(err)
	}
	probes := 0
	applied := []picker.NodeResult{}
	rotation := buildScheduledRotation(c, nil, func(ctx context.Context, cfg config.Config, r picker.NodeResult) error {
		if probes != 1 {
			t.Fatalf("apply happened before exactly one health probe; probes=%d", probes)
		}
		applied = append(applied, r)
		return nil
	}, func(context.Context) health.Result {
		probes++
		return health.Result{FailoverNeeded: false}
	})

	if err := rotation(context.Background()); err != nil {
		t.Fatal(err)
	}
	if probes != 1 || len(applied) != 1 || applied[0].Name != "fast" {
		t.Fatalf("probes=%d applied=%+v, want probed once and applied fast", probes, applied)
	}
}

func TestScheduledRotationSkipsAlreadyCurrentFastest(t *testing.T) {
	c := testConfig()
	c.StateDir = t.TempDir()
	rs := []picker.NodeResult{{Index: 2, OK: true, Name: "fast", Host: "fast", Port: 443, Mbps: 30}}
	b, _ := json.Marshal(rs)
	if err := state.SaveJSON(c.StateDir, "last-results.json", json.RawMessage(b)); err != nil {
		t.Fatal(err)
	}
	if err := state.SaveJSON(c.StateDir, "current-node.json", state.Current{Name: "fast", Host: "fast", Port: 443}); err != nil {
		t.Fatal(err)
	}
	applies := 0
	rotation := buildScheduledRotation(c, nil, func(ctx context.Context, cfg config.Config, r picker.NodeResult) error { applies++; return nil }, func(context.Context) health.Result { return health.Result{} })

	if err := rotation(context.Background()); err != nil {
		t.Fatal(err)
	}
	if applies != 0 {
		t.Fatalf("applies=%d, want 0 when fastest is current", applies)
	}
}
