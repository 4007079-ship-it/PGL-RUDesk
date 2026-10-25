#!/usr/bin/env python3
"""PGL-RUDesk: восстановление пароля по почте и журнал писем для админа.

Слушает 127.0.0.1 (nginx проксирует /api/pgl/). Только стандартная библиотека Python.

  POST /api/pgl/reset/request   {"email"}                     — выслать код
  POST /api/pgl/reset/confirm   {"email","code","password"}   — сменить пароль
  GET  /api/pgl/admin/mail      ?page=&q=   (заголовок api-token админа) — журнал писем
  GET  /api/pgl/health
"""
import hashlib
import hmac
import json
import os
import re
import secrets
import smtplib
import sqlite3
import ssl
import subprocess
import threading
import time
import urllib.request
from email.message import EmailMessage
from email.utils import formatdate, make_msgid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ENV = os.environ.get
LISTEN = ENV("PGL_MAIL_LISTEN", "127.0.0.1:21125")
DB_PATH = ENV("PGL_MAIL_DB", "/opt/pgl-rudesk-api/data/pgl-mail.db")
API_DB = ENV("PGL_API_DB", "/opt/pgl-rudesk-api/data/rustdeskapi.db")
API_DIR = ENV("PGL_API_DIR", "/opt/pgl-rudesk-api")
API_URL = ENV("PGL_API_INTERNAL", "http://127.0.0.1:21124")
SMTP_HOST = ENV("PGL_SMTP_HOST", "127.0.0.1")
SMTP_PORT = int(ENV("PGL_SMTP_PORT", "25"))
SMTP_MODE = ENV("PGL_SMTP_MODE", "local")          # local | ssl | starttls
SMTP_USER = ENV("PGL_SMTP_USER", "")
SMTP_PASS = ENV("PGL_SMTP_PASS", "")
MAIL_FROM = ENV("PGL_MAIL_FROM", "PGL-RUDesk <no-reply@localhost>")
SITE_URL = ENV("PGL_SITE_URL", "")
CODE_TTL = 15 * 60
MAX_ATTEMPTS = 5
SECRET = ENV("PGL_MAIL_SECRET", "") or secrets.token_hex(32)

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
db_lock = threading.Lock()


def db():
    c = sqlite3.connect(DB_PATH, timeout=10)
    c.row_factory = sqlite3.Row
    return c


def init_db():
    with db_lock, db() as c:
        c.executescript("""
        CREATE TABLE IF NOT EXISTS codes(
          id INTEGER PRIMARY KEY, email TEXT, user_id INTEGER, code_hash TEXT,
          created INTEGER, expires INTEGER, attempts INTEGER DEFAULT 0, used INTEGER DEFAULT 0, ip TEXT);
        CREATE INDEX IF NOT EXISTS codes_email ON codes(email);
        CREATE TABLE IF NOT EXISTS outbox(
          id INTEGER PRIMARY KEY, created INTEGER, kind TEXT, to_addr TEXT, subject TEXT, body TEXT,
          status TEXT, detail TEXT, queue_id TEXT, ip TEXT, updated INTEGER);
        CREATE TABLE IF NOT EXISTS hits(ip TEXT, email TEXT, ts INTEGER);
        """)


def code_hash(email, code):
    return hmac.new(SECRET.encode(), f"{email}:{code}".encode(), hashlib.sha256).hexdigest()


# ---------- пользователи (только чтение базы сервера аккаунтов) ----------
def find_user(email):
    c = sqlite3.connect(f"file:{API_DB}?mode=ro", uri=True, timeout=10)
    try:
        r = c.execute(
            "SELECT id, is_admin, status FROM users WHERE lower(email)=? OR lower(username)=? LIMIT 1",
            (email, email)).fetchone()
    finally:
        c.close()
    if not r:
        return None
    uid, is_admin, status = r
    if is_admin or status != 1:
        return None
    return uid


