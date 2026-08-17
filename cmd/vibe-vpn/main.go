package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"sort"
	"strings"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
	"github.com/kcnc/vibe-practicum-vpn/internal/extranodes"
	"github.com/kcnc/vibe-practicum-vpn/internal/failover"
	"github.com/kcnc/vibe-practicum-vpn/internal/logging"
	"github.com/kcnc/vibe-practicum-vpn/internal/nettest"
	"github.com/kcnc/vibe-practicum-vpn/internal/picker"
	"github.com/kcnc/vibe-practicum-vpn/internal/service"
	"github.com/kcnc/vibe-practicum-vpn/internal/singbox"
	"github.com/kcnc/vibe-practicum-vpn/internal/state"
	"github.com/kcnc/vibe-practicum-vpn/internal/subscription"
	"github.com/kcnc/vibe-practicum-vpn/internal/vless"
	"github.com/kcnc/vibe-practicum-vpn/internal/xray"
	"github.com/spf13/cobra"
)

func main() {
	if err := newRootCommand().Execute(); err != nil {
		fmt.Fprintln(os.Stderr, "ERROR:", err)
		os.Exit(1)
	}
}

const defaultConfigPath = "/etc/vibe-vpn/config.json"

type cliOptions struct {
	configPath   string
	restartAsync bool
	filter       picker.FilterOptions
}

func newRootCommand() *cobra.Command {
	o := &cliOptions{}
	root := &cobra.Command{Use: "vibe-vpn", Short: "Safely test and select VLESS subscription nodes", SilenceUsage: true}
	root.PersistentFlags().StringVar(&o.configPath, "config", defaultConfigPath, "config path")

	addFilters := func(cmd *cobra.Command) {
		cmd.Flags().StringArrayVar(&o.filter.Include, "include", nil, "include only nodes whose name/host contains text (repeatable)")
		cmd.Flags().StringArrayVar(&o.filter.Exclude, "exclude", nil, "exclude nodes whose name/host contains text (repeatable)")
		cmd.Flags().StringArrayVar(&o.filter.Transport, "transport", nil, "include only transport/network values such as tcp, ws, grpc (repeatable)")
		cmd.Flags().StringArrayVar(&o.filter.Security, "security", nil, "include only security values such as tls or reality (repeatable)")
		cmd.Flags().Float64Var(&o.filter.MinMbps, "min-mbps", 0, "exclude successful nodes slower than this Mbps")
		cmd.Flags().BoolVar(&o.filter.DefaultExclude, "default-exclude", true, "exclude subscription metadata/traffic nodes")
		cmd.Flags().BoolVar(&o.filter.DefaultExclude, "no-default-exclude", true, "disable default subscription metadata exclusions")
		cmd.Flags().Lookup("no-default-exclude").NoOptDefVal = "false"
	}

	test := &cobra.Command{Use: "test", Short: "Benchmark subscription nodes with isolated temporary sing-box by default; no production changes", RunE: func(cmd *cobra.Command, args []string) error {
		max, _ := cmd.Flags().GetInt("max")
		lim, _ := cmd.Flags().GetInt("limit-kib")
		verbose, _ := cmd.Flags().GetBool("verbose")
		debug, _ := cmd.Flags().GetBool("debug")
		dur, _ := cmd.Flags().GetInt("duration-sec")
		return runTest(o, false, max, lim, dur, verbose, debug)
	}}
	test.Flags().Int("max", 0, "max nodes")
	test.Flags().Int("limit-kib", 0, "test KiB")
	test.Flags().Int("duration-sec", -1, "download duration per node in seconds; 0 disables duration mode")
	test.Flags().Bool("verbose", false, "print every node while testing")
	test.Flags().Bool("debug", false, "show temporary benchmark backend logs")
	addFilters(test)
	root.AddCommand(test)

	pick := &cobra.Command{Use: "pick", Short: "Benchmark in isolation, then apply the best non-excluded working node", RunE: func(cmd *cobra.Command, args []string) error {
		max, _ := cmd.Flags().GetInt("max")
		lim, _ := cmd.Flags().GetInt("limit-kib")
		verbose, _ := cmd.Flags().GetBool("verbose")
		debug, _ := cmd.Flags().GetBool("debug")
		dur, _ := cmd.Flags().GetInt("duration-sec")
		return runTest(o, true, max, lim, dur, verbose, debug)
	}}
	pick.Flags().Int("max", 0, "max nodes")
	pick.Flags().Int("limit-kib", 0, "test KiB")
	pick.Flags().Int("duration-sec", -1, "download duration per node in seconds; 0 disables duration mode")
	pick.Flags().Bool("verbose", false, "print every node while testing")
	pick.Flags().Bool("debug", false, "show temporary benchmark backend logs")
	pick.Flags().BoolVar(&o.restartAsync, "restart-async", false, "deprecated bootstrap compatibility flag; supervised request acknowledgement remains required")
	addFilters(pick)
	root.AddCommand(pick)

	list := &cobra.Command{Use: "list", Short: "List last benchmark results", RunE: func(cmd *cobra.Command, args []string) error { return cmdList(o, cmd) }}
	list.Flags().Int("top", 20, "number of successful nodes to show")
	list.Flags().Bool("all", false, "show all successful nodes")
	list.Flags().Bool("failed", false, "show failed nodes too")
	list.Flags().Bool("json", false, "print raw JSON results")
	addFilters(list)
	root.AddCommand(list)

	apply := &cobra.Command{Use: "apply <index|best>", Short: "Apply a node from last-results.json; 'best' respects filters", Args: cobra.ExactArgs(1), RunE: func(cmd *cobra.Command, args []string) error { return cmdApply(o, args[0]) }}
	addFilters(apply)
	root.AddCommand(apply)
	root.AddCommand(&cobra.Command{Use: "status", Short: "Show service and current-node status", RunE: func(cmd *cobra.Command, args []string) error { return cmdStatus(o) }})
	cur := &cobra.Command{Use: "current", Short: "Show current selected node", RunE: func(cmd *cobra.Command, args []string) error {
		link, _ := cmd.Flags().GetBool("link")
		return cmdCurrent(o, link)
	}}
	cur.Flags().Bool("link", false, "print only current VLESS link")
	root.AddCommand(cur)
	root.AddCommand(&cobra.Command{Use: "rollback", Short: "Rollback configured production runtime config to latest backup", RunE: func(cmd *cobra.Command, args []string) error { return cmdRollback(o) }})
	syncSingBox := &cobra.Command{Use: "sync-sing-box-config", Short: "Refresh runtime sing-box config from source while preserving selected outbound", Hidden: true, RunE: func(cmd *cobra.Command, args []string) error {
		source, _ := cmd.Flags().GetString("source")
		runtime, _ := cmd.Flags().GetString("runtime")
		c, err := loadConfig(o.configPath)
		if err != nil {
			return err
		}
		lock, err := state.AcquireLock(context.Background(), c.StateDir)
		if err != nil {
			return err
		}
		defer lock.Close()
		if os.Getenv("VIBE_VPN_DEFER_TRANSACTION_RECOVERY") != "1" {
			if err := recoverTransactionsLocked(context.Background(), c); err != nil {
				return fmt.Errorf("recover pending transaction: %w", err)
			}
		} else if pending, pendingErr := state.PendingTransactions(c.StateDir); pendingErr != nil {
			return pendingErr
		} else if len(pending) != 0 {
			// Entrypoint startup runs this sync before the request supervisor. Do
			// not overwrite a crash candidate; the post-health recovery command
			// below resolves it while the supervisor can emit acknowledgements.
			return nil
		}
		return singbox.SyncFromSourcePreserveSelectedLocked(source, runtime)
	}}
	syncSingBox.Flags().String("source", "/etc/sing-box/config.json", "rendered source sing-box config")
	syncSingBox.Flags().String("runtime", "/var/lib/vpnkit/sing-box/config.json", "persisted runtime sing-box config")
	root.AddCommand(syncSingBox)
	root.AddCommand(&cobra.Command{Use: "refresh", Short: "Fetch subscription and print summary", RunE: func(cmd *cobra.Command, args []string) error { return cmdRefresh(o) }})
	root.AddCommand(&cobra.Command{Use: "doctor", Short: "Run local configuration and safety checks", RunE: func(cmd *cobra.Command, args []string) error { return cmdDoctor(o) }})
	logs := &cobra.Command{Use: "logs", Short: "Show vibe-vpn state summary", RunE: func(cmd *cobra.Command, args []string) error {
		failed, _ := cmd.Flags().GetInt("failed")
		jsonOut, _ := cmd.Flags().GetBool("json")
		return cmdLogs(o, failed, jsonOut)
	}}
	logs.Flags().Int("failed", 10, "number of failed results to show")
	logs.Flags().Bool("json", false, "print raw last-results JSON")
	root.AddCommand(logs)
	prune := &cobra.Command{Use: "prune", Short: "Prune stale temporary benchmark backend configs and old runtime backups", RunE: func(cmd *cobra.Command, args []string) error {
		dry, _ := cmd.Flags().GetBool("dry-run")
		keep, _ := cmd.Flags().GetInt("keep")
		return cmdPrune(o, dry, keep)
	}}
	prune.Flags().Bool("dry-run", false, "show what would be removed without deleting")
	prune.Flags().Int("keep", 10, "number of newest backups to keep")
	root.AddCommand(prune)
	root.AddCommand(&cobra.Command{Use: "daemon", Short: "Run long-lived VPN health and failover service", RunE: func(cmd *cobra.Command, args []string) error { return cmdDaemon(o) }})
	root.AddCommand(&cobra.Command{Use: "recover-transactions", Short: "Recover pending runtime/state transactions", Hidden: true, RunE: func(cmd *cobra.Command, args []string) error { return cmdRecoverTransactions(o) }})
	root.AddCommand(newIKEv2Command(o))
	return root
}

