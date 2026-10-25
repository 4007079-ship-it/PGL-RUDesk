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
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates openssl python3 >/dev/null

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

green "==> Оформление панели администратора"
cat > "$TMP/pgl-admin-theme.py" <<'PGLTHEME'
#!/usr/bin/env python3
"""Оформление панели администратора в стиле PGL-RUDesk.
Запуск:  python3 pgl-admin-theme.py <папка resources/admin> <папка conf/admin>
Повторный запуск безопасен."""
import re
import sys
from pathlib import Path

LOGO = "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHLAAAV+klEQVR42u2deYwc1Z3HP+9VVXe7p2e6xzNgg3FiW8HGB9gQ2+ObwyCDIYs2AUJAC8lCEIogwMImf8QRIIvdhEVZooCEIJAFJSSgLJGSgDE2DusYMCZcsjFgHA474GsOz93dVfXe/tFVRc/l6R53NYOnfq3W2NM1VdXv9/3dv98rQXkkAANwin43GVgCLAQWA+OBGYWDBRpNxsqw86ydNMYasbWNQBDRQHK1S8pK8eyBZ7nglQuQQqK0Kj7kPaAV+CuwCfgb0FL0uQm4gC71mmYZ92d4J3eAGLAK+A5wFlAfsa8qNMP7uRj4AXAAWAc8BawH8t7nElClnFCWARQXsIB/BV4H/gj8s8d85X2uykFfRGWTLlprDUwAvu3x4nWPN5Z3jFkJAAjvGAdY6ameh4HZ3k34NyI9DSG9v4koHBJFay28tff5MNvjzV+BJo9nw/JDDvOZj7jbgY3eiX1JN4puJKLPDxA+H5TH9CZgi8czVSSgZQHAtyH1wLPAHUWqxyjDdERUPZJFptrwePZEkYmWpQKgmPnrPWfPLlI9EY1u8nlkA5d5PBwSBHIQlaKBBoFYLxALBMIWCEtwdK+IytXtR/USHs9sj4c+CHR/ky2HsPu/0+gFGm1rtKUZ2Uuh0GhsbUccLcvVL7xc7aKP7mV5PFwAPOTx1hgqD2ACTsJI3JGQiXM9FWIdLYo1mrSZjrRAGcy3hEXGygyWCBoJWR4vv5F1s7dnVfZOn9e+yscQhuFq122qb1r+1Pyn/k9ppQxhGJVUZzVmTQSCEtfK0Q49bk8lQaWVVkqh1IWvXNi0o3PHG1JIqbRSAkAKKS1hWZuXbH7p9PTpZyitlBRSVvJLmYYZcbeMdI+tKms2Xe26hjCMNzvefGP5i8sX29q2lVbKNIVpOtpxLpl0yeVz6uackVVZ19MIFWO+rWy2tWzD0U7E3BJMZsbKMK9uHq52EaJiWtPIq7wzu3b26ZeceMnlv/nHbx41hWkKKaSMy3h867Ktb36l5isna611paTft2eH8oeY+vxU8iofcbkEaqpvYuuyrXQ73UhRuZSL0koJIcTu7t3vL9qyaF5O5XKm0kqtGL/i7JNrTp7uq4kwkJ0yUxy2Dwcoj2gQERUGrnZJGslwMkVCSle77sk1J09fMX7F2esPrX/GBLjmS9dcp9GhckVphdIqAsAwguKvU8iRhr7mS9dct/7Q+mfkiYkTJy0fv/xMgRCVdPwiGp0khZQCIZaPX37miYkTJ8ml45cuT1vpTCEkEFGcduxrGaG0UmkrnVk6fulyc356fpOXtdOVjtOLc1IRjZ6183k9Pz2/yVyYWTjfEhYGhqikx1kcBVjCijhapi8ghMASFpXmCRDwemFm4XzTktbxzflmNFqEoQEsYdFit0RaoAyytU1bvo0epycUAPi8tqR1vMhYmdA5o7Wmw+mIQFAimcKk1qytynr55d+IxizYogLN6PQDRhiQ6TLTOZEGGOsaoFpebZ1ZV8nCRkRDrHOn01lW0c0M+4Y0mjqrjq3LttJgNUSTQSGR0oqkmeRr277Gi60vBnWFUaMBGqyGaDQsZADEzXjZOZeqdWnY2g7eEQDCAUBMx8oOHasGgKhLuDrrWy5F1b8xThEAxnoYaIjwhn38KCDMa0TUT6KFxBBGyWtuVqr580jUbrdHdYAqUZfThatdSuWreWbDmaFrgJSZQiJxtFPodI2cwIqT1hpb2SyqX0TSSJY8VCL013R1RDPieZWQUKYP0O10h3gvGikktrJ59fCr0VxAFejUulMZb40vWdOaYTQcFAPAEhaH3cNcuO3CaC6gCvTnhX/mwokX0mV3ldRMUrVUcDQXEL73r7TCFOWxtGqZwGguoDprXO7aRomgsa45oiUY2xRqIkijkUiqkWyK6DMzUFYiKGWlQo//0zraIaRalDJTGJZBmnRJuRfz2QPPhqoBTGHSbrdH+wSFTL7z93Lby7i49Dq9JYWBUVPoWPcBwkwE9bdNEVUnH1Cmha6OBqgW0Ma8KdDlDZRGJmCsm4BwA4DPysG/mvsr0lYaRztRRBCSiR1njOOWt2/hrY63Si4HVyUVbAmLVcevojZWG+mb8MIAMKHh/YZA+D53DVAcorTb7VjCitrCQ9QANbqm7JJ71YpBfp+aQkUACMncGsIoe20j13ysh43REkQAiGgsh4HRXMAxJtGjdS7A71aJuoHCi7Q0evTOBSSNZNCvFkUB4QBAIFhSv2R0zgUcyB2ICkJVoMZYI5ZhlZxwC30uwBQmrXYrS7Ysod1pj5pCQ7T9Siue+OoTrDxuJd12d0l+QOhzAX5yosVuocvpijgVMrnaxRAGUsjRMxcAhXqAv4lBpAHC0wDl+ldVA0BxBBABINz1LQs40dKNbTLD9Mz9h0dG3n/1yJ/AKtUcmDVmTbh3JCClUlHsXyVKGkmkJanVtSVtzCnObDhTh8t/ga1tXml7JRoPD3mdNZq5dXMZHyt9PDzqCRzrPkC1CjXReFj1wsFyzG3VNEBUESzTea6S4xyZgLFuAqpyEWHSVN+EJawoCTSM5BvCoDXfylsdb1UlaxqqBvC/QL1Vz4crPyQdS0f65kgA0BoRE7yw7wXOfvnskku6o14D+I0KCZmI2sKHcZRTIkWP23NsmQDfO5VCIpERAI4gKKVW8SrGl2jZx3jYGC1BFAV84eLjYzWScLUb7KdcNQCEaW/8KKAS13C1S0zGiJmxQuxyLLoRCohBvVUfuj8WAKAaGadOpzNoVR7JbuFSSFKxFM3ZZl5tfvWYLSxpNDEZY3f37uD/FZd4YfZZO3Nd07rQv5glLSYlJiGkIEGifMHQint338s9f7+HT7KfjKm8QCW1sSEMLj3xUq798rXk3XyhlVz/U/ht4VppNrVswlZ22YxPmAke2/sYj+599LNw8hj3XTU6FD9AConWmhun3sjP5/0cXBCdF3TqML+IJSya881M2zStbAAUkyGMY9oBrBb5D5S8YcoN/OK0X4RbDvZz24YwqDVrR7xbuEAMKhHl3LtGl72B0lD3IsTAx9/5TZml+lQCMahzrHWhjS40P1MrDGFw30f3ccHxF3yxdwsfiZr06+Xl/q1vQx3tDGubS9FWYan5UgTBp4f2PPTF2yvYB1BCJliQWYAhjGEB5WqXDqeDPb17OGwf/gwMyJKkzVebjnYwhMHs2tnMqp3FCfETSMgEPW4Pe7N7eafzHd7peif4voM9v9e//+NixzGnbk4QFfna8uOej/mg54NQK4G+lnqp9aUv3l7B/sJMiE9g4+KNxIxYSRXGnJvjUP4Qr7W/xmP/eIyn9j2FQg1bcZOiAOCJ8YlcP+V6vj7x60xPTSduxPvmIjT0OD1s79jO4588zsN7Hqbb7R4AAv98ZzWcxZOLn0TnNUIIlFbIuOTunXfzw3d+GGibMLXAwfzBL+5ewRpNp9NJUidLyi1IIZkQn8DFJ1zMxSdezPoD6/nuW99lb+/eQTWBb+uVVlzzpWtYe8paThh3AtrVZFWWLrurj4T6JqKpvommhiau/fK13LzjZjY1bxpUE9jaRtmKLqcrYHatrCWnclUzBwKBecErF3xuNqgSYY0UMhiNHsq2+lrD1jY5O4dGs2rCKjYs3sDKl1byafbTPprAd9Bc7XLPrHu49eRbsR2bznwnEhlct1hz+A5dt9ONQjGndg4bFm/gureu4+E9Dw8AgX+N4ippuf18FRHQY2mvYD/sTMaSfVQzGnqd3j67lbTn2plRO4MHT3uQi7ZdNKjaXztjLbfOuJXObIHxpjADgMVlHMu0gpYax3XIqmxhMBNJt1NQ/7+c90v2ZffxzMFnRmVfpHmsTO34adQPez7k0V2PBlJfa9Yyt24u5zSegxACWxUaUmIyRme+k9UTV3P+8eez7uC6gEGudll13CrWzFhDV7YrmHD2NU0qluLTnk95vf11WvOt1MfqmVc3j8k1k+m1PwOaq10c5XD/qfdzxuYzOGwfxhQmLqOnQ7qq+wSGGeYprTClyYc9H3LX+3cN+PycxnN4/IzHyViZAT7DlZOuZN3BdUF4GJdxfjrzp8H1g6IWEiEEa3au4aGPH+Jg/mBwjoZYA9+b8j1+PP3H5N18sB9il9PFlNQUrp58Nfd+cG/BVIyiXFbVcqrFxaBS3yMhS1iYwgx++v/e1LyJNe+uIW7GA3MkhUQpxenp07GEFcTuF024iLn1c+l1evsA15IWV79xNXe9fxcH8weDDZmkkLTkW1i7ay13vHsHNYkakkaSGrOGOrMOBFx10lWBaRlVJqAqFymzK/hoxsk0OtiQ2r+W72g9d+g5OnIdxGUcFzeQ+MZYI/Wxeg7mChL9rUnf6iOljnaojdXy8EcP88SnTxCTMWxlD3ACBYKfffAzzm48m8ZYY9D/aAqTTqeTjJmh1W4dOwAotsNPL3y69K5gAe35dqY+P5U2u+2okyJ+CjjrZulVvYwzxgWS6NvrmIwBkDbTLMgswHGdwLM3hEHOyXHfh/cFUtw/BAyuobOct/W8garecxYHCwmPeQ1QTlew78l3OV0jZnr/PL0pTVztckLiBOqt+uAefLve6/bi75U0rWYaE+MTyes8AoFCkTSSvN3xNjs6dww6dj3YfQ5wrr1DDIyxowEGi9mH6wquRGds/90y/CrkTdNuImbEyNv5QgpZawzD4OPej2l32gGYlJg04BghBLu6dwWp4GIJNoVJrVk7LFgFgm63e2z6ANWkIMFCIUEUl3GmJKdw09Sb+Pbkb9Nj9wSOnUIhpGDjoY2BxGbMzEDpFtCSbxm0PrAgs4Cnm56mx+kZErSudqmxarj+ret58tMnRxcAwsw8+eeuRnbLEAY5N8fcurm8tvy14PdJI8lJ404iaSbpcXqCTROUVljS4nDuMI/sfWTY/sWhJNwSFvWxepIyeUQAJKwEcRkffYmgMBss/HNX65mBSitqzBrmpef1+V1e5emyu/okegSChJXglh23sKd3DzEZI6/ydLvdA0GsIW2lB78mCkcVsoA+APrX+l3tEtfxUdnMYmasTOhRQNpMBynU4fauOdp9hfzS72BOoaMLnn3KTIGANW+v4YGPH+hj1/fn9ve5Rx8AU8ZNKTiF/e7LFCamZZIWRU/q1NDr9g64/mjMupo7z9pZFQdwQnxCOcgZ8b5CpjBJmslBzwngui4vtr7I2l1rWX9ofRDW+df6oOcD2vJt1Jq1hXyCEOTcHKekTmHyuMmF6mFRIWh753YufvliXOUihcTRDovrF/Oj6T8a8PTO/sAcFQBojDWGagL8cvBF2y6iy+kqKab3E0GdTucR7W//axnCoNVu5c3mN/t8Zmub5nwz73a+y+bWzWxt2/pZJtBjpJ/n35/dz7td77Jk/BJsx0YKSV7nScfTXDHpCn6y+ydYwiKv80DBOfzj/j/2ud7U5FSkLJSYJYVsYd7Ns7d37+gDQJj22Wdcj9vD+oPrQ+3lV1qRNJNsb9lOKSXuwRIyfl3+Twf+xNLGpX0YmHNy3PaV2/jD/j/wXtd7fZ7P4/sWOZWjxqjhhqk3BIkkPxL5qOcj3u9+f1gB8PsKSu10OmrtXJXQTAjSVhpDGJjCDL7gcO+Rpp2Lc/T+u/jaQy2erw1+/cmvacu1EROxQDM4yiFjZni66WlWNKwIWsQc7ZBTOXIqx+Rxk/ntV3/LzNRMsm42aIczDIMNhzbQ4/YEGcehKKuyuNolp3Kh1EoGrJclrFA1gCUsLGH1mQoKO/IYafOpotAx+0nvJ9z7wb3cOetOOrIdWNJCCknWzTJl3BQ2LtrIhuYNbG7ZTEu+hTqzjtPqTuP8489nQmJCsFO3b5ZyTo77P7r/iObMdxJPSZ3CysaVxGRsSCYbwqDD6eCl1peOei3NbYe37ZqWnDZdo7VAiDAA0GK3fGH6+ZUu9AnevftuzjvuPJY1LqM9105MxgIQSCFZPWE1qyeu7utrOHafcNNWNulxae7aeRc7OnccsQ7gA+XySZdz5UlXDj376D0gctfhXcx6YdZIhUp7bvEu8/xXzm82hTm96JeVl0qtAw94tAPBV/lZleWyv13GukXrmJuZS2e+M7DPQNATWNwo4psan8npcWl+v+f33L7r9qBVfLgUd07ljji/4D8g8ii33vd53Wx2OV1bgCV8wXbv8cu+/ji10qpio9U+o/bl9nHuy+fywGkP8I1J3wBVcGiLG0WK8x2udjGFScpKgYb7d9/PzTtu7hNpDHb/5QhFMIBydMMj/gW3mMDzAnFb2A5hpSXfEAbHxY4rVDM0FR+t9kHQnG/mkr9dwqWfXsqNU2+kKdNE0kr2XcaiPEPWzrLx4Eb+6+//xXOHnusDkGKKyzhm3CQjMuWtvAKswqNhKuD8bxJAA7ALGB+mGah4dtFKc/2Xr8eSVqAyg57AvY9WzNks7jYGmFs3l6XjlzK7djYT4xNJGAmybpZ9uX1s79jOltYtvN35dpBn6K/O/dzDzNRMvjnpm+RVvqyEl/8992f38+CeB0fi8Po8/gdwqo/dxzxs2QR9tNG7+G0Io+RjBaKs46v89nn8SJHi4nxgHeBCOB0LI0nrlpIwGexvwqy5F5eai51G//uVWscY6v7LoREm1pRnAs4GXhDef+LAm8DJHjqizaOOTVJ++AfMAZTpMbsX+A/gfzwtICst/XVmXUkPMOgfOkb7AVTYFy/w9j8BBzBFkVdoAS8Dp1fKFBQ7bFuXbaXBaii5J7DFbmHRlkW029GzBitEPk//6ql/ALe4JSwHXAO84gGiYhGBQNBgNfRplR4OACP1GyIaUvK1B4Kbi7W8LLINJvAGcJeHlIqW7mxtl/2OqGLkePy9DXjd46+in633D7oT+F/PJFSMC2IEr4gqI3seLx8F7vV4HIRJ5iB2QgDfNYTxJYFYUHSCEfsA/lPDP+/s4Rhm/qvA9zyB7xMjm0N4iW2udlcB6wEfBOZIfYLmfHMwdzccU/1jKhEnj3Gb73rM3+bleXqKfLshAQCgBEJqdFtCJlatnrD6gZmpmZcBWqNdQelcCfbzMRLUWXV9umiOGKxqxcRxE5lTO4fNLZtH5VDlKPf2pcfbRzynr9P7nRrIo6EzXlJppQBuP+X229fMWLPGFKbpaMeRSCmFlOXg8UDvgZK7Yl3tkoqleOijh/jBzh+Munm6UZzk8Z15B/h3z+YzFPMZTqULhBBCCKWVmp+Z33T3zLt/Pj8zv8ljkusDZahGkiCmz7ew7MVltDvlxfQCQZvdFrF2eFVvFPHyeeBH/cJ5PfQal0C+5FvCsq6YdMW/fH/a9/9tZmrm7CKVrfyOIiGE8AFRvFPo9L9MP9omhoj6FnVkP/7tAP7bU/t4oHCHF7ISqdgkxGQsdm7juauuOumq76xoWHFWxsrUH0kDNOebmf3C7BHtFBpFAkekjzyJ/x3wl6IoTgyl8kcMAN8kGMIwHO0ESaKTEidNXlS/aMn8zPyFTZmmxfWx+vHTa6bP6A+AWS/MGvFWsREF9B7QSiGdu4lC6r6jn1NfVgLv/wGkrcXwPhRskwAAAABJRU5ErkJggg=="
FAVICON = "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"
NAME = "PGL-RUDesk"