def set_password(uid, password):
    env = dict(os.environ)
    p = subprocess.run([os.path.join(API_DIR, "apimain"), "reset-pwd", str(uid), password],
                       cwd=API_DIR, env=env, capture_output=True, text=True, timeout=30)
    out = (p.stdout or "") + (p.stderr or "")
    return p.returncode == 0 and "reset password success" in out


# ---------- письма ----------
def build_message(to, subject, text):
    m = EmailMessage()
    m["From"] = MAIL_FROM
    m["To"] = to
    m["Subject"] = subject
    m["Date"] = formatdate(localtime=True)
    dom = MAIL_FROM.split("@")[-1].strip(" >") or "localhost"
    m["Message-ID"] = make_msgid(domain=dom)
    m.set_content(text)
    return m


def send_mail(kind, to, subject, text, ip):
    now = int(time.time())
    with db_lock, db() as c:
        cur = c.execute(
            "INSERT INTO outbox(created,kind,to_addr,subject,body,status,detail,ip,updated) VALUES(?,?,?,?,?,?,?,?,?)",
            (now, kind, to, subject, text, "sending", "", ip, now))
        oid = cur.lastrowid
    status, detail, qid = "failed", "", ""
    try:
        msg = build_message(to, subject, text)
        if SMTP_MODE == "ssl":
            s = smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, timeout=30, context=ssl.create_default_context())
        else:
            s = smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=30)
            if SMTP_MODE == "starttls":
                s.starttls(context=ssl.create_default_context())
        with s:
            if SMTP_USER:
                s.login(SMTP_USER, SMTP_PASS)
            sender = re.search(r"<([^>]+)>", MAIL_FROM)
            sender = sender.group(1) if sender else MAIL_FROM
            s.mail(sender)
            code, resp = s.rcpt(to)
            if code >= 400:
                raise smtplib.SMTPRecipientsRefused({to: (code, resp)})
            code, resp = s.data(msg.as_bytes())
            resp = resp.decode(errors="replace") if isinstance(resp, bytes) else str(resp)
            m = re.search(r"queued as ([0-9A-Za-z]+)", resp)
            if SMTP_MODE == "local" and m:
                status, qid, detail = "queued", m.group(1), "Передано почтовому серверу, ждём доставки"
            else:
                status, detail = "sent", "Принято сервером отправки: " + resp[:200]
    except Exception as e:  # noqa: BLE001
        status, detail = "failed", f"{type(e).__name__}: {e}"[:400]
    with db_lock, db() as c:
        c.execute("UPDATE outbox SET status=?, detail=?, queue_id=?, updated=? WHERE id=?",
                  (status, detail, qid, int(time.time()), oid))
    return status != "failed"


STATUS_RE = re.compile(r"\b([0-9A-F]{6,}|[0-9A-Za-z]{10,}): to=<[^>]*>.*?status=(sent|bounced|deferred|expired) \((.*)\)$")


def postfix_log_lines():
    try:
        p = subprocess.run(["journalctl", "--since=-12h", "-o", "cat", "--no-pager",
                            "SYSLOG_IDENTIFIER=postfix/smtp", "SYSLOG_IDENTIFIER=postfix/error",
                            "SYSLOG_IDENTIFIER=postfix/bounce", "SYSLOG_IDENTIFIER=postfix/qmgr"],
                           capture_output=True, text=True, timeout=20)
        if p.returncode == 0 and p.stdout.strip():
            return p.stdout.splitlines()
    except Exception:  # noqa: BLE001
        pass
    try:
        with open("/var/log/mail.log", encoding="utf-8", errors="replace") as f:
            return f.readlines()[-5000:]
    except Exception:  # noqa: BLE001
        return []