func cmdRecoverTransactions(o *cliOptions) error {
	c, err := loadConfig(o.configPath)
	if err != nil {
		return err
	}
	lock, err := state.AcquireLock(context.Background(), c.StateDir)
	if err != nil {
		return err
	}
	defer lock.Close()
	return recoverTransactionsLocked(context.Background(), c)
}

func cmdDaemon(o *cliOptions) error {
	c, err := loadConfig(o.configPath)
	if err != nil {
		return err
	}
	lock, err := state.AcquireLock(context.Background(), c.StateDir)
	if err != nil {
		return fmt.Errorf("daemon transaction lock: %w", err)
	}
	if err := recoverTransactionsLocked(context.Background(), c); err != nil {
		_ = lock.Close()
		return fmt.Errorf("recover pending transaction: %w", err)
	}
	if err := lock.Close(); err != nil {
		return fmt.Errorf("release daemon transaction lock: %w", err)
	}
	lg := logging.New(c.Logging.Path, c.Logging.AlsoJournal, os.Stdout)
	tester := func(ctx context.Context) error { return runScheduledTestContext(ctx, o, c) }
	apply := func(ctx context.Context, c config.Config, r picker.NodeResult) error {
		return applyResultLocked(ctx, c, r)
	}
	restore := func(ctx context.Context, c config.Config) error { return restoreRuntime(c) }
	fo := service.BuildFailoverWithRestore(c, lg, failover.ApplyFunc(apply), failover.RestoreFunc(restore))
	rotation := service.BuildScheduledRotationWithRestore(c, lg, failover.ApplyFunc(apply), failover.RestoreFunc(restore))
	svc := service.New(c, lg, tester, fo, rotation)
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	return svc.Run(ctx)
}

func runScheduledTest(o *cliOptions, c config.Config) error {
	return runScheduledTestContext(context.Background(), o, c)
}

type scheduledTestRunner func(context.Context, *cliOptions, config.Config, *state.FileVersion) (state.FileVersion, error)

// scheduledResultsSupersededError is a non-success outcome: the benchmark did
// not publish a result it owns, because another writer won the CAS. The marker
// lets the daemon distinguish this expected contention from a benchmark error.
type scheduledResultsSupersededError struct{}

func (scheduledResultsSupersededError) Error() string {
	return "scheduled benchmark results superseded"
}
func (scheduledResultsSupersededError) NoOwnedResult() bool { return true }

// ErrScheduledResultsSuperseded is the stable sentinel for the no-owned-result
// outcome. Callers must not continue into scheduled rotation and re-load the
// other writer's results.
var ErrScheduledResultsSuperseded = scheduledResultsSupersededError{}

func runScheduledTestContext(ctx context.Context, o *cliOptions, c config.Config) error {
	return runScheduledTestContextWithRunner(ctx, o, c, func(ctx context.Context, o *cliOptions, c config.Config, baseline *state.FileVersion) (state.FileVersion, error) {
		var candidate state.FileVersion
		err := runTestContextVersioned(ctx, o, false, 0, 0, -1, false, false, baseline, &candidate)
		return candidate, err
	})
}

// runScheduledTestContextWithRunner keeps the benchmark outside the shared
// state lock. Only its short result publication/conditional compensation uses
// that lock, so health probes and failover detection remain responsive.
func runScheduledTestContextWithRunner(ctx context.Context, o *cliOptions, c config.Config, run scheduledTestRunner) error {
	if ctx == nil {
		ctx = context.Background()
	}
	path := filepath.Join(c.StateDir, "last-results.json")
	baseline, err := state.CaptureFileVersion(path)
	if err != nil {
		return fmt.Errorf("snapshot last results: %w", err)
	}
	candidate, err := run(ctx, o, c, &baseline)
	if err != nil && candidate.Exists() && (!baseline.Exists() || !candidate.Equal(baseline)) {
		// A scheduled benchmark may have written a failed result before
		// returning an error. Compensate only if this exact scheduled version is
		// still current. A manual test/pick that published meanwhile therefore
		// wins, even across processes. With no baseline there is nothing to
		// restore: delete only this exact candidate version instead of leaving
		// failed results behind.
		compensationCtx := ctx
		if compensationCtx.Err() != nil {
			// The candidate was already published before cancellation. Cleanup is
			// a bounded ownership compensation, not a new benchmark publication;
			// keep it from being skipped solely because the run was canceled.
			compensationCtx = context.Background()
		}
		var compensationErr error
		if baseline.Exists() {
			_, compensationErr = state.RestoreIfVersion(compensationCtx, c.StateDir, "last-results.json", candidate, baseline.Data(), baseline.Perm())
		} else {
			_, compensationErr = state.DeleteIfVersion(compensationCtx, c.StateDir, "last-results.json", candidate)
		}
		if compensationErr != nil {
			return fmt.Errorf("%w; conditional last-results compensation failed: %v", err, compensationErr)
		}
	}
	return err
}

func loadConfig(path string) (config.Config, error) {
	if path != defaultConfigPath {
		if _, err := os.Stat(path); err != nil {
			if os.IsNotExist(err) {
				return config.Config{}, fmt.Errorf("config %s does not exist", path)
			}
			return config.Config{}, err
		}
	}
	return config.Load(path)
}

func runTest(o *cliOptions, apply bool, max, lim, dur int, verbose, debug bool) error {
	return runTestContext(context.Background(), o, apply, max, lim, dur, verbose, debug)
}

func runTestContext(ctx context.Context, o *cliOptions, apply bool, max, lim, dur int, verbose, debug bool) error {
	return runTestContextVersioned(ctx, o, apply, max, lim, dur, verbose, debug, nil, nil)
}

