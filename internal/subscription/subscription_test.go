package subscription

import (
	"encoding/base64"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
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

func TestURLList(t *testing.T) {
	got := URLList("\n # comment\r\n https://one.example/sub \n\thttps://two.example/sub\t\n")
	want := []string{"https://one.example/sub", "https://two.example/sub"}
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Fatalf("got %#v want %#v", got, want)
	}
}

func TestFetchManyContinuesAfterOneFailure(t *testing.T) {
	link1 := "vless://u@h1:443?type=tcp#one"
	link2 := "vless://u@h2:443?type=ws#two"
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/one":
			_, _ = w.Write([]byte(link1 + "\n"))
		case "/two":
			_, _ = w.Write([]byte(base64.StdEncoding.EncodeToString([]byte(link2 + "\n"))))
		default:
			http.Error(w, "nope", http.StatusBadGateway)
		}
	}))
	defer srv.Close()

	links, errs := FetchMany([]string{srv.URL + "/one", srv.URL + "/bad", srv.URL + "/two"}, time.Second)
	if len(errs) != 1 {
		t.Fatalf("errs=%v", errs)
	}
	if strings.Join(links, "|") != strings.Join([]string{link1, link2}, "|") {
		t.Fatalf("links=%#v", links)
	}
}
