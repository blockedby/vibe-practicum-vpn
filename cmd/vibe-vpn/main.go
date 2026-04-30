package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/kcnc/vibe-practicum-vpn/internal/config"
	"github.com/kcnc/vibe-practicum-vpn/internal/nettest"
	"github.com/kcnc/vibe-practicum-vpn/internal/picker"
	"github.com/kcnc/vibe-practicum-vpn/internal/state"
	"github.com/kcnc/vibe-practicum-vpn/internal/subscription"
	"github.com/kcnc/vibe-practicum-vpn/internal/vless"
	"github.com/kcnc/vibe-practicum-vpn/internal/xray"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "test":
		err = cmdTest(false)
	case "pick":
		err = cmdTest(true)
	case "status":
		err = cmdStatus()
	case "list":
		err = cmdList()
	case "apply":
		err = cmdApply()
	case "rollback":
		err = cmdRollback()
	default:
		usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERROR:", err)
		os.Exit(1)
	}
}

const defaultConfigPath = "/etc/vibe-vpn/config.json"

func usage() {
	fmt.Println("vibe-vpn status|test|list|apply|pick|rollback\n  test: isolated benchmark, no production changes\n  pick: isolated benchmark then apply winner once")
}
func load(fs *flag.FlagSet) (config.Config, error) {
	cfgPath := fs.String("config", defaultConfigPath, "config path")
	if err := fs.Parse(os.Args[2:]); err != nil {
		return config.Config{}, err
	}
	if *cfgPath != defaultConfigPath {
		if _, err := os.Stat(*cfgPath); err != nil {
			if os.IsNotExist(err) {
				return config.Config{}, fmt.Errorf("config %s does not exist", *cfgPath)
			}
			return config.Config{}, err
		}
	}
	return config.Load(*cfgPath)
}
func cmdTest(apply bool) error {
	fs := flag.NewFlagSet(os.Args[1], flag.ExitOnError)
	max := fs.Int("max", 0, "max nodes")
	lim := fs.Int("limit-kib", 0, "test KiB")
	verbose := fs.Bool("verbose", false, "print every node while testing")
	debug := fs.Bool("debug", false, "show temporary xray logs")
	c, err := load(fs)
	if err != nil {
		return err
	}
	if *lim > 0 {
		c.TestLimitKiB = *lim
	}
	subURLb, err := os.ReadFile(c.SubscriptionFile)
	if err != nil {
		return err
	}
	links, err := subscription.Fetch(stringTrim(string(subURLb)), time.Duration(c.TimeoutSeconds)*time.Second)
	if err != nil {
		return err
	}
	if *max > 0 && *max < len(links) {
		links = links[:*max]
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
	fmt.Printf("Found %d VLESS nodes. Testing isolated on %s; production stays untouched.\n", len(links), c.TestSocks)
	if !*verbose {
		fmt.Println("Progress is quiet by default; use --verbose to print every node.")
	}
	var results []picker.NodeResult
	for i, l := range links {
		n, err := vless.Parse(l)
		if err != nil {
			if *verbose {
				fmt.Printf("[%03d/%03d] FAIL %v\n", i+1, len(links), err)
			}
			results = append(results, picker.NodeResult{Index: i + 1, OK: false, Error: err.Error(), Link: l})
			continue
		}
		r, err := testOne(c, n, *debug)
		if err != nil {
			if *verbose {
				fmt.Printf("[%03d/%03d] FAIL %v\n", i+1, len(links), err)
			}
			results = append(results, picker.NodeResult{Index: i + 1, OK: false, Error: err.Error(), Link: l, Name: n.Name, Host: n.Host, Port: n.Port, Network: n.Network, Security: n.Security})
			continue
		}
		ok := r.Bytes >= successThreshold(int64(c.TestLimitKiB)*1024)
		nr := picker.FromNode(i+1, n, r.Mbps, r.Bytes, r.Seconds)
		nr.OK = ok
		results = append(results, nr)
		if *verbose {
			fmt.Printf("[%03d/%03d] %7.2f Mbps %5.2fs %s\n", i+1, len(links), r.Mbps, r.Seconds, n.Name)
		}
	}
	if err := state.SaveJSON(c.StateDir, "last-results.json", results); err != nil {
		return err
	}
	printSummary(results, 20)
	b := picker.Best(results)
	if b == nil {
		return fmt.Errorf("no working node")
	}
	fmt.Printf("\nBEST:\n  %s\n  %.2f Mbps\n", b.Name, b.Mbps)
	if apply {
		backup, err := xray.Apply(c.XrayConfig, c.StateDir, b.Outbound)
		if err != nil {
			return err
		}
		cur := state.Current{Name: b.Name, Host: b.Host, Port: b.Port, Network: b.Network, Security: b.Security, Link: b.Link, Mbps: b.Mbps, TestedAt: time.Now().Format(time.RFC3339)}
		if err := state.SaveJSON(c.StateDir, "current-node.json", cur); err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(c.StateDir, "current-link.txt"), []byte(b.Link+"\n"), 0600); err != nil {
			return err
		}
		fmt.Println("Applied to production xray. Backup:", backup)
	} else {
		fmt.Println("Dry run only. Use 'vibe-vpn pick' to apply winner.")
	}
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
func cmdStatus() error {
	fs := flag.NewFlagSet("status", flag.ExitOnError)
	c, err := load(fs)
	if err != nil {
		return err
	}
	out, _ := exec.Command("systemctl", "is-active", "xray").CombinedOutput()
	fmt.Printf("xray: %s", out)
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
func cmdRollback() error {
	fs := flag.NewFlagSet("rollback", flag.ExitOnError)
	c, err := load(fs)
	if err != nil {
		return err
	}
	b, err := xray.Rollback(c.XrayConfig, c.StateDir)
	if err == nil {
		fmt.Println("Rolled back", b)
	}
	return err
}
func stringTrim(s string) string {
	for len(s) > 0 && (s[0] == '\n' || s[0] == '\r' || s[0] == ' ' || s[0] == '\t') {
		s = s[1:]
	}
	for len(s) > 0 {
		c := s[len(s)-1]
		if c != '\n' && c != '\r' && c != ' ' && c != '\t' {
			break
		}
		s = s[:len(s)-1]
	}
	return s
}

func sortedOK(results []picker.NodeResult) []picker.NodeResult {
	ok := make([]picker.NodeResult, 0, len(results))
	for _, r := range results {
		if r.OK {
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
	backup, err := xray.Apply(c.XrayConfig, c.StateDir, b.Outbound)
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
	fmt.Println("Applied to production xray. Backup:", backup)
	return nil
}

func cmdList() error {
	fs := flag.NewFlagSet("list", flag.ExitOnError)
	top := fs.Int("top", 20, "number of successful nodes to show")
	all := fs.Bool("all", false, "show all successful nodes")
	failed := fs.Bool("failed", false, "show failed nodes too")
	jsonOut := fs.Bool("json", false, "print raw JSON results")
	c, err := load(fs)
	if err != nil {
		return err
	}
	var results []picker.NodeResult
	b, err := os.ReadFile(filepath.Join(c.StateDir, "last-results.json"))
	if err != nil {
		return err
	}
	if *jsonOut {
		fmt.Print(string(b))
		return nil
	}
	if err := json.Unmarshal(b, &results); err != nil {
		return err
	}
	if *all {
		*top = len(results)
	}
	printSummary(results, *top)
	if *failed {
		fmt.Println("\nFailed:")
		for _, r := range results {
			if !r.OK {
				fmt.Printf("  #%03d  FAIL  %-42s  %s\n", r.Index, truncate(r.Name, 42), r.Error)
			}
		}
	}
	return nil
}

func cmdApply() error {
	fs := flag.NewFlagSet("apply", flag.ExitOnError)
	c, err := load(fs)
	if err != nil {
		return err
	}
	if fs.NArg() != 1 {
		return fmt.Errorf("usage: vibe-vpn apply <index-from-last-results>")
	}
	var idx int
	if _, err := fmt.Sscanf(fs.Arg(0), "%d", &idx); err != nil || idx <= 0 {
		return fmt.Errorf("invalid index %q", fs.Arg(0))
	}
	var results []picker.NodeResult
	b, err := os.ReadFile(filepath.Join(c.StateDir, "last-results.json"))
	if err != nil {
		return err
	}
	if err := json.Unmarshal(b, &results); err != nil {
		return err
	}
	for _, r := range results {
		if r.Index == idx {
			if !r.OK {
				return fmt.Errorf("node #%03d is not OK: %s", idx, r.Error)
			}
			fmt.Printf("Applying #%03d %.2f Mbps %s (%s:%d %s/%s)\n", r.Index, r.Mbps, r.Name, r.Host, r.Port, r.Network, r.Security)
			return applyResult(c, r)
		}
	}
	return fmt.Errorf("node #%03d not found in last-results.json", idx)
}