// runTestContextVersioned publishes results under the shared state lock. When
// expected is non-nil, publication is compare-and-swap: a long-running
// scheduled benchmark never replaces a result written after its snapshot.
func runTestContextVersioned(ctx context.Context, o *cliOptions, apply bool, max, lim, dur int, verbose, debug bool, expected, published *state.FileVersion) error {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	c, err := loadConfig(o.configPath)
	if err != nil {
		return err
	}
	if lim > 0 {
		c.TestLimitKiB = lim
	}
	if dur >= 0 {
		c.TestDurationSeconds = dur
	}
	extra, err := extranodes.Load(c.ExtraNodesFile)
	if err != nil {
		return err
	}
	links, warnings, err := loadSubscriptionLinksContext(ctx, c)
	for _, w := range warnings {
		fmt.Fprintf(os.Stderr, "WARN %v\n", w)
	}
	if err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if len(extra) == 0 {
			return err
		}
		fmt.Fprintf(os.Stderr, "WARN subscription unavailable: %v; testing extra nodes only\n", err)
	}
	type candidate struct {
		idx  int
		link string
		node vless.Node
	}
	candidates := []candidate{}
	parseFailures := []picker.NodeResult{}
	for i, l := range links {
		n, err := vless.Parse(l)
		if err != nil {
			parseFailures = append(parseFailures, picker.NodeResult{Index: i + 1, OK: false, Error: err.Error(), Link: l})
			continue
		}
		probe := picker.NodeResult{Index: i + 1, Name: n.Name, Host: n.Host, Port: n.Port, Network: n.Network, Security: n.Security, Link: l}
		if ok, _ := o.filter.MatchResult(probe); ok {
			candidates = append(candidates, candidate{i + 1, l, n})
		}
	}
	for i, n := range extra {
		idx := len(links) + i + 1
		probe := picker.NodeResult{Index: idx, Name: n.Name, Host: n.Host, Port: n.Port, Network: n.Network, Security: n.Security, Link: n.Link}
		if ok, _ := o.filter.MatchResult(probe); ok {
			candidates = append(candidates, candidate{idx, n.Link, n})
		}
	}
	beforeMax := len(candidates)
	if max > 0 && max < len(candidates) {
		candidates = candidates[:max]
	}
	if len(candidates) == 0 {
		return fmt.Errorf("no nodes match filters")
	}
	if tcpOpen(c.TestSocks, 200*time.Millisecond) {
		if n := cleanupStaleTestBackends(); n > 0 {
			fmt.Printf("Test SOCKS address %s is busy; cleaned up %d stale temporary benchmark backend process(es).\n", c.TestSocks, n)
			if err := waitContext(ctx, 300*time.Millisecond); err != nil {
				return err
			}
		}
	}
	if tcpOpen(c.TestSocks, 200*time.Millisecond) {
		alt, err := freeLocalSocksAddr()
		if err != nil {
			return fmt.Errorf("test SOCKS address %s is already in use and no free fallback port found: %w", c.TestSocks, err)
		}
		fmt.Printf("Test SOCKS address %s is still busy; using fallback %s for this run.\n", c.TestSocks, alt)
		c.TestSocks = alt
	}
	fmt.Printf("Fetched %d subscription nodes + %d extra nodes, %d after filters", len(links), len(extra), beforeMax)
	if max > 0 && max < beforeMax {
		fmt.Printf(", testing first %d", len(candidates))
	}
	fmt.Printf(".\n")
	fmt.Printf("Testing isolated on %s; production stays untouched.\n", c.TestSocks)
	if c.TestDurationSeconds > 0 {
		fmt.Printf("Benchmark mode: download for %ds per node.\n", c.TestDurationSeconds)
	} else {
		fmt.Printf("Benchmark mode: download up to %d KiB per node.\n", c.TestLimitKiB)
	}
	if !verbose {
		fmt.Println("Progress is quiet by default; use --verbose to print every node.")
	}
	results := append([]picker.NodeResult{}, parseFailures...)
	for j, cand := range candidates {
		if err := ctx.Err(); err != nil {
			return err
		}
		n := cand.node
		r, err := testOneContext(ctx, c, n, debug)
		if err != nil {
			if verbose {
				fmt.Printf("[%03d/%03d] FAIL %v\n", j+1, len(candidates), err)
			}
			results = append(results, picker.NodeResult{Index: cand.idx, OK: false, Error: err.Error(), Link: cand.link, Name: n.Name, Host: n.Host, Port: n.Port, Network: n.Network, Security: n.Security})
			continue
		}
		threshold := successThreshold(int64(c.TestLimitKiB) * 1024)
		if c.TestDurationSeconds > 0 {
			threshold = 64 * 1024
		}
		ok := r.Bytes >= threshold
		nr := picker.FromNode(cand.idx, n, r.Mbps, r.Bytes, r.Seconds)
		nr.OK = ok
		results = append(results, nr)
		if verbose {
			fmt.Printf("[%03d/%03d] %7.2f Mbps %5.2fs #%03d %s\n", j+1, len(candidates), r.Mbps, r.Seconds, cand.idx, n.Name)
		}
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	results = o.filter.Apply(results)
	var publishedVersion state.FileVersion
	if expected == nil {
		publishedVersion, err = state.SaveJSONVersioned(ctx, c.StateDir, "last-results.json", results)
	} else {
		var committed bool
		publishedVersion, committed, err = state.SaveJSONIfVersion(ctx, c.StateDir, "last-results.json", results, *expected)
		if err == nil && !committed {
			fmt.Println("Scheduled results superseded by a newer writer; keeping newer last-results.json.")
			// This is deliberately non-nil and owns no result: the scheduled
			// service must not treat another writer's manual results as its own
			// successful benchmark and rotate based on them.
			if published != nil {
				*published = state.FileVersion{}
			}
			return ErrScheduledResultsSuperseded
		}
	}
	if published != nil {
		*published = publishedVersion
	}
	if err != nil {
		return err
	}
	printSummary(results, 20)
	b := picker.BestFiltered(results)
	if b == nil {
		return fmt.Errorf("no working non-excluded node")
	}
	fmt.Printf("\nBEST:\n  #%03d %s\n  %.2f Mbps\n", b.Index, b.Name, b.Mbps)
	if apply {
		return applyResultWithOptions(ctx, c, *b, o.restartAsync)
	}
	fmt.Println("Dry run only. Use 'vibe-vpn pick' to apply winner.")
	return nil
}
func testOne(c config.Config, n vless.Node, debug bool) (nettest.Result, error) {
	return testOneContext(context.Background(), c, n, debug)
}

func testOneContext(ctx context.Context, c config.Config, n vless.Node, debug bool) (nettest.Result, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return nettest.Result{}, err
	}
	if tcpOpen(c.TestSocks, 200*time.Millisecond) {
		return nettest.Result{}, fmt.Errorf("test SOCKS address %s became busy during run", c.TestSocks)
	}
	backend, err := tempBenchmarkBackend(c, n)
	if err != nil {
		return nettest.Result{}, err
	}
	defer os.Remove(backend.configPath)
	backendCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	cmd := exec.CommandContext(backendCtx, backend.bin, backend.args...)
	if debug {
		cmd.Stdout = os.Stderr
		cmd.Stderr = os.Stderr
	}
	if err := cmd.Start(); err != nil {
		return nettest.Result{}, err
	}
	defer func() { cancel(); _ = cmd.Process.Kill(); _ = cmd.Wait() }()
	if err := waitTCPContext(backendCtx, c.TestSocks, 3*time.Second); err != nil {
		return nettest.Result{}, err
	}
	resultCh := make(chan struct {
		result nettest.Result
		err    error
	}, 1)
	go func() {
		var result nettest.Result
		var err error
		if c.TestDurationSeconds > 0 {
			result, err = nettest.DownloadFor(c.TestSocks, c.TestURL, time.Duration(c.TestDurationSeconds)*time.Second, time.Duration(c.TimeoutSeconds)*time.Second)
		} else {
			result, err = nettest.Download(c.TestSocks, c.TestURL, int64(c.TestLimitKiB)*1024, time.Duration(c.TimeoutSeconds)*time.Second)
		}
		resultCh <- struct {
			result nettest.Result
			err    error
		}{result: result, err: err}
	}()
	select {
	case result := <-resultCh:
		return result.result, result.err
	case <-ctx.Done():
		// CommandContext tears down the isolated backend. The buffered result
		// channel lets the short-lived network worker exit without blocking.
		return nettest.Result{}, ctx.Err()
	}
}

type benchmarkBackend struct {
	bin        string
	args       []string
	configPath string
}

func tempBenchmarkBackend(c config.Config, n vless.Node) (benchmarkBackend, error) {
	if normalizedRuntime(c) == "xray" {
		b, err := xray.TempConfig(n.Outbound, c.TestSocks)
		if err != nil {
			return benchmarkBackend{}, err
		}
		path, err := writeTempBenchmarkConfig("vibe-vpn-xray-*.json", b)
		if err != nil {
			return benchmarkBackend{}, err
		}
		return benchmarkBackend{bin: c.XrayBin, args: []string{"run", "-config", path}, configPath: path}, nil
	}
	b, err := singBoxTempConfig(n, c.TestSocks)
	if err != nil {
		return benchmarkBackend{}, err
	}
	path, err := writeTempBenchmarkConfig("vibe-vpn-singbox-*.json", b)
	if err != nil {
		return benchmarkBackend{}, err
	}
	return benchmarkBackend{bin: c.SingBoxBin, args: []string{"run", "-c", path}, configPath: path}, nil
}

func writeTempBenchmarkConfig(pattern string, b []byte) (string, error) {
	f, err := os.CreateTemp("", pattern)
	if err != nil {
		return "", err
	}
	path := f.Name()
	if _, err := f.Write(b); err != nil {
		f.Close()
		os.Remove(path)
		return "", err
	}
	if err := f.Close(); err != nil {
		os.Remove(path)
		return "", err
	}
	return path, nil
}

func singBoxTempConfig(n vless.Node, socksAddr string) ([]byte, error) {
	host, portText, err := net.SplitHostPort(socksAddr)
	if err != nil {
		return nil, err
	}
	var port int
	if _, err := fmt.Sscanf(portText, "%d", &port); err != nil {
		return nil, fmt.Errorf("invalid test_socks port %q: %w", portText, err)
	}
	out, err := singBoxOutboundForNode(n)
	if err != nil {
		return nil, err
	}
	out["tag"] = "benchmark-out"
	cfg := map[string]any{
		"log":       map[string]any{"level": "warn"},
		"inbounds":  []any{map[string]any{"type": "socks", "tag": "test-socks", "listen": host, "listen_port": port}},
		"outbounds": []any{out},
		"route":     map[string]any{"final": "benchmark-out"},
	}
	return json.MarshalIndent(cfg, "", "  ")
}

func singBoxOutboundForNode(n vless.Node) (map[string]any, error) {
	if t, _ := n.Outbound["type"].(string); t != "" {
		return cloneMap(n.Outbound), nil
	}
	return vless.SingBoxOutbound(n.Link)
}

func singBoxOutboundForResult(r picker.NodeResult) (map[string]any, error) {
	if t, _ := r.Outbound["type"].(string); t != "" {
		return cloneMap(r.Outbound), nil
	}
	return vless.SingBoxOutbound(r.Link)
}

func cloneMap(in map[string]any) map[string]any {
	out := make(map[string]any, len(in))
	for k, v := range in {
		out[k] = v
	}
	return out
}
func successThreshold(limitBytes int64) int64 {
	if limitBytes <= 0 {
		return 1
	}
	const maxThreshold = 64 * 1024
	if limitBytes < maxThreshold {
		return limitBytes
	}
	return maxThreshold
}

func cleanupStaleTestXray() int { return cleanupStaleProcesses("xray run -config /tmp/vibe-vpn-xray-") }

func cleanupStaleTestSingBox() int {
	return cleanupStaleProcesses("sing-box run -c /tmp/vibe-vpn-singbox-")
}

func cleanupStaleTestBackends() int { return cleanupStaleTestSingBox() + cleanupStaleTestXray() }

