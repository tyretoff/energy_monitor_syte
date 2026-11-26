# 🚀 Автоматическое развертывание Energy Monitor Site

Два варианта установки веб-приложения для мониторинга энергопотребления на Ubuntu Server с LAMP стеком.

## 📋 Предварительные требования

- Ubuntu Server 20.04+ (проверено на 24.04)
- Root доступ или sudo права
- Интернет-соединение
- Для HTTPS версии: настроенный домен, указывающий на IP сервера

---

## ⚡ Вариант 1: Базовая установка (HTTP)

Простая установка без SSL сертификата. Доступ по IP адресу через HTTP.

### Что устанавливается:
- ✅ Apache2, MySQL, PHP (LAMP stack)
- ✅ PHP cURL (`php<версия>-curl`) — устанавливается автоматически под определённую версию PHP
- ✅ Настройка часовых поясов (система, PHP, MySQL)
- ✅ База данных с импортом дампа
- ✅ phpMyAdmin
- ✅ Сайт доступен по HTTP

### Установка:

```bash
wget https://raw.githubusercontent.com/tyretoff/energy_monitor_syte/master/deploy_ip.sh -O deploy_ip.sh
chmod +x deploy_ip.sh
./deploy_ip.sh
```

### После установки доступно:

- 🌐 **Сайт:** `http://ВАШ_IP/`
- 🛠️ **phpMyAdmin:** `http://ВАШ_IP/phpmyadmin/`

### Обновление кода:

```bash
cd /var/www/power_site && git pull
```

---

## 🔒 Вариант 2: Установка с HTTPS (Let's Encrypt)

Полная установка с SSL сертификатом от Let's Encrypt на кастомном порту 8443.

### Что устанавливается:
- ✅ Всё из базовой версии (включая PHP cURL)
- ✅ Certbot для получения SSL сертификата
- ✅ HTTPS на порту 8443
- ✅ Автоматический редирект с HTTP на HTTPS для домена
- ✅ HTTP API остаётся доступным по IP (для скриптов обновления данных)
- ✅ Автообновление сертификата каждые 60 дней

### ⚠️ Важные требования:

1. **Домен должен указывать на IP сервера** (проверьте DNS)
2. **Порт 8443 свободен** (порт 443 может быть занят другими сервисами)
3. **Откройте порт 8443 в firewall** если используется

### Перед установкой:

```bash
# Проверьте DNS домена
dig +short elbs.ru  # Должен вернуть ваш IP

# Откройте порт 8443 (если используется UFW)
sudo ufw allow 8443/tcp

# Или для iptables
sudo iptables -A INPUT -p tcp --dport 8443 -j ACCEPT
```

### Установка:

```bash
wget https://raw.githubusercontent.com/tyretoff/energy_monitor_syte/master/deploy_ip_https.sh -O deploy_ip_https.sh
chmod +x deploy_ip_https.sh
./deploy_ip_https.sh
```

### Настройка домена:

Отредактируйте скрипт перед запуском, если нужен другой домен:

```bash
nano deploy_ip_https.sh

# Измените переменные:
DOMAIN="ваш-домен.ru"
HTTPS_PORT="8443"  # Или другой порт
EMAIL="admin@ваш-домен.ru"
```

### После установки доступно:

- 🔓 **HTTP (редирект):** `http://elbs.ru/` → автоматически перенаправляет на HTTPS
- 🔒 **HTTPS:** `https://elbs.ru:8443/`
- 🌐 **HTTP API:** `http://ВАШ_IP/` (без редиректа, для скриптов)
- 🛠️ **phpMyAdmin:** `http://ВАШ_IP/phpmyadmin/`

---

## 🌐 Вариант 3: Установка с HTTPS + Telegram WEB-proxy

Разворачивает всё из **Варианта 2** (Apache2, MySQL, PHP, Let's Encrypt на порту 443) и дополнительно устанавливает **Telegram WEB-proxy** (`telegramdesktop/tproxy-server` + официальный `MTProxy`) на основной домен `elbs.ru`.

- При открытии `https://elbs.ru/` в обычном браузере загружается ваш реальный сайт мониторинга энергии.
- Трафик Telegram маскируется под стандартные HTTPS/WebSocket-запросы к этому же домену.
- HTTP API по IP и `broker.php` продолжают работать на порту 80 без изменений.

### Установка на чистый VPS (x86_64, Ubuntu 22.04+ / 24.04):

```bash
wget https://raw.githubusercontent.com/tyretoff/energy_monitor_syte/master/deploy_ip_https_webproxy.sh -O deploy_ip_https_webproxy.sh
chmod +x deploy_ip_https_webproxy.sh
./deploy_ip_https_webproxy.sh
```

### Переезд на новый VPS с сохранением прежнего секрета (чтобы не перенастраивать клиентов):

```bash
WEBPROXY_SECRET=ваш_32_hex_секрет ./deploy_ip_https_webproxy.sh
```
или:
```bash
./deploy_ip_https_webproxy.sh --secret ваш_32_hex_секрет
```

### Если сайт с HTTPS уже развёрнут ранее:

```bash
cd /var/www/power_site && git pull
chmod +x install_webproxy.sh
sudo ./install_webproxy.sh
```

---

## 🛠️ Что делают скрипты

### Общие действия:

1. **Устанавливают LAMP стек:** Apache, MySQL, PHP
2. **Устанавливают PHP cURL:** определяется версия PHP (`php -r 'echo PHP_MAJOR_VERSION...'`) и ставится `php<версия>-curl` (например `php8.3-curl`)
3. **Настраивают часовые пояса:** 
   - Система: `Europe/Moscow` (UTC+3)
   - PHP: `date.timezone = Europe/Moscow`
   - MySQL: `default-time-zone = '+03:00'`
4. **Клонируют код с GitHub** в `/var/www/power_site`
5. **Парсят конфиг** `CFG/config.php` для параметров БД
6. **Создают базу данных** и импортируют дамп `s817757_power.sql`
7. **Настраивают Apache** с правильными виртуальными хостами
8. **Устанавливают phpMyAdmin**

### Дополнительно для HTTPS версии:

8. **Получают SSL сертификат** от Let's Encrypt через Certbot
9. **Настраивают два виртуальных хоста:**
   - Домен → редирект на HTTPS:8443
   - IP → прямой HTTP доступ (для API)
10. **Настраивают автообновление сертификата**
11. **Исключают порт 443** из Apache (если занят Docker/другими сервисами)

---

## 📁 Структура проекта

```
/var/www/power_site/
├── CFG/
│   └── config.php          # Конфигурация БД
├── index.php               # Главная страница
├── s817757_power.sql       # SQL дамп базы данных
└── ...                     # Остальные файлы проекта
```

---

## 🔧 Устранение неполадок

### Apache не запускается

```bash
# Проверьте синтаксис конфигурации
sudo apache2ctl configtest

# Посмотрите логи ошибок
sudo journalctl -xeu apache2.service --no-pager | tail -30

# Проверьте, что порты свободны
sudo lsof -i :80
sudo lsof -i :8443
```

### Сертификат не получается

```bash
# Проверьте DNS
dig +short elbs.ru

# Попробуйте получить вручную
sudo certbot certonly --apache -d elbs.ru -d www.elbs.ru
```

### Данные не обновляются

```bash
# Проверьте доступность HTTP API
curl -I http://ВАШ_IP/

# Проверьте логи Apache
sudo tail -f /var/log/apache2/power_site_error.