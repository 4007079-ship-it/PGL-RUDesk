"""Сборка сайта PGL-RUDesk: dist/ и установщик pgl-rudesk-site-install.sh."""
import base64
import io
import shutil
import tarfile
import urllib.parse
from pathlib import Path

HERE = Path(__file__).parent
DIST = HERE / "dist"
SERVER = "157.228.187.7"
RELEASES = "https://github.com/4007079-ship-it/PGL-RUDesk/releases/tag/pgl-rudesk"
DL = "https://github.com/4007079-ship-it/PGL-RUDesk/releases/download/pgl-rudesk/"

svg = Path("/home/claude/pgl-icons/res/logo.svg").read_text(encoding="utf-8").replace("\n", "")
fav = urllib.parse.quote(svg)


def render(name):
    t = (HERE / name).read_text(encoding="utf-8")
    return (t.replace("__LOGO__", svg).replace("__FAVICON__", fav)
             .replace("__RELEASES__", RELEASES).replace("__SERVER__", SERVER)
             .replace("__DL__", DL).replace("__ADMIN_URL__", "/pgl-odmin/"))


shutil.rmtree(DIST, ignore_errors=True)
(DIST / "account").mkdir(parents=True)
(DIST / "index.html").write_text(render("template.html"), encoding="utf-8")
(DIST / "account" / "index.html").write_text(render("account-template.html"), encoding="utf-8")

buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode="w:gz", compresslevel=9) as tar:
    for f in ["index.html", "account/index.html"]:
        info = tar.gettarinfo(DIST / f, arcname=f)
        info.uid = info.gid = 0
        info.uname = info.gname = "root"
        info.mode = 0o644
        with open(DIST / f, "rb") as fh:
            tar.addfile(info, fh)
payload = base64.b64encode(buf.getvalue()).decode()

inst = (HERE / "installer-template.sh").read_text(encoding="utf-8").replace("__PAYLOAD__", payload)
Path("/home/claude/pgl-rudesk-site-install.sh").write_text(inst, encoding="utf-8")
print("dist и установщик собраны, архив", len(buf.getvalue()), "байт")
