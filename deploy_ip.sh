#!/bin/bash
set -e

SITE_DIR="/var/www/power_site"
GIT_REPO="https://github.com/tyretoff/energy_monitor_syte.git"
TIMEZONE="Europe/Moscow"
DOMAIN="elbs.ru"
HTTPS_PORT="8443"
EMAIL="admin@${DOMAIN}"  # Email для Let's Encrypt уведомлений

echo "=== Обновляем систему и ставим LAMP ==="
sudo apt update
sudo apt install -y apache2 mysql-server php libapache2-mod-php php-mysql unzip wget git certbot python3-certbot-apache

echo "=== Настраиваем часовой пояс системы ==="
sudo timedatectl set-timezone $TIMEZONE
echo "✅ Системное время: $(date)"

echo "=== Настраиваем часовой пояс PHP ==="
PHP_INI_APACHE=$(php -r "echo php_ini_loaded_file();" 2>/dev/null || echo "/etc/php/8.3/apache2/php.ini")
PHP_INI_CLI="/etc/php/8.3/cli/php.ini"

# Настраиваем PHP для Apache
if [ -f "$PHP_INI_APACHE" ]; then
    sudo sed -i "s|;date.timezone =.*|date.timezone = $TIMEZONE|" "$PHP_INI_APACHE"
    sudo sed -i "s|date.timezone =.*|date.timezone = $TIMEZONE|" "$PHP_INI_APACHE"
    echo "✅ PHP Apache timezone: $TIMEZONE"
fi

# Настраиваем PHP CLI
if [ -f "$PHP_INI_CLI" ]; then
    sudo sed -i "s|;date.timezone =.*|date.timezone = $TIMEZONE|" "$PHP_INI_CLI"
    sudo sed -i "s|date.timezone =.*|date.timezone = $TIMEZONE|" "$PHP_INI_CLI"
fi

echo "=== Настраиваем часовой пояс MySQL ==="
MYSQL_CONF="/etc/mysql/mysql.conf.d/mysqld.cnf"
if ! grep -q "default-time-zone" "$MYSQL_CONF"; then
    echo -e "\n# Timezone settings\ndefault-time-zone = '+03:00'" | sudo tee -a "$MYSQL_CONF" > /dev/null
    echo "✅ MySQL timezone: +03:00"
else
    echo "⚠️ MySQL timezone уже настроен"
fi

echo "=== Подтягиваем код сайта с GitHub ==="
if [ -d "$SITE_DIR/.git" ]; then
    cd $SITE_DIR && git pull
else
    sudo rm -rf $SITE_DIR
    sudo git clone $GIT_REPO $SITE_DIR
    sudo chown -R $USER:$USER $SITE_DIR
fi

echo "=== Читаем параметры из config.php ==="
CONFIG_FILE="$SITE_DIR/CFG/config.php"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Файл $CONFIG_FILE не найден. Проверь структуру проекта."
    exit 1
fi

# Исправленный парсинг для формата массива PHP
DB_NAME=$(grep -oP "'dbname'\s*=>\s*'\K[^']+" "$CONFIG_FILE")
DB_USER=$(grep -oP "'username'\s*=>\s*'\K[^']+" "$CONFIG_FILE")
DB_PASS=$(grep -oP "'password'\s*=>\s*'\K[^']+" "$CONFIG_FILE")

if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]; then
    echo "❌ Не удалось извлечь параметры БД из $CONFIG_FILE"
    echo "Проверь формат файла конфигурации."
    exit 1
fi

echo "📦 Найдено:"
echo "  БД: $DB_NAME"
echo "  Пользователь: $DB_USER"
echo "  Пароль: $DB_PASS"

SQL_FILE="$SITE_DIR/s817757_power.sql"
DB_EXISTS=$(sudo mysql -sse "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${DB_NAME}'")

if [ "$DB_EXISTS" == "${DB_NAME}" ]; then
    echo "⚠️ База ${DB_NAME} уже существует — импорт пропущен."
else
    echo "=== Создаём базу и пользователя MySQL ==="
    sudo mysql -e "CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
    sudo mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
    sudo mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
    sudo mysql -e "FLUSH PRIVILEGES;"

    if [ -f "$SQL_FILE" ]; then
        echo "=== Импортируем SQL-дамп из репозитория ==="
        mysql -u ${DB_USER} -p${DB_PASS} ${DB_NAME} < "$SQL_FILE"
        echo "✅ Дамп успешно импортирован"
    else
        echo "⚠️ Файл $SQL_FILE не найден в репозитории!"
    fi
fi

echo "=== Проверяем и настраиваем Apache (HTTP) ==="
VHOST_FILE="/etc/apache2/sites-available/power_site.conf"
SERVER_IP=$(hostname -I | awk '{print $1}')

# Создаём HTTP конфиг
sudo bash -c "cat > $VHOST_FILE" <<EOL
<VirtualHost *:80>
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}
    DocumentRoot $SITE_DIR

    <Directory $SITE_DIR>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/power_site_error.log
    CustomLog \${APACHE_LOG_DIR}/power_site_access.log combined

    # Редирект на HTTPS
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}:${HTTPS_PORT}\$1 [R=301,L]
</VirtualHost>
EOL