def status_watcher():
    labels = {"sent": "delivered", "bounced": "rejected", "expired": "rejected", "deferred": "queued"}
    while True:
        try:
            with db_lock, db() as c:
                pending = {r["queue_id"]: r["id"] for r in c.execute(
                    "SELECT id, queue_id FROM outbox WHERE status='queued' AND queue_id<>''")}
            if pending:
                found = {}
                for line in postfix_log_lines():
                    m = STATUS_RE.search(line.strip())
                    if m and m.group(1) in pending:
                        found[m.group(1)] = (labels[m.group(2)], m.group(3)[:400])
                if found:
                    with db_lock, db() as c:
                        for qid, (st, det) in found.items():
                            c.execute("UPDATE outbox SET status=?, detail=?, updated=? WHERE id=?",
                                      (st, det, int(time.time()), pending[qid]))
        except Exception:  # noqa: BLE001
            pass
        time.sleep(20)


# ---------- лимиты ----------
def too_many(ip, email):
    now = int(time.time())
    with db_lock, db() as c:
        c.execute("DELETE FROM hits WHERE ts < ?", (now - 3600,))
        ip_hour = c.execute("SELECT count(*) FROM hits WHERE ip=?", (ip,)).fetchone()[0]
        em_hour = c.execute("SELECT count(*) FROM hits WHERE email=?", (email,)).fetchone()[0]
        em_min = c.execute("SELECT count(*) FROM hits WHERE email=? AND ts>?", (email, now - 60)).fetchone()[0]
        if ip_hour >= 10 or em_hour >= 5 or em_min >= 1:
            return True
        c.execute("INSERT INTO hits VALUES(?,?,?)", (ip, email, now))
    return False


# ---------- обработчики ----------
GENERIC_OK = "Если такая почта зарегистрирована, на неё отправлен код. Проверьте также папку «Спам»."


def reset_request(data, ip):
    email = str(data.get("email", "")).strip().lower()
    if not EMAIL_RE.match(email):
        return 400, {"code": 1, "message": "Введите почту"}
    if too_many(ip, email):
        return 429, {"code": 1, "message": "Слишком много запросов. Подождите минуту и попробуйте снова."}
    uid = find_user(email)
    if uid:
        code = f"{secrets.randbelow(1000000):06d}"
        now = int(time.time())
        with db_lock, db() as c:
            c.execute("UPDATE codes SET used=1 WHERE email=? AND used=0", (email,))
            c.execute("INSERT INTO codes(email,user_id,code_hash,created,expires,ip) VALUES(?,?,?,?,?,?)",
                      (email, uid, code_hash(email, code), now, now + CODE_TTL, ip))
        text = (
            "Здравствуйте!\n\n"
            "Кто-то запросил восстановление пароля для аккаунта PGL-RUDesk с этой почтой.\n\n"
            f"Код восстановления: {code}\n\n"
            "Код действует 15 минут. Введите его на странице восстановления пароля"
            + (f":\n{SITE_URL}/account/#forgot\n\n" if SITE_URL else ".\n\n")
            + "Если вы не запрашивали восстановление — просто проигнорируйте это письмо,\n"
            "пароль останется прежним.\n\n— PGL-RUDesk\n")
        send_mail("reset_code", email, f"Код восстановления пароля PGL-RUDesk: {code}", text, ip)
    return 200, {"code": 0, "message": GENERIC_OK}


def reset_confirm(data, ip):
    email = str(data.get("email", "")).strip().lower()
    code = re.sub(r"\D", "", str(data.get("code", "")))
    password = str(data.get("password", ""))
    if not EMAIL_RE.match(email) or len(code) != 6:
        return 400, {"code": 1, "message": "Введите почту и 6-значный код из письма"}
    if not (6 <= len(password) <= 32):
        return 400, {"code": 1, "message": "Пароль — от 6 до 32 символов"}
    now = int(time.time())
    with db_lock, db() as c:
        row = c.execute("SELECT * FROM codes WHERE email=? AND used=0 ORDER BY id DESC LIMIT 1",
                        (email,)).fetchone()
        if not row or row["expires"] < now:
            return 400, {"code": 1, "message": "Код устарел или не запрашивался. Запросите новый код."}
        if row["attempts"] >= MAX_ATTEMPTS:
            c.execute("UPDATE codes SET used=1 WHERE id=?", (row["id"],))
            return 400, {"code": 1, "message": "Слишком много неверных попыток. Запросите новый код."}
        if not hmac.compare_digest(row["code_hash"], code_hash(email, code)):
            c.execute("UPDATE codes SET attempts=attempts+1 WHERE id=?", (row["id"],))
            left = MAX_ATTEMPTS - row["attempts"] - 1
            return 400, {"code": 1, "message": f"Неверный код. Осталось попыток: {left}"}
        c.execute("UPDATE codes SET used=1 WHERE id=?", (row["id"],))
        uid = row["user_id"]
    if not set_password(uid, password):
        return 500, {"code": 1, "message": "Не удалось сменить пароль. Попробуйте позже."}
    send_mail("password_changed", email, "Пароль PGL-RUDesk изменён",
              "Здравствуйте!\n\nПароль вашего аккаунта PGL-RUDesk только что изменён.\n"
              "Все сеансы на устройствах завершены — войдите заново с новым паролем.\n\n"
              "Если это были не вы — срочно напишите администратору.\n\n— PGL-RUDesk\n", ip)
    return 200, {"code": 0, "message": "Пароль изменён. Войдите с новым паролем."}