func cleanupStaleProcesses(pattern string) int {
	out, err := exec.Command("pgrep", "-f", pattern).Output()
	if err != nil {
		return 0
	}
	count := 0
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		_ = exec.Command("kill", line).Run()
		count++
	}
	return count
}

func freeLocalSocksAddr() (string, error) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return "", err
	}
	defer ln.Close()
	return ln.Addr().String(), nil
}

func tcpOpen(addr string, timeout time.Duration) bool {
	conn, err := net.DialTimeout("tcp", addr, timeout)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}

func waitContext(ctx context.Context, d time.Duration) error {
	if ctx == nil {
		ctx = context.Background()
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-t.C:
		return nil
	}
}

func waitTCP(addr string, d time.Duration) error {
	return waitTCPContext(context.Background(), addr, d)
}

func waitTCPContext(ctx context.Context, addr string, d time.Duration) error {
	if ctx == nil {
		ctx = context.Background()
	}
	deadline := time.NewTimer(d)
	defer deadline.Stop()
	tick := time.NewTicker(50 * time.Millisecond)
	defer tick.Stop()
	for {
		if tcpOpen(addr, 200*time.Millisecond) {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-deadline.C:
			return fmt.Errorf("temp benchmark backend did not open %s", addr)
		case <-tick.C:
		}
	}
}
func cmdStatus(o *cliOptions) error {
	c, err := loadConfig(o.configPath)
	if err != nil {
		return err
	}
	runtime, serviceName := runtimeService(c)
	out, _ := exec.Command("systemctl", "is-active", serviceName).CombinedOutput()
	fmt.Printf("runtime: %s\n", runtime)
	fmt.Printf("%s: %s", serviceName, out)
	fmt.Printf("production_socks: %s\n", c.ProductionSocks)

	cur, source, curErr := loadCurrentWithLegacy(c.StateDir)
	if curErr != nil {
		fmt.Printf("\ncurrent: unknown (%v)\n", curErr)
	} else {
		fmt.Printf("\ncurrent:\n")
		fmt.Printf("  name: %s\n", valueOr(cur.Name, "unknown"))
		fmt.Printf("  server: %s:%d\n", valueOr(cur.Host, "unknown"), cur.Port)
		fmt.Printf("  transport: %s/%s\n", valueOr(cur.Network, "unknown"), valueOr(cur.Security, "unknown"))
		if cur.Mbps > 0 {
			fmt.Printf("  last_speed: %.2f Mbps\n", cur.Mbps)
		} else {
			fmt.Printf("  last_speed: unknown\n")
		}
		fmt.Printf("  tested_at: %s\n", valueOr(cur.TestedAt, "unknown"))
		fmt.Printf("  state: %s\n", source)
	}

	fmt.Printf("\nlive_check:\n")
	if r, err := nettest.Get(c.ProductionSocks, "https://ifconfig.me/ip", 128, time.Duration(c.TimeoutSeconds)*time.Second); err == nil {
		fmt.Printf("  socks: OK\n")
		fmt.Printf("  egress_ip: %s\n", strings.TrimSpace(r.Body))
		fmt.Printf("  latency: %.0f ms\n", r.Seconds*1000)
	} else {
		fmt.Printf("  socks: FAIL %v\n", err)
	}
	return nil
}

func loadCurrentWithLegacy(stateDir string) (state.Current, string, error) {
	cur, err := state.LoadCurrent(stateDir)
	if err == nil {
		return cur, filepath.Join(stateDir, "current-node.json"), nil
	}

	legacyDir := "/var/lib/vibe-proxy"
	var legacy struct {
		Name string  `json:"name"`
		Mbps float64 `json:"mbps"`
		Link string  `json:"link"`
	}
	b, lerr := os.ReadFile(filepath.Join(legacyDir, "current-node.json"))
	if lerr != nil {
		return cur, filepath.Join(stateDir, "current-node.json"), err
	}
	if jerr := json.Unmarshal(b, &legacy); jerr != nil {
		return cur, filepath.Join(legacyDir, "current-node.json"), jerr
	}
	link := legacy.Link
	if link == "" {
		if lb, e := os.ReadFile(filepath.Join(legacyDir, "current-link.txt")); e == nil {
			link = strings.TrimSpace(string(lb))
		}
	}
	if link != "" {
		if n, e := vless.Parse(link); e == nil {
			cur.Name = n.Name
			if legacy.Name != "" {
				cur.Name = legacy.Name
			}
			cur.Host = n.Host
			cur.Port = n.Port
			cur.Network = n.Network
			cur.Security = n.Security
			cur.Link = link
		}
	}
	cur.Mbps = legacy.Mbps
	if cur.Name == "" {
		cur.Name = legacy.Name
	}
	return cur, filepath.Join(legacyDir, "current-node.json") + " (legacy)", nil
}

func valueOr(v, fallback string) string {
	if v == "" {
		return fallback
	}
	return v
}
func cmdRollback(o *cliOptions) error {
	c, err := loadConfig(o.configPath)
	if err != nil {
		return err
	}
	lock, err := state.AcquireLock(context.Background(), c.StateDir)
	if err != nil {
		return fmt.Errorf("rollback state lock: %w", err)
	}
	defer lock.Close()
	b, err := rollbackRuntimeAndStateLocked(context.Background(), c)
	if err != nil {
		return err
	}
	fmt.Println("Rolled back", b)
	return nil
}
func loadSubscriptionLinks(c config.Config) ([]string, []error, error) {
	return loadSubscriptionLinksContext(context.Background(), c)
}

func loadSubscriptionLinksContext(ctx context.Context, c config.Config) ([]string, []error, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	b, err := os.ReadFile(c.SubscriptionFile)
	if err != nil {
		return nil, nil, err
	}
	urls := subscription.URLList(string(b))
	if len(urls) == 0 {
		return nil, nil, fmt.Errorf("%s contains no subscription URLs", c.SubscriptionFile)
	}
	links := []string{}
	warnings := []error{}
	for i, rawURL := range urls {
		var fetched []string
		var fetchErr error
		for attempt := 0; attempt < 3; attempt++ {
			fetched, fetchErr = fetchSubscriptionContext(ctx, rawURL, time.Duration(c.TimeoutSeconds)*time.Second)
			if fetchErr == nil {
				break
			}
			if ctx.Err() != nil {
				return nil, warnings, ctx.Err()
			}
			if attempt < 2 {
				t := time.NewTimer(time.Duration(attempt+1) * 250 * time.Millisecond)
				select {
				case <-ctx.Done():
					t.Stop()
					return nil, warnings, ctx.Err()
				case <-t.C:
				}
			}
		}
		if fetchErr != nil {
			// Do not include the subscription URL or response body in warnings.
			warnings = append(warnings, fmt.Errorf("subscription %d fetch failed", i+1))
			continue
		}
		links = append(links, fetched...)
	}
	if len(links) == 0 && len(warnings) > 0 {
		return nil, warnings, fmt.Errorf("all %d subscription URLs failed", len(urls))
	}
	return links, warnings, nil
}

func fetchSubscriptionContext(ctx context.Context, rawURL string, timeout time.Duration) ([]string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, fmt.Errorf("invalid subscription request")
	}
	req.Header.Set("User-Agent", "vibe-vpn/1")
	client := http.Client{Timeout: timeout}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("subscription request failed")
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("subscription response status %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 10<<20))
	if err != nil {
		return nil, fmt.Errorf("subscription response read failed")
	}
	return subscription.Parse(string(body))
}

func sortedOK(results []picker.NodeResult) []picker.NodeResult {
	ok := make([]picker.NodeResult, 0, len(results))
	for _, r := range results {
		if r.OK && !r.Excluded {
			ok = append(ok, r)
		}
	}
	sort.Slice(ok, func(i, j int) bool { return ok[i].Mbps > ok[j].Mbps })
	return ok
}

func printSummary(results []picker.NodeResult, top int) {
	ok := sortedOK(results)
	failed := len(results) - len(ok)
	fmt.Printf("\nDone: %d ok, %d failed. Results saved to last-results.json.\n", len(ok), failed)
	if len(ok) == 0 {
		return
	}
	if top <= 0 || top > len(ok) {
		top = len(ok)
	}
	fmt.Printf("\nTop %d by speed:\n", top)
	for _, r := range ok[:top] {
		fmt.Printf("  #%03d  %7.2f Mbps  %-42s  %s:%d %s/%s\n", r.Index, r.Mbps, truncate(r.Name, 42), r.Host, r.Port, r.Network, r.Security)
	}
}

func truncate(s string, max int) string {
	if max <= 0 || len([]rune(s)) <= max {
		return s
	}
	r := []rune(s)
	return string(r[:max-1]) + "…"
}

func redactedNodeResults(results []picker.NodeResult) []picker.NodeResult {
	out := make([]picker.NodeResult, len(results))
	copy(out, results)
	for i := range out {
		out[i].Link = ""
		out[i].Outbound = nil
	}
	return out
}

func applyResult(c config.Config, b picker.NodeResult) error {
	return applyResultContext(context.Background(), c, b)
}

