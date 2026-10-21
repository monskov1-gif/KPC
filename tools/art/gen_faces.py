"""Текстуры лиц персонажей (аниме-стиль, рисуются кодом по референсам пользователя).

Запуск: python3 tools/art/gen_faces.py → art/characters/textures/face_<id>.png
Проекция на голову: u = 0.5 + x / (2·rx), v = 0.5 − (z − cz) / (2·rz) (см. build_characters.py).
Глаза, брови и рот рассчитаны в этих координатах.
"""
import os

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "art", "characters", "textures")
N = 1024
SS = 2
SKIN = (248, 226, 214)

CHARS = {
    # Кот (реф. 04): светло-голубые глаза, спокойное лицо, лёгкий румянец.
    "kot": {"iris": (120, 176, 226), "iris_dark": (40, 74, 130), "brow": (40, 120, 120), "mouth": "neutral",
            "blush": 0.55, "bags": False, "lash": (52, 40, 58)},
    # Габи (реф. 05–07): фиолетовые глаза, мягкая улыбка.
    "gabi": {"iris": (160, 132, 214), "iris_dark": (70, 48, 120), "brow": (150, 50, 70), "mouth": "smile",
             "blush": 0.7, "bags": False, "lash": (60, 36, 50)},
    # Сора (реф. 12): тёмные глаза, тени усталости, хитрая улыбка.
    "sora": {"iris": (92, 104, 116), "iris_dark": (30, 36, 44), "brow": (36, 92, 96), "mouth": "smirk",
             "blush": 0.35, "bags": True, "lash": (38, 32, 40)},
}


def soft_ellipse(img, box, color, alpha, blur):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).ellipse(box, fill=int(255 * alpha))
    m = m.filter(ImageFilter.GaussianBlur(blur))
    layer = Image.new("RGBA", img.size, color + (255,))
    layer.putalpha(m)
    img.alpha_composite(layer)


def eye(img, cx, cy, c, mirror):
    d = ImageDraw.Draw(img)
    S = N * SS
    w, h = S * 0.085, S * 0.105
    # Склера (миндалевидная).
    d.ellipse((cx - w, cy - h * 0.85, cx + w, cy + h * 0.95), fill=(255, 252, 250, 255))
    # Радужка: вытянутый овал с градиентом сверху вниз.
    iw, ih = w * 0.78, h * 0.92
    iris = Image.new("RGBA", img.size, (0, 0, 0, 0))
    idr = ImageDraw.Draw(iris)
    steps = 24
    for k in range(steps):
        t = k / (steps - 1)
        col = tuple(int(c["iris_dark"][i] + (c["iris"][i] - c["iris_dark"][i]) * t) for i in range(3))
        yy = cy - ih * 0.8 + ih * 1.7 * t
        idr.ellipse((cx - iw, cy - ih * 0.85, cx + iw, cy + ih * 0.95), fill=None)
        idr.rectangle((cx - iw, yy, cx + iw, yy + ih * 1.7 / steps + 2), fill=col + (255,))
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).ellipse((cx - iw, cy - ih * 0.85, cx + iw, cy + ih * 0.95), fill=255)
    iris.putalpha(m)
    img.alpha_composite(iris)
    d.ellipse((cx - iw, cy - ih * 0.85, cx + iw, cy + ih * 0.95), outline=c["iris_dark"] + (255,), width=int(S * 0.006))
    # Зрачок.
    d.ellipse((cx - iw * 0.42, cy - ih * 0.3, cx + iw * 0.42, cy + ih * 0.5), fill=tuple(v // 2 for v in c["iris_dark"]) + (255,))
    # Нижний светлый полумесяц радужки.
    soft_ellipse(img, (cx - iw * 0.6, cy + ih * 0.25, cx + iw * 0.6, cy + ih * 0.85), tuple(min(255, v + 60) for v in c["iris"]), 0.7, S * 0.006)
    # Блики.
    hx = -1 if not mirror else 1
    d.ellipse((cx + hx * iw * 0.45 - w * 0.22, cy - ih * 0.6, cx + hx * iw * 0.45 + w * 0.22, cy - ih * 0.12), fill=(255, 255, 255, 255))
    d.ellipse((cx - hx * iw * 0.35 - w * 0.09, cy + ih * 0.35, cx - hx * iw * 0.35 + w * 0.09, cy + ih * 0.55), fill=(255, 255, 255, 230))
    # Верхнее веко-ресницы: толстая дуга + стрелка во внешний угол.
    lw = int(S * 0.016)
    d.arc((cx - w * 1.08, cy - h * 0.95, cx + w * 1.08, cy + h * 0.9), 195, 345, fill=c["lash"] + (255,), width=lw)
    ox = cx + (w * 1.05 if mirror else -w * 1.05)
    tip = ox + (w * 0.35 if mirror else -w * 0.35)
    d.polygon([(ox, cy - h * 0.2), (tip, cy - h * 0.48), (ox + (-w * 0.1 if mirror else w * 0.1), cy - h * 0.55)], fill=c["lash"] + (255,))
    # Нижнее веко.
    d.arc((cx - w * 0.8, cy - h * 0.6, cx + w * 0.8, cy + h * 1.0), 60, 120, fill=c["lash"] + (150,), width=int(S * 0.005))


def face(cid, c):
    S = N * SS
    img = Image.new("RGBA", (S, S), SKIN + (255,))
    eye_v, eye_du = 0.545, 0.19
    for side in (-1, 1):
        cx, cy = S * (0.5 + side * eye_du), S * eye_v
        if c["bags"]:
            d = ImageDraw.Draw(img)
            d.arc((cx - S * 0.08, cy - S * 0.02, cx + S * 0.08, cy + S * 0.13), 20, 160, fill=(170, 120, 150, 140), width=int(S * 0.006))
        eye(img, cx, cy, c, side > 0)
        # Брови — тонкие дуги цвета волос.
        d = ImageDraw.Draw(img)
        bx = cx + side * S * 0.01
        d.arc((bx - S * 0.09, S * 0.36, bx + S * 0.09, S * 0.46), 200, 330, fill=c["brow"] + (255,), width=int(S * 0.009))
        # Румянец.
        soft_ellipse(img, (cx - S * 0.08, S * 0.63, cx + S * 0.08, S * 0.69), (240, 150, 160), c["blush"] * 0.6, S * 0.015)
    d = ImageDraw.Draw(img)
    # Нос — маленькая тень.
    d.line((S * 0.505, S * 0.66, S * 0.495, S * 0.69), fill=(214, 168, 160, 255), width=int(S * 0.005))
    # Рот.
    mc = (150, 82, 92, 255)
    mw = int(S * 0.006)
    if c["mouth"] == "neutral":
        d.arc((S * 0.46, S * 0.75, S * 0.54, S * 0.79), 20, 160, fill=mc, width=mw)
    elif c["mouth"] == "smile":
        d.arc((S * 0.44, S * 0.72, S * 0.56, S * 0.79), 15, 165, fill=mc, width=mw)
    else:  # хитрая полуулыбка
        d.arc((S * 0.45, S * 0.72, S * 0.57, S * 0.79), 10, 120, fill=mc, width=mw)
        d.line((S * 0.45, S * 0.755, S * 0.47, S * 0.76), fill=mc, width=mw)
    img.resize((N, N), Image.LANCZOS).convert("RGB").save(os.path.join(OUT, f"face_{cid}.png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    for cid, c in CHARS.items():
        face(cid, c)
    print("ok", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
