package service

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
	"github.com/kcnc/vibe-practicum-vpn/internal/failover"
	"github.com/kcnc/vibe-practicum-vpn/internal/health"
	ilog "github.com/kcnc/vibe-practicum-vpn/internal/logging"
)

type Tester func(context.Context) error
type Failover func(context.Context) error
type ScheduledRotation func(context.Context) error

type Service struct {
	Config            config.Config
	Logger            *ilog.Logger
	Health            health.Runner
	Test              Tester
	Failover          Failover
	ScheduledRotation ScheduledRotation
	Now               func() time.Time

	// runtimeMu covers only runtime-mutating operations. A benchmark is
	// deliberately outside this lock so health can probe and confirm failure
	// while a long, non-mutating benchmark is still running.
	runtimeMu sync.Mutex

	healthMu    sync.Mutex
	healthEpoch uint64

	testMu      sync.Mutex
	testRunning bool
	testPending bool
	testWG      sync.WaitGroup
}

func New(c config.Config, lg *ilog.Logger, test Tester, fo Failover, rotation ScheduledRotation) *Service {
	return &Service{Config: c, Logger: lg, Health: health.NewRunner(c.ProductionSocks, c.Health.RequiredURLs, c.Health.DiagnosticURLs, c.Health.ProbeTimeout.Duration), Test: test, Failover: fo, ScheduledRotation: rotation}
}

func (s *Service) Run(ctx context.Context) error {
	if ctx == nil {
		ctx = context.Background()
	}
	s.log("vibe-vpn daemon starting")
	_ = ilog.Cleanup(s.Config.Logging.Path, s.Config.Logging.Retention.Duration, time.Now())
	if s.Config.Service.StartupTest && s.Test != nil {
		s.scheduleTest(ctx)
	}
	testTicker := time.NewTicker(s.Config.Test.Interval.Duration)
	defer testTicker.Stop()
	healthTicker := time.NewTicker(s.Config.Health.NormalInterval.Duration)
	defer healthTicker.Stop()
	for {
		select {
		case <-ctx.Done():
			s.waitForTests()
			s.log("vibe-vpn daemon stopping")
			return nil
		case <-testTicker.C:
			s.scheduleTest(ctx)
		case <-healthTicker.C:
			s.checkHealth(ctx)
		}
	}
}

// scheduleTest starts one worker for scheduled benchmarks. Ticks received
// while it is running collapse into one pending run instead of spawning a
// queue of stale goroutines.
func (s *Service) scheduleTest(ctx context.Context) {
	if ctx == nil {
		ctx = context.Background()
	}
	s.testMu.Lock()
	if s.testRunning {
		s.testPending = true
		s.testMu.Unlock()
		return
	}
	s.testRunning = true
	s.testWG.Add(1)
	s.testMu.Unlock()
	go func() {
		defer s.testWG.Done()
		for {
			s.runTest(ctx)
			s.testMu.Lock()
			if ctx.Err() != nil || !s.testPending {
				s.testPending = false
				s.testRunning = false
				s.testMu.Unlock()
				return
			}
			s.testPending = false
			s.testMu.Unlock()
		}
	}()
}

func (s *Service) waitForTests() {
	s.testWG.Wait()
}

func (s *Service) runTest(ctx context.Context) {
	if s.Test == nil {
		s.log("scheduled test skipped: tester is nil")
		return
	}
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return
	}
	startedHealthEpoch := s.healthVersion()
	if err := s.Test(ctx); err != nil {
		if ctx.Err() == nil {
			s.log("scheduled test failed: %v", err)
		}
		return
	}
	if err := ctx.Err(); err != nil {
		return
	}
	s.log("scheduled test completed")
	if s.Config.Service.Mode == config.ServiceModeFastestRotation && s.ScheduledRotation != nil {
		if startedHealthEpoch != s.healthVersion() {
			return
		}
		s.runtimeMu.Lock()
		if ctx.Err() == nil && startedHealthEpoch == s.healthVersion() {
			if err := s.ScheduledRotation(ctx); err != nil && ctx.Err() == nil {
				s.log("scheduled fastest rotation skipped/failed: %v", err)
			}
		}
		s.runtimeMu.Unlock()
	}
	_ = ilog.Cleanup(s.Config.Logging.Path, s.Config.Logging.Retention.Duration, time.Now())
}

