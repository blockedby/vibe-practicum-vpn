# План: постоянный VPN failover service

## 1. Архитектура

Мониторинг должен работать **не как ручная команда**, а как постоянный `systemd`-сервис:

```bash
sudo systemctl enable --now vibe-vpn
```

Внутри бинарника может быть служебный entrypoint типа:

```bash
vibe-vpn daemon
```

Но пользователь руками его обычно не запускает.

## 2. Что делает сервис

Сервис постоянно выполняет две независимые задачи:

### A. Тест нод

Каждые 30 минут:

```bash
vibe-vpn test
```

или внутренняя переиспользованная test-логика.

Результаты сохраняются в `last-results.json`.

Важно:

- test не должен менять текущую production-ноду;
- если test упал, сервис не падает;
- если есть старые результаты — продолжает использовать их.

### B. Health-check VPN

В нормальном состоянии каждые 5 секунд сервис асинхронно проверяет URL:

```text
https://x.com/
https://rutracker.org/
https://ya.ru/
```

Проверки идут **параллельно** через production SOCKS/VPN.

## 3. Логика URL

Лучше разделить URL на два типа:

```yaml
health:
  required_urls:
    - https://x.com/
    - https://rutracker.org/

  diagnostic_urls:
    - https://ya.ru/
```

### Required URLs

Используются для решения: надо ли переключать ноду.

Если `x.com` и `rutracker.org` не открываются — считаем VPN-ноду плохой.

### Diagnostic URLs

`ya.ru` нужен для диагностики.

Примеры:

```text
x.com fail, rutracker fail, ya.ru ok
=> интернет есть, но VPN плохо обходит блокировки

x.com fail, rutracker fail, ya.ru fail
=> возможно умер SOCKS/xray/сеть целиком
```

## 4. Прогрессивный интервал между fail-check

Нормальный режим:

```text
каждые 5 секунд health-check
```

Если случился fail, сервис не ждёт следующие 5 секунд, а запускает ускоренную проверку:

```text
обычный check через 5s -> fail
через 1s -> повторный check
через 2s -> повторный check
через 3s -> повторный check
если всё ещё fail -> switch node
```

То есть последовательность такая:

```text
healthy mode:
  probe every 5s

failure confirmation mode:
  wait 1s, probe
  wait 2s, probe
  wait 3s, probe
  if still failed:
    failover
```

Если на любом этапе probe стал successful:

```text
сбросить fail state
вернуться к обычному режиму 5s
```

## 5. Failover logic

Когда подтверждён fail:

```text
load last-results.json
filter working nodes
sort by speed descending
find current node
take next node after current
apply node
restart runtime
probe URLs again
```

Если новая нода заработала:

```text
оставить её
сбросить fail state
вернуться к обычному health loop
```

Если не заработала:

```text
пробовать следующую ноду по скорости
```

И так далее, пока:

- не найдётся рабочая нода;
- или список не закончится.

Если список закончился:

```text
логировать critical
оставить сервис живым
ждать новых результатов test
продолжать health-check
```

## 6. Конфиг

Пример:

```yaml
service:
  enabled: true
  startup_test: true

test:
  interval: 30m

health:
  normal_interval: 5s
  failure_retry_delays:
    - 1s
    - 2s
    - 3s
  probe_timeout: 5s

  required_urls:
    - https://x.com/
    - https://rutracker.org/

  diagnostic_urls:
    - https://ya.ru/

logging:
  path: /var/log/vibe-vpn/
  retention: 12h
  also_journal: true
```

## 7. Systemd service

Добавить unit:

```ini
[Unit]
Description=Vibe VPN auto failover service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/vibe-vpn daemon --config /etc/vibe-vpn/config.yaml
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
```

## 8. Ограничение логов

Логи хранить максимум 12 часов.

Варианты:

### Основной вариант

Писать собственные rotating logs:

```text
/var/log/vibe-vpn/vibe-vpn-2026-05-27-10.log
/var/log/vibe-vpn/vibe-vpn-2026-05-27-11.log
...
```

Cleaner внутри сервиса удаляет файлы старше 12 часов.

### Плюс

Дублировать важные события в `journalctl`:

```bash
journalctl -u vibe-vpn -f
journalctl -u vibe-vpn --since "12 hours ago"
```

Важно: не логировать полные `vless://` ссылки и секреты.

## 9. Основные файлы для изменения

Вероятно:

```text
cmd/vibe-vpn/main.go
internal/config/
internal/nettest/
internal/picker/
internal/state/
internal/xray/
```

Новые модули:

```text
internal/service/
internal/health/
internal/failover/
internal/logging/
```

Документация:

```text
README.md
docs/...
systemd/vibe-vpn.service
```

## 10. Acceptance criteria

Готово, если:

