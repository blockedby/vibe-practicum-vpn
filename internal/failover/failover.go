package failover

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
	"github.com/kcnc/vibe-practicum-vpn/internal/health"
	"github.com/kcnc/vibe-practicum-vpn/internal/picker"
	"github.com/kcnc/vibe-practicum-vpn/internal/state"
)

type ApplyFunc func(context.Context, config.Config, picker.NodeResult) error
type ProbeFunc func(context.Context) health.Result
type LogFunc func(string, ...any)

type Manager struct {
	Config config.Config
	Apply  ApplyFunc
	Probe  ProbeFunc
	Logf   LogFunc
}

func LoadResults(stateDir string) ([]picker.NodeResult, error) {
	var rs []picker.NodeResult
	b, err := os.ReadFile(filepath.Join(stateDir, "last-results.json"))
	if err != nil {
		return nil, err
	}
	return rs, json.Unmarshal(b, &rs)
}

func Candidates(results []picker.NodeResult, cur state.Current) []picker.NodeResult {
	ok := make([]picker.NodeResult, 0, len(results))
	for _, r := range results {
		if r.OK && !r.Excluded {
			ok = append(ok, r)
		}
	}
	sort.SliceStable(ok, func(i, j int) bool { return ok[i].Mbps > ok[j].Mbps })
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
func same(r picker.NodeResult, c state.Current) bool {
	return (c.Link != "" && r.Link == c.Link) || (r.Host == c.Host && r.Port == c.Port && r.Name == c.Name)
}

func (m Manager) Run(ctx context.Context) error {
	if m.Apply == nil {
		return fmt.Errorf("failover apply adapter is nil")
	}
	probe := m.Probe
	if probe == nil {
		runner := health.NewRunner(m.Config.ProductionSocks, m.Config.Health.RequiredURLs, m.Config.Health.DiagnosticURLs, m.Config.Health.ProbeTimeout.Duration)
		probe = runner.Run
	}
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
	for _, cand := range candidates {
		m.log("failover applying candidate #%03d %s %.2f Mbps", cand.Index, cand.Name, cand.Mbps)
		if err := m.Apply(ctx, m.Config, cand); err != nil {
			m.log("failover apply failed for #%03d: %v", cand.Index, err)
			continue
		}
		if res := probe(ctx); !res.FailoverNeeded {
			m.log("failover succeeded with #%03d %s", cand.Index, cand.Name)
			return nil
		}
		m.log("failover candidate #%03d applied but health probe failed; trying next", cand.Index)
	}
	err = fmt.Errorf("all failover candidates exhausted")
	m.log("CRITICAL failover exhausted: %v", err)
	return err
}
func (m Manager) log(f string, args ...any) {
	if m.Logf != nil {
		m.Logf(f, args...)
	}
}