func applyResultWithOptions(ctx context.Context, c config.Config, b picker.NodeResult, asyncRestart bool) error {
	if ctx == nil {
		ctx = context.Background()
	}
	lock, err := state.AcquireLock(ctx, c.StateDir)
	if err != nil {
		return fmt.Errorf("apply state lock: %w", err)
	}
	defer lock.Close()
	return applyResultLockedWithOptions(ctx, c, b, asyncRestart)
}

// applyResultContext is the manual/CLI transaction boundary. Daemon callers
// already hold the state-dir lock in the failover/rotation manager and use
// applyResultLocked directly to avoid nested file locks.
func applyResultContext(ctx context.Context, c config.Config, b picker.NodeResult) error {
	return applyResultWithOptions(ctx, c, b, false)
}

func applyResultLocked(ctx context.Context, c config.Config, b picker.NodeResult) error {
	return applyResultLockedWithOptions(ctx, c, b, false)
}

var transactionSequence uint64

func transactionID() string {
	return fmt.Sprintf("txn-%d-%d", time.Now().UTC().UnixNano(), atomic.AddUint64(&transactionSequence, 1))
}

func transactionRuntimePath(c config.Config) string {
	if normalizedRuntime(c) == "xray" {
		return c.XrayConfig
	}
	return c.SingBoxConfig
}

func transactionRuntimeName(c config.Config) string {
	if normalizedRuntime(c) == "xray" {
		return "xray"
	}
	return "singbox"
}

func beginRuntimeTransactionLocked(c config.Config, operation state.TransactionOperation, candidate state.Snapshot) (string, error) {
	runtimePath := transactionRuntimePath(c)
	oldRuntime, err := os.ReadFile(runtimePath)
	if err != nil {
		return "", err
	}
	oldState, err := state.Capture(c.StateDir)
	if err != nil {
		return "", err
	}
	id := transactionID()
	if err := state.BeginTransactionWithMetadata(c.StateDir, id, operation, transactionRuntimeName(c), runtimePath, oldRuntime, nil, oldState, candidate); err != nil {
		return "", err
	}
	return id, nil
}

func recoverTransactionsLocked(ctx context.Context, c config.Config) error {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := state.MigrateLegacyTransactionArtifacts(c.StateDir); err != nil {
		return err
	}
	transactions, err := state.PendingTransactions(c.StateDir)
	if err != nil {
		return err
	}
	for _, tx := range transactions {
		if err := recoverTransactionLocked(ctx, c, tx); err != nil {
			return err
		}
	}
	return state.PruneOrphanTransactionArtifacts(c.StateDir)
}

func recoverTransactionLocked(ctx context.Context, c config.Config, tx state.Transaction) error {
	configPath := transactionRuntimePath(c)
	if tx.Runtime != "" && tx.Runtime != transactionRuntimeName(c) {
		return fmt.Errorf("pending transaction targets a different runtime")
	}
	if tx.ConfigPath != "" && filepath.Clean(tx.ConfigPath) != filepath.Clean(configPath) {
		return fmt.Errorf("pending transaction targets a different runtime config")
	}
	current, err := os.ReadFile(configPath)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	if os.IsNotExist(err) {
		current = nil
	}

	switch tx.Phase {
	case state.PhasePrepared:
		// Equality with OldRuntime only proves the file bytes. It says nothing
		// about a service that died after compensation wrote those bytes. Apply
		// the old runtime again and require the backend health contract before
		// publishing the old state or deleting the journal.
		if err := restoreTransactionRuntimeLocked(ctx, c, tx, true); err != nil {
			return fmt.Errorf("prepared transaction old runtime is not healthy: %w", err)
		}
		if err := tx.OldState.Restore(c.StateDir); err != nil {
			return err
		}
		if err := state.AcknowledgeTransaction(c.StateDir, tx.ID, tx.OldRuntime); err != nil {
			return err
		}
		if err := state.UpdateTransactionPhase(c.StateDir, tx.ID, state.PhaseStateCommitted); err != nil {
			return err
		}
		return state.CompleteTransaction(c.StateDir, tx.ID)
	case state.PhaseRuntimeAcknowledged:
		if tx.CandidateRuntimeReady && bytes.Equal(current, tx.CandidateRuntime) {
			// A previous acknowledgement is not durable proof that the child is
			// still serving. Re-run the backend-specific restart/health contract
			// before restoring candidate state and advancing the journal.
			if err := restartCurrentRuntimeLocked(ctx, c); err != nil {
				return recoverTransactionToOldPair(ctx, c, tx, fmt.Errorf("candidate runtime health recheck failed: %w", err))
			}
			if err := verifyRuntimeBytes(configPath, tx.CandidateRuntime); err != nil {
				return recoverTransactionToOldPair(ctx, c, tx, fmt.Errorf("candidate runtime changed during recovery: %w", err))
			}
			if err := tx.CandidateState.Restore(c.StateDir); err != nil {
				return err
			}
			if err := state.UpdateTransactionPhase(c.StateDir, tx.ID, state.PhaseStateCommitted); err != nil {
				return err
			}
			return state.CompleteTransaction(c.StateDir, tx.ID)
		}
		// A torn or externally replaced candidate is resolved to the exact old
		// pair, but only after the old runtime has also passed health checks.
		if err := restoreTransactionRuntimeLocked(ctx, c, tx, true); err != nil {
			return fmt.Errorf("runtime-acknowledged transaction old runtime is not healthy: %w", err)
		}
		if err := verifyRuntimeBytes(configPath, tx.OldRuntime); err != nil {
			return fmt.Errorf("runtime-acknowledged transaction old runtime changed during recovery: %w", err)
		}
		if err := tx.OldState.Restore(c.StateDir); err != nil {
			return err
		}
		if err := state.UpdateTransactionPhase(c.StateDir, tx.ID, state.PhaseStateCommitted); err != nil {
			return err
		}
		return state.CompleteTransaction(c.StateDir, tx.ID)
	case state.PhaseStateCommitted:
		if tx.CandidateRuntimeReady && bytes.Equal(current, tx.CandidateRuntime) {
			// Journal cleanup is still gated by a fresh health proof. If the
			// candidate is unhealthy, restore the old pair for safety but retain
			// the journal so a later invocation must re-prove it before cleanup.
			if err := restartCurrentRuntimeLocked(ctx, c); err != nil {
				return recoverTransactionToOldPair(ctx, c, tx, fmt.Errorf("state-committed candidate runtime is not healthy: %w", err))
			}
			if err := verifyRuntimeBytes(configPath, tx.CandidateRuntime); err != nil {
				return recoverTransactionToOldPair(ctx, c, tx, fmt.Errorf("state-committed candidate runtime changed during recovery: %w", err))
			}
			if err := tx.CandidateState.Restore(c.StateDir); err != nil {
				return err
			}
			return state.CompleteTransaction(c.StateDir, tx.ID)
		}
		// For old, missing, or externally replaced bytes, fail closed to old.
		// The old service must be restarted and verified even when bytes already
		// match, and the old state is restored before journal removal.
		if err := restoreTransactionRuntimeLocked(ctx, c, tx, true); err != nil {
			return fmt.Errorf("state-committed transaction old runtime is not healthy: %w", err)
		}
		if err := verifyRuntimeBytes(configPath, tx.OldRuntime); err != nil {
			return fmt.Errorf("state-committed transaction old runtime changed during recovery: %w", err)
		}
		if err := tx.OldState.Restore(c.StateDir); err != nil {
			return err
		}
		return state.CompleteTransaction(c.StateDir, tx.ID)
	default:
		return fmt.Errorf("invalid pending transaction phase")
	}
}

func restartCurrentRuntimeLocked(ctx context.Context, c config.Config) error {
	if normalizedRuntime(c) == "xray" {
		return xray.RestartWithHealthContext(ctx, c.XrayConfig, xrayHealthConfig(c))
	}
	return singbox.RestartWithAckContext(ctx, singboxRestartConfig(c))
}

// recoverTransactionToOldPair is deliberately not a journal-closing abort.
// When candidate health fails, the old pair is restored only as a fail-closed
// safety action; the journal remains until a later recovery proves the old
// runtime and completes the durable cleanup.
func recoverTransactionToOldPair(ctx context.Context, c config.Config, tx state.Transaction, cause error) error {
	restoreErr := restoreTransactionRuntimeLocked(ctx, c, tx, true)
	if restoreErr != nil {
		if stateErr := restoreOldStateIfRuntimeMatches(c, tx); stateErr != nil {
			return fmt.Errorf("%w; old runtime recovery failed: %v; old state recovery failed: %v; journal retained", cause, restoreErr, stateErr)
		}
		return fmt.Errorf("%w; old runtime recovery failed: %v; old state restored; journal retained", cause, restoreErr)
	}
	if err := verifyRuntimeBytes(transactionRuntimePath(c), tx.OldRuntime); err != nil {
		return fmt.Errorf("%w; old runtime changed during recovery: %v; journal retained", cause, err)
	}
	if err := tx.OldState.Restore(c.StateDir); err != nil {
		return fmt.Errorf("%w; old state recovery failed: %v; journal retained", cause, err)
	}
	return fmt.Errorf("%w; old pair restored; journal retained for retry", cause)
}