1. Есть постоянный `vibe-vpn.service`.
2. Сервис стартует при boot.
3. Сервис автоматически рестартится при падении.
4. Ноды тестируются каждые 30 минут.
5. Health-check идёт через VPN/SOCKS.
6. В норме проверки идут каждые 5 секунд.
7. URL проверяются асинхронно/параллельно.
8. Проверяются:
   - `x.com`
   - `rutracker.org`
   - `ya.ru`
9. Для failover используются `x.com` и `rutracker.org`.
10. После первого fail запускается прогрессивная проверка:
    - через 1 секунду
    - через 2 секунды
    - через 3 секунды
11. Если после этого всё ещё fail — происходит switch.
12. Switch идёт на следующую быструю рабочую ноду из test results.
13. Если новая нода не работает — пробуется следующая.
14. Если ноды закончились — сервис не падает.
15. Логи хранятся максимум 12 часов.
16. В логах нет полных VPN-секретов.
17. Есть документация по установке, запуску, логам и rollback.

## 11. Проверка

Минимум:

```bash
go test ./...
go vet ./...
go build ./cmd/vibe-vpn
```

Manual smoke:

```bash
sudo systemctl start vibe-vpn
sudo systemctl status vibe-vpn
journalctl -u vibe-vpn -f
```

Тест с ускоренным конфигом:

```yaml
test:
  interval: 1m

health:
  normal_interval: 5s
  failure_retry_delays: [1s, 2s, 3s]
```

Так можно быстро проверить failover без ожидания 30 минут.

## 12. AAD/agent task breakdown для будущей реализации

Цель этого breakdown — подготовить реализацию через AAD без изменения продуктового поведения из разделов выше. Корневой owner держит общий контекст сервиса failover, а отдельные `aad-slice-owner`-срезы отвечают за свои границы, acceptance и отчёты. Реализацию внутри срезов выполняют `aad-implementer`; supporting agents используются только для узкой проверки, ревью, классификации падений или ручного smoke/evidence.

### 12.1 Волны и зависимости

```text
Wave 0 — контракты и конфиг (блокирует большинство кода)
  S1 config/contracts

Wave 1 — независимые ядра после S1
  S2 health probes
  S3 scheduled tester
  S4 logging/retention
  S5 systemd/daemon skeleton

Wave 2 — failover orchestration после S1+S2 и с reuse state/picker/xray
  S6 failover selection/apply loop

Wave 3 — интеграция сервиса после S2+S3+S4+S5+S6
  S7 daemon integration and lifecycle

Wave 4 — документация, упаковка, acceptance evidence после S7
  S8 docs/runbook/system readiness
  S9 final integration verification
```

Параллельно можно запускать S2, S3, S4 и S5 после фиксации S1, если в routing packet явно зафиксированы интерфейсы конфигурации, формат логов и do-not-touch границы. S6 не должен начинаться до ясного контракта health-result и правил выбора текущей/следующей ноды. S7 ждёт рабочих API всех внутренних модулей.

### 12.2 Срезы

#### S1 — Config/contracts foundation

- **Goal:** расширить модель конфигурации для `service`, `test.interval`, `health`, `logging` и зафиксировать внутренние контракты между daemon, health, failover, logging.
- **Scope/boundary:** только конфиг, defaults, validation, типы/интерфейсы и тесты контрактов; не запускать реальные probes, xray restart или systemd.
- **Likely files:** `internal/config/`, возможные новые contract-файлы в `internal/service/`, `internal/health/`, `internal/failover/`, документация формата конфига.
- **Owner/routing:** `aad-slice-owner` владеет срезом; `aad-implementer` делает config/types/tests; при спорных defaults — короткий design-refinement owner-pass.
- **Acceptance:** YAML/JSON config принимает пример из этого плана; defaults соответствуют 30m/5s/[1s,2s,3s]/5s/12h; явная ошибка на невалидные durations/пустые required URLs; секреты и VLESS links не попадают в ошибки/логи.
- **Verification evidence:** `go test ./internal/config/...` или ближайшие package tests; targeted tests на defaults/validation; diff с обновлённой документацией конфига.
- **Expected report:** список утверждённых полей и defaults, что считается backward-compatible, какие интерфейсы должны использовать следующие срезы.

#### S2 — Health probes через production SOCKS/VPN

