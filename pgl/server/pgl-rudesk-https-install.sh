#!/usr/bin/env bash
# =====================================================================
#  HTTPS для PGL-RUDesk: сайт, панель администратора и API на домене.
#  Бесплатный сертификат Let's Encrypt, продлевается автоматически.
#
#  Запуск:  bash pgl-rudesk-https-install.sh pgl-rudesk.ddns.info
#  Нужны: сайт (pgl-rudesk-site-install.sh) и, по желанию, сервер
#  аккаунтов (pgl-rudesk-api-install.sh).
# =====================================================================
set -euo pipefail

DOMAIN="${1:-}"
SITE_DIR="/var/www/pgl-rudesk"
API_ENV="/etc/pgl-rudesk-api.env"
API_INTERNAL="127.0.0.1:21124"
ADMIN_PATH="pgl-odmin"
CONF="/etc/nginx/sites-available/pgl-rudesk"

green() { echo -e "\e[32m$*\e[0m"; }
yellow(){ echo -e "\e[33m$*\e[0m"; }
red()   { echo -e "\e[31m$*\e[0m"; }

[[ $EUID -eq 0 ]] || { red "Запустите от root"; exit 1; }
[[ -n "$DOMAIN" ]] || { red "Укажите домен:  bash $0 pgl-rudesk.ddns.info"; exit 1; }
[[ -f "$SITE_DIR/index.html" ]] || { red "Сначала установите сайт (pgl-rudesk-site-install.sh)"; exit 1; }

green "==> Проверка домена $DOMAIN"
MY_IP="$(curl -4 -fs --max-time 5 https://ifconfig.me || hostname -I | awk '{print $1}')"
DNS_IP="$(getent ahostsv4 "$DOMAIN" | awk 'NR==1{print $1}')"
if [[ -z "$DNS_IP" ]]; then
  red "Домен $DOMAIN пока не находится в DNS."
  red "Укажите в панели DNS-сервиса адрес $MY_IP и подождите 5–30 минут."
  exit 1
fi
if [[ "$DNS_IP" != "$MY_IP" ]]; then
  red "Домен указывает на $DNS_IP, а у этого сервера адрес $MY_IP."
  red "Исправьте адрес в панели DNS-сервиса и запустите скрипт снова."
  exit 1
fi
green "  $DOMAIN → $MY_IP"

green "==> Установка certbot"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx certbot python3-certbot-nginx >/dev/null

API_BLOCK=""
if [[ -f "$API_ENV" ]]; then
  API_BLOCK="
    location = /${ADMIN_PATH} { return 301 /${ADMIN_PATH}/; }
    location /${ADMIN_PATH}/ {
        proxy_pass http://${API_INTERNAL}/_admin/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location /_admin { return 404; }
    location /api/pgl/ {
        proxy_pass http://127.0.0.1:21125;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
    location /api/ {
        proxy_pass http://${API_INTERNAL};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }"
fi

green "==> Настройка nginx"
cat > "$CONF" <<EOF
# PGL-RUDesk HTTPS
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${DOMAIN} _;
    root ${SITE_DIR};
    index index.html;
    server_tokens off;
    client_max_body_size 20m;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    location / { try_files \$uri \$uri/ =404; }
${API_BLOCK}
}
EOF
ln -sf "$CONF" /etc/nginx/sites-enabled/pgl-rudesk
rm -f /etc/nginx/sites-enabled/default
nginx -t -q
systemctl reload nginx

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
fi

green "==> Получение сертификата Let's Encrypt"
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos \
  --register-unsafely-without-email --redirect --keep-until-expiring || {
  red "Сертификат не получен. Частые причины:"
  red "  - порт 80 закрыт у хостера (нужен для проверки домена);"
  red "  - превышен лимит Let's Encrypt для домена ${DOMAIN#*.} — повторите через несколько часов."
  exit 1
}

if [[ -f "$API_ENV" ]]; then
  sed -i "s|^RUSTDESK_API_RUSTDESK_API_SERVER=.*|RUSTDESK_API_RUSTDESK_API_SERVER=https://${DOMAIN}|" "$API_ENV"
  systemctl restart pgl-rudesk-api
fi

green "==> Проверка"
sleep 2
curl -fsS -o /dev/null "https://${DOMAIN}/" && green "  Сайт по HTTPS: OK" || yellow "  Сайт по HTTPS не отвечает"
if [[ -f "$API_ENV" ]]; then
  curl -fsS -o /dev/null "https://${DOMAIN}/api/login-options" && green "  API по HTTPS: OK" || yellow "  API по HTTPS не отвечает"
fi

echo
green "================================================================"
green "  HTTPS включён"
green "================================================================"
echo "  Сайт           : https://${DOMAIN}"
if [[ -f "$API_ENV" ]]; then
  echo "  Панель админа  : https://${DOMAIN}/${ADMIN_PATH}/"
  echo "  API приложения : https://${DOMAIN}"
fi
echo "  Сертификат продлевается автоматически (certbot.timer)."
green "================================================================"
