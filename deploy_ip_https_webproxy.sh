#!/bin/bash
# Полное развертывание Energy Monitor Site (HTTPS) + Telegram WEB-proxy на основном домене.
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/tyretoff/energy_monitor_syte/master"
SITE_DIR="/var/www/power_site"

# Поддержка передачи секрета через аргумент --secret или переменную WEBPROXY_SECRET
while [[ $# -gt 0 ]]; do
    case "$1" in
        --secret)
            export WEBPROXY_SECRET="${2:-}"
            shift 2
            ;;
        *)
            echo "Использование: $0 [--secret 32_hex_секрет]" >&2
            exit 2
            ;;
    esac
done

echo "=== Этап 1/2: Развертывание Energy Monitor Site с HTTPS ==="
if [ -f "./deploy_ip_https.sh" ]; then
    chmod +x ./deploy_ip_https.sh
    ./deploy_ip_https.sh
else
    wget -qO deploy_ip_https.sh "${REPO_RAW}/deploy_ip_https.sh"
    chmod +x deploy_ip_https.sh
    ./deploy_ip_https.sh
fi

echo "=== Этап 2/2: Установка Telegram WEB-proxy (tproxy-server + MTProxy) ==="
if [ ! -f "${SITE_DIR}/install_webproxy.sh" ]; then
    wget -qO "${SITE_DIR}/install_webproxy.sh" "${REPO_RAW}/install_webproxy.sh"
fi

chmod +x "${SITE_DIR}/install_webproxy.sh"
sudo WEBPROXY_SECRET="${WEBPROXY_SECRET:-}" "${SITE_DIR}/install_webproxy.sh"
