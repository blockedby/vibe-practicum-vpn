package vless

import "testing"

func TestParseWS(t *testing.T) {
	n, err := Parse("vless://uuid@h:80?security=none&type=ws&path=%2Fws&host=ex#Name")
	if err != nil {
		t.Fatal(err)
	}
	if n.Name != "Name" || n.Host != "h" || n.Port != 80 || n.Network != "ws" {
		t.Fatalf("%+v", n)
	}
	ss := n.Outbound["streamSettings"].(map[string]any)
	if ss["network"] != "ws" {
		t.Fatal(ss)
	}
}
func TestParseReality(t *testing.T) {
	n, err := Parse("vless://u@h:443?type=tcp&security=reality&sni=github.com&fp=chrome&pbk=pk&sid=aa&spx=%2F&flow=xtls-rprx-vision#r")
	if err != nil {
		t.Fatal(err)
	}
	if n.Security != "reality" {
		t.Fatal(n)
	}
	ss := n.Outbound["streamSettings"].(map[string]any)
	rs := ss["realitySettings"].(map[string]any)
	if rs["publicKey"] != "pk" || rs["spiderX"] != "/" {
		t.Fatal(rs)
	}
}

func TestParseRejectsMissingHostAndBadPort(t *testing.T) {
	for _, link := range []string{"vless://u@:443?security=tls", "vless://u@h:99999?security=tls", "vless://@h:443?security=tls"} {
		if _, err := Parse(link); err == nil {
			t.Fatalf("expected error for %s", link)
		}
	}
}

func TestParseTLSALPNAndDefaultName(t *testing.T) {
	n, err := Parse("vless://u@example.com?security=tls&alpn=h2,http/1.1")
	if err != nil {
		t.Fatal(err)
	}
	if n.Port != 443 || n.Name != "example.com:443" {
		t.Fatalf("%+v", n)
	}
	ss := n.Outbound["streamSettings"].(map[string]any)
	tls := ss["tlsSettings"].(map[string]any)
	if got := tls["alpn"].([]string); len(got) != 2 || got[0] != "h2" || got[1] != "http/1.1" {
		t.Fatal(tls)
	}
}
