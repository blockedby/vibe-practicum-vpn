package subscription

import (
	"encoding/base64"
	"testing"
)

func TestParsePlainAndBase64(t *testing.T) {
	link := "vless://u@h:80?type=ws#n"
	got, _ := Parse("x\n" + link + "\n")
	if len(got) != 1 || got[0] != link {
		t.Fatalf("%v", got)
	}
	enc := base64.StdEncoding.EncodeToString([]byte(link + "\n"))
	got, _ = Parse(enc)
	if len(got) != 1 || got[0] != link {
		t.Fatalf("b64 %v", got)
	}
	wrapped := enc[:8] + "\n" + enc[8:]
	got, _ = Parse(wrapped)
	if len(got) != 1 || got[0] != link {
		t.Fatalf("wrapped b64 %v", got)
	}
}
