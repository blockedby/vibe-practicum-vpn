# RU direct rule sets

Date: 2026-04-27

## Goal

For the Pixel canary, keep default traffic through VLESS/proxy, but route Russian/local services directly from the VPS.

Examples we care about:

- banks;
- Госуслуги;
- ФНС/налоговая;
- 2ГИС/maps;
- Yandex services;
- Avito/Tele2/Rostelecom/etc.

## Sources investigated

### legiz-ru/sb-rule-sets

Repository:

```text
https://github.com/legiz-ru/sb-rule-sets
```

It provides native sing-box `.srs` and source JSON rule-sets.

Investigated files:

- `itdoginfo-inside-russia.json/.srs`
- `no-russia-hosts.json/.srs`
- `ru-bundle.json/.srs`
- `ru-app-list.json/.srs`
- `unbanru-app-list.json/.srs`

Findings:

- `itdoginfo-inside-russia`: 1162 domain suffixes.
- `no-russia-hosts`: 700 domain suffixes.
- `ru-bundle`: 1949 domain suffixes.
- `itdoginfo-inside-russia` and `no-russia-hosts` are both subsets of `ru-bundle`.
- `ru-bundle` additionally contains many non-RU/proxy-intended domains such as OpenAI, Twitter/X, ProtonMail, GitHub API, etc.
- Therefore `ru-bundle` is **not safe as a direct whitelist** for our use case.
- `ru-app-list` is Android `package_name` based. On the VPS router we see Tailscale traffic, not Android package names, so this is not useful for server-side TProxy routing.
- `unbanru-app-list` is proxy-intended app list, not direct whitelist.

### runetfreedom/russia-v2ray-rules-dat

Repository:

```text
https://github.com/runetfreedom/russia-v2ray-rules-dat
```

Useful native sing-box SRS files from release branch:

```text
https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geoip/geoip-ru.srs
https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geosite/geosite-ru-available-only-inside.srs
```

These are a better fit for direct routing:

- `geoip-ru`: Russian IP ranges.
- `geosite-ru-available-only-inside`: domains available only inside Russia.

## Applied to Pixel canary

Added remote rule-sets to `configs/sing-box/tproxy-canary.json`:

```text
geoip-ru -> direct-out
geosite-ru-available-only-inside -> direct-out
```

Also added inline direct domain suffixes for Russian TLDs:

```text
.ru
.su
.рф / xn--p1ai
.moscow
.tatar
other RU punycode zones
```

And a small curated direct suffix list for common non-.ru Russian infra:

```text
yandex.com
yandex.net
yastatic.net
yandexcloud.net
2gis.com
2gis.ae
dublgis.com
dgis.com
avito.st
avito.net
```

## Validation

`sing-box check` passed.

After restart, sing-box downloaded rule-sets successfully:

```text
router: updated rule-set geoip-ru
router: updated rule-set geosite-ru-available-only-inside
```

Local SOCKS validation:

```text
ya.ru -> direct-out
gosuslugi.ru -> direct-out
```

Pixel canary remains enabled and should now route RU/direct services directly while keeping default traffic through VLESS.
