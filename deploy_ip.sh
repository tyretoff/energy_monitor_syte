#!/bin/bash
set -e

SITE_DIR="/var/www/power_site"
GIT_REPO="https://github.com/tyretoff/energy_monitor_syte.git"

echo "=== Обновляем систему и ставим LAMP ==="
sudo apt update
sudo apt install -y apache2 mysql-server php libapache2-mod-php php-mysql unzip wget git

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

DB_NAME=$(grep -oP '\$dbname\s*=\s*"\K[^"]+' "$CONFIG_FILE")
DB_USER=$(grep -oP '\$dbuser\s*=\s*"\K[^"]+' "$CONFIG_FILE")
DB_PASS=$(grep -oP '\$dbpass\s*=\s*"\K[^"]+' "$CONFIG_FILE")

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

echo "=== Настраиваем Apache на IP ==="
VHOST_FILE="/etc/apache2/sites-available/power_site.conf"
SERVER_IP=$(hostname -I | awk '{print $1}')

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

echo "=== Активируем сайт и отключаем дефолтный Apache ==="
sudo a2ensite power_site.conf > /dev/null 2>&1 || true
sudo a2dissite 000-default.conf > /dev/null 2>&1 || true
sudo a2enmod rewrite > /dev/null 2>&1 || true
sudo systemctl reload apache2
sudo systemctl restart apache2

CURRENT_ROOT=$(sudo apache2ctl -S 2>/dev/null | grep "DocumentRoot" | awk '{print $2}')
if [ "$CURRENT_ROOT" = "/var/www/power_site" ]; then
    echo "✅ Apache настроен правильно. Сайт будет доступен по IP."
else
    echo "⚠️ Внимание: DocumentRoot сейчас $CURRENT_ROOT — возможно, включен дефолтный сайт."
    echo "Попробуй выполнить вручную: sudo a2ensite power_site.conf && sudo a2dissite 000-default.conf && sudo systemctl reload apache2"
fi

echo "=== Устанавливаем phpMyAdmin ==="
sudo apt install -y phpmyadmin

if [ ! -f /etc/apache2/conf-enabled/phpmyadmin.conf ]; then
    echo "Include /etc/phpmyadmin/apache.conf" | sudo tee /etc/apache2/conf-available/phpmyadmin.conf
    sudo a2enconf phpmyadmin.conf
    sudo systemctl reload apache2
fi

echo "=== Всё готово! ==="
echo "🌐 Сайт:        http://${SERVER_IP}/"
echo "🛠 phpMyAdmin:  http://${SERVER_IP}/phpmyadmin/"
echo "📂 Код сайта:   $SITE_DIR"
echo "💾 Конфигурация БД: CFG/config.php"
echo "🔄 Обновить код вручную: cd $SITE_DIR && git pull"
