#!/usr/bin/env python3
"""Генерирует все иконки PGL-RUDesk в папку pgl-icons/ (структура как в репозитории rustdesk)."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).parent))
from logo import (PINK, BLACK, RECTS, svg, label_geometry,  # noqa: E402
                  LABEL, LABEL_FONT, LABEL_SIZE, PLATE_RADIUS)

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "pgl-icons")
SS = 4  # суперсэмплинг для ровных краёв


def render(size, bg=True, color=PINK, scale=1.0, label=None):
    """Логотип size x size. scale<1 — логотип по центру с полями.
    label — надпись PGL на плашке (по умолчанию есть у цветных иконок, нет у силуэтов)."""
    if label is None:
        label = bg
    big = size * SS
    im = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    s = big * scale / 640
    off = (big - 640 * s) / 2
    if bg:
        d.rectangle([off, off, off + 640 * s - 1, off + 640 * s - 1], fill=BLACK + (255,))
    for a, b, c, e in RECTS:
        d.rectangle([off + a * s, off + b * s, off + c * s - 1, off + e * s - 1], fill=tuple(color) + (255,))
    if label:
        (x, y), (px1, py1, px2, py2) = label_geometry()
        d.rounded_rectangle([off + px1 * s, off + py1 * s, off + px2 * s - 1, off + py2 * s - 1],
                            radius=PLATE_RADIUS * s, fill=BLACK + (255,))
        d.text((off + x * s, off + y * s), LABEL, anchor="lt", fill=PINK + (255,),
               font=ImageFont.truetype(LABEL_FONT, max(1, round(LABEL_SIZE * s))))
    return im.resize((size, size), Image.LANCZOS)


def masked(im, shape, radius_ratio=0.18):
    size = im.size[0]
    m = Image.new("L", (size * SS, size * SS), 0)
    d = ImageDraw.Draw(m)
    if shape == "circle":
        d.ellipse([0, 0, size * SS - 1, size * SS - 1], fill=255)
    else:
        d.rounded_rectangle([0, 0, size * SS - 1, size * SS - 1], radius=size * SS * radius_ratio, fill=255)
    m = m.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), m)
    return out


def save(im, rel, **kw):
    p = OUT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    im.save(p, **kw)


def ico(rel, sizes):
    big = render(256)
    save(big, rel, format="ICO", sizes=[(s, s) for s in sizes])


# ---------- общие (Windows / Linux) ----------
save(render(1024), "res/icon.png")
for s, name in [(32, "32x32.png"), (64, "64x64.png"), (128, "128x128.png"), (256, "128x128@2x.png")]:
    save(render(s), f"res/{name}")
ico("res/icon.ico", [16, 24, 32, 48, 64, 128, 256])
ico("res/tray-icon.ico", [16, 24, 32, 48])
ico("flutter/windows/runner/resources/app_icon.ico", [16, 24, 32, 48, 64, 128, 256])
for rel in ["res/logo.svg", "res/scalable.svg", "flutter/assets/icon.svg"]:
    (OUT / rel).parent.mkdir(parents=True, exist_ok=True)
    (OUT / rel).write_text(svg(), encoding="utf-8")
save(render(512), "flutter/assets/icon.png")

# ---------- macOS ----------
mac = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
mac.paste(masked(render(824), "round", 0.225), (100, 100))  # сетка иконок Apple
save(mac, "res/mac-icon.png")
save(mac, "flutter/macos/Runner/AppIcon.icns", format="ICNS")
# значок в строке меню: силуэт розовых полос
save(render(60, bg=False, color=(26, 26, 26)), "res/mac-tray-dark-x2.png")
save(render(48, bg=False, color=(255, 255, 255)), "res/mac-tray-light-x2.png")

# ---------- Android ----------
dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
for d, k in dens.items():
    base = f"flutter/android/app/src/main/res/mipmap-{d}"
    s = int(48 * k)
    save(masked(render(s), "round", 0.12), f"{base}/ic_launcher.png")
    save(masked(render(s), "circle"), f"{base}/ic_launcher_round.png")
    # адаптивная иконка: розовые полосы на прозрачном, фон — чёрный цвет
    save(render(int(108 * k), bg=False, scale=72 / 108, label=True), f"{base}/ic_launcher_foreground.png")
    # значок уведомления: белый силуэт
    save(render(int(24 * k), bg=False, color=(255, 255, 255)).convert("LA"), f"{base}/ic_stat_logo.png")

# ---------- логотип-надпись в шапке программы (макс. 300x60) ----------
def font(size):
    for f in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"]:
        if Path(f).exists():
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def wordmark(text_color):
    h = 120
    f = font(64)
    w = h + 24 + int(ImageDraw.Draw(Image.new("RGBA", (1, 1))).textlength("PGL-RUDesk", font=f)) + 8
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    im.paste(masked(render(h), "round", 0.18), (0, 0))
    d = ImageDraw.Draw(im)
    d.text((h + 24, h / 2), "PGL-RUDesk", font=f, fill=text_color, anchor="lm")
    return im


save(wordmark((20, 20, 20, 255)), "flutter/assets/logo_light.png")
save(wordmark((240, 240, 240, 255)), "flutter/assets/logo_dark.png")
save(wordmark((20, 20, 20, 255)), "flutter/assets/logo.png")

print("Иконки созданы в", OUT)
