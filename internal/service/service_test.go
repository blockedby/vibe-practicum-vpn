package service

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
	"github.com/kcnc/vibe-practicum-vpn/internal/health"
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
