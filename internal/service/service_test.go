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

func TestCheckHealthProgressiveConfirmationTriggersFailoverAfterOnePersistentRequiredFailure(t *testing.T) {
	c := testConfig()
	var mu sync.Mutex
	probeCalls := 0
	failoverCalls := 0
	s := &Service{Config: c, Health: health.Runner{RequiredURLs: c.Health.RequiredURLs, Probe: func(_ context.Context, _ string, u string, _ time.Duration) health.ProbeResult {
		mu.Lock()
		defer mu.Unlock()
		probeCalls++
		return health.ProbeResult{URL: u, OK: u == "https://x.com/"}
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

func TestRunTestFailoverOnlyModeDoesNotRotateAfterSuccess(t *testing.T) {
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
	if err := state.SaveJSON(c.StateDir, "current-node.json", state.Current{Name: "slow", Host: "slow", Port: 443, Mbps: 10}); err != nil {
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
	if probes != 2 || len(applied) != 1 || applied[0].Name != "fast" {
		t.Fatalf("probes=%d applied=%+v, want pre/post health probes and applied fast", probes, applied)
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

func TestScheduledRotationRequiresMinimumImprovement(t *testing.T) {
	c := testConfig()
	c.StateDir = t.TempDir()
	c.Service.FastestRotation.MinImprovementPercent = 10
	c.Service.FastestRotation.Cooldown = config.NewDuration(0)
	results := []picker.NodeResult{{Index: 1, OK: true, Name: "candidate", Host: "candidate", Port: 443, Mbps: 109}}
	b, _ := json.Marshal(results)
	if err := state.SaveJSON(c.StateDir, "last-results.json", json.RawMessage(b)); err != nil {
		t.Fatal(err)
	}
	if err := state.SaveJSON(c.StateDir, "current-node.json", state.Current{Name: "current", Host: "current", Port: 443, Mbps: 100}); err != nil {
		t.Fatal(err)
	}
	applies := 0
	rotation := buildScheduledRotation(c, nil, func(context.Context, config.Config, picker.NodeResult) error {
		applies++
		return nil
	}, func(context.Context) health.Result { return health.Result{} })

	if err := rotation(context.Background()); err != nil {
		t.Fatal(err)
	}
	if applies != 0 {
		t.Fatalf("applies=%d, want no marginal performance rotation", applies)
	}

	results[0].Mbps = 111
	b, _ = json.Marshal(results)
	if err := state.SaveJSON(c.StateDir, "last-results.json", json.RawMessage(b)); err != nil {
		t.Fatal(err)
	}
	if err := rotation(context.Background()); err != nil {
		t.Fatal(err)
	}
	if applies != 1 {
		t.Fatalf("applies=%d, want rotation after sufficient improvement", applies)
	}
}

func TestScheduledRotationCooldownUsesSuccessfulApplicationsOnly(t *testing.T) {
	c := testConfig()
	c.StateDir = t.TempDir()
	c.Service.FastestRotation.MinImprovementPercent = 0
	c.Service.FastestRotation.Cooldown = config.NewDuration(time.Hour)
	results := []picker.NodeResult{{Index: 1, OK: true, Name: "candidate", Host: "candidate", Port: 443, Mbps: 200}}
	b, _ := json.Marshal(results)
	if err := state.SaveJSON(c.StateDir, "last-results.json", json.RawMessage(b)); err != nil {
		t.Fatal(err)
	}
	if err := state.SaveJSON(c.StateDir, "current-node.json", state.Current{Name: "current", Host: "current", Port: 443, Mbps: 100}); err != nil {
		t.Fatal(err)
	}
	at := time.Unix(100, 0)
	probes, applies := 0, 0
	failNext := true
	rotation := buildScheduledRotationWithClock(c, nil, func(context.Context, config.Config, picker.NodeResult) error {
		applies++
		if failNext {
			failNext = false
			return context.Canceled
		}
		return nil
	}, func(context.Context) health.Result {
		probes++
		return health.Result{}
	}, func() time.Time { return at })

	if err := rotation(context.Background()); err == nil {
		t.Fatal("expected first apply to fail")
	}
	if err := rotation(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := rotation(context.Background()); err != nil {
		t.Fatal(err)
	}
	if applies != 2 || probes != 3 {
		t.Fatalf("before cooldown expiry: applies=%d probes=%d, want 2/3", applies, probes)
	}

	at = at.Add(time.Hour)
	if err := rotation(context.Background()); err != nil {
		t.Fatal(err)
	}
	if applies != 3 || probes != 5 {
		t.Fatalf("after cooldown expiry: applies=%d probes=%d, want 3/5", applies, probes)
	}
}

func TestScheduledBenchmarkAndHealthFailoverAreSerialized(t *testing.T) {
	c := testConfig()
	c.Health.FailureRetryDelays = nil
	c.Health.RequiredURLs = []string{"https://required.invalid/"}
	rotationStarted := make(chan struct{})
	releaseRotation := make(chan struct{})
	failoverEntered := make(chan struct{})
	healthProbed := make(chan struct{})
	var probeOnce sync.Once
	runTestDone := make(chan struct{})
	failoverDone := make(chan struct{})

	s := &Service{
		Config: c,
		Health: health.Runner{
			RequiredURLs: c.Health.RequiredURLs,
			Probe: func(context.Context, string, string, time.Duration) health.ProbeResult {
				probeOnce.Do(func() { close(healthProbed) })
				return health.ProbeResult{OK: false}
			},
		},
		Test: func(context.Context) error { return nil },
		ScheduledRotation: func(context.Context) error {
			close(rotationStarted)
			<-releaseRotation
			return nil
		},
		Failover: func(context.Context) error {
			close(failoverEntered)
			close(failoverDone)
			return nil
		},
	}

	go func() {
		s.runTest(context.Background())
		close(runTestDone)
	}()
	select {
	case <-rotationStarted:
	case <-time.After(time.Second):
		t.Fatal("scheduled rotation did not start")
	}

	go s.checkHealth(context.Background())
	select {
	case <-failoverEntered:
		t.Fatal("health failover entered while scheduled operation was running")
	default:
	}

	close(releaseRotation)
	select {
	case <-runTestDone:
	case <-time.After(time.Second):
		t.Fatal("scheduled operation did not finish")
	}
	select {
	case <-healthProbed:
	case <-time.After(time.Second):
		t.Fatal("health confirmation did not run after scheduled operation released")
	}
	select {
	case <-failoverDone:
	case <-time.After(time.Second):
		t.Fatal("health failover did not run after scheduled operation released")
	}
}

func TestScheduledBenchmarksPropagateCancellationAndCoalesceTicks(t *testing.T) {
	c := testConfig()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	started := make(chan struct{})
	var once sync.Once
	var mu sync.Mutex
	calls := 0
	var got context.Context
	s := New(c, nil, func(gotCtx context.Context) error {
		mu.Lock()
		calls++
		got = gotCtx
		mu.Unlock()
		once.Do(func() { close(started) })
		<-gotCtx.Done()
		return gotCtx.Err()
	}, nil, nil)

	s.scheduleTest(ctx)
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("scheduled benchmark did not start")
	}
	for i := 0; i < 25; i++ {
		s.scheduleTest(ctx)
	}
	cancel()
	s.waitForTests()

	mu.Lock()
	defer mu.Unlock()
	if got != ctx {
		t.Fatal("scheduled benchmark did not receive the daemon context")
	}
	if calls != 1 {
		t.Fatalf("benchmark calls=%d, want one in-flight call with coalesced cancellation", calls)
	}
	s.testMu.Lock()
	defer s.testMu.Unlock()
	if s.testRunning || s.testPending {
		t.Fatalf("stale scheduled work remains: running=%t pending=%t", s.testRunning, s.testPending)
	}
}

func TestHealthPriorityDoesNotWaitBehindNonMutatingBenchmark(t *testing.T) {
	c := testConfig()
	c.Health.FailureRetryDelays = nil
	c.Health.RequiredURLs = []string{"https://required.invalid/"}
	benchmarkStarted := make(chan struct{})
	releaseBenchmark := make(chan struct{})
	failoverEntered := make(chan struct{})
	benchmarkDone := make(chan struct{})
	s := &Service{
		Config: c,
		Health: health.Runner{
			RequiredURLs: c.Health.RequiredURLs,
			Probe: func(context.Context, string, string, time.Duration) health.ProbeResult {
				return health.ProbeResult{OK: false}
			},
		},
		Test: func(context.Context) error {
			close(benchmarkStarted)
			<-releaseBenchmark
			return nil
		},
		Failover: func(context.Context) error {
			close(failoverEntered)
			return nil
		},
	}
	go func() {
		s.runTest(context.Background())
		close(benchmarkDone)
	}()
	select {
	case <-benchmarkStarted:
	case <-time.After(time.Second):
		t.Fatal("benchmark did not start")
	}

	healthDone := make(chan struct{})
	go func() {
		s.checkHealth(context.Background())
		close(healthDone)
	}()
	select {
	case <-failoverEntered:
	case <-time.After(time.Second):
		t.Fatal("health failover waited behind non-mutating benchmark")
	}
	select {
	case <-benchmarkDone:
		t.Fatal("benchmark unexpectedly completed before health priority assertion")
	default:
	}
	close(releaseBenchmark)
	select {
	case <-healthDone:
	case <-time.After(time.Second):
		t.Fatal("health check did not finish")
	}
}
