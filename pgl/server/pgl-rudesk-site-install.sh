#!/usr/bin/env bash
# =====================================================================
#  Сайт PGL-RUDesk на VPS (nginx). Ubuntu / Debian.
#  Запуск:  bash pgl-rudesk-site-install.sh
#  Повторный запуск = обновление страницы.
# =====================================================================
set -euo pipefail
SITE_DIR="/var/www/pgl-rudesk"

green() { echo -e "\e[32m$*\e[0m"; }
[[ $EUID -eq 0 ]] || { echo "Запустите от root"; exit 1; }

green "==> Установка nginx"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx >/dev/null

green "==> Копирование страницы"
install -d "$SITE_DIR"
echo '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' | base64 -d | gunzip > "$SITE_DIR/index.html"

cat > /etc/nginx/sites-available/pgl-rudesk <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/pgl-rudesk;
    index index.html;
    server_tokens off;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    location / { try_files $uri $uri/ =404; }
}
NGINX
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/pgl-rudesk /etc/nginx/sites-enabled/pgl-rudesk
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
green "================================================================"
echo "  Если страница не открывается — откройте порт 80 (TCP)"
echo "  в файрволе панели хостера."
