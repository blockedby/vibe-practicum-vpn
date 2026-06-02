package nettest

import (
	"bytes"
	"testing"
)

func TestCheckHTTPStatus(t *testing.T) {
	if err := checkHTTPStatus([]byte("HTTP/1.1 204 No Content\r\nServer: test")); err != nil {
		t.Fatal(err)
	}
	if err := checkHTTPStatus([]byte("HTTP/1.1 404 Not Found\r\nServer: test")); err == nil {
		t.Fatal("expected non-2xx status to fail")
	}
	if err := checkHTTPStatus([]byte("not-http")); err == nil {
		t.Fatal("expected malformed status to fail")
	}
}

func TestReadSocksReplyConsumesDomainReply(t *testing.T) {
	reply := []byte{5, 0, 0, 3, 3, 'a', 'b', 'c', 0x12, 0x34, 'T', 'L', 'S'}
	r := bytes.NewReader(reply)
	if err := readSocksReply(r); err != nil {
		t.Fatal(err)
	}
	left, _ := r.ReadByte()
	if left != 'T' {
		t.Fatalf("reply parser consumed application byte %q", left)
	}
}

func TestReadSocksReplyRejectsFailure(t *testing.T) {
	if err := readSocksReply(bytes.NewReader([]byte{5, 5, 0, 1})); err == nil {
		t.Fatal("expected error")
	}
}
