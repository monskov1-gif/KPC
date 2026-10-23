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
_FACE = json.load(open(os.path.join(os.path.dirname(__file__), "face_params.json"), encoding="utf-8"))


def face_params(cid):
    fp = dict(_FACE["default"])
    fp.update(_FACE.get(cid, {}))
    return fp

CHARS = {
    # Кот (реф. 04): светло-голубые глаза, спокойное лицо, лёгкий румянец.
    # Ресницы, складка века и брови у Кота — объёмные (build_characters.build_lashes), на текстуре их нет.
    "kot": {"iris": (146, 162, 208), "iris_dark": (62, 72, 122), "iris_pale": (214, 226, 248), "pupil": (26, 30, 62),
            "pupil_r": 0.58, "brow": (44, 118, 120), "mouth": "lips",
            "blush": 0.45, "bags": False, "lash": (48, 36, 54), "lash_len": 1.0, "geo_lashes": True},
    # Габи (реф. 05–07): фиолетовые глаза, мягкая улыбка, ресницы гуще.
    "gabi": {"iris": (176, 146, 226), "iris_dark": (72, 44, 124), "brow": (150, 50, 70), "mouth": "smile",
             "blush": 0.65, "bags": False, "lash": (58, 32, 46), "lash_len": 1.35},
    # Сора (реф. 12): тёмные глаза, тени усталости, хитрая полуулыбка.
    "sora": {"iris": (104, 116, 128), "iris_dark": (28, 34, 42), "brow": (36, 92, 96), "mouth": "smirk",
             "blush": 0.3, "bags": True, "lash": (36, 30, 38), "lash_len": 0.8},
}


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
    img = Image.new("RGBA", (S, S), SKIN + (255,))
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
            pts = [(S * u, S * v) for u, v in (eye_shape.to_uv(q, es, side, cu, cv) for q in eye_shape.contour())]
            n_up = (len(eye_shape.UPPER) - 1) * 8 + 1
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
    pale = np.array(c.get("iris_pale", (214, 224, 244)), np.float32)
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
    top = np.clip((0.5 - ys) / 0.32, 0, 1) ** 0.8
    corner = np.clip((np.abs(xs) - 0.55) / 0.45, 0, 1) ** 1.5
    k = np.clip(top * 0.85 + corner * 0.35, 0, 1)[..., None]
    col = base * (1 - k) + shade * k
    Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), "RGB").save(os.path.join(OUT, f"sclera_{cid}.png"))


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
    for cid, c in CHARS.items():
        face(cid, c)
        eye(cid, c)
        if face_params(cid).get("eye_shape"):
            iris(cid, c)
            sclera(cid)
    hair_strands()
    knit()
    print("ok", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
