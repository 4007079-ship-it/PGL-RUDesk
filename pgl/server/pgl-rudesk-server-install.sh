#!/usr/bin/env bash
# =====================================================================
#  Установка сервера PGL-RUDesk (на базе RustDesk OSS: hbbs + hbbr) на VPS
#  Ubuntu / Debian. Без Docker — бинарники с GitHub + службы systemd.
#
#  Запуск:  sudo bash pgl-rudesk-server-install.sh
#  Повторный запуск = обновление до последней версии (ключи сохраняются).
# =====================================================================
set -euo pipefail

INSTALL_DIR="/opt/pgl-rudesk"
DATA_DIR="/var/lib/pgl-rudesk"
SVC_USER="pgl-rudesk"

green() { echo -e "\e[32m$*\e[0m"; }
yellow(){ echo -e "\e[33m$*\e[0m"; }
red()   { echo -e "\e[31m$*\e[0m"; }

# --- 1. Проверки ------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  red "Запустите скрипт от root:  sudo bash $0"; exit 1
fi
if ! command -v apt-get >/dev/null; then
  red "Скрипт рассчитан на Ubuntu/Debian (apt)."; exit 1
fi

case "$(uname -m)" in
  x86_64|amd64)  ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64v8" ;;
  armv7l)        ARCH="armv7" ;;
  *) red "Неподдерживаемая архитектура: $(uname -m)"; exit 1 ;;
esac

green "==> Установка зависимостей"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl unzip ca-certificates >/dev/null

# --- 2. Загрузка бинарников ------------------------------------------
green "==> Загрузка серверных компонентов PGL-RUDesk ($ARCH)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
URL="https://github.com/rustdesk/rustdesk-server/releases/latest/download/rustdesk-server-linux-${ARCH}.zip"
curl -fL --retry 3 -o "$TMP/server.zip" "$URL" || {
  red "Не удалось скачать $URL"
  red "Проверьте доступ VPS к github.com."; exit 1; }
unzip -q "$TMP/server.zip" -d "$TMP/x"

HBBS="$(find "$TMP/x" -type f -name hbbs | head -n1)"
HBBR="$(find "$TMP/x" -type f -name hbbr | head -n1)"
[[ -n "$HBBS" && -n "$HBBR" ]] || { red "В архиве не найдены hbbs/hbbr"; exit 1; }

# Останавливаем старые службы при обновлении
systemctl stop pgl-rudesk-hbbs pgl-rudesk-hbbr 2>/dev/null || true

install -d "$INSTALL_DIR"
install -m 755 "$HBBS" "$INSTALL_DIR/hbbs"
install -m 755 "$HBBR" "$INSTALL_DIR/hbbr"

# --- 3. Пользователь и папка данных (там хранятся ключи) --------------
id "$SVC_USER" >/dev/null 2>&1 || \
  useradd --system --no-create-home --shell /usr/sbin/nologin "$SVC_USER"
install -d -o "$SVC_USER" -g "$SVC_USER" -m 750 "$DATA_DIR"

# --- 4. Службы systemd ------------------------------------------------
green "==> Создание служб systemd"
cat > /etc/systemd/system/pgl-rudesk-hbbr.service <<EOF
[Unit]
Description=PGL-RUDesk Relay Server (hbbr)
After=network-online.target
Wants=network-online.target

[Service]
User=$SVC_USER
WorkingDirectory=$DATA_DIR
ExecStart=$INSTALL_DIR/hbbr -k _
Restart=always
RestartSec=5
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/pgl-rudesk-hbbs.service <<EOF
[Unit]
Description=PGL-RUDesk ID Server (hbbs)
After=network-online.target pgl-rudesk-hbbr.service
Wants=network-online.target pgl-rudesk-hbbr.service

[Service]
User=$SVC_USER
WorkingDirectory=$DATA_DIR
ExecStart=$INSTALL_DIR/hbbs -k _
Restart=always
RestartSec=5
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now pgl-rudesk-hbbr pgl-rudesk-hbbs >/dev/null

# --- 5. Файрвол -------------------------------------------------------
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  green "==> Открытие портов в ufw"
  ufw allow 21115:21117/tcp >/dev/null
  ufw allow 21116/udp       >/dev/null
else
  yellow "ufw не активен — убедитесь, что порты открыты в панели хостера:"
  yellow "  TCP 21115-21117, UDP 21116 (21118-21119 нужны только для веб-клиента)"
fi

# --- 6. Ожидание ключа и вывод результата ----------------------------
green "==> Ожидание генерации ключа"
for _ in $(seq 1 20); do
  [[ -s "$DATA_DIR/id_ed25519.pub" ]] && break; sleep 1
done

if [[ ! -s "$DATA_DIR/id_ed25519.pub" ]]; then
  red "Ключ не появился. Посмотрите логи:  journalctl -u pgl-rudesk-hbbs -n 50"
  exit 1
fi

KEY="$(cat "$DATA_DIR/id_ed25519.pub")"
IP="$(curl -4 -fs --max-time 5 https://ifconfig.me || hostname -I | awk '{print $1}')"

echo
green "================================================================"
green "  PGL-RUDesk Server установлен и запущен!"
green "================================================================"
echo "  ID сервер : $IP"
echo "  Key       : $KEY"
echo
echo "  Вставьте эти данные в клиенте:  Настройки → Сеть → ID/Relay сервер"
echo "  (Relay и API оставьте пустыми)"
echo
echo "  Статус    : systemctl status pgl-rudesk-hbbs pgl-rudesk-hbbr"
echo "  Логи      : journalctl -u pgl-rudesk-hbbs -f"
echo "  Ключи     : $DATA_DIR  (сделайте резервную копию!)"
echo "  Обновить  : повторно запустите этот скрипт"
green "================================================================"
