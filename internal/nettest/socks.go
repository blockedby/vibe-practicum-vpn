package nettest

import (
	"bytes"
	"crypto/tls"
	"fmt"
	"io"
	"net"
	"net/url"
	"strconv"
	"strings"
	"time"
)

type Result struct {
	Bytes   int64   `json:"bytes"`
	Seconds float64 `json:"seconds"`
	Mbps    float64 `json:"mbps"`
}

func Download(socksAddr, testURL string, limit int64, timeout time.Duration) (Result, error) {
	if limit <= 0 {
		return Result{}, fmt.Errorf("download limit must be positive")
	}
	u, err := url.Parse(testURL)
	if err != nil {
		return Result{}, err
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return Result{}, fmt.Errorf("unsupported test URL scheme %q", u.Scheme)
	}
	host := u.Hostname()
	if host == "" {
		return Result{}, fmt.Errorf("test URL missing host")
	}
	if len(host) > 255 {
		return Result{}, fmt.Errorf("test URL host too long for SOCKS5 domain request")
	}
	port := u.Port()
	if port == "" {
		if u.Scheme == "https" {
			port = "443"
		} else {
			port = "80"
		}
	}
	path := u.RequestURI()
	if path == "" {
		path = "/"
	}
	d := net.Dialer{Timeout: timeout}
	raw, err := d.Dial("tcp", socksAddr)
	if err != nil {
		return Result{}, err
	}
	defer raw.Close()
	if err := raw.SetDeadline(time.Now().Add(timeout)); err != nil {
		return Result{}, err
	}
	if _, err := raw.Write([]byte{5, 1, 0}); err != nil {
		return Result{}, err
	}
	gr := make([]byte, 2)
	if _, err := io.ReadFull(raw, gr); err != nil || gr[1] != 0 {
		return Result{}, fmt.Errorf("socks greeting")
	}
	hb := []byte(host)
	p, err := strconv.Atoi(port)
	if err != nil || p <= 0 || p > 65535 {
		return Result{}, fmt.Errorf("invalid test URL port %q", port)
	}
	req := append([]byte{5, 1, 0, 3, byte(len(hb))}, hb...)
	req = append(req, byte(p>>8), byte(p))
	if _, err := raw.Write(req); err != nil {
		return Result{}, err
	}
	if err := readSocksReply(raw); err != nil {
		return Result{}, err
	}
	conn := raw
	if u.Scheme == "https" {
		tlsconn := tls.Client(raw, &tls.Config{ServerName: host})
		if err := tlsconn.Handshake(); err != nil {
			return Result{}, err
		}
		conn = tlsconn
	}
	t := time.Now()
	if _, err := fmt.Fprintf(conn, "GET %s HTTP/1.1\r\nHost: %s\r\nUser-Agent: vibe-vpn/1\r\nConnection: close\r\n\r\n", path, u.Host); err != nil {
		return Result{}, err
	}
	buf := make([]byte, 32768)
	var n int64
	header := []byte{}
	haveHeader := false
	for n < limit {
		c, err := conn.Read(buf)
		if c > 0 {
			data := buf[:c]
			if !haveHeader {
				header = append(header, data...)
				if len(header) > 64<<10 {
					return Result{}, fmt.Errorf("http response headers too large")
				}
				if i := bytes.Index(header, []byte("\r\n\r\n")); i >= 0 {
					if err := checkHTTPStatus(header[:i]); err != nil {
						return Result{}, err
					}
					haveHeader = true
					n += int64(len(header) - i - 4)
				}
			} else {
				n += int64(c)
			}
		}
		if err != nil {
			break
		}
	}
	if !haveHeader {
		return Result{}, fmt.Errorf("http response missing complete headers")
	}
	sec := time.Since(t).Seconds()
	if sec <= 0 {
		return Result{}, fmt.Errorf("download completed too quickly to measure")
	}
	return Result{n, sec, float64(n) * 8 / sec / 1e6}, nil
}

func checkHTTPStatus(header []byte) error {
	line := string(header)
	if i := strings.Index(line, "\r\n"); i >= 0 {
		line = line[:i]
	}
	fields := strings.Fields(line)
	if len(fields) < 2 || !strings.HasPrefix(fields[0], "HTTP/") {
		return fmt.Errorf("invalid http response status %q", line)
	}
	code, err := strconv.Atoi(fields[1])
	if err != nil {
		return fmt.Errorf("invalid http response status %q", line)
	}
	if code < 200 || code >= 300 {
		return fmt.Errorf("http response status %d", code)
	}
	return nil
}

func readSocksReply(r io.Reader) error {
	h := make([]byte, 4)
	if _, err := io.ReadFull(r, h); err != nil {
		return err
	}
	if h[0] != 5 || h[1] != 0 {
		return fmt.Errorf("socks connect reply %v", h)
	}
	var rest int
	switch h[3] {
	case 1:
		rest = 4 + 2
	case 3:
		lb := make([]byte, 1)
		if _, err := io.ReadFull(r, lb); err != nil {
			return err
		}
		rest = int(lb[0]) + 2
	case 4:
		rest = 16 + 2
	default:
		return fmt.Errorf("socks connect unknown address type %d", h[3])
	}
	_, err := io.CopyN(io.Discard, r, int64(rest))
	return err
}
