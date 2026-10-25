#!/usr/bin/env bash
# =====================================================================
#  Почта PGL-RUDesk: восстановление пароля по почте + раздел «Почта»
#  в панели администратора. Свой почтовый сервер (Postfix, только отправка).
#
#  Запуск:  bash pgl-rudesk-mail-install.sh pgl-rudesk.ddns.info
#  Через внешний ящик (если письма не доходят):
#           bash pgl-rudesk-mail-install.sh pgl-rudesk.ddns.info --relay smtp.yandex.ru:465 box@yandex.ru
#  Нужен установленный сервер аккаунтов (pgl-rudesk-api-install.sh).
#  Повторный запуск = обновление (журнал писем сохраняется).
# =====================================================================
set -euo pipefail

DOMAIN="${1:-}"
RELAY="" ; RELAY_USER=""
if [[ "${2:-}" == "--relay" ]]; then RELAY="${3:-}"; RELAY_USER="${4:-}"; fi

API_DIR="/opt/pgl-rudesk-api"
API_ENV="/etc/pgl-rudesk-api.env"
MAIL_DIR="/opt/pgl-rudesk-mail"
MAIL_ENV="/etc/pgl-rudesk-mail.env"
SVC_USER="pgl-rudesk-api"

green() { echo -e "\e[32m$*\e[0m"; }
yellow(){ echo -e "\e[33m$*\e[0m"; }
red()   { echo -e "\e[31m$*\e[0m"; }

[[ $EUID -eq 0 ]] || { red "Запустите от root"; exit 1; }
[[ -n "$DOMAIN" ]] || { red "Укажите домен:  bash $0 pgl-rudesk.ddns.info"; exit 1; }
[[ -f "$API_ENV" && -x "$API_DIR/apimain" ]] || { red "Сначала установите сервер аккаунтов (pgl-rudesk-api-install.sh)"; exit 1; }
if [[ -n "$RELAY" && ( -z "$RELAY_USER" || "$RELAY" != *:* ) ]]; then
  red "Формат:  --relay smtp.yandex.ru:465 box@yandex.ru"; exit 1
fi

MODE="local"; SMTP_HOST="127.0.0.1"; SMTP_PORT="25"; SMTP_PASS=""
if [[ -n "$RELAY" ]]; then
  SMTP_HOST="${RELAY%:*}"; SMTP_PORT="${RELAY##*:}"
  [[ "$SMTP_PORT" == "465" ]] && MODE="ssl" || MODE="starttls"
  read -r -s -p "Пароль приложения для $RELAY_USER (ввод скрыт): " SMTP_PASS; echo
  [[ -n "$SMTP_PASS" ]] || { red "Пароль не введён"; exit 1; }
fi

green "==> Установка пакетов"
apt-get update -qq
if [[ "$MODE" == "local" ]]; then
  echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
  echo "postfix postfix/mailname string $DOMAIN" | debconf-set-selections
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postfix python3 >/dev/null

  green "==> Настройка Postfix (только отправка)"
  echo "$DOMAIN" > /etc/mailname
  postconf -e "myhostname = $DOMAIN" "myorigin = $DOMAIN" "mydestination = localhost" \
    "inet_interfaces = loopback-only" "inet_protocols = ipv4" "mynetworks = 127.0.0.0/8" \
    "relayhost =" "smtp_tls_security_level = may" "smtputf8_enable = yes" \
    "maximal_queue_lifetime = 1d" "bounce_queue_lifetime = 1d"
  systemctl enable postfix >/dev/null 2>&1 || true
  systemctl restart postfix
  if timeout 7 bash -c '</dev/tcp/gmail-smtp-in.l.google.com/25' 2>/dev/null; then
    green "  Исходящий порт 25 открыт"
  else
    yellow "  Исходящий порт 25 закрыт хостером — письма не уйдут."
    yellow "  Коды всё равно будут видны в админке (раздел «Почта»)."
    yellow "  Или используйте внешний ящик:  --relay smtp.yandex.ru:465 box@yandex.ru"
  fi
else
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 >/dev/null
fi

green "==> Служба восстановления пароля"
systemctl stop pgl-rudesk-mail 2>/dev/null || true
install -d "$MAIL_DIR"
echo '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' | base64 -d | tar -xz -C "$MAIL_DIR"
chown -R root:root "$MAIL_DIR"
cp "$MAIL_DIR/pgl-mail.html" "$API_DIR/resources/admin/pgl-mail.html"

