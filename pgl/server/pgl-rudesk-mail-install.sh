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
