package failover

import (
	"context"
	"encoding/json"
	"path/filepath"
	"testing"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
	"github.com/kcnc/vibe-practicum-vpn/internal/health"
	"github.com/kcnc/vibe-practicum-vpn/internal/picker"
	"github.com/kcnc/vibe-practicum-vpn/internal/state"
)

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
