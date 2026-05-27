package health

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/kcnc/vibe-practicum-vpn/internal/nettest"
)

type ProbeFunc func(ctx context.Context, socksAddr, targetURL string, timeout time.Duration) ProbeResult

type ProbeResult struct {
	URL        string
	OK         bool
	StatusCode int
	Err        error
	Duration   time.Duration
}

type Result struct {
	Required       []ProbeResult
	Diagnostic     []ProbeResult
	FailoverNeeded bool
}

type Runner struct {
	SocksAddr      string
	RequiredURLs   []string
	DiagnosticURLs []string
	Timeout        time.Duration
	Probe          ProbeFunc
}

func NewRunner(socks string, required, diagnostic []string, timeout time.Duration) Runner {
	return Runner{SocksAddr: socks, RequiredURLs: required, DiagnosticURLs: diagnostic, Timeout: timeout, Probe: DefaultProbe}
}

func DefaultProbe(ctx context.Context, socksAddr, targetURL string, timeout time.Duration) ProbeResult {
	start := time.Now()
	type out struct {
		r   nettest.HTTPResult
		err error
	}
	ch := make(chan out, 1)
	go func() { r, err := nettest.Get(socksAddr, targetURL, 4096, timeout); ch <- out{r, err} }()
	select {
	case <-ctx.Done():
		return ProbeResult{URL: targetURL, Err: ctx.Err(), Duration: time.Since(start)}
	case o := <-ch:
		return ProbeResult{URL: targetURL, StatusCode: o.r.StatusCode, OK: o.err == nil && o.r.StatusCode >= 200 && o.r.StatusCode < 400, Err: o.err, Duration: time.Since(start)}
	}
}

func (r Runner) Run(ctx context.Context) Result {
	probe := r.Probe
	if probe == nil {
		probe = DefaultProbe
	}
	timeout := r.Timeout
	if timeout <= 0 {
		timeout = 5 * time.Second
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	res := Result{Required: make([]ProbeResult, len(r.RequiredURLs)), Diagnostic: make([]ProbeResult, len(r.DiagnosticURLs))}
	var wg sync.WaitGroup
	for i, u := range r.RequiredURLs {
		i, u := i, u
		wg.Add(1)
		go func() { defer wg.Done(); res.Required[i] = probe(ctx, r.SocksAddr, u, timeout) }()
	}
	for i, u := range r.DiagnosticURLs {
		i, u := i, u
		wg.Add(1)
		go func() { defer wg.Done(); res.Diagnostic[i] = probe(ctx, r.SocksAddr, u, timeout) }()
	}
	wg.Wait()
	res.FailoverNeeded = len(res.Required) > 0
	for _, pr := range res.Required {
		if pr.OK {
			res.FailoverNeeded = false
			break
		}
	}
	return res
}

func (p ProbeResult) ErrorString() string {
	if p.Err == nil {
		return ""
	}
	return fmt.Sprintf("%v", p.Err)
}
