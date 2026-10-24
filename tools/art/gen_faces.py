"""Текстуры лиц, глаз, волос и тканей персонажей (рисуются кодом по референсам пользователя).

Запуск: python3 tools/art/gen_faces.py → art/characters/textures/
  face_<id>.png  — лицо 2048², RGBA: в глазах ПРОРЕЗИ (alpha = 0), за ними глазные яблоки;
                    ресницы с отдельными штрихами, складка века, брови, тень носа, губы, румянец;
  eye_<id>.png   — глазное яблоко: склера, радужка с радиальными прожилками, зрачок, блики;
  hair_strands.png — полупрозрачная карта прядей для «карт» волос (тонируется цветом вершин);
  knit.png, rib.png, cloth.png — фактуры вязки и гладкой ткани (умножаются на цвет вещи).
Проекция лица на голову: u = 0.5 + x / (2·rx), v = 0.5 − (z − cz) / (2·rz) (см. build_characters.py).
Ориентир качества — art/references/style/13–15 и 3d/ (только как образец, без копирования).
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "art", "characters", "textures")
N = 2048
SS = 2
SKIN = (250, 230, 220)

# Геометрия лица (глаза, нос, рот) — общая с build_characters.py: tools/art/face_params.json.
import json  # noqa: E402
import sys  # noqa: E402
sys.path.insert(0, os.path.dirname(__file__))
import eye_shape  # noqa: E402
import face_table  # noqa: E402
_FACE = face_table.load()


def face_params(cid):
    return face_table.resolve(_FACE, cid)

CHARS = {
    # Кот (реф. 04): светло-голубые глаза, спокойное лицо, лёгкий румянец.
    # Ресницы, складка века и брови у Кота — объёмные (build_characters.build_lashes), на текстуре их нет.
    "kot": {"iris": (146, 162, 208), "iris_dark": (62, 72, 122), "iris_pale": (214, 226, 248), "pupil": (26, 30, 62),
            "pupil_r": 0.58, "brow": (44, 118, 120), "mouth": "lips",
            "blush": 0.45, "bags": False, "lash": (48, 36, 54), "lash_len": 1.0, "geo_lashes": True},
    # Габи (реф. 05–07): фиолетовые глаза, мягкая улыбка, ресницы гуще.
    "gabi": {"iris": (176, 146, 226), "iris_dark": (72, 44, 124), "brow": (150, 50, 70), "mouth": "smile",
             "blush": 0.65, "bags": False, "lash": (58, 32, 46), "lash_len": 1.35},
    # Хотто (реф. hotto_*): мех вместо кожи, серо-голубые прищуренные глаза, светлые брови; нос и пасть — геометрия.
    "hotto": {"iris": (150, 170, 200), "iris_dark": (60, 72, 96), "brow": (214, 196, 168), "mouth": "none",
              "blush": 0.0, "bags": False, "lash": (70, 58, 54), "lash_len": 0.8, "skin": (243, 230, 214), "muzzle": True,
              "eye_shape": "sharp"},
    # Сора (реф. 12): тёмные глаза, тени усталости, хитрая полуулыбка.
    "sora": {"iris": (104, 116, 128), "iris_dark": (28, 34, 42), "brow": (36, 92, 96), "mouth": "smirk",
             "blush": 0.3, "bags": True, "lash": (36, 30, 38), "lash_len": 0.8},
}
# Персонажи пролога (docs/STORY.md): дети — те же лица, что взрослые; остальные — черновые.
CHARS["kot_child"] = dict(CHARS["kot"], blush=0.6)
CHARS["gabi_child"] = dict(CHARS["gabi"], blush=0.75)
CHARS["sora_young"] = dict(CHARS["sora"], bags=False, mouth="smile")
CHARS.update({
    "papa": {"iris": (96, 128, 140), "iris_dark": (26, 40, 48), "brow": (30, 70, 76), "mouth": "smile",
             "blush": 0.2, "bags": False, "lash": (36, 30, 38), "lash_len": 0.75},
    "mama": {"iris": (150, 112, 160), "iris_dark": (62, 38, 70), "brow": (120, 64, 66), "mouth": "smile",
             "blush": 0.5, "bags": False, "lash": (58, 32, 46), "lash_len": 1.25},
    "girl": {"iris": (120, 92, 72), "iris_dark": (48, 30, 24), "brow": (70, 44, 40), "mouth": "smile",
             "blush": 0.7, "bags": False, "lash": (52, 34, 40), "lash_len": 1.1},
    "passerby_a": {"iris": (110, 84, 66), "iris_dark": (46, 30, 22), "brow": (96, 66, 54), "mouth": "smile",
                   "blush": 0.4, "bags": False, "lash": (52, 34, 40), "lash_len": 1.1},
    "passerby_b": {"iris": (84, 76, 70), "iris_dark": (30, 26, 24), "brow": (44, 36, 38), "mouth": "smirk",
                   "blush": 0.15, "bags": False, "lash": (36, 30, 38), "lash_len": 0.7},
    "doctor": {"iris": (92, 100, 110), "iris_dark": (30, 34, 40), "brow": (110, 110, 116), "mouth": "neutral",
               "blush": 0.1, "bags": True, "lash": (40, 36, 40), "lash_len": 0.7},
    "nurse": {"iris": (96, 74, 64), "iris_dark": (40, 26, 22), "brow": (50, 36, 40), "mouth": "smile",
              "blush": 0.45, "bags": False, "lash": (48, 32, 40), "lash_len": 1.1},
    "resident_a": {"iris": (100, 82, 64), "iris_dark": (40, 30, 22), "brow": (70, 56, 46), "mouth": "neutral",
                   "blush": 0.15, "bags": True, "lash": (40, 34, 36), "lash_len": 0.7},
    "resident_b": {"iris": (80, 72, 90), "iris_dark": (30, 26, 34), "brow": (40, 34, 44), "mouth": "neutral",
                   "blush": 0.3, "bags": False, "lash": (40, 30, 40), "lash_len": 1.0},
})
# Базы тела для просмотра (build_characters.py base_*): нейтральные карие глаза.
for _b, _m in (("teen_m", "lips"), ("teen_f", "lips"), ("adult_m", "neutral"), ("adult_f", "lips"),
               ("muscular_m", "neutral"), ("child", "lips")):
    CHARS["base_" + _b] = {"iris": (128, 96, 76), "iris_dark": (52, 34, 26), "brow": (70, 50, 46), "mouth": _m,
                           "blush": 0.35, "bags": False, "lash": (44, 32, 36), "lash_len": 1.0}


def soft(size, color, alpha, blur, draw_fn):
    m = Image.new("L", size, 0)
    draw_fn(ImageDraw.Draw(m))
    if blur:
        m = m.filter(ImageFilter.GaussianBlur(blur))
    layer = Image.new("RGBA", size, color + (255,))
    layer.putalpha(Image.fromarray((np.array(m, dtype=np.float32) * alpha).astype(np.uint8)))
    return layer


def almond(cx, cy, w, h, steps=40, lift=0.18):
    """Миндалевидный контур глаза: верх выпуклее, внешний угол чуть приподнят."""
    pts = []
    for i in range(steps + 1):
        a = math.pi * i / steps
        x = cx - w * math.cos(a)
        y = cy - h * math.sin(a) * 1.0 + (x - cx) / w * h * lift
        pts.append((x, y))
    for i in range(steps + 1):
        a = math.pi * i / steps
        x = cx + w * math.cos(a)
        y = cy + h * math.sin(a) * 0.62 + (x - cx) / w * h * lift * 0.5
        pts.append((x, y))
    return pts


def face(cid, c):
    fp = face_params(cid)
    EYE_U, EYE_V, EYE_W, EYE_H = fp["eye_u"], fp["eye_v"], fp["eye_w"], fp["eye_h"]
    NOSE_Y, MOUTH_Y = 0.5 - fp["nose_z"] / 2, 0.5 - fp["mouth_z"] / 2      # y текстуры = 0.5 − z / 2
    mk = fp["mouth_w"] / 0.032                                           # ширина рта относительно базовой

    def mx(u):
        return 0.5 + (u - 0.5) * mk
    S = N * SS
    skin = c.get("skin", SKIN)
    img = Image.new("RGBA", (S, S), skin + (255,))
    # Лёгкая объёмная тень по краям лица и под подбородком.
    img.alpha_composite(soft((S, S), (232, 196, 190), 0.55, S * 0.05,
                             lambda d: (d.rectangle((0, 0, S * 0.08, S), fill=255), d.rectangle((S * 0.92, 0, S, S), fill=255),
                                        d.rectangle((0, S * 0.93, S, S), fill=255))))
    holes = Image.new("L", (S, S), 255)
    hd = ImageDraw.Draw(holes)
    for side in (-1, 1):
        cx, cy = S * (0.5 + side * EYE_U), S * EYE_V
        w, h = S * EYE_W, S * EYE_H
        # Внешний угол — к краю лица: для правого глаза зеркалим наклон.
        pts = almond(cx, cy, w, h, lift=-fp["eye_lift"] * side)
        es = fp.get("eye_shape")
        if es:
            # Прорезь по контуру век с арта (tools/art/eye_shape.py); центр — центр радужки.
            cu, cv = 0.5 + side * EYE_U, EYE_V
            pts = [(S * u, S * v) for u, v in (eye_shape.to_uv(q, fp, side, cu, cv) for q in eye_shape.contour())]
            n_up = (len(eye_shape.UPPER) - 1) * 6 + 1
            hd.polygon(pts, fill=0)
            # Тень века на коже над прорезью и розоватое нижнее веко (как у образца-подростка).
            img.alpha_composite(soft((S, S), (206, 150, 150), 0.55, S * 0.006,
                                     lambda dd: dd.line(pts[:n_up], fill=255, width=int(S * 0.016))))
            img.alpha_composite(soft((S, S), (238, 168, 160), 0.5, S * 0.004,
                                     lambda dd: dd.line(pts[n_up - 1:] + pts[:1], fill=255, width=int(S * 0.008))))
            img.alpha_composite(soft((S, S), (242, 150, 160), c["blush"] * 0.55, S * 0.02,
                                     lambda dd: dd.ellipse((cx - w * 0.9, cy + h * 2.2, cx + w * 0.9, cy + h * 3.0), fill=255)))
            continue
        hd.polygon(pts, fill=0)
        d = ImageDraw.Draw(img)
        # Тень под верхним веком на коже (вокруг прорези) — глубина глазницы.
        img.alpha_composite(soft((S, S), (214, 160, 160), 0.6, S * 0.006, lambda dd: dd.line(pts[:41], fill=255, width=int(S * 0.012))))
        if c.get("geo_lashes"):
            img.alpha_composite(soft((S, S), (242, 150, 160), c["blush"] * 0.55, S * 0.02,
                                     lambda dd: dd.ellipse((cx - w * 0.9, cy + h * 1.6, cx + w * 0.9, cy + h * 2.4), fill=255)))
            continue
        # Складка века.
        crease = [(x, y - h * 0.42) for x, y in pts[6:36]]
        d.line(crease, fill=(196, 140, 140, 200), width=int(S * 0.0025))
        # Верхнее веко: толстая линия ресниц, к внешнему углу толще.
        up = pts[:41]
        for i in range(len(up) - 1):
            t = i / (len(up) - 1)
            outer = t if side > 0 else 1 - t
            wd = int(S * (0.006 + 0.01 * outer))
            d.line((up[i], up[i + 1]), fill=c["lash"] + (255,), width=wd)
        # Отдельные ресницы-штрихи к внешнему углу.
        rnd = random.Random(7 + side)
        for k in range(7):
            t = 0.55 + 0.45 * k / 6
            i = int(t * 40) if side > 0 else int((1 - t) * 40)
            x, y = up[i]
            L = S * 0.022 * c["lash_len"] * (0.6 + 0.6 * k / 6)
            ang = math.radians(-60 - 25 * k / 6) if side > 0 else math.radians(-120 + 25 * k / 6)
            d.line((x, y, x + math.cos(ang) * L, y + math.sin(ang) * L), fill=c["lash"] + (255,), width=int(S * 0.004))
        # Нижнее веко — тонкая неполная линия.
        low = pts[41:]
        d.line(low[8:33], fill=c["lash"] + (150,), width=int(S * 0.003))
        if c["bags"]:
            d.arc((cx - w * 0.9, cy + h * 0.1, cx + w * 0.9, cy + h * 1.6), 25, 155, fill=(176, 120, 150, 150), width=int(S * 0.004))
        # Брови.
        bx = cx + side * S * 0.004
        d.arc((bx - w * 1.15, cy - h * 3.0, bx + w * 1.15, cy - h * 0.9), 205 if side > 0 else 215, 325 if side > 0 else 335,
              fill=c["brow"] + (255,), width=int(S * 0.006))
        # Румянец.
        img.alpha_composite(soft((S, S), (242, 150, 160), c["blush"] * 0.55, S * 0.02,
                                 lambda dd: dd.ellipse((cx - w * 0.9, cy + h * 1.6, cx + w * 0.9, cy + h * 2.4), fill=255)))
    d = ImageDraw.Draw(img)
    if c.get("muzzle"):
        # Морда (Хотто): нос и пасть — геометрия головы, на текстуре только глаза и брови.
        img.putalpha(Image.fromarray(np.minimum(np.array(img.split()[3]), np.array(holes))))
        img.resize((N, N), Image.LANCZOS).save(os.path.join(OUT, f"face_{cid}.png"))
        return
    # Нос: мягкая тень сбоку и блик.
    img.alpha_composite(soft((S, S), (220, 168, 160), 0.7, S * 0.004,
                             lambda dd: dd.line((S * 0.506, S * (NOSE_Y - 0.045), S * 0.5, S * (NOSE_Y + 0.005)), fill=255, width=int(S * 0.005))))
    img.alpha_composite(soft((S, S), (255, 250, 246), 0.8, S * 0.003,
                             lambda dd: dd.ellipse((S * 0.493, S * (NOSE_Y - 0.012), S * 0.499, S * (NOSE_Y - 0.005)), fill=255)))
    # Тень под кончиком носа.
    img.alpha_composite(soft((S, S), (212, 150, 148), 0.8, S * 0.004,
                             lambda dd: dd.ellipse((S * 0.484, S * (NOSE_Y + 0.008), S * 0.516, S * (NOSE_Y + 0.016)), fill=255)))
    # Губы.
    mc = (176, 96, 104, 255)
    mw = int(S * 0.0045)
    my = MOUTH_Y - 0.0
    if c["mouth"] == "lips":
        # Спокойные губы (реф. 16): тонкая линия рта, мягкая розовая нижняя губа, лёгкая тень под ней.
        img.alpha_composite(soft((S, S), (236, 160, 160), 0.75, S * 0.005,
                                 lambda dd: dd.ellipse((S * mx(0.478), S * (my + 0.004), S * mx(0.522), S * (my + 0.02)), fill=255)))
        img.alpha_composite(soft((S, S), (232, 172, 170), 0.5, S * 0.004,
                                 lambda dd: dd.ellipse((S * mx(0.474), S * (my - 0.016), S * mx(0.526), S * (my - 0.002)), fill=255)))
        img.alpha_composite(soft((S, S), (214, 170, 166), 0.35, S * 0.006,
                                 lambda dd: dd.ellipse((S * mx(0.485), S * (my + 0.03), S * mx(0.515), S * (my + 0.042)), fill=255)))
        d = ImageDraw.Draw(img)
        d.line([(S * mx(0.468), S * (my + 0.002)), (S * mx(0.485), S * my), (S * 0.5, S * (my + 0.0015)), (S * mx(0.515), S * my), (S * mx(0.532), S * (my + 0.002))],
               fill=(150, 80, 90, 255), width=int(S * 0.0045), joint="curve")
    elif c["mouth"] == "neutral":
        d.arc((S * 0.47, S * (my - 0.012), S * 0.53, S * (my + 0.013)), 25, 155, fill=mc, width=mw)
    elif c["mouth"] == "smile":
        d.arc((S * 0.46, S * (my - 0.027), S * 0.54, S * (my + 0.018)), 20, 160, fill=mc, width=mw)
        img.alpha_composite(soft((S, S), (232, 140, 150), 0.35, S * 0.004, lambda dd: dd.ellipse((S * 0.485, S * (my + 0.016), S * 0.515, S * (my + 0.026)), fill=255)))
    else:
        d.arc((S * 0.47, S * (my - 0.027), S * 0.55, S * (my + 0.018)), 15, 120, fill=mc, width=mw)
        d.line((S * 0.468, S * (my - 0.004), S * 0.48, S * (my - 0.001)), fill=mc, width=mw)
    img.putalpha(Image.fromarray(np.minimum(np.array(img.split()[3]), np.array(holes))))
    img.resize((N, N), Image.LANCZOS).save(os.path.join(OUT, f"face_{cid}.png"))


# ------------------------------------------------------------------ сменные лица (просьба пользователя 24.10)
# Лицо собирается в игре из слоёв (art/shaders/toon_face.gdshader, src/visual/face_rig.gd):
#   face_<id>.png               — кожа лица: мягкая тень по краям, нос (линия только под кончиком), прорези глаз
#                                 и тень вокруг них — для формы глаза «default»;
#   faces/face_<id>__<форма>.png — то же для форм round / sharp и закрытых глаз closed (^^) / blink;
#   faces/makeup_<id>.png       — маски макияжа: R — румянец, G — тени вокруг глаз (цвет и сила задаёт стиль лица);
#   faces/mouths.png            — общий атлас ртов 4×2 (выражения), каналы: R — линия, G — губы, B — рот внутри;
#   faces/iris_patterns.png     — общий атлас узоров зрачка 4×2 (бабочка, сердце, звезда, цветок, искры, луна, вихрь).
# По видео 2AM (docs/MODEL_STUDY.md): кожа мягкая, румянец под глазами и на носу, нос — только линия снизу,
# линия губ тоньше к середине, уголки чуть подчёркнуты.
FACES_OUT = os.path.join(os.path.dirname(__file__), "..", "..", "art", "characters", "faces")
FACE_VARIANTS = ("default", "round", "sharp", "closed", "blink")
MOUTHS = ("neutral", "smile", "surprised", "serious", "happy", "smirk", "pout", "cat")
IRIS_PATTERNS = ("none", "butterfly", "heart", "star", "flower", "sparkles", "moon", "swirl")


def _eye_geom(fp, side, S, variant="default"):
    """Контур прорези в пикселях, центр глаза и «единица» U в пикселях по высоте и ширине."""
    cu, cv = 0.5 + side * fp["eye_u"], fp["eye_v"]
    pts = [(S * u, S * v) for u, v in (eye_shape.to_uv(q, fp, side, cu, cv)
                                        for q in eye_shape.contour(6, variant if variant in eye_shape.VARIANTS else "default"))]
    um = eye_shape.unit_m(fp)
    es = fp["eye_shape"]
    ux, uz = S * um / (2 * es["head_rx"]), S * um / (2 * es["head_rz"])
    return pts, (S * cu, S * cv), ux, uz


def _uv(fp, side, q, S):
    cu, cv = 0.5 + side * fp["eye_u"], fp["eye_v"]
    u, v = eye_shape.to_uv(q, fp, side, cu, cv)
    return S * u, S * v


def face_v2(cid, c, variant="default"):
    """Кожа лица со слоями вокруг глаз для формы variant (см. шапку раздела)."""
    fp = face_params(cid)
    NOSE_Y = 0.5 - fp["nose_z"] / 2
    S = N * SS
    skin = c.get("skin", SKIN)
    img = Image.new("RGBA", (S, S), skin + (255,))
    shade = tuple(max(0, int(v * 0.9)) for v in skin)
    # мягкая объёмная тень к краям лица и под подбородком (ровная заливка в центре — «аниме-кожа»)
    img.alpha_composite(soft((S, S), shade, 0.45, S * 0.06,
                             lambda d: (d.rectangle((0, 0, S * 0.06, S), fill=255), d.rectangle((S * 0.94, 0, S, S), fill=255),
                                        d.rectangle((0, S * 0.95, S, S), fill=255))))
    holes = Image.new("L", (S, S), 255)
    hd = ImageDraw.Draw(holes)
    lash = c.get("lash", (48, 36, 54))
    for side in (-1, 1):
        n_up = (len(eye_shape.UPPER) - 1) * 6 + 1
        if variant in ("closed", "blink"):
            pts, (cx, cy), ux, uz = _eye_geom(fp, side, S)
            up = pts[:n_up]
            if variant == "closed":
                # «^^»: дуга выпуклостью вверх на уровне середины глаза
                xs = [p[0] for p in up]
                x0, x1 = min(xs), max(xs)
                arc = [(x0 + (x1 - x0) * t, cy - uz * 0.02 - uz * 0.11 * math.sin(math.pi * t)) for t in (k / 30 for k in range(31))]
            else:
                # моргание: веко опущено — линия по нижнему краю, чуть провисает
                lo = pts[n_up - 1:]
                arc = [(p[0], p[1] - uz * 0.035) for p in lo]
            img.alpha_composite(soft((S, S), (206, 150, 150), 0.45, S * 0.008,
                                     lambda dd: dd.line(arc, fill=255, width=int(S * 0.02))))
            d = ImageDraw.Draw(img)
            for i in range(len(arc) - 1):
                t = i / (len(arc) - 1)
                outer = t if (arc[-1][0] - arc[0][0]) * side > 0 else 1 - t
                d.line((arc[i], arc[i + 1]), fill=lash + (255,), width=max(2, int(S * (0.003 + 0.0045 * outer))))
            continue
        pts, (cx, cy), ux, uz = _eye_geom(fp, side, S, variant)
        hd.polygon(pts, fill=0)
        up = pts[:n_up]
        lo = pts[n_up - 1:] + pts[:1]
        # тень века над прорезью и розоватое нижнее веко (глубина глазницы, «зоны вокруг глаз»)
        img.alpha_composite(soft((S, S), (204, 146, 148), 0.5, S * 0.007,
                                 lambda dd: dd.line(up, fill=255, width=int(S * 0.018))))
        img.alpha_composite(soft((S, S), (236, 164, 158), 0.55, S * 0.004,
                                 lambda dd: dd.line(lo, fill=255, width=int(S * 0.008))))
        # внутренний уголок — тёплая розовая точка (слёзное мясцо)
        ix, iy = min(pts, key=lambda p: p[0] * side)
        img.alpha_composite(soft((S, S), (232, 150, 150), 0.6, S * 0.003,
                                 lambda dd: dd.ellipse((ix - ux * 0.035, iy - uz * 0.03, ix + ux * 0.035, iy + uz * 0.03), fill=255)))
    if c.get("muzzle"):
        # морда (Хотто): нос и пасть — геометрия головы, на текстуре только глаза
        img.putalpha(Image.fromarray(np.minimum(np.array(img.split()[3]), np.array(holes))))
        out = img.resize((N, N), Image.LANCZOS)
        if variant == "default":
            out.save(os.path.join(OUT, f"face_{cid}.png"))
        else:
            os.makedirs(FACES_OUT, exist_ok=True)
            out.resize((N // 2, N // 2), Image.LANCZOS).save(os.path.join(FACES_OUT, f"face_{cid}__{variant}.png"))
        return
    # Нос — только мягкая линия под кончиком и маленький блик (видео 2AM)
    nx0, nx1, ny = S * 0.489, S * 0.511, S * (NOSE_Y + 0.006)
    img.alpha_composite(soft((S, S), (196, 124, 124), 0.9, S * 0.0018,
                             lambda dd: dd.arc((nx0, ny - S * 0.007, nx1, ny + S * 0.004), 25, 155, fill=255, width=int(S * 0.0036))))
    img.alpha_composite(soft((S, S), (226, 170, 162), 0.5, S * 0.006,
                             lambda dd: dd.ellipse((S * 0.502, S * (NOSE_Y - 0.03), S * 0.512, S * (NOSE_Y + 0.004)), fill=255)))
    img.alpha_composite(soft((S, S), (255, 252, 250), 0.9, S * 0.002,
                             lambda dd: dd.ellipse((S * 0.494, S * (NOSE_Y - 0.012), S * 0.5, S * (NOSE_Y - 0.006)), fill=255)))
    img.putalpha(Image.fromarray(np.minimum(np.array(img.split()[3]), np.array(holes))))
    out = img.resize((N, N), Image.LANCZOS)
    if variant == "default":
        out.save(os.path.join(OUT, f"face_{cid}.png"))
    else:
        os.makedirs(FACES_OUT, exist_ok=True)
        out.resize((N // 2, N // 2), Image.LANCZOS).save(os.path.join(FACES_OUT, f"face_{cid}__{variant}.png"))


def _hex(c):
    return "#%02x%02x%02x" % tuple(int(v) for v in c)


def face_info(cid, c):
    """faces/<id>.json для игры: прямоугольник рта в UV лица и стиль лица героя по умолчанию."""
    fp = face_params(cid)
    mw = fp["mouth_w"]
    info = {
        "_comment": "Сгенерировано tools/art/gen_faces.py: рот (центр u, v; полуширина, полувысота в UV лица) "
                    "и стиль лица по умолчанию (src/visual/face_rig.gd).",
        # клетка атласа на 2.2·mouth_w в каждую сторону: спокойный рот ≈ 1.2 см у Кота (было 5 мм — почти не видно)
        "mouth_rect": [0.5, round(0.5 - fp["mouth_z"] / 2, 4), round(mw * 2.2, 4), round(mw * 1.4, 4)],
        "default": {
            "expression": {"lips": "neutral", "smile": "smile", "smirk": "smirk", "neutral": "neutral"}.get(c["mouth"], "neutral"),
            "eye_shape": c.get("eye_shape", "default"),
            "makeup": {"blush": "#f296a0", "blush_amount": round(0.2 + c["blush"] * 0.45, 3),
                       "eyeshadow": "#cf8486", "eyeshadow_amount": 0.38 if c.get("lash_len", 1.0) >= 1.0 else 0.22,
                       "lips": "#e48a96", "lips_amount": 0.5},
            "iris": {"tint": 0.0, "top": _hex(c["iris_dark"]), "bottom": _hex(c["iris"]), "pattern": "none",
                     "pattern_color": "#ffffff", "rainbow": 0.0, "sparkle": 0.0},
        },
    }
    if c.get("muzzle"):
        del info["mouth_rect"]          # рот — геометрия морды, атлас ртов не нужен
    os.makedirs(FACES_OUT, exist_ok=True)
    with open(os.path.join(FACES_OUT, f"{cid}.json"), "w", encoding="utf-8") as f:
        json.dump(info, f, ensure_ascii=False, indent=1)


def makeup_mask(cid, size=512):
    """Маски макияжа (R — румянец, G — тени вокруг глаз) в координатах текстуры лица."""
    fp = face_params(cid)
    S = size * 4
    R = Image.new("L", (S, S), 0)
    G = Image.new("L", (S, S), 0)
    dr, dg = ImageDraw.Draw(R), ImageDraw.Draw(G)
    NOSE_Y = 0.5 - fp["nose_z"] / 2
    for side in (-1, 1):
        pts, (cx, cy), ux, uz = _eye_geom(fp, side, S)
        n_up = (len(eye_shape.UPPER) - 1) * 6 + 1
        lo_y = max(p[1] for p in pts)
        # румянец: овал под глазом, чуть к виску
        bx = cx + side * ux * 0.05
        dr.ellipse((bx - ux * 0.3, lo_y + uz * 0.1, bx + ux * 0.3, lo_y + uz * 0.38), fill=255)
        # тени: полоса над верхним веком (шире к внешнему углу) и хвостик под внешним углом
        up = pts[:n_up]
        band = [(p[0], p[1] - uz * (0.05 + 0.07 * (abs(p[0] - cx) / ux))) for p in up] + \
               [(p[0], p[1] + uz * 0.01) for p in reversed(up)]
        dg.polygon(band, fill=255)
        ox, oy = max(pts, key=lambda p: p[0] * side)
        dg.ellipse((ox - ux * 0.07, oy - uz * 0.04, ox + ux * 0.05, oy + uz * 0.08), fill=200)
    # лёгкий румянец через переносицу (аниме-штрих)
    dr.ellipse((S * 0.44, S * (NOSE_Y - 0.075), S * 0.56, S * (NOSE_Y - 0.035)), fill=120)
    R = R.filter(ImageFilter.GaussianBlur(S * 0.018))
    G = G.filter(ImageFilter.GaussianBlur(S * 0.008))
    img = Image.merge("RGBA", (R, G, Image.new("L", (S, S), 0), Image.new("L", (S, S), 255)))
    os.makedirs(FACES_OUT, exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(os.path.join(FACES_OUT, f"makeup_{cid}.png"))


def mouths(cell=256):
    """Общий атлас ртов 4×2 (порядок — MOUTHS). Рот занимает середину клетки; игра растягивает клетку на
    прямоугольник рта лица (4.4·mouth_w × 2.8·mouth_w в UV лица — по высоте клетка сжата). R — линия, G — губы,
    B — рот внутри."""
    C = cell * 4
    W, H = C * 4, C * 2
    chans = [Image.new("L", (W, H), 0) for _ in range(3)]
    d = [ImageDraw.Draw(ch) for ch in chans]

    def line(i, pts, w0, w1=None):
        """Линия губ: тоньше к середине, уголки толще (видео 2AM)."""
        ox, oy = (i % 4) * C, (i // 4) * C
        P = [(ox + x * C, oy + y * C) for x, y in pts]
        n = len(P) - 1
        for k in range(n):
            t = abs((k + 0.5) / n - 0.5) * 2               # 0 — середина, 1 — уголки
            wd = (w0 + ((w1 if w1 is not None else w0 * 1.8) - w0) * t ** 1.5) * C
            d[0].line((P[k], P[k + 1]), fill=255, width=max(2, int(wd)))
            d[0].ellipse((P[k + 1][0] - wd / 2, P[k + 1][1] - wd / 2, P[k + 1][0] + wd / 2, P[k + 1][1] + wd / 2), fill=255)

    def blob(i, ch, x0, y0, x1, y1, v=255):
        ox, oy = (i % 4) * C, (i // 4) * C
        d[ch].ellipse((ox + x0 * C, oy + y0 * C, ox + x1 * C, oy + y1 * C), fill=v)

    def poly(i, ch, pts, v=255):
        ox, oy = (i % 4) * C, (i // 4) * C
        d[ch].polygon([(ox + x * C, oy + y * C) for x, y in pts], fill=v)

    def curve(x0, x1, y_mid, y_end, n=24):
        return [(x0 + (x1 - x0) * t, y_end + (y_mid - y_end) * math.sin(math.pi * t)) for t in (k / n for k in range(n + 1))]
    # 0 спокойный: короткая линия, нижняя губа — мягкий розовый овал
    line(0, curve(0.36, 0.64, 0.5, 0.505), 0.012)
    blob(0, 1, 0.42, 0.52, 0.58, 0.6, 200)
    # 1 улыбка: уголки вверх
    line(1, curve(0.32, 0.68, 0.53, 0.47), 0.012)
    blob(1, 1, 0.42, 0.55, 0.58, 0.61, 150)
    # 2 удивление: маленькое «о»
    blob(2, 2, 0.44, 0.42, 0.56, 0.6)
    blob(2, 1, 0.46, 0.53, 0.54, 0.6, 160)
    line(2, [(0.44 + 0.06 * (1 - math.cos(a)), 0.51 - 0.09 * math.sin(a)) for a in (math.pi * k / 16 for k in range(17))], 0.009, 0.011)
    # 3 серьёзный: прямая, уголки чуть вниз, губы почти без цвета
    line(3, [(0.34, 0.515), (0.4, 0.5), (0.5, 0.5), (0.6, 0.5), (0.66, 0.515)], 0.011)
    blob(3, 1, 0.44, 0.52, 0.56, 0.57, 90)
    # 4 радость: открытый рот «D», внутри тёмный, снизу язычок
    top = [(0.3 + 0.4 * t, 0.45 + 0.012 * math.sin(math.pi * t)) for t in (k / 16 for k in range(17))]
    bot = [(0.7 - 0.4 * t, 0.46 + 0.2 * math.sin(math.pi * t)) for t in (k / 16 for k in range(17))]
    poly(4, 2, top + bot)
    blob(4, 1, 0.42, 0.56, 0.58, 0.67, 220)
    line(4, top, 0.012)
    # 5 ухмылка: один уголок вверх
    line(5, [(0.36, 0.52), (0.45, 0.515), (0.55, 0.5), (0.62, 0.475), (0.67, 0.45)], 0.011)
    blob(5, 1, 0.44, 0.52, 0.58, 0.58, 140)
    # 6 «надутые губы»: маленький круглый рот
    blob(6, 1, 0.43, 0.44, 0.57, 0.6, 255)
    line(6, curve(0.45, 0.55, 0.51, 0.505), 0.01)
    # 7 «:3» — кошачий рот
    for x0 in (0.38, 0.5):
        line(7, [(x0 + 0.12 * t, 0.49 + 0.05 * math.sin(math.pi * t)) for t in (k / 12 for k in range(13))], 0.01, 0.012)
    chans = [ch.filter(ImageFilter.GaussianBlur(C * 0.004)) for ch in chans]
    a = np.maximum.reduce([np.array(ch) for ch in chans])
    img = Image.merge("RGBA", chans + [Image.fromarray(a)])
    os.makedirs(FACES_OUT, exist_ok=True)
    img.resize((W // 4, H // 4), Image.LANCZOS).save(os.path.join(FACES_OUT, "mouths.png"))


def iris_patterns(cell=256):
    """Общий атлас узоров зрачка 4×2 (порядок — IRIS_PATTERNS): белые формы, игра тонирует цветом узора."""
    C = cell * 4
    W, H = C * 4, C * 2
    A = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(A)

    def cxy(i):
        return (i % 4) * C + C / 2, (i // 4) * C + C / 2

    # 1 бабочка: четыре крыла и тельце
    x, y = cxy(1)
    for sx in (-1, 1):
        d.ellipse((x + sx * C * 0.02 - (C * 0.26 if sx < 0 else 0), y - C * 0.3, x + sx * C * 0.02 + (C * 0.26 if sx > 0 else 0), y + C * 0.02), fill=255)
        d.ellipse((x + sx * C * 0.02 - (C * 0.19 if sx < 0 else 0), y - C * 0.02, x + sx * C * 0.02 + (C * 0.19 if sx > 0 else 0), y + C * 0.26), fill=255)
    d.rectangle((x - C * 0.02, y - C * 0.24, x + C * 0.02, y + C * 0.24), fill=0)
    d.ellipse((x - C * 0.025, y - C * 0.22, x + C * 0.025, y + C * 0.2), fill=255)
    # 2 сердце
    x, y = cxy(2)
    d.polygon([(x - C * 0.33, y - C * 0.06), (x, y + C * 0.32), (x + C * 0.33, y - C * 0.06)], fill=255)
    for sx in (-1, 1):
        d.ellipse((x + sx * C * 0.165 - C * 0.175, y - C * 0.3, x + sx * C * 0.165 + C * 0.175, y + C * 0.04), fill=255)
    # 3 звезда
    x, y = cxy(3)
    star = [(x + C * (0.34 if k % 2 == 0 else 0.14) * math.sin(math.pi * k / 5),
             y - C * (0.34 if k % 2 == 0 else 0.14) * math.cos(math.pi * k / 5)) for k in range(10)]
    d.polygon(star, fill=255)
    # 4 цветок: пять лепестков и пустая серединка
    x, y = cxy(4)
    for k in range(5):
        a = 2 * math.pi * k / 5 - math.pi / 2
        px, py = x + math.cos(a) * C * 0.18, y + math.sin(a) * C * 0.18
        d.ellipse((px - C * 0.14, py - C * 0.14, px + C * 0.14, py + C * 0.14), fill=255)
    d.ellipse((x - C * 0.07, y - C * 0.07, x + C * 0.07, y + C * 0.07), fill=0)
    # 5 искры (сказочный мир): большая четырёхлучевая и две маленькие
    x, y = cxy(5)
    for (dx, dy, r) in ((0, 0, 0.3), (0.24, -0.22, 0.1), (-0.24, 0.2, 0.08)):
        px, py = x + dx * C, y + dy * C
        q = r * C
        d.polygon([(px, py - q), (px + q * 0.22, py - q * 0.22), (px + q, py), (px + q * 0.22, py + q * 0.22),
                   (px, py + q), (px - q * 0.22, py + q * 0.22), (px - q, py), (px - q * 0.22, py - q * 0.22)], fill=255)
    # 6 полумесяц
    x, y = cxy(6)
    d.ellipse((x - C * 0.3, y - C * 0.3, x + C * 0.3, y + C * 0.3), fill=255)
    d.ellipse((x - C * 0.16, y - C * 0.36, x + C * 0.4, y + C * 0.2), fill=0)
    # 7 вихрь: спираль
    x, y = cxy(7)
    pts = [(x + math.cos(t) * C * 0.035 * t, y + math.sin(t) * C * 0.035 * t) for t in (k * 0.12 for k in range(80))]
    d.line(pts, fill=255, width=int(C * 0.05), joint="curve")
    A = A.filter(ImageFilter.GaussianBlur(C * 0.004))
    img = Image.merge("RGBA", (Image.new("L", (W, H), 255),) * 3 + (A,))
    os.makedirs(FACES_OUT, exist_ok=True)
    img.resize((W // 4, H // 4), Image.LANCZOS).save(os.path.join(FACES_OUT, "iris_patterns.png"))


def eye(cid, c, size=512):
    """Глазное яблоко: склера с тенью от века, радужка с тонкими волокнами, тёмный лимб, светлое кольцо
    у зрачка, «каустика» снизу, зрачок, блики (как на реф. 16)."""
    S = size * SS
    img = Image.new("RGBA", (S, S), (250, 249, 252, 255))
    cx = cy = S / 2
    img.alpha_composite(soft((S, S), (176, 166, 198), 0.85, S * 0.06, lambda d: d.rectangle((0, 0, S, S * 0.3), fill=255)))
    r = S * 0.36
    ys = np.linspace(-1, 1, S)[:, None]
    xs = np.linspace(-1, 1, S)[None, :]
    rr = np.sqrt((xs / 0.72) ** 2 + (ys / 0.72) ** 2)
    ang = np.arctan2(ys, xs)
    t = np.clip((ys + 0.72) / 1.44, 0, 1)
    dark, light = np.array(c["iris_dark"], np.float32), np.array(c["iris"], np.float32)
    col = dark[None, None, :] * (1 - t[..., None] ** 1.2) + light[None, None, :] * (t[..., None] ** 1.2)
    rnd = np.random.default_rng(11)
    fib = np.zeros_like(ang)
    for f, a in ((38, 0.05), (71, 0.04), (113, 0.035), (167, 0.03)):
        fib += a * np.sin(ang * f + rnd.uniform(0, 6.28) + rr * rnd.uniform(2, 6))
    col = col * (0.95 + fib)[..., None]
    collar = np.exp(-((rr - 0.5) / 0.08) ** 2)[..., None]          # светлое кольцо вокруг зрачка
    col = col * (1 - collar * 0.25) + light[None, None, :] * 1.15 * collar * 0.25
    rim = np.clip((rr - 0.8) / 0.2, 0, 1)[..., None]
    col = col * (1 - rim ** 1.5 * 0.75)
    alpha = np.clip((1.0 - rr) * 60, 0, 1) * 255
    iris = Image.fromarray(np.dstack([np.clip(col, 0, 255), alpha]).astype(np.uint8), "RGBA")
    img.alpha_composite(iris)
    pr = r * 0.34
    img.alpha_composite(soft((S, S), tuple(int(v * 0.25) for v in c["iris_dark"]), 1.0, S * 0.004,
                             lambda d: d.ellipse((cx - pr, cy - pr * 1.08, cx + pr, cy + pr * 1.08), fill=255)))
    img.alpha_composite(soft((S, S), tuple(min(255, v + 60) for v in c["iris"]), 0.55, S * 0.03,
                             lambda dd: dd.ellipse((cx - r * 0.62, cy + r * 0.3, cx + r * 0.62, cy + r * 0.9), fill=255)))
    img.alpha_composite(soft((S, S), (40, 40, 70), 0.35, S * 0.04,
                             lambda dd: dd.rectangle((0, 0, S, cy - r * 0.45), fill=255)))        # тень от ресниц на радужке
    img.alpha_composite(soft((S, S), (255, 255, 255), 1.0, S * 0.003,
                             lambda dd: dd.ellipse((cx - r * 0.58, cy - r * 0.62, cx - r * 0.16, cy - r * 0.22), fill=255)))
    img.alpha_composite(soft((S, S), (255, 255, 255), 0.85, S * 0.002,
                             lambda dd: dd.ellipse((cx + r * 0.28, cy + r * 0.32, cx + r * 0.44, cy + r * 0.48), fill=255)))
    img.alpha_composite(soft((S, S), (255, 255, 255), 0.7, S * 0.002,
                             lambda dd: dd.ellipse((cx + r * 0.05, cy - r * 0.52, cx + r * 0.13, cy - r * 0.44), fill=255)))
    img.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, f"eye_{cid}.png"))


# Радужка, присланная пользователем (23.10): круг вырезается по центру и радиусу.
USER_IRIS = {"kot": ("art/characters/textures/src/iris_kot_user.png", (506, 577), 490)}
USER_IRIS["kot_child"] = USER_IRIS["kot"]


def iris_from_user(cid, size=1024):
    src, (cx, cy), r = USER_IRIS[cid]
    im = Image.open(os.path.join(os.path.dirname(__file__), "..", "..", src)).convert("RGB")
    im = im.crop((cx - r, cy - r, cx + r, cy + r)).resize((size, size), Image.LANCZOS).convert("RGBA")
    ys = np.linspace(-1, 1, size)[:, None]
    xs = np.linspace(-1, 1, size)[None, :]
    rr = np.sqrt(xs ** 2 + ys ** 2)
    # Тень верхнего века и ресниц на радужке (как у образца-подростка): верх темнее, мягкий переход.
    a = np.asarray(im).astype(np.float32)
    shade = 1 - 0.6 * np.clip((0.25 - ys) / 0.85, 0, 1) ** 1.4
    a[..., :3] *= shade[..., None] * np.ones_like(xs)[..., None]
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
    im.putalpha(Image.fromarray((np.clip((1.0 - rr) * 120, 0, 1) * 255).astype(np.uint8)))
    im.save(os.path.join(OUT, f"iris_{cid}.png"))


def iris(cid, c, size=1024):
    """Радужка отдельным диском (как у образца-подростка: радужка — свой меш перед склерой).
    Сверху темнее (тень века и ресниц), книзу светлее; тёмный лимб; крупный вертикальный зрачок со светлой
    каймой и тёмным кольцом (реф. 16 — зрачок-кольцо); радиальные волокна и штрихи вокруг зрачка;
    светлый серп внизу. Блики — отдельной геометрией. RGBA: вне диска прозрачно."""
    S = size * SS
    ys = np.linspace(-1, 1, S)[:, None]
    xs = np.linspace(-1, 1, S)[None, :]
    rr = np.sqrt(xs ** 2 + ys ** 2)
    ang = np.arctan2(ys, xs)
    dark = np.array(c["iris_dark"], np.float32)
    light = np.array(c["iris"], np.float32)
    pale = np.array(c.get("iris_pale", tuple(min(255, int(v * 1.35 + 40)) for v in c["iris"])), np.float32)
    t = np.clip((ys + 1) / 2, 0, 1)[..., None]                       # 0 — верх, 1 — низ
    col = dark * (1 - t) ** 1.6 + light * (1 - (1 - t) ** 1.6)
    rnd = np.random.default_rng(23)
    fib = np.zeros_like(rr)
    for f, a in ((29, 0.06), (53, 0.05), (97, 0.04), (151, 0.03)):
        fib += a * np.sin(ang * f + rnd.uniform(0, 6.28) + rr * rnd.uniform(3, 9))
    col = col * (0.94 + fib * np.clip((rr - 0.4) / 0.3, 0, 1))[..., None]
    # Светлый серп снизу (свет проходит сквозь радужку) — мягкий, внутри лимба.
    cres = np.exp(-((xs / 0.62) ** 2 + ((ys - 0.5) / 0.3) ** 2) * 1.6)[..., None]
    col = col * (1 - cres * 0.72) + pale * cres * 0.72
    # Лимб: тёмное кольцо по краю.
    rim = np.clip((rr - 0.78) / 0.18, 0, 1)[..., None]
    col = col * (1 - rim ** 1.3 * 0.72) + dark * 0.35 * rim ** 1.3 * 0.72
    # Тень века/ресниц сверху.
    top = np.clip((-ys - 0.25) / 0.6, 0, 1)[..., None]
    col = col * (1 - top * 0.45)
    # Зрачок: вертикальный овал, крупный.
    pr = c.get("pupil_r", 0.5)
    pe = np.sqrt((xs / (pr * 0.82)) ** 2 + ((ys + 0.02) / pr) ** 2)
    ring = np.exp(-((pe - 1.0) / 0.06) ** 2)[..., None]               # тёмное кольцо по краю зрачка
    halo = np.exp(-((pe - 1.12) / 0.07) ** 2)[..., None]              # светлая кайма снаружи
    inside = (pe < 1.0)[..., None]
    pd = np.array(c.get("pupil", (22, 24, 52)), np.float32)
    core = np.clip(1 - pe, 0, 1)[..., None]
    pin = pd * (1 - t * 0.7) + light * 0.45 * t * 0.7                 # внутри зрачка — книзу светлее (глубина)
    pin = pin * (1 - core * 0.25) + np.array(c["iris_dark"], np.float32) * core * 0.25   # мягкая глубина в центре
    col = np.where(inside, pin, col)
    col = col * (1 - ring * 0.8) + pd * ring * 0.8
    col = col * (1 - halo * 0.45) + pale * halo * 0.45
    # Штрихи вокруг зрачка в нижней половине (как у образца): короткие тёмные радиальные чёрточки.
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    d = ImageDraw.Draw(img)
    cx = cy = S / 2
    rnd2 = random.Random(5)
    for k in range(30):
        a = -math.radians(195 + 150 * k / 29 + rnd2.uniform(-2.5, 2.5))
        r0, r1 = S / 2 * (pr * 1.28 + rnd2.uniform(0.0, 0.05)), S / 2 * (pr * 1.36 + rnd2.uniform(0.07, 0.15))
        wd = S * rnd2.uniform(0.004, 0.0065)
        nx, ny = -math.sin(a), math.cos(a)
        p0 = (cx + math.cos(a) * r0, cy + math.sin(a) * r0)
        p1 = (cx + math.cos(a) * r1, cy + math.sin(a) * r1)
        d.polygon([(p0[0] + nx * wd * 0.3, p0[1] + ny * wd * 0.3), (p1[0] + nx * wd, p1[1] + ny * wd),
                   (p1[0] - nx * wd, p1[1] - ny * wd), (p0[0] - nx * wd * 0.3, p0[1] - ny * wd * 0.3)],
                  fill=tuple(int(v * 0.6) for v in c["iris_dark"]) + (190,))
    # Мелкие светлые искры в верхней тёмной части.
    for k in range(9):
        a = rnd2.uniform(math.pi * 1.1, math.pi * 1.9)
        r = S / 2 * rnd2.uniform(pr * 1.3, 0.75)
        q = S * rnd2.uniform(0.006, 0.011)
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        d.ellipse((x - q, y - q, x + q, y + q), fill=tuple(min(255, int(v * 1.25)) for v in c["iris"]) + (160,))
    alpha = (np.clip((1.0 - rr) * 120, 0, 1) * 255).astype(np.uint8)
    img.putalpha(Image.fromarray(alpha))
    img.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, f"iris_{cid}.png"))


def sclera(cid, size=512):
    """Склера (белок): прохладный белый, сверху серо-лиловая тень века (как у образца-подростка), к углам темнее."""
    S = size
    ys = np.linspace(0, 1, S)[:, None]
    xs = np.linspace(-1, 1, S)[None, :]
    base = np.array((250, 249, 252), np.float32)
    shade = np.array((170, 164, 196), np.float32)
    # тень века — чёткая полоса сверху (а не размытая лиловая заливка белка), углы лишь чуть темнее
    top = np.clip((0.36 - ys) / 0.08, 0, 1)
    corner = np.clip((np.abs(xs) - 0.7) / 0.3, 0, 1) ** 1.5
    k = np.clip(top * 0.55 + corner * 0.18, 0, 1)[..., None]
    col = base * (1 - k) + shade * k
    Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), "RGB").save(os.path.join(OUT, f"sclera_{cid}.png"))


def fur(name="fur", size=512, seed=3):
    """Плиточная фактура меха (умножается на цвет меха): мягкие пряди-штрихи разной длины и светлоты, без швов."""
    rnd = random.Random(seed)
    S = size
    img = Image.new("L", (S * 3, S * 3), 236)
    d = ImageDraw.Draw(img)
    for _ in range(5200):
        x, y = rnd.uniform(S, 2 * S), rnd.uniform(S, 2 * S)
        L = rnd.uniform(S * 0.02, S * 0.07)
        a = math.radians(90 + rnd.uniform(-28, 28))
        v = int(rnd.uniform(190, 255))
        for ox in (-S, 0, S):
            for oy in (-S, 0, S):
                d.line((x + ox, y + oy, x + ox + math.cos(a) * L, y + oy + math.sin(a) * L), fill=v, width=rnd.choice((1, 2, 2, 3)))
    img = img.filter(ImageFilter.GaussianBlur(0.8)).crop((S, S, 2 * S, 2 * S))
    a = np.asarray(img).astype(np.float32)
    a = 200 + (a - a.min()) / max(1.0, a.max() - a.min()) * 55
    Image.fromarray(np.dstack([a, a, a]).astype(np.uint8), "RGB").save(os.path.join(OUT, f"{name}.png"))


def strand_lines(name="strand_lines", w=256, h=512, seed=9):
    """Фактура прядей для объёмных лент-волос: тонкие продольные линии (вдоль v), без швов по u."""
    rnd = np.random.default_rng(seed)
    xs = np.linspace(0, 1, w, endpoint=False)
    col = np.full(w, 0.93, np.float32)
    for f, a in ((7, 0.04), (13, 0.035), (29, 0.03), (53, 0.025)):
        col += a * np.sin(2 * np.pi * (xs * f + rnd.uniform()))
    col = np.clip(col, 0.78, 1.0)
    img = np.repeat(col[None, :], h, axis=0)
    img = img * (0.97 + 0.03 * np.sin(np.linspace(0, 2 * np.pi * 3, h))[:, None])
    v = (img * 255).astype(np.uint8)
    Image.fromarray(np.dstack([v, v, v]), "RGB").save(os.path.join(OUT, f"{name}.png"))


def hair_strands(w=512, h=1024):
    """Карта прядей: много тонких линий разной яркости, сужение к кончику (низ), прозрачные промежутки."""
    rnd = random.Random(3)
    S = SS
    img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Плотная основа клока: широкая у корня, сужается к кончику (иначе пряди просвечивают).
    base = Image.new("L", (w * S, h * S), 0)
    bd = ImageDraw.Draw(base)
    bd.polygon([(0.02 * w * S, 0), (0.98 * w * S, 0), (0.78 * w * S, 0.7 * h * S), (0.5 * w * S, 0.98 * h * S),
                (0.22 * w * S, 0.7 * h * S)], fill=235)
    base = base.filter(ImageFilter.GaussianBlur(10 * S))
    core = Image.new("RGBA", (w * S, h * S), (200, 200, 200, 255))
    core.putalpha(base)
    img.alpha_composite(core)
    d = ImageDraw.Draw(img)
    for _ in range(420):
        x0 = rnd.uniform(0.02, 0.98) * w * S
        length = rnd.uniform(0.7, 1.0) * h * S
        sway = rnd.uniform(-0.05, 0.05) * w * S
        bright = int(rnd.uniform(150, 255))
        width = rnd.uniform(1.5, 4.5) * S
        pts = []
        for k in range(21):
            t = k / 20
            x = x0 + sway * math.sin(t * math.pi) + (0.5 * w * S - x0) * t * 0.35
            pts.append((x, t * length))
        for k in range(20):
            t = k / 20
            a = int(255 * (1 - t ** 3))
            d.line((pts[k], pts[k + 1]), fill=(bright, bright, bright, a), width=max(1, int(width * (1 - 0.7 * t))))
    # Аниме-блик: светлая полоса в верхней трети.
    hl = soft((w * S, h * S), (255, 255, 255), 0.0, 0, lambda dd: None)
    arr = np.array(img).astype(np.float32)
    yy = np.linspace(0, 1, h * S)[:, None]
    band = np.exp(-((yy - 0.22) / 0.05) ** 2) * 0.35
    arr[..., :3] = np.clip(arr[..., :3] * (1 + band[..., None]), 0, 255)
    # «Растекание» цвета в прозрачные пиксели: иначе при уменьшении края прядей темнеют (тёмные «волоски»).
    a = arr[..., 3:4] / 255.0
    arr[..., :3] = arr[..., :3] * a + 205 * (1 - a)
    img = Image.fromarray(arr.astype(np.uint8), "RGBA")
    img.resize((w, h), Image.LANCZOS).save(os.path.join(OUT, "hair_strands.png"))


def knit(size=512):
    """Вязка «резинка»: вертикальные рубчики + мелкие петли. Серая — умножается на цвет вещи."""
    S = size
    ys, xs = np.mgrid[0:S, 0:S].astype(np.float32)
    rib = 0.82 + 0.18 * np.abs(np.sin(xs / S * math.pi * 24))
    loops = 0.94 + 0.06 * np.sin(ys / S * math.pi * 96 + np.sin(xs / S * math.pi * 48) * 2)
    v = np.clip(rib * loops * 255, 0, 255).astype(np.uint8)
    Image.fromarray(np.dstack([v, v, v]), "RGB").save(os.path.join(OUT, "knit.png"))
    # Мягкая «резинка» свитера Кота (реф. 16): ровные вертикальные рубчики без «ёлочки».
    prof = 0.5 + 0.5 * np.cos(xs / S * math.pi * 2 * 16)
    v = np.clip((0.8 + 0.2 * prof ** 0.6) * (0.97 + 0.03 * np.sin(ys / S * math.pi * 128)) * 255, 0, 255).astype(np.uint8)
    Image.fromarray(np.dstack([v, v, v]), "RGB").save(os.path.join(OUT, "rib.png"))
    rnd = np.random.default_rng(5)
    noise = rnd.normal(0, 1, (S, S)).astype(np.float32)
    img = Image.fromarray(np.clip(noise * 40 + 128, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    a = np.array(img).astype(np.float32)
    weave = 0.95 + 0.05 * np.sin(xs / S * math.pi * 160) * np.sin(ys / S * math.pi * 160)
    v = np.clip((0.93 + (a - 128) / 128 * 0.05) * weave * 255, 0, 255).astype(np.uint8)
    Image.fromarray(np.dstack([v, v, v]), "RGB").save(os.path.join(OUT, "cloth.png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    only = [a for a in sys.argv[1:] if a in CHARS]
    for cid, c in CHARS.items():
        if only and cid not in only:
            continue
        if face_params(cid).get("eye_shape"):
            for v in FACE_VARIANTS:
                face_v2(cid, c, v)
            makeup_mask(cid)
            face_info(cid, c)
            iris_from_user(cid) if cid in USER_IRIS else iris(cid, c)
            sclera(cid)
        else:
            face(cid, c)
        eye(cid, c)
    mouths()
    iris_patterns()
    hair_strands()
    fur()
    strand_lines()
    knit()
    print("ok", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
