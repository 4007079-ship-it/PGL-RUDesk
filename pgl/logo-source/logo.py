# Векторная геометрия логотипа PGL-RUDesk (холст 640x640)
from PIL import ImageFont

PINK = (246, 74, 246)
BLACK = (0, 0, 0)
RECTS = [  # x1, y1, x2, y2
    (130, 0, 509, 64), (0, 50, 130, 106), (509, 50, 640, 106),
    (130, 131, 582, 184), (0, 174, 130, 224), (582, 174, 640, 224),
    (130, 247, 582, 301), (0, 294, 130, 337), (582, 294, 640, 337),
    (130, 364, 509, 414), (0, 407, 130, 444), (509, 407, 640, 444),
    (130, 474, 313, 517), (0, 510, 130, 540), (313, 510, 640, 540),
    (130, 580, 313, 620), (0, 613, 130, 640), (313, 613, 640, 640),
]

# Надпись PGL на чёрной плашке в правом нижнем углу (вариант 2)
LABEL = "PGL"
LABEL_FONT = "/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf"
LABEL_SIZE = 170
PLATE_PAD, PLATE_MARGIN, PLATE_RADIUS = 30, 80, 36


def label_geometry():
    """Возвращает (x, y) текста (якорь left-top) и прямоугольник плашки в координатах 640."""
    f = ImageFont.truetype(LABEL_FONT, LABEL_SIZE)
    l, t, r, b = f.getbbox(LABEL, anchor="lt")
    x, y = 640 - (r - l) - PLATE_MARGIN, 640 - (b - t) - PLATE_MARGIN
    return (x, y), (x - PLATE_PAD, y - PLATE_PAD, 640, 640)


def _label_path(x, y):
    """Буквы PGL в виде SVG-контура (не нужен шрифт у пользователя)."""
    from fontTools.ttLib import TTFont
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen
    font = TTFont(LABEL_FONT)
    k = LABEL_SIZE / font["head"].unitsPerEm
    pf = ImageFont.truetype(LABEL_FONT, LABEL_SIZE)
    # расстояние от верха (якорь "t" в PIL) до базовой линии — как в растровых иконках
    ascent = pf.getbbox(LABEL, anchor="lt")[3] - pf.getbbox(LABEL, anchor="ls")[3]
    gs, cmap, hmtx = font.getGlyphSet(), font.getBestCmap(), font["hmtx"]
    pen = SVGPathPen(gs)
    pen_x = x
    for ch in LABEL:
        g = cmap[ord(ch)]
        gs[g].draw(TransformPen(pen, (k, 0, 0, -k, pen_x, y + ascent)))
        pen_x += hmtx[g][0] * k
    return pen.getCommands()


def svg(bg=True, label=True):
    out = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 640">']
    if bg:
        out.append('<rect width="640" height="640" fill="#000"/>')
    out += [f'<rect x="{a}" y="{b}" width="{c-a}" height="{d-b}" fill="#f64af6"/>' for a, b, c, d in RECTS]
    if label:
        (x, y), (px1, py1, px2, py2) = label_geometry()
        out.append(f'<rect x="{px1}" y="{py1}" width="{px2-px1}" height="{py2-py1}" '
                   f'rx="{PLATE_RADIUS}" fill="#000"/>')
        out.append(f'<path fill="#f64af6" d="{_label_path(x, y)}"/>')
    out.append('</svg>')
    return "\n".join(out)
