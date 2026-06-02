# Browser/web evidence: цены VPS Москва/РФ для secondary VPN host

Дата проверки: 2026-06-02. Проверялись официальные страницы тарифов через headless Chrome; где страница была статической, дополнительно сверялся HTML. Критерий: Linux/KVM/cloud VM, >=1 vCPU, >=1 GB RAM, >=10 GB disk, публичный IPv4 включён или явно оценён, Москва предпочтительно/РФ допустимо.

| Провайдер | Дешёвый жизнеспособный план | Цена/мес | Ресурсы | Локация/зона | IPv4 | Трафик/канал | Direct URL | Уверенность |
|---|---:|---:|---|---|---|---|---|---|
| VDSina | Standard VPS/VDS 1 core/1 Gb/10 Gb | 150 ₽ | 1 core, 1 Gb RAM, 10 Gb disk | дата-центры в Москве и Нидерландах | дополнительные IPv4 доступны; основной IPv4 подразумевается для VDS, точная цена add-on не видна | 1 Tb/мес, порт 1000 Мбит/с; превышение 200 ₽/ТБ | https://vdsina.ru/pricing/standard | Высокая |
| Selectel | VDS 1-1-10 | 200 ₽ | 1 vCPU, 1 GB RAM, 10 GB NVMe SSD, KVM | РФ, Selectel; страница продукта говорит дата-центры Tier III, регионы/зоны облака РФ | не раскрыто на VDS-странице; для cloud servers IPv4 часто отдельный, но VDS-страница даёт готовый VDS price | не указано на VDS-странице | https://selectel.ru/services/cloud/vps-vds/ | Средняя (IPv4 неявен) |
| RuVDS | Старт Хит | 259 ₽ | Linux, CPU 1, RAM 1 Гб, HDD 20 Гб, IP 1 | широкая сеть ДЦ, Москва доступна; страница home перечисляет Москва | 1 IP включён | 100 Мбит/с, безлимитный трафик | https://ruvds.com/ru/vps_start/ | Высокая |
| FirstVDS | Прогрев | 249 ₽ | 1 ядро, 1 Гб RAM, 15 Гб SSD/NVMe, KVM | Москва | 1 выделенный IP бесплатно с каждым VDS/VPS; доп. IPv4 180 ₽/мес | 100 Мбит/с для Прогрев; Москва до 1 Гбит/с/32 ТБ для старших | https://firstvds.ru/products/vds_vps_hosting | Высокая |
| Beget VPS | фиксированная конфигурация 1 ядро / 1 ГБ / 10 ГБ NVMe + публичный IPv4 | 16 ₽/день ≈ 480 ₽/30 дней | 1 CPU 3–3.3 GHz, 1 GB RAM, 10 GB NVMe | Москва, Санкт-Петербург | публичный IPv4 5 ₽/день; сервер 11 ₽/день | 1 Гбит/с | https://beget.com/ru/vps | Высокая |
| REG.RU / Рег.облако | HP C1-M1-D10 + floating IPv4 | 521,45 ₽ + 162,94 ₽ = 684,39 ₽ | 1 vCPU, 1 GB RAM, 10 GB NVMe | Москва/Москва-2, также СПб/Самара; DC list includes Moscow | публичный плавающий IPv4 162,94 ₽/мес | 350 Мбит/с исходящий через public IP; private 1 Гбит/с | https://reg.cloud/cloud/servers | Высокая |
| Timeweb Cloud | Cloud MSK 40 | 882 ₽ | 2 x 3.3 GHz, 2 GB RAM, 40 GB NVMe | Moscow line: Cloud MSK | Public IP column present/included in plan table | 1 Гбит/с | https://timeweb.cloud/services/vds-vps/ | Высокая |
| VK Cloud | Cloud Servers custom минимум | ~1 263 ₽ | 1 CPU Cascade Lake 820 ₽ + 1 GB RAM 223 ₽ + 10 GB HDD 40 ₽ + floating IPv4 188 ₽ | VK Cloud РФ; конкретная Москва на pricelist не была явно видна | floating IPv4 188 ₽/мес | исходящий трафик 1,31 ₽/GB visible in pricelist | https://cloud.vk.com/pricelist/ | Средняя (расчёт по компонентам) |
| AEZA | MSKs-1 Shared | 5.93 € | 1 core, 2 GB RAM, 30 GB NVMe | MSK / Moscow tariff prefix | 1 IPv4 included, /48 IPv6 | до 25 Gbit/s, traffic ∞ | https://aeza.net/ru/virtual-servers | Высокая |
| PQ.Hosting | unresolved | — | — | страница PQ.Hosting сейчас выглядит как рейтинг VPS providers, не собственный тариф Russia/Moscow | — | — | https://pq.hosting/vps-vds/russia | Низкая: официального собственного тарифа PQ.Hosting Russia/Moscow не найдено |
| Yandex Cloud | unresolved | — | — | РФ-зоны ожидаемы, но официальная price/docs page отдала Yandex captcha | — | — | https://yandex.cloud/ru/docs/compute/pricing | Низкая: заблокировано captcha |

## Top 3 дешёвых viable

1. **VDSina — 150 ₽/мес**: самый дешёвый тариф, ровно 1/1/10, Москва указана, но IPv4 add-on price не виден; перепроверить наличие включённого public IPv4 при заказе.
2. **FirstVDS Прогрев — 249 ₽/мес**: 1/1/15, Москва, KVM, 1 выделенный IP включён; очень практичный дешёвый вариант.
3. **RuVDS Старт Хит — 259 ₽/мес**: 1/1/20, 1 IP включён, Москва доступна, безлимитный 100 Мбит/с; чуть дороже FirstVDS, но понятные VPS-тарифы.

## Browser/navigation notes

- FirstVDS, RuVDS, Selectel VDS, REG.RU rendered prices were verified in headless Chrome snapshots.
- VDSina, Timeweb, Beget, AEZA prices were visible in official HTML/pages and consistent with browser-accessible content.
- Yandex Cloud official pages redirected to `showcaptcha`, so concrete current prices were not verified from official source in this run.
- PQ.Hosting official pages found were ranking pages, not a concrete own VPS tariff/order flow for Moscow/Russia.