func (s *Service) checkHealth(ctx context.Context) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return
	}
	// Probing and confirmation stay outside runtimeMu. This keeps health
	// detection responsive while a scheduled benchmark is doing no mutation.
	res := s.Health.Run(ctx)
	if ctx.Err() != nil || !res.FailoverNeeded {
		return
	}
	s.markHealthFailure()
	s.log("health failure detected; confirming")
	for _, d := range s.Config.Health.FailureRetryDelays {
		t := time.NewTimer(d.Duration)
		select {
		case <-ctx.Done():
			t.Stop()
			return
		case <-t.C:
		}
		if r := s.Health.Run(ctx); ctx.Err() != nil {
			return
		} else if !r.FailoverNeeded {
			s.log("health recovered during confirmation")
			return
		}
	}
	s.log("health failure confirmed; starting failover")
	if s.Failover == nil {
		return
	}
	// Only the runtime mutation waits for an in-flight rotation. A benchmark
	// cannot hold this lock because it is intentionally non-mutating.
	s.runtimeMu.Lock()
	defer s.runtimeMu.Unlock()
	if ctx.Err() != nil {
		return
	}
	if err := s.Failover(ctx); err != nil {
		s.log("CRITICAL failover ended with error: %v", err)
	}
}

func (s *Service) healthVersion() uint64 {
	s.healthMu.Lock()
	defer s.healthMu.Unlock()
	return s.healthEpoch
}

func (s *Service) markHealthFailure() {
	s.healthMu.Lock()
	s.healthEpoch++
	s.healthMu.Unlock()
}

func (s *Service) log(f string, args ...any) {
	if s.Logger != nil {
		_ = s.Logger.Important(f, args...)
	} else {
		fmt.Printf(f+"\n", args...)
	}
}

func BuildFailover(c config.Config, lg *ilog.Logger, apply failover.ApplyFunc) Failover {
	return BuildFailoverWithRestore(c, lg, apply, nil)
}

func BuildFailoverWithRestore(c config.Config, lg *ilog.Logger, apply failover.ApplyFunc, restore failover.RestoreFunc) Failover {
	m := failover.Manager{Config: c, Apply: apply, Restore: restore, Logf: func(f string, args ...any) {
		if lg != nil {
			_ = lg.Important(f, args...)
		}
	}}
	return m.Run
}

func BuildScheduledRotation(c config.Config, lg *ilog.Logger, apply failover.ApplyFunc) ScheduledRotation {
	return BuildScheduledRotationWithRestore(c, lg, apply, nil)
}

func BuildScheduledRotationWithRestore(c config.Config, lg *ilog.Logger, apply failover.ApplyFunc, restore failover.RestoreFunc) ScheduledRotation {
	runner := health.NewRunner(c.ProductionSocks, c.Health.RequiredURLs, c.Health.DiagnosticURLs, c.Health.ProbeTimeout.Duration)
	return buildScheduledRotationWithClockAndRestore(c, lg, apply, runner.Run, nil, restore)
}

func buildScheduledRotation(c config.Config, lg *ilog.Logger, apply failover.ApplyFunc, probe func(context.Context) health.Result) ScheduledRotation {
	return buildScheduledRotationWithClockAndRestore(c, lg, apply, probe, nil, nil)
}

func buildScheduledRotationWithClock(c config.Config, lg *ilog.Logger, apply failover.ApplyFunc, probe func(context.Context) health.Result, now func() time.Time) ScheduledRotation {
	return buildScheduledRotationWithClockAndRestore(c, lg, apply, probe, now, nil)
}

func buildScheduledRotationWithClockAndRestore(c config.Config, lg *ilog.Logger, apply failover.ApplyFunc, probe func(context.Context) health.Result, now func() time.Time, restore failover.RestoreFunc) ScheduledRotation {
	if probe == nil {
		runner := health.NewRunner(c.ProductionSocks, c.Health.RequiredURLs, c.Health.DiagnosticURLs, c.Health.ProbeTimeout.Duration)
		probe = runner.Run
	}
	m := &failover.RotationManager{
		Config:  c,
		Apply:   apply,
		Probe:   probe,
		Restore: restore,
		Now:     now,
		Logf: func(f string, args ...any) {
			if lg != nil {
				_ = lg.Important(f, args...)
			}
		},
	}
	return m.Run
}