- **Goal:** реализовать параллельные health-check probes для required и diagnostic URL через production SOCKS/VPN с timeout и классификацией результата.
- **Scope/boundary:** `internal/health/`; не принимать решения о failover и не менять production config/runtime.
- **Likely files:** новый `internal/health/`, переиспользование существующих сетевых helper-паттернов из `internal/nettest/` где безопасно.
- **Owner/routing:** `aad-slice-owner`; `aad-implementer` реализует probe runner и unit tests; supporting agent можно вызвать для review сетевых timeout/concurrency.
- **Acceptance:** required и diagnostic URL проверяются асинхронно/параллельно; общий результат отвечает на вопрос “failover needed?” только по required URLs; diagnostic URLs сохраняют диагностический статус; timeout применён на запрос; production SOCKS address берётся из config/существующих runtime settings.
- **Verification evidence:** unit tests с fake HTTP/SOCKS transport или injectable client; тесты на all-required-fail, partial recovery, diagnostic-only-fail; `go test ./internal/health/...`.
- **Expected report:** API health-result, как отличить required failure от diagnostic failure, ограничения моков и manual smoke requirements.

#### S3 — Scheduled node testing loop

- **Goal:** встроить периодический запуск существующей test-логики каждые 30 минут без падения сервиса при ошибке test.
- **Scope/boundary:** scheduler/service adapter вокруг существующего `vibe-vpn test`; не менять алгоритм benchmark/pick без необходимости; не применять победителя.
- **Likely files:** `internal/service/`, существующие `internal/nettest/`, `internal/state/`, `internal/picker/`, возможно CLI command wiring.
- **Owner/routing:** `aad-slice-owner`; `aad-implementer` делает scheduler и reuse existing test function; failure-classification support только если текущая test-логика плохо отделена от CLI.
- **Acceptance:** startup test опционален; interval из config; ошибка test логируется и не останавливает daemon; старый `last-results.json` остаётся usable; нет production switch во время scheduled test.
- **Verification evidence:** unit tests/fake clock на interval/startup_test/error handling; targeted package tests; при интеграции — smoke с ускоренным `test.interval: 1m`.
- **Expected report:** какие существующие функции переиспользованы, как гарантировано отсутствие apply/restart в scheduled test.

#### S4 — Logging and 12h retention

- **Goal:** добавить сервисные логи с ротацией/очисткой старше 12 часов и дублированием важных событий в journal-compatible stdout/stderr.
- **Scope/boundary:** `internal/logging/` и wiring; не логировать полные `vless://`, subscription URLs, tokens, auth secrets.
- **Likely files:** новый `internal/logging/`, config docs, места вызовов в service/failover после интеграции.
- **Owner/routing:** `aad-slice-owner`; `aad-implementer` реализует sanitizer, file writer/cleaner, tests; supporting security review можно вызвать для проверки redaction.
- **Acceptance:** файлы в `/var/log/vibe-vpn/` или configured path; retention default 12h; cleaner удаляет только свои старые log-файлы; важные события видны в journal; secrets redacted.
- **Verification evidence:** unit tests на retention boundary, filename ownership, redaction; targeted package tests; manual `journalctl -u vibe-vpn --since "12 hours ago"` в финальном smoke.
- **Expected report:** redaction rules, retention behavior, какие события считаются important.

#### S5 — Daemon CLI entrypoint и systemd unit

- **Goal:** добавить `vibe-vpn daemon` и installable `vibe-vpn.service` как постоянный root-service.
- **Scope/boundary:** CLI wiring, graceful shutdown context, unit-файл; без полной failover логики до S7.
- **Likely files:** `cmd/vibe-vpn/main.go` или cobra command files, `internal/service/`, `systemd/vibe-vpn.service`, README/docs.
- **Owner/routing:** `aad-slice-owner`; `aad-implementer` реализует command/unit; devops-runtime-readiness support для review unit-файла.
- **Acceptance:** `vibe-vpn daemon --config /etc/vibe-vpn/config.yaml` стартует service loop; systemd unit содержит `After/Wants=network-online.target`, `Restart=always`, `RestartSec=5`, root user; корректная остановка по SIGTERM/SIGINT.
- **Verification evidence:** `go build ./cmd/vibe-vpn`; command help/smoke; static review unit; позже manual `sudo systemctl start/status vibe-vpn`.
- **Expected report:** точный ExecStart, install path assumptions, команды установки/rollback.

#### S6 — Failover selection/apply loop

- **Goal:** при подтверждённом fail выбрать следующую быструю рабочую ноду из `last-results.json`, применить её, перезапустить runtime и проверить результат; при неудаче идти дальше.
- **Scope/boundary:** `internal/failover/` и adapters к `internal/state/`, `internal/picker/`, `internal/xray/`; не менять формат state без миграционной необходимости.
- **Likely files:** новый `internal/failover/`, `internal/state/`, `internal/picker/`, `internal/xray/`, tests.
- **Owner/routing:** `aad-slice-owner`; `aad-implementer` реализует deterministic selection/apply orchestration; acceptance-auditor или review support желателен из-за production safety.
- **Acceptance:** берет только working nodes из latest results; сортирует по speed descending; находит current node и начинает со следующей; если новая нода не проходит health probe — пробует следующую; при окончании списка логирует critical и оставляет daemon живым; не раскрывает секреты в логах.
- **Verification evidence:** unit tests на порядок выбора/current-not-found/end-of-list/apply-failure/probe-failure; fake xray/runtime adapter; targeted `go test ./internal/failover/...`.
- **Expected report:** state assumptions, rollback/safety behavior, какие ошибки являются retryable vs critical.

