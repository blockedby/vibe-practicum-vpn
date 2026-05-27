package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"sort"
	"strings"
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
	configPath string
	filter     picker.FilterOptions
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

	test := &cobra.Command{Use: "test", Short: "Benchmark subscription nodes with isolated temporary xray; no production changes", RunE: func(cmd *cobra.Command, args []string) error {
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
	test.Flags().Bool("debug", false, "show temporary xray logs")
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
	pick.Flags().Bool("debug", false, "show temporary xray logs")
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
	prune := &cobra.Command{Use: "prune", Short: "Prune stale temporary xray benchmark configs and old runtime backups", RunE: func(cmd *cobra.Command, args []string) error {
		dry, _ := cmd.Flags().GetBool("dry-run")
		keep, _ := cmd.Flags().GetInt("keep")
		return cmdPrune(o, dry, keep)
	}}
	prune.Flags().Bool("dry-run", false, "show what would be removed without deleting")
	prune.Flags().Int("keep", 10, "number of newest backups to keep")
	root.AddCommand(prune)
	root.AddCommand(&cobra.Command{Use: "daemon", Short: "Run long-lived VPN health and failover service", RunE: func(cmd *cobra.Command, args []string) error { return cmdDaemon(o) }})
	root.AddCommand(newIKEv2Command(o))
	return root
}

func cmdDaemon(o *cliOptions) error {
	c, err := loadConfig(o.configPath)
	if err != nil {
		return err
	}
	lg := logging.New(c.Logging.Path, c.Logging.AlsoJournal, os.Stdout)
	tester := func(ctx context.Context) error { return runScheduledTest(o, c) }
	apply := func(ctx context.Context, c config.Config, r picker.NodeResult) error { return applyResult(c, r) }
	fo := service.BuildFailover(c, lg, failover.ApplyFunc(apply))
	rotation := service.BuildScheduledRotation(c, lg, failover.ApplyFunc(apply))
	svc := service.New(c, lg, tester, fo, rotation)
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	return svc.Run(ctx)
}

func runScheduledTest(o *cliOptions, c config.Config) error {
	path := filepath.Join(c.StateDir, "last-results.json")
	old, readErr := os.ReadFile(path)
	err := runTest(o, false, 0, 0, -1, false, false)
	if err != nil && readErr == nil {
		_ = os.MkdirAll(c.StateDir, 0700)
		_ = os.WriteFile(path, old, 0600)
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
	links, warnings, err := loadSubscriptionLinks(c)
	for _, w := range warnings {
		fmt.Fprintf(os.Stderr, "WARN %v\n", w)
	}
	if err != nil {
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
		if n := cleanupStaleTestXray(); n > 0 {
			fmt.Printf("Test SOCKS address %s is busy; cleaned up %d stale temporary xray process(es).\n", c.TestSocks, n)
			time.Sleep(300 * time.Millisecond)
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
		n := cand.node
		r, err := testOne(c, n, debug)
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
	results = o.filter.Apply(results)
	if err := state.SaveJSON(c.StateDir, "last-results.json", results); err != nil {
		return err
	}
	printSummary(results, 20)
	b := picker.BestFiltered(results)
	if b == nil {
		return fmt.Errorf("no working non-excluded node")
	}
	fmt.Printf("\nBEST:\n  #%03d %s\n  %.2f Mbps\n", b.Index, b.Name, b.Mbps)
	if apply {
		return applyResult(c, *b)
	}
	fmt.Println("Dry run only. Use 'vibe-vpn pick' to apply winner.")
	return nil
}
func testOne(c config.Config, n vless.Node, debug bool) (nettest.Result, error) {
	if tcpOpen(c.TestSocks, 200*time.Millisecond) {
		return nettest.Result{}, fmt.Errorf("test SOCKS address %s became busy during run", c.TestSocks)
	}
	b, err := xray.TempConfig(n.Outbound, c.TestSocks)
	if err != nil {
		return nettest.Result{}, err
	}
	f, err := os.CreateTemp("", "vibe-vpn-xray-*.json")
	if err != nil {
		return nettest.Result{}, err
	}
	path := f.Name()
	if _, err := f.Write(b); err != nil {
		f.Close()
		os.Remove(path)
		return nettest.Result{}, err
	}
	if err := f.Close(); err != nil {
		os.Remove(path)
		return nettest.Result{}, err
	}
	defer os.Remove(path)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	cmd := exec.CommandContext(ctx, c.XrayBin, "run", "-config", path)
	if debug {
		cmd.Stdout = os.Stderr
		cmd.Stderr = os.Stderr
	}
	if err := cmd.Start(); err != nil {
		return nettest.Result{}, err
	}
	defer func() { cancel(); _ = cmd.Process.Kill(); _ = cmd.Wait() }()
	if err := waitTCP(c.TestSocks, 3*time.Second); err != nil {
		return nettest.Result{}, err
	}
	if c.TestDurationSeconds > 0 {
		return nettest.DownloadFor(c.TestSocks, c.TestURL, time.Duration(c.TestDurationSeconds)*time.Second, time.Duration(c.TimeoutSeconds)*time.Second)
	}
	return nettest.Download(c.TestSocks, c.TestURL, int64(c.TestLimitKiB)*1024, time.Duration(c.TimeoutSeconds)*time.Second)
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

func cleanupStaleTestXray() int {
	out, err := exec.Command("pgrep", "-f", "xray run -config /tmp/vibe-vpn-xray-").Output()
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

func waitTCP(addr string, d time.Duration) error {
	end := time.Now().Add(d)
	for time.Now().Before(end) {
		if tcpOpen(addr, 200*time.Millisecond) {
			return nil
		}
		time.Sleep(50 * time.Millisecond)
	}
	return fmt.Errorf("temp xray did not open %s", addr)
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
	var b string
	var rollbackErr error
	if normalizedRuntime(c) == "xray" {
		b, rollbackErr = xray.Rollback(c.XrayConfig, c.StateDir)
	} else {
		b, rollbackErr = singbox.Rollback(c.SingBoxConfig, c.StateDir, c.SingBoxService)
	}
	if rollbackErr == nil {
		fmt.Println("Rolled back", b)
	}
	return rollbackErr
}
func loadSubscriptionLinks(c config.Config) ([]string, []error, error) {
	b, err := os.ReadFile(c.SubscriptionFile)
	if err != nil {
		return nil, nil, err
	}
	urls := subscription.URLList(string(b))
	if len(urls) == 0 {
		return nil, nil, fmt.Errorf("%s contains no subscription URLs", c.SubscriptionFile)
	}
	links, warnings := subscription.FetchMany(urls, time.Duration(c.TimeoutSeconds)*time.Second)
	if len(links) == 0 && len(warnings) > 0 {
		return nil, warnings, fmt.Errorf("all %d subscription URLs failed", len(urls))
	}
	return links, warnings, nil
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

func applyResult(c config.Config, b picker.NodeResult) error {
	var backup string
	var err error
	if normalizedRuntime(c) == "xray" {
		backup, err = xray.Apply(c.XrayConfig, c.StateDir, b.Outbound)
	} else {
		out, convErr := vless.SingBoxOutbound(b.Link)
		if convErr != nil {
			return fmt.Errorf("build sing-box outbound from selected link: %w", convErr)
		}
		backup, err = singbox.Apply(c.SingBoxConfig, c.StateDir, c.SingBoxService, out)
	}
	if err != nil {
		return err
	}
	cur := state.Current{Name: b.Name, Host: b.Host, Port: b.Port, Network: b.Network, Security: b.Security, Link: b.Link, Mbps: b.Mbps, TestedAt: time.Now().Format(time.RFC3339)}
	if err := state.SaveJSON(c.StateDir, "current-node.json", cur); err != nil {
		return fmt.Errorf("production applied but state update failed: %w", err)
	}
	if err := os.WriteFile(filepath.Join(c.StateDir, "current-link.txt"), []byte(b.Link+"\n"), 0600); err != nil {
		return fmt.Errorf("production applied but current-link update failed: %w", err)
	}
	fmt.Printf("Applied to production %s. Backup: %s\n", normalizedRuntime(c), backup)
	return nil
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
		enc, _ := json.MarshalIndent(results, "", "  ")
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
	if jsonOut {
		fmt.Print(string(b))
		return nil
	}
	if err := json.Unmarshal(b, &results); err != nil {
		return err
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
	c, err := loadConfig(o.configPath)
	if err != nil {
		return err
	}
	if keep < 0 {
		return fmt.Errorf("--keep must be non-negative")
	}
	killed := 0
	if dryRun {
		out, _ := exec.Command("pgrep", "-f", "xray run -config /tmp/vibe-vpn-xray-").Output()
		for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
			if strings.TrimSpace(line) != "" {
				killed++
			}
		}
	} else {
		killed = cleanupStaleTestXray()
	}
	files, _ := filepath.Glob(filepath.Join(os.TempDir(), "vibe-vpn-xray-*.json"))
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
	backs, _ := filepath.Glob(filepath.Join(c.StateDir, "backups", "xray-*.json"))
	sort.Strings(backs)
	brem := 0
	if len(backs) > keep {
		for _, f := range backs[:len(backs)-keep] {
			brem++
			if !dryRun {
				_ = os.Remove(f)
			}
		}
	}
	prefix := "removed"
	if dryRun {
		prefix = "would_remove"
	}
	fmt.Printf("%s: stale_xray=%d temp_files=%d backups=%d keep=%d\n", prefix, killed, removed, brem, keep)
	return nil
}
