#!/bin/bash
set -e

SITE_DIR="/var/www/power_site"
GIT_REPO="https://github.com/tyretoff/energy_monitor_syte.git"
TIMEZONE="Europe/Moscow"

echo "=== Обновляем систему и ставим LAMP ==="
sudo apt update
sudo apt install -y apache2 mysql-server php libapache2-mod-php php-mysql unzip wget git

echo "=== Определяем версию PHP и устанавливаем php-curl ==="
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)
if [ -n "$PHP_VERSION" ]; then
    echo "📦 Установлена PHP $PHP_VERSION — ставим php${PHP_VERSION}-curl"
    sudo apt install -y php${PHP_VERSION}-curl
else
    echo "⚠️ Не удалось определить версию PHP, пробуем установить php-curl"
    sudo apt install -y php-curl
fi
sudo systemctl restart apache2

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

echo "=== Проверяем и обновляем структуру таблицы (миграция колонок энергии) ==="
sudo mysql ${DB_NAME} -e "ALTER TABLE t_power3 ADD COLUMN energy decimal(10,2) DEFAULT NULL;" 2>/dev/null || true
sudo mysql ${DB_NAME} -e "ALTER TABLE t_power3 ADD COLUMN energy_t1 decimal(10,2) DEFAULT NULL;" 2>/dev/null || true
sudo mysql ${DB_NAME} -e "ALTER TABLE t_power3 ADD COLUMN energy_t2 decimal(10,2) DEFAULT NULL;" 2>/dev/null || true
sudo mysql ${DB_NAME} -e "ALTER TABLE t_power3 ADD COLUMN energy_t3 decimal(10,2) DEFAULT NULL;" 2>/dev/null || true
echo "ℹ️ Проверка структуры t_power3 завершена"

echo "=== Проверяем и создаём таблицу для логгера SDM01 ==="
sudo mysql ${DB_NAME} -e "CREATE TABLE IF NOT EXISTS t_power_sdm LIKE t_power3;" 2>/dev/null || true

echo "=== Проверяем и настраиваем Apache (HTTP) ==="
VHOST_FILE="/etc/apache2/sites-available/power_site.conf"
SERVER_IP=$(hostname -I | awk '{print $1}')

# Создаём простой HTTP конфиг
sudo bash -c "cat > $VHOST_FILE" <<EOL
<VirtualHost *:80>
    ServerName ${SERVER_IP}
    DocumentRoot $SITE_DIR

    <Directory $SITE_DIR>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/power_site_error.log
    CustomLog \${APACHE_LOG_DIR}/power_site_access.log combined
</VirtualHost>
EOL

echo "✅ HTTP конфигурация создана для IP: ${SERVER_IP}"

echo "=== Активируем сайт и отключаем дефолтный Apache ==="
sudo a2ensite power_site.conf > /dev/null 2>&1 || true
sudo a2dissite 000-default.conf > /dev/null 2>&1 || true
sudo a2enmod rewrite > /dev/null 2>&1 || true

echo "=== Перезапускаем сервисы ==="
sudo systemctl restart mysql
sudo systemctl restart apache2

CURRENT_ROOT=$(sudo apache2ctl -S 2>/dev/null | grep "DocumentRoot" | awk '{print $2}')
if [ "$CURRENT_ROOT" = "/var/www/power_site" ]; then
    echo "✅ Apache настроен правильно. Сайт доступен по IP."
else
    echo "⚠️ Внимание: DocumentRoot сейчас $CURRENT_ROOT — возможно, включен дефолтный сайт."
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
echo "🌐 Сайт (Меркурий):  http://${SERVER_IP}/"
echo "🌐 Сайт (SDM01):      http://${SERVER_IP}/sdm/"
echo "🛠  phpMyAdmin:       http://${SERVER_IP}/phpmyadmin/"
echo "📂 Код сайта:        $SITE_DIR"
echo "💾 Конфигурация БД:  CFG/config.php"
echo "🔄 Обновить код:     cd $SITE_DIR && git pull"
echo ""
echo "💡 Для установки с HTTPS используйте deploy_ip_https.sh"
echo "════════════════════════════════════════════════════════════"