CSS = """
:root,html.dark{--el-color-primary:#f64af6;--el-color-primary-light-3:#f980f9;--el-color-primary-light-5:#fba5fb;
--el-color-primary-light-7:#fcc9fc;--el-color-primary-light-8:#fddbfd;--el-color-primary-light-9:#feedfe;--el-color-primary-dark-2:#c93ac9}
html.dark{--el-color-primary-light-3:#c93ac9;--el-color-primary-light-5:#8e2f8e;--el-color-primary-light-7:#5a245a;
--el-color-primary-light-8:#421d42;--el-color-primary-light-9:#2a172a;--el-bg-color:#18191e;--el-bg-color-page:#0f0f12;
--el-bg-color-overlay:#202128;--el-fill-color-blank:#18191e;--el-fill-color-light:#202128;--el-fill-color-lighter:#1c1d23;
--el-border-color:#2c2d35;--el-border-color-light:#2c2d35;--el-border-color-lighter:#25262d;--el-text-color-primary:#ececef}
html.dark body{background:#0f0f12}
.login-container{background:#0f0f12 repeating-linear-gradient(180deg,rgba(246,74,246,.09) 0 22px,transparent 22px 52px)!important}
.login-card{background:#18191e!important;border:1px solid #2c2d35;border-radius:14px!important}
.login-card img{border-radius:18px}
.app-header{background:#18191e!important;border-bottom:1px solid #2c2d35}
.app-header .title{color:#ececef;font-weight:700}
.scroll-sidebar,.menus,.el-menu--inline,.el-menu--vertical{background:#18191e!important}
.menus .el-sub-menu__title{background:#141519!important}
.menus .el-menu-item:hover,.menus .el-sub-menu__title:hover{background:#2a172a!important}
.menus .el-menu-item.is-active{color:#f64af6!important;background:#2a172a!important;border-left:3px solid #f64af6}
.app-main a,.el-card a{color:#f64af6}
"""

