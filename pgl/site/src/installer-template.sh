#!/usr/bin/env bash
# =====================================================================
#  Сайт PGL-RUDesk на VPS (nginx): главная страница и личный кабинет.
#  Ubuntu / Debian.
#  Запуск:  bash pgl-rudesk-site-install.sh
#  Повторный запуск = обновление страниц.
# =====================================================================
set -euo pipefail
SITE_DIR="/var/www/pgl-rudesk"
API_INTERNAL="127.0.0.1:21124"
ADMIN_PATH="pgl-odmin"

green() { echo -e "\e[32m$*\e[0m"; }
[[ $EUID -eq 0 ]] || { echo "Запустите от root"; exit 1; }

green "==> Установка nginx"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx >/dev/null

green "==> Копирование страниц"
install -d "$SITE_DIR"
rm -rf "$SITE_DIR/account"
echo '__PAYLOAD__' | base64 -d | tar -xz -C "$SITE_DIR"

if grep -q 'PGL-RUDesk HTTPS' /etc/nginx/sites-available/pgl-rudesk 2>/dev/null; then
  green "==> HTTPS уже настроен, конфигурацию nginx не трогаю"
else
cat > /etc/nginx/sites-available/pgl-rudesk <<NGINX
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root ${SITE_DIR};
    index index.html;
    server_tokens off;
    client_max_body_size 20m;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    location / { try_files \$uri \$uri/ =404; }

    location = /${ADMIN_PATH} { return 301 /${ADMIN_PATH}/; }
    location /${ADMIN_PATH}/ {
        proxy_pass http://${API_INTERNAL}/_admin/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location /_admin { return 404; }
    location /api/ {
        proxy_pass http://${API_INTERNAL};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINX
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/pgl-rudesk /etc/nginx/sites-enabled/pgl-rudesk
fi
nginx -t -q
systemctl enable --now nginx >/dev/null
systemctl reload nginx

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow 80/tcp >/dev/null
fi

IP="$(curl -4 -fs --max-time 5 https://ifconfig.me || hostname -I | awk '{print $1}')"
echo
green "================================================================"
green "  Сайт PGL-RUDesk опубликован:  http://$IP"
green "  Личный кабинет:               http://$IP/account/"
green "================================================================"
echo "  Регистрация и вход в кабинет работают, когда установлен сервер"
echo "  аккаунтов (pgl-rudesk-api-install.sh)."
echo "  Если страница не открывается — откройте порт 80 (TCP)"
echo "  в файрволе панели хостера."
