#!/bin/bash
# Переключает Apache с порта 8443 на стандартный 443
set -e

DOMAIN="elbs.ru"

echo "=== Проверяем, свободен ли порт 443 ==="
if sudo ss -tlnp | grep -q ':443'; then
    echo "❌ Порт 443 уже занят:"
    sudo ss -tlnp | grep ':443'
    echo "Прерываем. Освободи порт и запусти снова."
    exit 1
else
    echo "✅ Порт 443 свободен"
fi

echo "=== Обновляем ports.conf ==="
sudo bash -c "cat > /etc/apache2/ports.conf" <<'EOF'
# If you just change the port or add more ports here, you will likely also
# have to change the VirtualHost statement in
# /etc/apache2/sites-enabled/000-default.conf

Listen 80

<IfModule ssl_module>
    Listen 443
</IfModule>

<IfModule mod_gnutls.c>
    Listen 443
</IfModule>
EOF
echo "✅ ports.conf обновлён"

echo "=== Обновляем HTTPS виртуальный хост ==="
SSL_CONF="/etc/apache2/sites-available/power_site-ssl.conf"
if [ -f "$SSL_CONF" ]; then
    sudo sed -i 's/<VirtualHost \*:8443>/<VirtualHost *:443>/' "$SSL_CONF"
    echo "✅ power_site-ssl.conf: порт изменён на 443"
else
    echo "❌ Файл $SSL_CONF не найден!"
    exit 1
fi

echo "=== Обновляем редирект в HTTP конфиге ==="
HTTP_CONF="/etc/apache2/sites-available/power_site.conf"
if [ -f "$HTTP_CONF" ]; then
    sudo sed -i 's|https://%{HTTP_HOST}:8443|https://%{HTTP_HOST}|g' "$HTTP_CONF"
    echo "✅ power_site.conf: редирект обновлён (убран :8443)"
else
    echo "❌ Файл $HTTP_CONF не найден!"
    exit 1
fi

echo "=== Проверяем конфигурацию Apache ==="
sudo apache2ctl configtest

echo "=== Перезапускаем Apache ==="
sudo systemctl restart apache2
echo "✅ Apache перезапущен"

echo ""
echo "=== Проверка ==="
echo "Порты Apache:"
sudo ss -tlnp | grep apache2 || sudo ss -tlnp | grep ':443\|:80'

echo ""
echo "════════════════════════════════════"
echo "✅ Готово! Сайт доступен по адресу:"
echo "   https://${DOMAIN}/"
echo "════════════════════════════════════"
