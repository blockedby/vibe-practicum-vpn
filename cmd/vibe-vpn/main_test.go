package main

import (
	"net"
	"testing"
	"time"
)

func TestSuccessThresholdAdaptsToSmallLimits(t *testing.T) {
	if got := successThreshold(32 * 1024); got != 32*1024 {
		t.Fatalf("small limit threshold = %d", got)
	}
	if got := successThreshold(512 * 1024); got != 64*1024 {
		t.Fatalf("large limit threshold = %d", got)
	}
}

func TestTCPOpen(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	if !tcpOpen(ln.Addr().String(), time.Second) {
		t.Fatal("expected listener to be detected")
	}
}
