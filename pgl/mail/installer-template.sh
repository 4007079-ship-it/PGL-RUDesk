#!/usr/bin/env bash
# =====================================================================
#  Почта PGL-RUDesk: восстановление пароля по почте + раздел «Почта»
#  в панели администратора. Свой почтовый сервер (Postfix, только отправка).
#
#  Запуск:  bash pgl-rudesk-mail-install.sh pgl-rudesk.ddns.info --reply-to me@gmail.com
#  Параметры (необязательные, при обновлении сохраняются прежние):
#    --reply-to адрес      куда приходят ответы пользователей
#    --from-name "Имя"     имя отправителя (по умолчанию PGL-RUDesk Support)
#  Через внешний ящик (если письма не доходят):
#           bash pgl-rudesk-mail-install.sh pgl-rudesk.ddns.info --relay smtp.yandex.ru:465 box@yandex.ru
#  Нужен установленный сервер аккаунтов (pgl-rudesk-api-install.sh).
#  Повторный запуск = обновление (журнал писем сохраняется).
# =====================================================================
set -euo pipefail

API_DIR="/opt/pgl-rudesk-api"
API_ENV="/etc/pgl-rudesk-api.env"
MAIL_DIR="/opt/pgl-rudesk-mail"
MAIL_ENV="/etc/pgl-rudesk-mail.env"
SVC_USER="pgl-rudesk-api"

green() { echo -e "\e[32m$*\e[0m"; }
yellow(){ echo -e "\e[33m$*\e[0m"; }
red()   { echo -e "\e[31m$*\e[0m"; }

[[ $EUID -eq 0 ]] || { red "Запустите от root"; exit 1; }

DOMAIN="${1:-}"; [[ $# -gt 0 ]] && shift
RELAY=""; RELAY_USER=""; REPLY_TO=""; FROM_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --relay)     RELAY="${2:-}"; RELAY_USER="${3:-}"; shift $(( $# < 3 ? $# : 3 ));;
    --reply-to)  REPLY_TO="${2:-}"; shift $(( $# < 2 ? $# : 2 ));;
    --from-name) FROM_NAME="${2:-}"; shift $(( $# < 2 ? $# : 2 ));;
    *) red "Неизвестный параметр: $1"; exit 1;;
  esac
done
if [[ -f "$MAIL_ENV" ]]; then
  [[ -n "$REPLY_TO" ]]  || REPLY_TO="$(grep -oP '^PGL_MAIL_REPLY_TO=\K.*' "$MAIL_ENV" || true)"
  [[ -n "$FROM_NAME" ]] || FROM_NAME="$(grep -oP '^PGL_MAIL_FROM_NAME=\K.*' "$MAIL_ENV" || true)"
fi
[[ -n "$FROM_NAME" ]] || FROM_NAME="PGL-RUDesk Support"
if [[ -n "$REPLY_TO" && ! "$REPLY_TO" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
  red "Неверный адрес для ответов: $REPLY_TO"; exit 1
fi
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
echo '__PAYLOAD__' | base64 -d | tar -xz -C "$MAIL_DIR"
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
PGL_MAIL_FROM_NAME=${FROM_NAME}
PGL_MAIL_FROM=${FROM_NAME} <$( [[ -n "$RELAY_USER" ]] && echo "$RELAY_USER" || echo "support@${DOMAIN}" )>
PGL_MAIL_REPLY_TO=${REPLY_TO}
PGL_MAIL_SIGNATURE=С уважением,|служба поддержки PGL-RUDesk
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
echo "  Ответы приходят  : ${REPLY_TO:-никуда (ответить на письмо нельзя)}"
echo "  Режим            : $( [[ "$MODE" == "local" ]] && echo "своя почта (Postfix)" || echo "внешний SMTP ${RELAY}" )"
echo "  Для пользователей: ${SITE_URL}/account/#forgot"
echo "  Журнал писем     : админка → кнопка «Почта» в шапке"
echo "  Логи             : journalctl -u pgl-rudesk-mail -f"
if [[ "$MODE" == "local" ]]; then
  yellow "  Без SPF/DKIM и PTR письма могут попадать в спам или отклоняться."
  yellow "  Статус каждого письма виден в разделе «Почта»."
fi
green "================================================================"