def is_admin(token):
    if not token:
        return False
    req = urllib.request.Request(API_URL + "/api/admin/user/current", headers={"api-token": token})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            d = json.loads(r.read())
        return d.get("code") == 0 and "*" in ((d.get("data") or {}).get("route_names") or [])
    except Exception:  # noqa: BLE001
        return False


def admin_mail(query, token):
    if not is_admin(token):
        return 403, {"code": 403, "message": "Только для администратора"}
    page = max(1, int((query.get("page") or ["1"])[0] or 1))
    size = 30
    q = (query.get("q") or [""])[0].strip().lower()
    where, args = "", []
    if q:
        where, args = "WHERE lower(to_addr) LIKE ?", [f"%{q}%"]
    with db_lock, db() as c:
        total = c.execute(f"SELECT count(*) FROM outbox {where}", args).fetchone()[0]
        rows = [dict(r) for r in c.execute(
            f"SELECT id,created,kind,to_addr,subject,body,status,detail,ip FROM outbox {where} "
            "ORDER BY id DESC LIMIT ? OFFSET ?", args + [size, (page - 1) * size])]
        stats = {r[0]: r[1] for r in c.execute("SELECT status, count(*) FROM outbox GROUP BY status")}
    return 200, {"code": 0, "data": {"list": rows, "total": total, "page": page, "page_size": size,
                                     "stats": stats, "mode": SMTP_MODE, "from": MAIL_FROM}}


class Handler(BaseHTTPRequestHandler):
    server_version = "pgl-mail"

    def _ip(self):
        return (self.headers.get("X-Real-IP") or self.client_address[0])[:64]

    def _send(self, status, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        from urllib.parse import parse_qs, urlparse
        u = urlparse(self.path)
        if u.path == "/api/pgl/health":
            return self._send(200, {"code": 0, "mode": SMTP_MODE})
        if u.path == "/api/pgl/admin/mail":
            return self._send(*admin_mail(parse_qs(u.query), self.headers.get("api-token", "")))
        self._send(404, {"code": 404, "message": "not found"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n > 10000:
            return self._send(413, {"code": 1, "message": "too large"})
        try:
            data = json.loads(self.rfile.read(n) or b"{}")
            if not isinstance(data, dict):
                raise ValueError
        except Exception:  # noqa: BLE001
            return self._send(400, {"code": 1, "message": "Неверный запрос"})
        if self.path == "/api/pgl/reset/request":
            return self._send(*reset_request(data, self._ip()))
        if self.path == "/api/pgl/reset/confirm":
            return self._send(*reset_confirm(data, self._ip()))
        self._send(404, {"code": 404, "message": "not found"})

    def log_message(self, *a):
        pass


def main():
    init_db()
    threading.Thread(target=status_watcher, daemon=True).start()
    host, port = LISTEN.rsplit(":", 1)
    ThreadingHTTPServer((host, int(port)), Handler).serve_forever()


if __name__ == "__main__":
    main()
