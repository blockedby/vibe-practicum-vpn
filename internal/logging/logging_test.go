package logging

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestCleanupDeletesOnlyOwnedOldLogs(t *testing.T) {
	dir := t.TempDir()
	now := time.Date(2026, 5, 27, 12, 0, 0, 0, time.UTC)
	oldOwned := filepath.Join(dir, "vibe-vpn-2026-05-26-23.log")
	newOwned := filepath.Join(dir, "vibe-vpn-2026-05-27-11.log")
	oldOther := filepath.Join(dir, "other-2026-05-26-23.log")
	for _, p := range []string{oldOwned, newOwned, oldOther} {
		if err := os.WriteFile(p, []byte("x"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	oldTime := now.Add(-13 * time.Hour)
	newTime := now.Add(-time.Hour)
	os.Chtimes(oldOwned, oldTime, oldTime)
	os.Chtimes(oldOther, oldTime, oldTime)
	os.Chtimes(newOwned, newTime, newTime)
	if err := Cleanup(dir, 12*time.Hour, now); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(oldOwned); !os.IsNotExist(err) {
		t.Fatalf("old owned log not deleted: %v", err)
	}
	for _, p := range []string{newOwned, oldOther} {
		if _, err := os.Stat(p); err != nil {
			t.Fatalf("unexpected delete %s: %v", p, err)
		}
	}
}

func TestRedactSecrets(t *testing.T) {
	in := `link vless://uuid@example.com:443?security=reality&pbk=secret sub=https://host/path?token=abc&x=1 Authorization: Bearer abc.def token=secret password=hunter2`
	out := Redact(in)
	for _, secret := range []string{"uuid@example.com", "pbk=secret", "token=abc", "abc.def", "token=secret", "hunter2"} {
		if strings.Contains(out, secret) {
			t.Fatalf("secret %q leaked in %q", secret, out)
		}
	}
	if !strings.Contains(out, "vless://[REDACTED]") || !strings.Contains(out, "[REDACTED]") {
		t.Fatalf("redaction markers missing: %q", out)
	}
}

func TestLoggerWritesHourlyAndJournalRedacted(t *testing.T) {
	dir := t.TempDir()
	var journal bytes.Buffer
	l := New(dir, true, &journal)
	fixed := time.Date(2026, 5, 27, 10, 15, 0, 0, time.UTC)
	l.now = func() time.Time { return fixed }
	if err := l.Important("using %s", "vless://secret@example.com/path"); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(journal.String(), "secret@example.com") {
		t.Fatalf("journal leaked secret: %q", journal.String())
	}
	b, err := os.ReadFile(HourlyLogPath(dir, fixed))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(b), "secret@example.com") || !strings.Contains(string(b), "vless://[REDACTED]") {
		t.Fatalf("bad log content: %q", string(b))
	}
}