THEME_JS = """(function(){try{var k='vueuse-color-scheme',v=localStorage.getItem(k);
if(!v||v==='auto'){localStorage.setItem(k,'dark')}
if(localStorage.getItem(k)==='dark'){document.documentElement.classList.add('dark')}
if(!localStorage.getItem('lang')){localStorage.setItem('lang','ru')}}catch(e){}})();"""

HELLO = (
    "### Добро пожаловать в панель PGL-RUDesk, ***{{username}}***\n\n"
    "Здесь хранятся пользователи, их устройства, адресные книги и история входов.\n"
)


def patch_index(admin: Path):
    p = admin / "index.html"
    s = p.read_text(encoding="utf-8")
    s = re.sub(r"<title>.*?</title>", f"<title>{NAME}</title>", s, count=1, flags=re.S)
    s = re.sub(r'<link rel="icon"[^>]*>', f'<link rel="icon" type="image/png" href="data:image/png;base64,{FAVICON}">', s, count=1)
    s = re.sub(r'\s*<style id="pgl-theme">.*?</style>\s*<script id="pgl-theme-js">.*?</script>', "", s, flags=re.S)
    inject = f'\n    <style id="pgl-theme">{CSS}</style>\n    <script id="pgl-theme-js">{THEME_JS}</script>\n  </head>'
    s = s.replace("</head>", inject, 1)
    p.write_text(s, encoding="utf-8")


