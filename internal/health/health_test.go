package health

import (
	"context"
	"sync"
	"testing"
	"time"
)

func TestRunnerParallelAndDiagnosticNotDecisive(t *testing.T) {
	start := make(chan struct{})
	var seenMu sync.Mutex
	seen := 0
	r := Runner{SocksAddr: "127.0.0.1:10808", RequiredURLs: []string{"https://x.com/", "https://rutracker.org/"}, DiagnosticURLs: []string{"https://ya.ru/"}, Timeout: 5 * time.Second}
	r.Probe = func(ctx context.Context, socks, u string, timeout time.Duration) ProbeResult {
		if socks != r.SocksAddr {
			t.Errorf("unexpected socks %s", socks)
		}
		if timeout != 5*time.Second {
			t.Errorf("timeout not passed through: %v", timeout)
		}
		seenMu.Lock()
		seen++
		if seen == 3 {
			close(start)
		}
		seenMu.Unlock()
		select {
		case <-start:
		case <-time.After(time.Second):
			t.Errorf("probe did not run in parallel")
		}
		ok := u != "https://ya.ru/"
		return ProbeResult{URL: u, OK: ok}
	}
	res := r.Run(context.Background())
	if res.FailoverNeeded {
		t.Fatalf("diagnostic-only failure must not require failover: %+v", res)
	}
	if len(res.Required) != 2 || len(res.Diagnostic) != 1 || res.Diagnostic[0].OK {
		t.Fatalf("unexpected result: %+v", res)
	}
}

func TestRunnerFailoverNeedsAllRequiredFailed(t *testing.T) {
	r := Runner{RequiredURLs: []string{"a", "b"}, Timeout: time.Second, Probe: func(ctx context.Context, socks, u string, timeout time.Duration) ProbeResult {
		return ProbeResult{URL: u, OK: false}
	}}
	if !r.Run(context.Background()).FailoverNeeded {
		t.Fatal("expected failover when all required URLs fail")
	}
	r.Probe = func(ctx context.Context, socks, u string, timeout time.Duration) ProbeResult {
		return ProbeResult{URL: u, OK: u == "b"}
	}
	if r.Run(context.Background()).FailoverNeeded {
		t.Fatal("one successful required URL should avoid failover")
	}
}
