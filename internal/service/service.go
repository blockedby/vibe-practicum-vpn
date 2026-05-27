package service

import (
	"context"
	"fmt"
	"time"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
	"github.com/kcnc/vibe-practicum-vpn/internal/failover"
	"github.com/kcnc/vibe-practicum-vpn/internal/health"
	ilog "github.com/kcnc/vibe-practicum-vpn/internal/logging"
)

type Tester func(context.Context) error
type Failover func(context.Context) error

type Service struct {
	Config   config.Config
	Logger   *ilog.Logger
	Health   health.Runner
	Test     Tester
	Failover Failover
	Now      func() time.Time
}

func New(c config.Config, lg *ilog.Logger, test Tester, fo Failover) *Service {
	return &Service{Config: c, Logger: lg, Health: health.NewRunner(c.ProductionSocks, c.Health.RequiredURLs, c.Health.DiagnosticURLs, c.Health.ProbeTimeout.Duration), Test: test, Failover: fo}
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
