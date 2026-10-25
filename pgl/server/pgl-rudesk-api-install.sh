#!/usr/bin/env bash
# =====================================================================
#  Сервер аккаунтов PGL-RUDesk (регистрация, вход, адресная книга)
#  на базе открытого rustdesk-api (MIT). Ubuntu / Debian.
#
#  Нужен уже установленный сервер PGL-RUDesk (pgl-rudesk-server-install.sh).
#  Запуск:  bash pgl-rudesk-api-install.sh
#  Повторный запуск = обновление (пользователи и данные сохраняются).
# =====================================================================
set -euo pipefail

APP_DIR="/opt/pgl-rudesk-api"
ENV_FILE="/etc/pgl-rudesk-api.env"
KEY_FILE="/var/lib/pgl-rudesk/id_ed25519.pub"
SVC_USER="pgl-rudesk-api"
PORT=21114

green() { echo -e "\e[32m$*\e[0m"; }
yellow(){ echo -e "\e[33m$*\e[0m"; }
red()   { echo -e "\e[31m$*\e[0m"; }

[[ $EUID -eq 0 ]] || { red "Запустите от root:  bash $0"; exit 1; }
[[ -s "$KEY_FILE" ]] || { red "Не найден ключ $KEY_FILE — сначала установите сервер PGL-RUDesk."; exit 1; }

case "$(uname -m)" in
  x86_64|amd64)  ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  armv7l)        ARCH="armv7l" ;;
  *) red "Неподдерживаемая архитектура: $(uname -m)"; exit 1 ;;
esac

green "==> Установка зависимостей"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates openssl >/dev/null

green "==> Загрузка сервера аккаунтов ($ARCH)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
URL="https://github.com/lejianwen/rustdesk-api/releases/latest/download/linux-${ARCH}.tar.gz"
curl -fL --retry 3 -o "$TMP/api.tar.gz" "$URL" || {
  red "Не удалось скачать $URL"; red "Проверьте доступ VPS к github.com."; exit 1; }
tar -xzf "$TMP/api.tar.gz" -C "$TMP"
[[ -x "$TMP/release/apimain" ]] || { red "В архиве нет apimain"; exit 1; }

systemctl stop pgl-rudesk-api 2>/dev/null || true

id "$SVC_USER" >/dev/null 2>&1 || \
  useradd --system --no-create-home --shell /usr/sbin/nologin "$SVC_USER"

FIRST_INSTALL=0
[[ -d "$APP_DIR/data" ]] || FIRST_INSTALL=1

install -d "$APP_DIR"
for item in apimain resources conf docs; do
  rm -rf "${APP_DIR:?}/$item"
  cp -a "$TMP/release/$item" "$APP_DIR/"
done
install -d -o "$SVC_USER" -g "$SVC_USER" -m 750 "$APP_DIR/data" "$APP_DIR/runtime"
chown -R root:root "$APP_DIR/apimain" "$APP_DIR/resources" "$APP_DIR/conf" "$APP_DIR/docs"

IP="$(curl -4 -fs --max-time 5 https://ifconfig.me || hostname -I | awk '{print $1}')"

green "==> Настройка"
cat > "$ENV_FILE" <<EOF
RUSTDESK_API_LANG=ru
RUSTDESK_API_APP_REGISTER=true
RUSTDESK_API_APP_REGISTER_STATUS=1
RUSTDESK_API_APP_WEB_CLIENT=0
RUSTDESK_API_APP_WEB_SSO=false
RUSTDESK_API_ADMIN_TITLE=PGL-RUDesk
RUSTDESK_API_GIN_API_ADDR=0.0.0.0:${PORT}
RUSTDESK_API_RUSTDESK_ID_SERVER=${IP}:21116
RUSTDESK_API_RUSTDESK_RELAY_SERVER=${IP}:21117
RUSTDESK_API_RUSTDESK_API_SERVER=http://${IP}:${PORT}
RUSTDESK_API_RUSTDESK_KEY=$(cat "$KEY_FILE")
EOF
chmod 640 "$ENV_FILE"
chgrp "$SVC_USER" "$ENV_FILE"

cat > /etc/systemd/system/pgl-rudesk-api.service <<EOF
[Unit]
Description=PGL-RUDesk Account Server
After=network-online.target
Wants=network-online.target

[Service]
User=$SVC_USER
WorkingDirectory=$APP_DIR
EnvironmentFile=$ENV_FILE
ExecStart=$APP_DIR/apimain
Restart=always
RestartSec=5
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now pgl-rudesk-api >/dev/null

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow ${PORT}/tcp >/dev/null
fi

green "==> Проверка"
for _ in $(seq 1 20); do
  curl -fs -o /dev/null "http://127.0.0.1:${PORT}/api/login-options" && break; sleep 1
done
if ! curl -fs -o /dev/null "http://127.0.0.1:${PORT}/api/login-options"; then
  red "Сервер не отвечает. Логи:  journalctl -u pgl-rudesk-api -n 50"
  exit 1
fi

ADMIN_PWD=""
if [[ $FIRST_INSTALL -eq 1 ]]; then
  ADMIN_PWD="$(openssl rand -base64 12 | tr -dc 'A-Za-z0-9' | head -c 14)"
  ( cd "$APP_DIR" && set -a && . "$ENV_FILE" && set +a && \
    runuser -u "$SVC_USER" -- ./apimain reset-admin-pwd "$ADMIN_PWD" >/dev/null 2>&1 )
fi

echo
green "================================================================"
green "  Сервер аккаунтов PGL-RUDesk запущен"
green "================================================================"
echo "  API-сервер      : http://${IP}:${PORT}"
echo "  Панель админа   : http://${IP}:${PORT}/_admin/"
if [[ -n "$ADMIN_PWD" ]]; then
  echo "  Логин админа    : admin"
  echo "  Пароль админа   : ${ADMIN_PWD}"
  yellow "  Сохраните пароль! Сменить: зайти в панель → профиль."
fi
echo
echo "  Регистрация в приложении: включена"
echo "  Данные (пользователи, адресные книги): $APP_DIR/data"
echo "  Логи  : journalctl -u pgl-rudesk-api -f"
echo "  Если панель не открывается — откройте порт ${PORT}/TCP у хостера."
green "================================================================"