// abortTransactionLocked restores the journal's old runtime and state. It is
// used for bounded cancellation/error paths; the journal is retained if any
// step fails so the next locked invocation can retry recovery.
func abortTransactionLocked(ctx context.Context, c config.Config, id string, forceRestart bool) error {
	tx, err := state.LoadTransaction(c.StateDir, id)
	if err != nil {
		return err
	}
	if err := restoreTransactionRuntimeLocked(ctx, c, tx, forceRestart); err != nil {
		if stateErr := restoreOldStateIfRuntimeMatches(c, tx); stateErr != nil {
			return fmt.Errorf("%w; old state recovery failed: %v", err, stateErr)
		}
		return err
	}
	if err := verifyRuntimeBytes(transactionRuntimePath(c), tx.OldRuntime); err != nil {
		return err
	}
	if err := tx.OldState.Restore(c.StateDir); err != nil {
		return err
	}
	if tx.Phase == state.PhasePrepared {
		if err := state.AcknowledgeTransaction(c.StateDir, id, tx.OldRuntime); err != nil {
			return err
		}
	}
	if err := state.UpdateTransactionPhase(c.StateDir, id, state.PhaseStateCommitted); err != nil {
		return err
	}
	return state.CompleteTransaction(c.StateDir, id)
}

func restoreTransactionRuntimeLocked(ctx context.Context, c config.Config, tx state.Transaction, forceRestart bool) error {
	if ctx == nil {
		ctx = context.Background()
	}
	// forceRestart is retained for the bounded compensation call sites, but
	// byte equality is never a sufficient reason to skip the runtime health
	// proof. A crash can leave identical bytes with a dead service.
	_ = forceRestart
	oldPath, err := state.TransactionOldRuntimePath(c.StateDir, tx.ID)
	if err != nil {
		return err
	}
	// Compensating restart deliberately uses a non-cancelable context. A
	// canceled caller must not leave the runtime half-restored while the
	// journal is being closed.
	ctx = context.Background()
	var restoreErr error
	if normalizedRuntime(c) == "xray" {
		restoreErr = xray.RestoreBackupLockedContextWithHealth(ctx, c.XrayConfig, oldPath, xrayHealthConfig(c))
	} else {
		restoreErr = singbox.RestoreBackupWithRestartLockedContext(ctx, c.SingBoxConfig, c.StateDir, oldPath, singboxRestartConfig(c))
	}
	if restoreErr != nil {
		return restoreErr
	}
	return verifyRuntimeBytes(transactionRuntimePath(c), tx.OldRuntime)
}

func verifyRuntimeBytes(path string, expected []byte) error {
	got, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if !bytes.Equal(got, expected) {
		return fmt.Errorf("runtime bytes changed during transaction")
	}
	return nil
}

func restoreOldStateIfRuntimeMatches(c config.Config, tx state.Transaction) error {
	if err := verifyRuntimeBytes(transactionRuntimePath(c), tx.OldRuntime); err != nil {
		return err
	}
	return tx.OldState.Restore(c.StateDir)
}

func transactionFailpoint(name string) {
	point := strings.TrimSpace(os.Getenv("VIBE_VPN_TX_FAILPOINT"))
	if point == "" {
		point = strings.TrimSpace(os.Getenv("VIBE_VPN_TRANSACTION_FAILPOINT"))
	}
	if point == "" {
		point = strings.TrimSpace(os.Getenv("VIBE_VPN_FAILPOINT"))
	}
	point = strings.ReplaceAll(point, "_", "-")
	if point != name && !(name == "after-runtime-ack" && (point == "after-runtime-ack-before-save-current" || point == "after-runtime-ack-before-state-commit")) && !(name == "after-rollback-runtime-ack" && (point == "after-rollback-runtime-ack-before-state-restore" || point == "after-rollback-runtime-ack-before-state-commit")) {
		return
	}
	// Test-only crash injection. SIGKILL is intentional: no deferred cleanup
	// may erase the journal before the recovery subprocess gets to observe it.
	_ = syscall.Kill(os.Getpid(), syscall.SIGKILL)
	os.Exit(137)
}

func applyResultLockedWithOptions(ctx context.Context, c config.Config, b picker.NodeResult, asyncRestart bool) error {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if err := recoverTransactionsLocked(ctx, c); err != nil {
		return fmt.Errorf("recover pending transaction: %w", err)
	}
	cur := state.Current{Name: b.Name, Host: b.Host, Port: b.Port, Network: b.Network, Security: b.Security, Link: b.Link, Mbps: b.Mbps, TestedAt: time.Now().UTC().Format(time.RFC3339)}
	candidateState, err := state.SnapshotForCurrent(cur)
	if err != nil {
		return fmt.Errorf("prepare selected state: %w", err)
	}
	txID, err := beginRuntimeTransactionLocked(c, state.TransactionApply, candidateState)
	if err != nil {
		return fmt.Errorf("begin runtime transaction: %w", err)
	}

	var backup string
	if normalizedRuntime(c) == "xray" {
		backup, err = xray.ApplyLockedContextWithHealth(ctx, c.XrayConfig, c.StateDir, b.Outbound, xrayHealthConfig(c))
	} else {
		out, convErr := singBoxOutboundForResult(b)
		if convErr != nil {
			_ = abortTransactionLocked(context.Background(), c, txID, false)
			return fmt.Errorf("build sing-box outbound from selected result: %w", convErr)
		}
		restart := singboxRestartConfig(c)
		// The flag remains accepted for old bootstrap command lines, but it no
		// longer disables the request/generation/health acknowledgement. The
		// entrypoint starts its request supervisor before invoking bootstrap.
		_ = asyncRestart
		backup, err = singbox.ApplyWithRestartLockedContext(ctx, c.SingBoxConfig, c.StateDir, out, restart)
	}
	if err != nil {
		// The runtime package may already have compensated its file, but the
		// transaction boundary still re-applies and verifies the exact old
		// runtime before it can close the prepared journal.
		abortErr := abortTransactionLocked(context.Background(), c, txID, false)
		if abortErr != nil {
			return fmt.Errorf("runtime apply failed: %w; transaction restore failed: %v", err, abortErr)
		}
		return err
	}
	candidateRuntime, err := os.ReadFile(transactionRuntimePath(c))
	if err != nil {
		abortErr := abortTransactionLocked(context.Background(), c, txID, true)
		if abortErr != nil {
			return fmt.Errorf("read acknowledged runtime failed: %w; transaction restore failed: %v", err, abortErr)
		}
		return err
	}
	if err := state.AcknowledgeTransaction(c.StateDir, txID, candidateRuntime); err != nil {
		abortErr := abortTransactionLocked(context.Background(), c, txID, true)
		if abortErr != nil {
			return fmt.Errorf("journal runtime acknowledgement failed: %w; transaction restore failed: %v", err, abortErr)
		}
		return err
	}
	transactionFailpoint("after-runtime-ack")
	if err := ctx.Err(); err != nil {
		if abortErr := abortTransactionLocked(context.Background(), c, txID, true); abortErr != nil {
			return fmt.Errorf("apply canceled; transaction restore failed: %w", abortErr)
		}
		return err
	}
	if err := verifyRuntimeBytes(transactionRuntimePath(c), candidateRuntime); err != nil {
		if abortErr := abortTransactionLocked(context.Background(), c, txID, true); abortErr != nil {
			return fmt.Errorf("candidate runtime changed before state commit: %w; transaction restore failed: %v", err, abortErr)
		}
		return err
	}
	if err := state.SaveCurrent(c.StateDir, cur); err != nil {
		abortErr := abortTransactionLocked(context.Background(), c, txID, true)
		if abortErr != nil {
			return fmt.Errorf("production applied but state update failed: %w; transaction restore failed: %v", err, abortErr)
		}
		return fmt.Errorf("production applied but state update failed: %w", err)
	}
	if err := state.UpdateTransactionPhase(c.StateDir, txID, state.PhaseStateCommitted); err != nil {
		return fmt.Errorf("selected state committed but transaction journal update failed: %w", err)
	}
	if err := state.CompleteTransaction(c.StateDir, txID); err != nil {
		return fmt.Errorf("selected state committed but transaction cleanup failed: %w", err)
	}
	fmt.Printf("Applied to production %s. Backup: %s\n", normalizedRuntime(c), backup)
	return nil
}

func latestPairedRuntimeBackup(c config.Config) (string, state.Snapshot, error) {
	prefix := "sing-box-"
	if normalizedRuntime(c) == "xray" {
		prefix = "xray-"
	}
	files, err := state.PairedRuntimeBackups(c.StateDir, prefix)
	if err != nil {
		return "", state.Snapshot{}, err
	}
	if len(files) == 0 {
		return "", state.Snapshot{}, fmt.Errorf("no paired backups")
	}
	last := files[len(files)-1]
	snap, err := state.LoadSnapshotForBackup(c.StateDir, last)
	if err != nil {
		return "", state.Snapshot{}, err
	}
	return last, snap, nil
}

