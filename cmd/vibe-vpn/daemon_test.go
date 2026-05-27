package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestDaemonHelp(t *testing.T) {
	cmd := newRootCommand()
	var out bytes.Buffer
	cmd.SetOut(&out)
	cmd.SetErr(&out)
	cmd.SetArgs([]string{"daemon", "--help"})
	if err := cmd.Execute(); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "long-lived VPN health") {
		t.Fatalf("daemon help missing: %s", out.String())
	}
}
