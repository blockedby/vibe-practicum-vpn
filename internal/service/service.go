package service

import (
	"context"
	"fmt"
	"time"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
	"github.com/kcnc/vibe-practicum-vpn/internal/failover"
	"github.com/kcnc/vibe-practicum-vpn/internal/health"
	ilog "github.com/kcnc/vibe-practicum-vpn/internal/logging"
	"github.com/kcnc/vibe-practicum-vpn/internal/state"
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
}

func New(c config.Config, lg *ilog.Logger, test Tester, fo Failover, rotation ScheduledRotation) *Service {
	return &Service{Config: c, Logger: lg, Health: health.NewRunner(c.ProductionSocks, c.Health.RequiredURLs, c.Health.DiagnosticURLs, c.Health.ProbeTimeout.Duration), Test: test, Failover: fo, ScheduledRotation: rotation}
}

func (s *Service) Run(ctx context.Context) error {
	s.log("vibe-vpn daemon starting")
	_ = ilog.Cleanup(s.Config.Logging.Path, s.Config.Logging.Retention.Duration, time.Now())
	if s.Config.Service.StartupTest && s.Test != nil {
		go s.runTest(ctx)
	}
	testTicker := time.NewTicker(s.Config.Test.Interval.Duration)
	defer testTicker.Stop()
	healthTicker := time.NewTicker(s.Config.Health.NormalInterval.Duration)
	defer healthTicker.Stop()
	for {
		select {
		case <-ctx.Done():
			s.log("vibe-vpn daemon stopping")
			return nil
		case <-testTicker.C:
			go s.runTest(ctx)
		case <-healthTicker.C:
			s.checkHealth(ctx)
		}
	}
}

func (s *Service) runTest(ctx context.Context) {
	if err := s.Test(ctx); err != nil {
		s.log("scheduled test failed: %v", err)
	} else {
		s.log("scheduled test completed")
		if s.Config.Service.Mode == config.ServiceModeFastestRotation && s.ScheduledRotation != nil {
			if err := s.ScheduledRotation(ctx); err != nil {
				s.log("scheduled fastest rotation skipped/failed: %v", err)
			}
		}
	}
	_ = ilog.Cleanup(s.Config.Logging.Path, s.Config.Logging.Retention.Duration, time.Now())
}

func (s *Service) checkHealth(ctx context.Context) {
	res := s.Health.Run(ctx)
	if !res.FailoverNeeded {
		return
	}
	s.log("health failure detected; confirming")
	for _, d := range s.Config.Health.FailureRetryDelays {
		select {
		case <-ctx.Done():
			return
		case <-time.After(d.Duration):
		}
		if r := s.Health.Run(ctx); !r.FailoverNeeded {
			s.log("health recovered during confirmation")
			return
		}
	}
	s.log("health failure confirmed; starting failover")
	if s.Failover != nil {
		if err := s.Failover(ctx); err != nil {
			s.log("CRITICAL failover ended with error: %v", err)
		}
	}
}
func (s *Service) log(f string, args ...any) {
	if s.Logger != nil {
		_ = s.Logger.Important(f, args...)
	} else {
		fmt.Printf(f+"\n", args...)
	}
}

func BuildFailover(c config.Config, lg *ilog.Logger, apply failover.ApplyFunc) Failover {
	m := failover.Manager{Config: c, Apply: apply, Logf: func(f string, args ...any) {
		if lg != nil {
			_ = lg.Important(f, args...)
		}
	}}
	return m.Run
}

func BuildScheduledRotation(c config.Config, lg *ilog.Logger, apply failover.ApplyFunc) ScheduledRotation {
	runner := health.NewRunner(c.ProductionSocks, c.Health.RequiredURLs, c.Health.DiagnosticURLs, c.Health.ProbeTimeout.Duration)
	return buildScheduledRotation(c, lg, apply, runner.Run)
}

func buildScheduledRotation(c config.Config, lg *ilog.Logger, apply failover.ApplyFunc, probe func(context.Context) health.Result) ScheduledRotation {
	return func(ctx context.Context) error {
		if apply == nil {
			return fmt.Errorf("scheduled rotation apply adapter is nil")
		}
		if probe == nil {
			runner := health.NewRunner(c.ProductionSocks, c.Health.RequiredURLs, c.Health.DiagnosticURLs, c.Health.ProbeTimeout.Duration)
			probe = runner.Run
		}
		res := probe(ctx)
		if res.FailoverNeeded {
			logWith(lg, "scheduled fastest rotation health probe reports failover-needed; fastest rotation may still apply before normal failover confirmation")
		}
		results, err := failover.LoadResults(c.StateDir)
		if err != nil {
			return err
		}
		fastest, ok := failover.Fastest(results)
		if !ok {
			return fmt.Errorf("no working non-excluded node available for scheduled rotation")
		}
		cur, _ := state.LoadCurrent(c.StateDir)
		if failover.SameCurrent(fastest, cur) {
			logWith(lg, "scheduled fastest rotation: fastest node #%03d %s is already current", fastest.Index, fastest.Name)
			return nil
		}
		logWith(lg, "scheduled fastest rotation applying #%03d %s %.2f Mbps", fastest.Index, fastest.Name, fastest.Mbps)
		return apply(ctx, c, fastest)
	}
}

func logWith(lg *ilog.Logger, f string, args ...any) {
	if lg != nil {
		_ = lg.Important(f, args...)
	}
}
