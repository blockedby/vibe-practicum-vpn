package logging

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const Prefix = "vibe-vpn-"

var (
	vlessRE             = regexp.MustCompile(`vless://[^\s"'<>]+`)
	sensitiveURLParamRE = regexp.MustCompile(`(?i)([?&](?:token|auth|password|passwd|secret|key|access_token|subscription|sub)[^=]*=)[^\s&"'<>]+`)
	bearerRE            = regexp.MustCompile(`(?i)\b(bearer\s+)[A-Za-z0-9._~+/=-]+`)
	assignmentRE        = regexp.MustCompile(`(?i)\b(token|auth|password|passwd|secret|access_token|subscription_url|sub_url)=([^\s]+)`)
)

func Redact(s string) string {
	s = vlessRE.ReplaceAllString(s, "vless://[REDACTED]")
	s = sensitiveURLParamRE.ReplaceAllString(s, `${1}[REDACTED]`)
	s = bearerRE.ReplaceAllString(s, `${1}[REDACTED]`)
	s = assignmentRE.ReplaceAllString(s, `${1}=[REDACTED]`)
	return s
}

func HourlyLogPath(dir string, t time.Time) string {
	return filepath.Join(dir, fmt.Sprintf("%s%s.log", Prefix, t.UTC().Format("2006-01-02-15")))
}

func Cleanup(dir string, retention time.Duration, now time.Time) error {
	if retention <= 0 {
		return fmt.Errorf("retention must be positive")
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	cutoff := now.Add(-retention)
	for _, e := range entries {
		if e.IsDir() || !strings.HasPrefix(e.Name(), Prefix) || !strings.HasSuffix(e.Name(), ".log") {
			continue
		}
		p := filepath.Join(dir, e.Name())
		info, err := e.Info()
		if err != nil {
			return err
		}
		if info.ModTime().Before(cutoff) {
			if err := os.Remove(p); err != nil {
				return err
			}
		}
	}
	return nil
}

type Logger struct {
	dir         string
	alsoJournal bool
	journal     io.Writer
	now         func() time.Time
}

func New(dir string, alsoJournal bool, journal io.Writer) *Logger {
	if journal == nil {
		journal = os.Stdout
	}
	return &Logger{dir: dir, alsoJournal: alsoJournal, journal: journal, now: time.Now}
}

func (l *Logger) Important(format string, args ...any) error {
	msg := Redact(fmt.Sprintf(format, args...))
	if l.alsoJournal {
		fmt.Fprintln(l.journal, msg)
	}
	return l.write(msg)
}

func (l *Logger) write(msg string) error {
	if l.dir == "" {
		return fmt.Errorf("log dir is empty")
	}
	if err := os.MkdirAll(l.dir, 0755); err != nil {
		return err
	}
	now := time.Now()
	if l.now != nil {
		now = l.now()
	}
	f, err := os.OpenFile(HourlyLogPath(l.dir, now), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = fmt.Fprintln(f, now.UTC().Format(time.RFC3339), msg)
	return err
}