func rollbackRuntimeAndStateLocked(ctx context.Context, c config.Config) (string, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := recoverTransactionsLocked(ctx, c); err != nil {
		return "", fmt.Errorf("recover pending transaction: %w", err)
	}
	backup, targetState, err := latestPairedRuntimeBackup(c)
	if err != nil {
		return "", err
	}
	txID, err := beginRuntimeTransactionLocked(c, state.TransactionRollback, targetState)
	if err != nil {
		return "", fmt.Errorf("begin rollback transaction: %w", err)
	}
	if normalizedRuntime(c) == "xray" {
		err = xray.RestoreBackupLockedContextWithHealth(ctx, c.XrayConfig, backup, xrayHealthConfig(c))
	} else {
		err = singbox.RestoreBackupWithRestartLockedContext(ctx, c.SingBoxConfig, c.StateDir, backup, singboxRestartConfig(c))
	}
	if err != nil {
		abortErr := abortTransactionLocked(context.Background(), c, txID, false)
		if abortErr != nil {
			return "", fmt.Errorf("runtime rollback failed: %w; transaction restore failed: %v", err, abortErr)
		}
		return "", err
	}
	candidateRuntime, err := os.ReadFile(transactionRuntimePath(c))
	if err != nil {
		return "", abortRollbackWithError(c, txID, err)
	}
	if err := state.AcknowledgeTransaction(c.StateDir, txID, candidateRuntime); err != nil {
		return "", abortRollbackWithError(c, txID, err)
	}
	transactionFailpoint("after-rollback-runtime-ack")
	if err := ctx.Err(); err != nil {
		return "", abortRollbackWithError(c, txID, err)
	}
	if err := verifyRuntimeBytes(transactionRuntimePath(c), candidateRuntime); err != nil {
		return "", abortRollbackWithError(c, txID, fmt.Errorf("rollback runtime changed before state commit: %w", err))
	}
	if err := targetState.Restore(c.StateDir); err != nil {
		return "", abortRollbackWithError(c, txID, fmt.Errorf("runtime rolled back but selected-node state restore failed: %w", err))
	}
	if err := state.UpdateTransactionPhase(c.StateDir, txID, state.PhaseStateCommitted); err != nil {
		return "", fmt.Errorf("selected state restored but transaction journal update failed: %w", err)
	}
	if err := state.CompleteTransaction(c.StateDir, txID); err != nil {
		return "", fmt.Errorf("rollback committed but transaction cleanup failed: %w", err)
	}
	return backup, nil
}

func abortRollbackWithError(c config.Config, txID string, cause error) error {
	if abortErr := abortTransactionLocked(context.Background(), c, txID, true); abortErr != nil {
		return fmt.Errorf("%w; transaction restore failed: %v", cause, abortErr)
	}
	return cause
}

func restoreRuntime(c config.Config) error {
	_, err := rollbackRuntimeAndStateLocked(context.Background(), c)
	return err
}

func runtimeHealthTimeout(c config.Config) time.Duration {
	if d := c.SingBoxRestartAckTimeout.Duration; d > 0 {
		return d
	}
	return 30 * time.Second
}

func xrayHealthConfig(c config.Config) xray.HealthConfig {
	return xray.HealthConfig{
		Service:      "xray",
		Binary:       c.XrayBin,
		ProbeAddress: c.ProductionSocks,
		Timeout:      runtimeHealthTimeout(c),
	}
}

func singboxRestartConfig(c config.Config) singbox.RestartConfig {
	generationFile := strings.TrimSpace(c.SingBoxRestartAckGenerationFile)
	// Existing local request-file configs predate the explicit generation and
	// health-ack keys. Infer only the known vpnkit namespace; arbitrary request
	// files must explicitly configure the full protocol.
	if generationFile == "" && strings.EqualFold(strings.TrimSpace(c.SingBoxRestartMode), string(singbox.RestartModeRequestFile)) {
		generationFile = strings.TrimSpace(os.Getenv("SINGBOX_GENERATION_FILE"))
		if generationFile == "" {
			generationFile = strings.TrimSpace(os.Getenv("VPNKIT_SINGBOX_GENERATION_FILE"))
		}
		if generationFile == "" && filepath.Clean(c.SingBoxRestartFile) == "/run/vpnkit/restart-sing-box" {
			generationFile = "/run/vpnkit/sing-box-generation"
		}
	}
	healthAckFile := strings.TrimSpace(c.SingBoxRestartAckFile)
	if healthAckFile == "" && generationFile != "" {
		healthAckFile = generationFile + ".ack"
	}
	return singbox.RestartConfig{
		Mode:              singbox.RestartMode(c.SingBoxRestartMode),
		Service:           c.SingBoxService,
		RequestFile:       c.SingBoxRestartFile,
		AckGenerationFile: generationFile,
		AckFile:           healthAckFile,
		ConfigPath:        c.SingBoxConfig,
		ProbeAddress:      c.ProductionSocks,
		HealthTimeout:     runtimeHealthTimeout(c),
		AckTimeout:        c.SingBoxRestartAckTimeout.Duration,
		SingBoxBin:        c.SingBoxBin,
	}
}

func normalizedRuntime(c config.Config) string {
	r := strings.ToLower(strings.TrimSpace(c.Runtime))
	if r == "" || r == "sing-box" {
		return "singbox"
	}
	return r
}

func runtimeService(c config.Config) (string, string) {
	if normalizedRuntime(c) == "xray" {
		return "xray", "xray"
	}
	return "singbox", c.SingBoxService
}

func cmdList(o *cliOptions, cmd *cobra.Command) error {
	top, _ := cmd.Flags().GetInt("top")
	all, _ := cmd.Flags().GetBool("all")
	failed, _ := cmd.Flags().GetBool("failed")
	jsonOut, _ := cmd.Flags().GetBool("json")
	c, err := loadConfig(o.configPath)
	if err != nil {
		return err
	}
	var results []picker.NodeResult
	b, err := os.ReadFile(filepath.Join(c.StateDir, "last-results.json"))
	if err != nil {
		return err
	}
	if err := json.Unmarshal(b, &results); err != nil {
		return err
	}
	results = o.filter.Apply(results)
	if jsonOut {
		enc, _ := json.MarshalIndent(redactedNodeResults(results), "", "  ")
		fmt.Println(string(enc))
		return nil
	}
	if all {
		top = len(results)
	}
	printSummary(results, top)
	if failed {
		fmt.Println("\nFailed/Excluded:")
		for _, r := range results {
			if !r.OK || r.Excluded {
				status := "FAIL"
				if r.Excluded {
					status = "EXCLUDED:" + strings.Join(r.ExcludeReasons, ",")
				}
				fmt.Printf("  #%03d  %s  %-42s  %s\n", r.Index, status, truncate(r.Name, 42), r.Error)
			}
		}
	}
	return nil
}

func cmdApply(o *cliOptions, arg string) error {
	c, err := loadConfig(o.configPath)
	if err != nil {
		return err
	}
	var results []picker.NodeResult
	b, err := os.ReadFile(filepath.Join(c.StateDir, "last-results.json"))
	if err != nil {
		return err
	}
	if err := json.Unmarshal(b, &results); err != nil {
		return err
	}
	results = o.filter.Apply(results)
	var chosen *picker.NodeResult
	if arg == "best" {
		chosen = picker.BestFiltered(results)
		if chosen == nil {
			return fmt.Errorf("no working non-excluded node")
		}
	} else {
		var idx int
		if _, err := fmt.Sscanf(arg, "%d", &idx); err != nil || idx <= 0 {
			return fmt.Errorf("invalid index %q", arg)
		}
		for i := range results {
			if results[i].Index == idx {
				chosen = &results[i]
				break
			}
		}
		if chosen == nil {
			return fmt.Errorf("node #%03d not found in last-results.json", idx)
		}
	}
	if !chosen.OK {
		return fmt.Errorf("node #%03d is not OK: %s", chosen.Index, chosen.Error)
	}
	if chosen.Excluded {
		fmt.Fprintf(os.Stderr, "WARNING: applying excluded node #%03d (%s)\n", chosen.Index, strings.Join(chosen.ExcludeReasons, ","))
	}
	fmt.Printf("Applying #%03d %.2f Mbps %s (%s:%d %s/%s)\n", chosen.Index, chosen.Mbps, chosen.Name, chosen.Host, chosen.Port, chosen.Network, chosen.Security)
	return applyResult(c, *chosen)
}

func cmdCurrent(o *cliOptions, linkOnly bool) error {
	c, err := loadConfig(o.configPath)
	if err != nil {
		return err
	}
	cur, source, err := loadCurrentWithLegacy(c.StateDir)
	if err != nil {
		return err
	}
	if linkOnly {
		fmt.Println(cur.Link)
		return nil
	}
	fmt.Printf("name: %s\nserver: %s:%d\ntransport: %s/%s\nlast_speed: %.2f Mbps\ntested_at: %s\nstate: %s\n", valueOr(cur.Name, "unknown"), valueOr(cur.Host, "unknown"), cur.Port, valueOr(cur.Network, "unknown"), valueOr(cur.Security, "unknown"), cur.Mbps, valueOr(cur.TestedAt, "unknown"), source)
	return nil
}