def patch_js(admin: Path):
    logo_re = re.compile(r"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAIAAAACA[A-Za-z0-9+/=]+")
    found_logo = False
    for p in (admin / "static").rglob("*.js"):
        s = p.read_text(encoding="utf-8", errors="surrogateescape")
        n = s
        if logo_re.search(n):
            n = logo_re.sub(f"data:image/png;base64,{LOGO}", n)
            found_logo = True
        n = n.replace("Rustdesk API Admin", NAME).replace("RustDesk API Admin", NAME)
        n = n.replace('language||"zh-CN"', 'language||"ru"')
        if n != s:
            p.write_text(n, encoding="utf-8", errors="surrogateescape")
    if not found_logo:
        print("  [!] логотип в панели не найден — новая версия интерфейса?")


def main():
    admin, conf = Path(sys.argv[1]), Path(sys.argv[2])
    if not (admin / "index.html").is_file():
        sys.exit(f"Не найдена панель: {admin}/index.html")
    patch_index(admin)
    patch_js(admin)
    conf.mkdir(parents=True, exist_ok=True)
    (conf / "hello.html").write_text(HELLO, encoding="utf-8")
    print("  Панель администратора оформлена в стиле PGL-RUDesk")


main()
PGLTHEME
python3 "$TMP/pgl-admin-theme.py" "$APP_DIR/resources/admin" "$APP_DIR/conf/admin" || yellow "  Оформление не применилось, панель будет в стандартном виде"

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