SECRET=""
[[ -f "$MAIL_ENV" ]] && SECRET="$(grep -oP '^PGL_MAIL_SECRET=\K.*' "$MAIL_ENV" || true)"
[[ -n "$SECRET" ]] || SECRET="$(openssl rand -hex 32)"
SITE_URL="https://${DOMAIN}"
grep -q 'PGL-RUDesk HTTPS' /etc/nginx/sites-available/pgl-rudesk 2>/dev/null || SITE_URL="http://$(curl -4 -fs --max-time 5 https://ifconfig.me || hostname -I | awk '{print $1}')"

umask 077
cat > "$MAIL_ENV" <<EOF
PGL_MAIL_LISTEN=127.0.0.1:21125
PGL_MAIL_DB=${API_DIR}/data/pgl-mail.db
PGL_API_DB=${API_DIR}/data/rustdeskapi.db
PGL_API_DIR=${API_DIR}
PGL_API_INTERNAL=http://127.0.0.1:21124
PGL_SMTP_MODE=${MODE}
PGL_SMTP_HOST=${SMTP_HOST}
PGL_SMTP_PORT=${SMTP_PORT}
PGL_SMTP_USER=${RELAY_USER}
PGL_SMTP_PASS=${SMTP_PASS}
PGL_MAIL_FROM=PGL-RUDesk <$( [[ -n "$RELAY_USER" ]] && echo "$RELAY_USER" || echo "no-reply@${DOMAIN}" )>
PGL_SITE_URL=${SITE_URL}
PGL_MAIL_SECRET=${SECRET}
EOF
umask 022
chown root:"$SVC_USER" "$MAIL_ENV"; chmod 640 "$MAIL_ENV"

cat > /etc/systemd/system/pgl-rudesk-mail.service <<EOF
[Unit]
Description=PGL-RUDesk Password Recovery Mail
After=network-online.target pgl-rudesk-api.service
Wants=pgl-rudesk-api.service

[Service]
User=${SVC_USER}
SupplementaryGroups=systemd-journal adm
WorkingDirectory=${API_DIR}
EnvironmentFile=${API_ENV}
EnvironmentFile=${MAIL_ENV}
ExecStart=/usr/bin/python3 ${MAIL_DIR}/pgl-mail.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now pgl-rudesk-mail >/dev/null

green "==> Маршрут /api/pgl/ в nginx"
python3 - <<'PYNGINX'
from pathlib import Path
loc = ("    location /api/pgl/ {\n"
       "        proxy_pass http://127.0.0.1:21125;\n"
       "        proxy_set_header Host $host;\n"
       "        proxy_set_header X-Real-IP $remote_addr;\n"
       "    }\n")
for name in ["pgl-rudesk", "pgl-rudesk-api"]:
    p = Path("/etc/nginx/sites-available") / name
    if not p.is_file():
        continue
    s = p.read_text()
    if "location /api/pgl/" in s:
        continue
    anchor = "    location /_admin { return 404; }\n"
    if anchor in s:
        s = s.replace(anchor, anchor + loc)
        p.write_text(s)
        print("  добавлено в", p)
PYNGINX
nginx -t -q && systemctl reload nginx

green "==> Проверка"
for _ in $(seq 1 15); do
  curl -fs -o /dev/null http://127.0.0.1:21125/api/pgl/health && break; sleep 1
done
if curl -fs -o /dev/null http://127.0.0.1:21125/api/pgl/health; then
  green "  Служба работает"
else
  red "  Служба не отвечает. Логи:  journalctl -u pgl-rudesk-mail -n 50"; exit 1
fi

echo
green "================================================================"
green "  Восстановление пароля по почте включено"
green "================================================================"
echo "  Отправитель      : $(grep -oP '^PGL_MAIL_FROM=\K.*' "$MAIL_ENV")"
echo "  Режим            : $( [[ "$MODE" == "local" ]] && echo "своя почта (Postfix)" || echo "внешний SMTP ${RELAY}" )"
echo "  Для пользователей: ${SITE_URL}/account/#forgot"
echo "  Журнал писем     : админка → кнопка «Почта» в шапке"
echo "  Логи             : journalctl -u pgl-rudesk-mail -f"
if [[ "$MODE" == "local" ]]; then
  yellow "  Без SPF/DKIM и PTR письма могут попадать в спам или отклоняться."
  yellow "  Статус каждого письма виден в разделе «Почта»."
fi
green "================================================================"