echo "=== Настраиваем Apache для порта ${HTTPS_PORT} ==="
PORTS_CONF="/etc/apache2/ports.conf"
if ! grep -q "Listen ${HTTPS_PORT}" "$PORTS_CONF"; then
    echo "Listen ${HTTPS_PORT}" | sudo tee -a "$PORTS_CONF" > /dev/null
    echo "✅ Добавлен порт ${HTTPS_PORT} в ports.conf"
fi

echo "=== Получаем SSL сертификат от Let's Encrypt ==="
# Проверяем, существует ли уже сертификат
if [ ! -d "/etc/letsencrypt/live/${DOMAIN}" ]; then
    echo "🔒 Запрашиваем новый сертификат для ${DOMAIN}..."
    sudo certbot certonly --apache --non-interactive --agree-tos --email ${EMAIL} \
        -d ${DOMAIN} -d www.${DOMAIN} || {
        echo "⚠️ Не удалось получить сертификат. Проверь DNS настройки домена ${DOMAIN}"
        echo "Продолжаем без HTTPS..."
    }
else
    echo "✅ Сертификат для ${DOMAIN} уже существует"
fi

# Создаём HTTPS конфиг на порту 8443
if [ -d "/etc/letsencrypt/live/${DOMAIN}" ]; then
    echo "=== Создаём HTTPS конфигурацию ==="
    VHOST_SSL_FILE="/etc/apache2/sites-available/power_site-ssl.conf"
    
    sudo bash -c "cat > $VHOST_SSL_FILE" <<EOL
<VirtualHost *:${HTTPS_PORT}>
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}
    DocumentRoot $SITE_DIR

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/${DOMAIN}/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/${DOMAIN}/privkey.pem

    <Directory $SITE_DIR>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/power_site_ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/power_site_ssl_access.log combined
</VirtualHost>
EOL

    sudo a2ensite power_site-ssl.conf > /dev/null 2>&1 || true
    echo "✅ HTTPS конфигурация создана на порту ${HTTPS_PORT}"
fi

echo "=== Активируем сайт и модули Apache ==="
sudo a2ensite power_site.conf > /dev/null 2>&1 || true
sudo a2dissite 000-default.conf > /dev/null 2>&1 || true
sudo a2enmod ssl > /dev/null 2>&1 || true
sudo a2enmod rewrite > /dev/null 2>&1 || true

echo "=== Перезапускаем сервисы ==="
sudo systemctl restart mysql
sudo systemctl restart apache2

echo "=== Настраиваем автообновление сертификатов ==="
# Certbot автоматически добавляет cron job, проверим его
if sudo systemctl is-active --quiet certbot.timer; then
    echo "✅ Автообновление сертификатов активно"
else
    sudo systemctl enable certbot.timer
    sudo systemctl start certbot.timer
    echo "✅ Включено автообновление сертификатов"
fi

CURRENT_ROOT=$(sudo apache2ctl -S 2>/dev/null | grep "DocumentRoot" | awk '{print $2}')
if [ "$CURRENT_ROOT" = "/var/www/power_site" ]; then
    echo "✅ Apache настроен правильно"
else
    echo "⚠️ Внимание: DocumentRoot сейчас $CURRENT_ROOT"
fi

echo "=== Устанавливаем phpMyAdmin ==="
sudo apt install -y phpmyadmin

if [ ! -f /etc/apache2/conf-enabled/phpmyadmin.conf ]; then
    echo "Include /etc/phpmyadmin/apache.conf" | sudo tee /etc/apache2/conf-available/phpmyadmin.conf
    sudo a2enconf phpmyadmin.conf
    sudo systemctl reload apache2
fi

echo ""
echo "=== Проверка настроек времени ==="
echo "🕐 Системное время:  $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "🕐 PHP timezone:     $(php -r 'echo date_default_timezone_get();')"
echo "🕐 MySQL время:      $(mysql -u ${DB_USER} -p${DB_PASS} -sse 'SELECT NOW();' 2>/dev/null || echo 'N/A')"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "✅ Всё готово!"
echo "════════════════════════════════════════════════════════════"
echo "🌐 HTTP (редирект):  http://${DOMAIN}/"
if [ -d "/etc/letsencrypt/live/${DOMAIN}" ]; then
    echo "🔒 HTTPS:            https://${DOMAIN}:${HTTPS_PORT}/"
fi
echo "🛠  phpMyAdmin:       http://${SERVER_IP}/phpmyadmin/"
echo "📂 Код сайта:        $SITE_DIR"
echo "💾 Конфигурация БД:  CFG/config.php"
echo "🔄 Обновить код:     cd $SITE_DIR && git pull"
echo ""
echo "📝 Важно: Убедись, что домен ${DOMAIN} указывает на IP ${SERVER_IP}"
echo "🔥 Firewall: Открой порт ${HTTPS_PORT} если используешь UFW/iptables"
echo "════════════════════════════════════════════════════════════"
