# ⚡ Energy Monitor Syte

Веб-приложение для отображения и анализа данных энергомониторинга.  
Сайт написан на **PHP**, использует **MySQL** и работает на сервере с **Apache (LAMP)**.

---

## 🚀 Установка на VPS (Ubuntu)

### 1. Подготовка сервера

Подключись к серверу по SSH и выполни:

```bash
sudo apt update
sudo apt install git -y
```

---

### 2. Клонирование репозитория

```bash
sudo git clone https://github.com/tyretoff/energy_monitor_syte.git /var/www/power_site
```

---

### 3. Установка всего окружения

```bash
wget https://raw.githubusercontent.com/tyretoff/energy_monitor_syte/master/deploy_ip.sh
chmod +x deploy_ip.sh
./deploy_ip.sh
```

Скрипт автоматически:
- Установит **Apache, MySQL, PHP**
- Создаст базу данных и пользователя
- Импортирует структуру и данные из `s817757_power.sql`
- Настроит Apache на работу по IP (без домена)
- Установит **phpMyAdmin**
- Подтянет код сайта из GitHub

---

### 4. Проверка работы

```
http://<IP_твоего_сервера>/
http://<IP_твоего_сервера>/phpmyadmin/
```

---

### 5. Настройка базы данных

Файл конфигурации: `CFG/config.php`  
Скрипт берёт из него `$dbname`, `$dbuser`, `$dbpass`.

---

### 6. Обновление сайта

```bash
cd /var/www/power_site
git pull
sudo systemctl reload apache2
```

---

### 7. Подключение домена и HTTPS

Когда появится домен, можно запустить расширенный скрипт с поддержкой Let's Encrypt.

---

## 🧰 Ошибки и отладка

Если сайт не открывается, проверь логи:

**Apache:**
```bash
sudo tail -n 30 /var/log/apache2/error.log
```

**MySQL:**
```bash
sudo systemctl status mysql
sudo journalctl -u mysql -n 20
```

**phpMyAdmin:**
Если не открывается `/phpmyadmin/`, проверь:
```bash
sudo a2enconf phpmyadmin.conf
sudo systemctl reload apache2
```

---

## 📂 Структура проекта

```
CFG/                # Настройки подключения к базе
s817757_power.sql   # Дамп базы данных
index.php           # Главная страница
deploy_ip.sh        # Скрипт установки
```

---

## 🧠 Автор

Проект: [tyretoff](https://github.com/tyretoff)
