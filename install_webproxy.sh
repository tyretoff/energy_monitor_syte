#!/bin/bash
# Установка Telegram WEB-proxy (telegramdesktop/tproxy-server) на основной домен
# поверх существующего Apache2 (Ubuntu 22.04+ / 24.04, x86_64).
set -euo pipefail

DOMAIN="elbs.ru"
EMAIL="admin@${DOMAIN}"
SITE_DIR="/var/www/power_site"
TPROXY_REPO="https://github.com/telegramdesktop/tproxy-server.git"
TPROXY_SRC="/opt/tproxy-server"
UPSTREAM_PORT="8088"
RELAY_PORT="8080"

if [ "${EUID}" -ne 0 ]; then
    echo "❌ Запустите скрипт от root или через sudo: sudo $0"
    exit 1
fi

if [ "$(uname -m)" != "x86_64" ]; then
    echo "❌ Официальный MTProxy требует архитектуру x86_64 (текущая: $(uname -m))"
    exit 1
fi

if [ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
    echo "❌ SSL-сертификат для ${DOMAIN} не найден в /etc/letsencrypt/live/${DOMAIN}/"
    echo "   Сначала выполните deploy_ip_https.sh и switch_to_443.sh."
    exit 1
fi

echo "=== 1. Генерация секрета WEB-прокси ==="
if [ -n "${WEBPROXY_SECRET:-}" ]; then
    SECRET="$WEBPROXY_SECRET"
else
    SECRET=$(openssl rand -hex 16)
fi
echo "🔑 Секрет сгенерирован (будет выведен в конце установки)"

echo "=== 2. Установка зависимостей и скачивание tproxy-server ==="
apt-get update -qq
apt-get install -y -qq git curl openssl

if [ -d "${TPROXY_SRC}/.git" ]; then
    git -C "$TPROXY_SRC" pull --ff-only
else
    rm -rf "$TPROXY_SRC"
    git clone "$TPROXY_REPO" "$TPROXY_SRC"
fi

echo "=== 3. Временная остановка Apache2 на время работы установщика tproxy-server ==="
# Установщик tproxy-server поднимает Caddy на 80/443 для проверки;
# после него мы отключим Caddy и вернём Apache2 с нашим Let's Encrypt SSL.
systemctl stop apache2 || true

trap 'systemctl start apache2 >/dev/null 2>&1 || true' ERR

echo "=== 4. Запуск официального установщика tproxy-server ==="
cd "$TPROXY_SRC"
./deploy/install.sh \
    --hostname "$DOMAIN" \
    --email "$EMAIL" \
    --site-upstream "http://127.0.0.1:${UPSTREAM_PORT}" \
    --base-path none \
    --secret "$SECRET"

echo "=== 5. Отключение Caddy (порты 80/443 остаются за Apache2) ==="
systemctl disable --now caddy.service >/dev/null 2>&1 || true

echo "=== 6. Настройка Apache2: локальный upstream (127.0.0.1:${UPSTREAM_PORT}) + HTTPS/WebSocket прокси (:443) ==="
a2enmod proxy proxy_http proxy_wstunnel rewrite ssl >/dev/null

# Добавляем Listen 127.0.0.1:8088 в ports.conf, если ещё не добавлен
PORTS_CONF="/etc/apache2/ports.conf"
if ! grep -q "127.0.0.1:${UPSTREAM_PORT}" "$PORTS_CONF"; then
    echo "Listen 127.0.0.1:${UPSTREAM_PORT}" >> "$PORTS_CONF"
fi

# Внутренний VirtualHost для отдачи реального сайта energy_monitor_syte через tproxy-server
UPSTREAM_CONF="/etc/apache2/sites-available/power_site-upstream.conf"
cat > "$UPSTREAM_CONF" <<EOL
<VirtualHost 127.0.0.1:${UPSTREAM_PORT}>
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}
    DocumentRoot ${SITE_DIR}

    <Directory ${SITE_DIR}>
        AllowOverride All
        Require local
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/power_site_upstream_error.log
    CustomLog \${APACHE_LOG_DIR}/power_site_upstream_access.log combined
</VirtualHost>
EOL
a2ensite power_site-upstream.conf >/dev/null

# Бэкап текущего SSL-конфига Apache и обновление под проксирование в tproxy-server
SSL_CONF="/etc/apache2/sites-available/power_site-ssl.conf"
if [ -f "$SSL_CONF" ]; then
    cp "$SSL_CONF" "${SSL_CONF}.bak.$(date +%Y%m%d_%H%M%S)"
fi

cat > "$SSL_CONF" <<EOL
<VirtualHost *:443>
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/${DOMAIN}/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/${DOMAIN}/privkey.pem

    Protocols h2 http/1.1
    TimeOut 3600

    ProxyPreserveHost On
    ProxyRequests Off

    # Проброс WebSocket-соединений Telegram WEB-proxy
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} =websocket [NC]
    RewriteRule ^/(.*) ws://127.0.0.1:${RELAY_PORT}/\$1 [P,L]

    # Проброс остальных HTTPS-запросов в tproxy-server
    # Обычные запросы без bridge-ключа tproxy-server сам отдаст на 127.0.0.1:${UPSTREAM_PORT}
    ProxyPass / http://127.0.0.1:${RELAY_PORT}/
    ProxyPassReverse / http://127.0.0.1:${RELAY_PORT}/

    ErrorLog \${APACHE_LOG_DIR}/power_site_ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/power_site_ssl_access.log combined
</VirtualHost>
EOL

a2ensite power_site-ssl.conf >/dev/null

echo "=== 7. Проверка конфигурации и запуск Apache2 ==="
apache2ctl configtest
systemctl start apache2

echo "=== 8. Проверка готовности сервисов ==="
sleep 2
curl --fail --silent http://127.0.0.1:8081/readyz >/dev/null && echo "✅ tproxy-server (127.0.0.1:${RELAY_PORT}) работает"
systemctl is-active --quiet mtproxy.service && echo "✅ mtproxy.service активен"
systemctl is-active --quiet apache2.service && echo "✅ apache2.service активен"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "✅ Telegram WEB-proxy установлен на https://${DOMAIN}/"
echo "════════════════════════════════════════════════════════════"
echo "🌐 Сайт в браузере:  https://${DOMAIN}/ (работает как раньше)"
echo "📡 Proxy server:     ${DOMAIN}"
echo "🔑 Proxy secret:     ${SECRET}"
echo "🔗 Ссылка для TG:    https://t.me/webproxy?server=${DOMAIN}&secret=${SECRET}"
echo "════════════════════════════════════════════════════════════"