#### S7 — Daemon integration and lifecycle

- **Goal:** собрать health loop, progressive failure confirmation, scheduled tests, logging и failover в один long-running daemon.
- **Scope/boundary:** orchestration в `internal/service/`; не расширять отдельные алгоритмы сверх контрактов S1-S6.
- **Likely files:** `internal/service/`, command wiring, integration tests with fakes.
- **Owner/routing:** `aad-slice-owner`; `aad-implementer` делает orchestration; systematic-debugging support при flaky concurrency/timer behavior.
- **Acceptance:** normal health каждые 5s; после fail идут проверки через 1s, 2s, 3s; recovery на любом этапе сбрасывает fail state; confirmed fail вызывает S6; test loop живёт независимо от health loop; daemon не падает от отдельных probe/test/failover errors; shutdown останавливает goroutines.
- **Verification evidence:** fake clock/integration tests на state machine; race-sensitive tests по возможности; `go test ./internal/service/...` и затем `go test ./...`.
- **Expected report:** state machine evidence, known timing tolerances, что проверено fake-clock vs manual smoke.

#### S8 — Docs, runbook, install/rollback

- **Goal:** обновить пользовательскую документацию для установки, запуска, логов, smoke, rollback и безопасных ускоренных проверок.
- **Scope/boundary:** docs/readme/systemd notes only; не менять код.
- **Likely files:** `README.md`, `docs/...`, `systemd/vibe-vpn.service` comments if needed.
- **Owner/routing:** `aad-slice-owner`; `aad-implementer` делает docs; supporting reviewer может проверить runbook на операционную полноту.
- **Acceptance:** documented `systemctl enable --now vibe-vpn`; команды `status`, `journalctl`, config example, accelerated smoke config, rollback path; security note про отсутствие секретов в логах; ясно, что ручной `vibe-vpn test/pick/apply/rollback` остаётся доступен.
- **Verification evidence:** markdown diff review; command snippets consistent with actual CLI/unit; no source-code changes in docs-only slice.
- **Expected report:** список обновлённых docs и mapping docs к AC 1,2,3,15,16,17.

#### S9 — Final integration verification and acceptance audit

- **Goal:** проверить готовность всей реализации против acceptance criteria из раздела 10 и минимальных проверок из раздела 11.
- **Scope/boundary:** verification/audit only, fixes только если owner явно возвращает findings в соответствующий срез или делает follow-up issue.
- **Likely files/artifacts:** task package verification reports, final AAD report, possible GitHub PR checks.
- **Owner/routing:** root `aad-root-owner` или финальный `aad-slice-owner` координирует; `aad-acceptance-auditor` проверяет evidence; browser/manual agents не нужны, кроме внешнего VPS smoke по запросу.
- **Acceptance:** каждый пункт из раздела 10 имеет тест, command evidence, manual smoke evidence или явно записанный waiver; финальный отчёт классифицирует R/F/U issues; PR/branch содержит только ожидаемые code/docs/systemd changes.
- **Verification evidence:** свежие `go test ./...`, `go vet ./...`, `go build ./cmd/vibe-vpn`; manual smoke `sudo systemctl start vibe-vpn`, `sudo systemctl status vibe-vpn`, `journalctl -u vibe-vpn -f`; accelerated config smoke; проверка логов/retention/redaction; `git diff --stat` и PR checks через `gh` если есть PR.
- **Expected report:** acceptance verification matrix, system readiness, open blockers, follow-up GitHub issues for every F-*.

### 12.3 Интеграционные правила для AAD execution

- Каждый срез пишет отчёт в task package: `reports/<slice-id>.md`, прогресс в `progress/<agent>.md`, verification artifacts в `verification/`.
- Routing packet для implementer должен включать: goal, boundaries, likely files, reuse targets, acceptance, verification commands, dependencies, do-not-touch и ожидаемый report path.
- Do-not-touch по умолчанию: не коммитить реальные subscription URLs, `vless://` links, auth secrets, production config с секретами; не менять unrelated CLI behavior; не запускать destructive VPS/systemd команды без явного manual-smoke шага.
- Интеграция дочерних результатов идёт через owner: owner читает отчёты, обновляет dependency graph, классифицирует findings как `R-*`, `F-*` или `U-*`, и только затем передаёт следующий срез.
- Перед final readiness обязательно fresh verification: минимум `go test ./...`, `go vet ./...`, `go build ./cmd/vibe-vpn`; если VPS smoke недоступен, это явный waiver/risk в S9, а не молчаливый pass.
