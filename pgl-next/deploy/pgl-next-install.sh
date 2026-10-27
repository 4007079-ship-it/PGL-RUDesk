#!/usr/bin/env bash
# =====================================================================
#  Новый сервер PGL (pgl-next) — предварительная версия для тестов.
#  Ставится РЯДОМ с текущим сервером RustDesk, на других портах,
#  и его не трогает.
#
#  Запуск:  bash pgl-next-install.sh [домен-или-IP]
#    без аргумента берётся публичный IP этого сервера.
#
#  Порты (откроются в ufw, если он включён):
#    21220/tcp         — сайт и API нового сервера
#    21221/udp         — STUN/TURN
#    21300-21400/udp   — ретранслятор TURN
#
#  Повторный запуск = обновление бинарника, данные сохраняются.
# =====================================================================
set -euo pipefail

REPO="4007079-ship-it/PGL-RUDesk"
TAG="pgl-next"
DIR="/opt/pgl-next"
SVC_USER="pgl-next"
HTTP_PORT=21220
TURN_PORT=21221
RELAY_MIN=21300
RELAY_MAX=21400

green() { echo -e "\e[32m$*\e[0m"; }
yellow(){ echo -e "\e[33m$*\e[0m"; }
red()   { echo -e "\e[31m$*\e[0m"; }

[[ $EUID -eq 0 ]] || { red "Запустите от root"; exit 1; }

PUBIP="$(curl -4 -fs --max-time 5 https://ifconfig.me || hostname -I | awk '{print $1}')"
HOST="${1:-$PUBIP}"
[[ -n "$PUBIP" ]] || { red "Не удалось определить публичный IP"; exit 1; }

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) BIN="pgl-server-linux-amd64";;
  aarch64|arm64) BIN="pgl-server-linux-arm64";;
  *) red "Архитектура $ARCH не поддерживается"; exit 1;;
esac

green "==> Загрузка сервера ($BIN)"
install -d "$DIR" "$DIR/data"
URL="https://github.com/$REPO/releases/download/$TAG/$BIN"
if ! curl -4 -fL --retry 3 -o "$DIR/pgl-server.new" "$URL"; then
  red "Не удалось скачать $URL"
  yellow "Сначала соберите сервер: GitHub → Actions → «PGL-Next Build» → Run workflow."
  exit 1
fi
chmod +x "$DIR/pgl-server.new"
mv -f "$DIR/pgl-server.new" "$DIR/pgl-server"

id "$SVC_USER" >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin "$SVC_USER"
chown -R "$SVC_USER":"$SVC_USER" "$DIR"

green "==> Служба systemd (pgl-next-server)"
cat > /etc/systemd/system/pgl-next-server.service <<EOF
[Unit]
Description=PGL-Next server (preview)
After=network-online.target
Wants=network-online.target

[Service]
User=${SVC_USER}
WorkingDirectory=${DIR}
Environment=PGL_ADDR=:${HTTP_PORT}
Environment=PGL_PUBLIC_IP=${PUBIP}
Environment=PGL_HOST=${HOST}
Environment=PGL_TURN_PORT=${TURN_PORT}
Environment=PGL_RELAY_MIN=${RELAY_MIN}
Environment=PGL_RELAY_MAX=${RELAY_MAX}
Environment=PGL_DATA=${DIR}/data/pgl-data.json
ExecStart=${DIR}/pgl-server
Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=${DIR}/data

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now pgl-next-server
systemctl restart pgl-next-server

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  green "==> Открываю порты в ufw"
  ufw allow ${HTTP_PORT}/tcp  >/dev/null
  ufw allow ${TURN_PORT}/udp  >/dev/null
  ufw allow ${RELAY_MIN}:${RELAY_MAX}/udp >/dev/null
fi

green "==> Проверка"
ok=0
for _ in $(seq 1 15); do
  if curl -fs -o /dev/null "http://127.0.0.1:${HTTP_PORT}/healthz"; then ok=1; break; fi
  sleep 1
done
echo
if [[ $ok -eq 1 ]]; then
  green "================================================================"
  green "  Новый сервер PGL запущен (предварительная версия)"
  green "================================================================"
  echo  "  Адрес     : http://${PUBIP}:${HTTP_PORT}"
  echo  "  STUN/TURN : ${HOST}:${TURN_PORT} (ретранслятор ${RELAY_MIN}-${RELAY_MAX}/udp)"
  echo  "  Данные    : ${DIR}/data/pgl-data.json"
  echo  "  Логи      : journalctl -u pgl-next-server -f"
  yellow "  Текущий сервер RustDesk не затронут."
  yellow "  Программа и управление из браузера для него ещё готовятся."
else
  red "  Сервер не отвечает. Логи:  journalctl -u pgl-next-server -n 50 --no-pager"
  exit 1
fi
