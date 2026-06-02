# Browser bandwidth re-check — 2026-06-02

Задача: уточнить shortlist VPS в Москве/РФ под публичный канал >=200 Мбит/с, предпочтительно 1 Гбит/с. Проверены официальные tariff/order/pricelist страницы в headless Chrome. Секреты/личные данные не использовались.

## Итоговая таблица

См. обновлённый раздел `## Фильтр >=200 Мбит/с` в `docs/plans/hosting-research-moscow-vps.md`.

## Ключевые browser evidence excerpts

- VDSina `https://vdsina.ru/pricing/standard`: минимальный тариф 150 ₽/мес, 1 core, 1 GB, 10 GB, 1 TB; сноска: «Скорость порта подключения к сети интернет — 1000 Мбит/сек»; локации Москва/Нидерланды; доп. IPv4 доступны.
- FirstVDS `https://firstvds.ru/products/vds_vps_hosting`: «Прогрев» 249 ₽ имеет канал 100 Мбит/сек; первый тариф >=200 — «Старт» 439 ₽, 1 ядро, 2 GB RAM, до 60 GB SSD/NVMe, «Канал до 1 Гбит/сек»; «1 выделенный IP-адрес» бесплатно с каждым VDS; Москва.
- RuVDS `https://ruvds.com/ru/vps_start/`: тарифы Start/Start SSD/Start Hit/Start Hit SSD показывают IP=1, но раздел преимуществ говорит: интернет-канал 100 Мбит/с и безлимитный трафик. Тариф >=200 Мбит/с на проверенной странице не найден.
- Selectel VDS `https://selectel.ru/services/cloud/vps-vds/`: VDS 1-1-10 стоит 200 ₽/мес, но публичный bandwidth на VDS-странице не указан. На `https://selectel.ru/services/cloud/servers/` для cloud servers указано: до 10 Гбит/с, 3 TB бесплатно, в сетевом блоке — 3 Гбит/с канал; Standard Line от 948,50 ₽/мес.
- Beget `https://beget.com/ru/vps`: фиксированный минимальный VPS 1 ядро/1 GB/10 GB — 11 ₽/день, канал 1 Гб/сек; публичный IPv4 5 ₽/день; итого около 16 ₽/день или 480 ₽/30 дней; проверенная локация — Россия, Санкт-Петербург.
- REG.RU/Рег.облако `https://reg.cloud/cloud/servers`: public floating IPv4 162,94 ₽/мес; «350 Мбит/с исходящий трафик в интернет через публичный IP-адрес»; Москва/Москва-2 в дата-центрах. Цена HP C1-M1-D10 684,39 ₽/мес сохранена из предыдущей browser-проверки, текущая страница подтвердила канал/IP, но конфигуратор не показал тарифы для выбранного образа в headless text.
- Timeweb Cloud `https://timeweb.cloud/services/vds-vps/`: Cloud MSK 40 — 882 ₽/мес, 2×3.3 GHz, 2 GB RAM, 40 GB NVMe, канал 1 Гбит/с; FAQ: трафик бесплатный и безлимитный; московский DC IXcellerate указан в списке архитектуры.
- AEZA `https://aeza.net/ru/virtual-servers`: Moscow Shared MSKs-1 — 5.93 €/мес, 1 core, 2 GB RAM, 30 GB NVMe, 25 Gbit/s, traffic ∞, 1 IPv4.
- VK Cloud `https://cloud.vk.com/pricelist/`: Cloud Servers prices: CPU Cascade Lake 820 ₽/30d, RAM 223 ₽/GB/30d, HDD 4 ₽/GB/30d; public IPv4 около 187–188 ₽/30d. Скорость публичного канала VM на прайсе не найдена, поэтому исключён до подтверждения bandwidth.

## Top 3 по критерию >=200 Мбит/с

1. VDSina Standard — 150 ₽/мес, 1 Гбит/с порт, Москва доступна; проверить включённый основной IPv4 при заказе.
2. FirstVDS Старт — 439 ₽/мес, до 1 Гбит/с, Москва, 1 IPv4 включён.
3. Beget VPS 1/1/10 + IPv4 — около 480 ₽/30 дней, 1 Гбит/с, но проверенная локация СПб; если нужна строго Москва, заменить на REG.RU/Рег.облако 684,39 ₽/мес с 350 Мбит/с.

Не коммитил.