func cmdRefresh(o *cliOptions) error {
	c, err := loadConfig(o.configPath)
	if err != nil {
		return err
	}
	extra, err := extranodes.Load(c.ExtraNodesFile)
	if err != nil {
		return err
	}
	links, warnings, err := loadSubscriptionLinks(c)
	for _, w := range warnings {
		fmt.Fprintf(os.Stderr, "WARN %v\n", w)
	}
	if err != nil {
		if len(extra) == 0 {
			return err
		}
		fmt.Fprintf(os.Stderr, "WARN subscription unavailable: %v; showing extra nodes only\n", err)
	}
	counts := map[string]int{}
	for _, l := range links {
		if n, err := vless.Parse(l); err == nil {
			counts[n.Network+"/"+n.Security]++
		}
	}
	for _, n := range extra {
		counts[n.Network+"/"+n.Security]++
	}
	fmt.Printf("subscription: %d VLESS nodes\n", len(links))
	fmt.Printf("extra_nodes: %d\n", len(extra))
	for k, v := range counts {
		fmt.Printf("  %s: %d\n", k, v)
	}
	return nil
}

func cmdDoctor(o *cliOptions) error {
	c, err := loadConfig(o.configPath)
	if err != nil {
		return err
	}
	checks := []struct {
		name string
		err  error
	}{
		{"config", c.Validate()}, {"subscription_file", fileReadable(c.SubscriptionFile)}, {"state_dir", os.MkdirAll(c.StateDir, 0700)},
	}
	if normalizedRuntime(c) == "xray" {
		checks = append(checks, struct {
			name string
			err  error
		}{"xray_bin", fileExecutable(c.XrayBin)}, struct {
			name string
			err  error
		}{"xray_config", fileReadable(c.XrayConfig)})
	} else {
		checks = append(checks, struct {
			name string
			err  error
		}{"sing_box_bin", fileExecutable(c.SingBoxBin)}, struct {
			name string
			err  error
		}{"sing_box_config", fileReadable(c.SingBoxConfig)})
	}
	failed := 0
	for _, ch := range checks {
		if ch.err != nil {
			failed++
			fmt.Printf("FAIL %s: %v\n", ch.name, ch.err)
		} else {
			fmt.Printf("OK   %s\n", ch.name)
		}
	}
	if tcpOpen(c.TestSocks, 200*time.Millisecond) {
		fmt.Printf("WARN test_socks_busy: %s\n", c.TestSocks)
	} else {
		fmt.Printf("OK   test_socks_free\n")
	}
	if failed > 0 {
		return fmt.Errorf("doctor found %d failed check(s)", failed)
	}
	return nil
}

func fileReadable(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	return f.Close()
}
func fileExecutable(path string) error {
	st, err := os.Stat(path)
	if err != nil {
		return err
	}
	if st.Mode()&0111 == 0 {
		return fmt.Errorf("not executable")
	}
	return nil
}

func cmdLogs(o *cliOptions, failedLimit int, jsonOut bool) error {
	c, err := loadConfig(o.configPath)
	if err != nil {
		return err
	}
	var results []picker.NodeResult
	b, err := os.ReadFile(filepath.Join(c.StateDir, "last-results.json"))
	if err != nil {
		return err
	}
	if err := json.Unmarshal(b, &results); err != nil {
		return err
	}
	if jsonOut {
		enc, _ := json.MarshalIndent(redactedNodeResults(results), "", "  ")
		fmt.Println(string(enc))
		return nil
	}
	if cur, source, err := loadCurrentWithLegacy(c.StateDir); err == nil {
		fmt.Printf("current:\n  name: %s\n  server: %s:%d\n  transport: %s/%s\n  last_speed: %.2f Mbps\n  state: %s\n\n", valueOr(cur.Name, "unknown"), valueOr(cur.Host, "unknown"), cur.Port, valueOr(cur.Network, "unknown"), valueOr(cur.Security, "unknown"), cur.Mbps, source)
	}
	ok := sortedOK(results)
	fmt.Printf("last_test:\n  total: %d\n  ok: %d\n  failed: %d\n", len(results), len(ok), len(results)-len(ok))
	if len(ok) > 0 {
		fmt.Printf("  best: #%03d %.2f Mbps %s (%s:%d %s/%s)\n", ok[0].Index, ok[0].Mbps, ok[0].Name, ok[0].Host, ok[0].Port, ok[0].Network, ok[0].Security)
	}
	if failedLimit > 0 {
		shown := 0
		fmt.Println("\nfailed:")
		for _, r := range results {
			if !r.OK {
				fmt.Printf("  #%03d %-38s %s\n", r.Index, truncate(r.Name, 38), r.Error)
				shown++
				if shown >= failedLimit {
					break
				}
			}
		}
		if shown == 0 {
			fmt.Println("  none")
		}
	}
	return nil
}

func cmdPrune(o *cliOptions, dryRun bool, keep int) error {
	return cmdPruneContext(context.Background(), o, dryRun, keep)
}

func cmdPruneContext(ctx context.Context, o *cliOptions, dryRun bool, keep int) error {
	if ctx == nil {
		ctx = context.Background()
	}
	c, err := loadConfig(o.configPath)
	if err != nil {
		return err
	}
	if keep < 0 {
		return fmt.Errorf("--keep must be non-negative")
	}
	var lock *state.Lock
	transactionCount := 0
	if !dryRun {
		lock, err = state.AcquireLock(ctx, c.StateDir)
		if err != nil {
			return fmt.Errorf("prune state lock: %w", err)
		}
		defer lock.Close()
		// Migration and crash recovery are writes and therefore deliberately do
		// not happen in dry-run mode. They run under the same lock as
		// apply/rollback/sync.
		if err := state.MigrateLegacySnapshots(c.StateDir); err != nil {
			return fmt.Errorf("migrate state snapshots: %w", err)
		}
		if err := recoverTransactionsLocked(ctx, c); err != nil {
			return fmt.Errorf("recover pending transaction: %w", err)
		}
		if err := state.PruneOrphanTransactionArtifacts(c.StateDir); err != nil {
			return fmt.Errorf("prune transaction artifacts: %w", err)
		}
	} else if pending, pendingErr := state.PendingTransactions(c.StateDir); pendingErr == nil {
		transactionCount = len(pending)
	}
	killedSingBox, killedXray := 0, 0
	if dryRun {
		killedSingBox = countStaleProcesses("sing-box run -c /tmp/vibe-vpn-singbox-")
		killedXray = countStaleProcesses("xray run -config /tmp/vibe-vpn-xray-")
	} else {
		killedSingBox = cleanupStaleTestSingBox()
		killedXray = cleanupStaleTestXray()
	}
	removedSingBox := pruneTempFiles("vibe-vpn-singbox-*.json", dryRun)
	removedXray := pruneTempFiles("vibe-vpn-xray-*.json", dryRun)

	singBackups, err := state.RuntimeBackupFiles(c.StateDir, "sing-box-")
	if err != nil {
		return err
	}
	xrayBackups, err := state.RuntimeBackupFiles(c.StateDir, "xray-")
	if err != nil {
		return err
	}
	backupsByBase := make(map[string]struct{}, len(singBackups)+len(xrayBackups))
	for _, f := range append(append([]string{}, singBackups...), xrayBackups...) {
		backupsByBase[filepath.Base(f)] = struct{}{}
	}
	brem := 0
	removeOld := func(files []string) error {
		if len(files) <= keep {
			return nil
		}
		for _, f := range files[:len(files)-keep] {
			brem++
			if dryRun {
				continue
			}
			if err := os.Remove(f); err != nil && !os.IsNotExist(err) {
				return err
			}
			if err := state.RemoveSnapshotForBackup(c.StateDir, f); err != nil {
				return err
			}
		}
		return nil
	}
	if err := removeOld(singBackups); err != nil {
		return err
	}
	if err := removeOld(xrayBackups); err != nil {
		return err
	}

	// Remove sidecars that no longer have their exact runtime basename. This
	// also cleans crash leftovers without ever feeding them to a runtime glob.
	orphanSnapshots, err := state.SnapshotFiles(c.StateDir)
	if err != nil {
		return err
	}
	orem := 0
	for _, snap := range orphanSnapshots {
		if _, ok := backupsByBase[state.RuntimeBackupBaseForSnapshot(snap)]; ok {
			continue
		}
		orem++
		if !dryRun {
			if err := os.Remove(snap); err != nil && !os.IsNotExist(err) {
				return err
			}
		}
	}
	prefix := "removed"
	if dryRun {
		prefix = "would_remove"
	}
	fmt.Printf("%s: stale_singbox=%d stale_xray=%d singbox_temp_files=%d xray_temp_files=%d backups=%d orphan_state_snapshots=%d pending_transactions=%d keep=%d\n", prefix, killedSingBox, killedXray, removedSingBox, removedXray, brem, orem, transactionCount, keep)
	return nil
}

func countStaleProcesses(pattern string) int {
	out, err := exec.Command("pgrep", "-f", pattern).Output()
	if err != nil {
		return 0
	}
	count := 0
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if strings.TrimSpace(line) != "" {
			count++
		}
	}
	return count
}

func pruneTempFiles(pattern string, dryRun bool) int {
	files, _ := filepath.Glob(filepath.Join(os.TempDir(), pattern))
	removed := 0
	cut := time.Now().Add(-24 * time.Hour)
	for _, f := range files {
		if st, err := os.Stat(f); err == nil && st.ModTime().Before(cut) {
			removed++
			if !dryRun {
				_ = os.Remove(f)
			}
		}
	}
	return removed
}
