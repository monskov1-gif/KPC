"""Генератор графики интерфейса KPC (собственная графика проекта, без внешних ассетов).

Запуск: python3 tools/art/gen_ui.py  → PNG в art/ui/
Всё рисуется в увеличенном масштабе (SS) и уменьшается с LANCZOS — так края гладкие.
Стиль: тёплая «облачная» гамма, тонкое золото, стекло, арки с небом (ориентир — art/references/ui/ui_03).
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "art", "ui")
SS = 4

GOLD_HI = (255, 240, 200)
GOLD = (222, 186, 120)
GOLD_LO = (168, 120, 66)
GOLD_DARK = (120, 82, 48)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def vgrad(w, h, stops):
    """Вертикальный градиент по списку (позиция 0..1, RGBA)."""
    ys = np.linspace(0, 1, h)
    out = np.zeros((h, w, 4), dtype=np.float32)
    for i in range(len(stops) - 1):
        p0, c0 = stops[i]
        p1, c1 = stops[i + 1]
        m = (ys >= p0) & (ys <= p1)
        t = ((ys[m] - p0) / max(p1 - p0, 1e-6))[:, None]
        out[m, :, :] = (np.array(c0) * (1 - t) + np.array(c1) * t)[:, None, :]
    return Image.fromarray(out.clip(0, 255).astype(np.uint8), "RGBA")


def soft(size, color, blur, draw_fn):
    """Мягкая фигура: рисуем и размываем только альфа-маску, цвет — сплошной.
    (Размытие RGBA с прозрачным чёрным даёт серые разводы.)"""
    m = Image.new("L", size, 0)
    draw_fn(ImageDraw.Draw(m))
    if blur > 0:
        m = m.filter(ImageFilter.GaussianBlur(blur))
    layer = Image.new("RGBA", size, color[:3] + (255,))
    a = np.array(m, dtype=np.float32) * (color[3] / 255.0 if len(color) > 3 else 1.0)
    layer.putalpha(Image.fromarray(a.clip(0, 255).astype(np.uint8)))
    return layer


def down(img, size):
    return img.resize(size, Image.LANCZOS)


def rounded_mask(w, h, r):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), r, fill=255)
    return m


def gold_stroke(draw, box, r, width):
    """Двойная золотая линия: тёмная подложка + светлая."""
    draw.rounded_rectangle(box, r, outline=GOLD_LO + (255,), width=width + 2)
    draw.rounded_rectangle(box, r, outline=GOLD + (255,), width=width)


def flourish(draw, cx, cy, s, flip_x=1, flip_y=1, color=GOLD):
    """Угловой орнамент: ромб + две завитушки."""
    pts = [(cx, cy - s * 0.5), (cx + s * 0.5, cy), (cx, cy + s * 0.5), (cx - s * 0.5, cy)]
    draw.polygon(pts, fill=color + (255,))
    draw.polygon([(cx, cy - s * 0.22), (cx + s * 0.22, cy), (cx, cy + s * 0.22), (cx - s * 0.22, cy)], fill=GOLD_HI + (255,))
    w = max(2, int(s * 0.09))
    for k in (1, -1):
        bx = cx + flip_x * s * 0.6 * (1 if k == 1 else 0.2)
        by = cy + flip_y * s * 0.6 * (0.2 if k == 1 else 1)
        draw.arc((bx - s * 0.5, by - s * 0.5, bx + s * 0.5, by + s * 0.5), 0, 360, fill=color + (200,), width=w)


# ---------------------------------------------------------------- фон с арками

def clouds(w, h, seed, count, tint=(255, 255, 255), alpha=220):
    rnd = random.Random(seed)

    def draw(d):
        for _ in range(count):
            cx, cy = rnd.uniform(0, w), rnd.uniform(h * 0.35, h * 0.95)
            for k in range(rnd.randint(4, 8)):
                rx = rnd.uniform(w * 0.04, w * 0.11)
                ry = rx * rnd.uniform(0.45, 0.7)
                ox, oy = rnd.uniform(-rx * 1.6, rx * 1.6), rnd.uniform(-ry * 0.6, ry * 0.3)
                d.ellipse((cx + ox - rx, cy + oy - ry, cx + ox + rx, cy + oy + ry), fill=255)
    return soft((w, h), tint + (alpha,), w * 0.01, draw)


def arch_path(x0, x1, top, bottom):
    cx = (x0 + x1) / 2
    r = (x1 - x0) / 2
    pts = [(x0, bottom), (x0, top + r)]
    for i in range(41):
        a = math.pi + math.pi * i / 40
        pts.append((cx + math.cos(a) * r, top + r + math.sin(a) * r))
    pts += [(x1, top + r), (x1, bottom)]
    return pts


def background(w, h, name, n_arches):
    W, H = w * 2, h * 2
    wall = vgrad(W, H, [(0, (196, 160, 158, 255)), (0.55, (214, 182, 176, 255)), (1, (176, 140, 140, 255))])
    sky = vgrad(W, H, [(0, (176, 186, 228, 255)), (0.45, (226, 206, 230, 255)), (0.75, (250, 222, 206, 255)), (1, (252, 236, 220, 255))])
    sky.alpha_composite(clouds(W, H, 7, 9))
    sky.alpha_composite(clouds(W, H, 11, 6, (255, 236, 226)))
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    frames = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(frames)
    gap = W / n_arches
    aw = gap * 0.62
    top, bottom = H * 0.06, H * 0.86
    for i in range(n_arches):
        cx = gap * (i + 0.5)
        pts = arch_path(cx - aw / 2, cx + aw / 2, top, bottom)
        md.polygon(pts, fill=255)
        outer = arch_path(cx - aw / 2 - W * 0.012, cx + aw / 2 + W * 0.012, top - W * 0.012, bottom)
        fd.line(outer + [outer[0]], fill=(236, 214, 200, 255), width=int(W * 0.016))
        fd.line(outer + [outer[0]], fill=GOLD + (200,), width=int(W * 0.003))
        fd.line(pts, fill=(150, 112, 108, 160), width=int(W * 0.004))
    img = wall.copy()
    img.paste(sky, (0, 0), mask)
    # Свет из окон: мягкое свечение и лучи.
    img.alpha_composite(soft((W, H), (255, 236, 220, 110), W * 0.03, lambda d: d.bitmap((0, 0), mask, fill=255)))

    def ray_draw(d):
        for i in range(5):
            x = W * (0.15 + i * 0.18)
            d.polygon([(x, 0), (x + W * 0.06, 0), (x + W * 0.22, H), (x + W * 0.1, H)], fill=255)
    img.alpha_composite(soft((W, H), (255, 245, 232, 30), W * 0.01, ray_draw))
    img.alpha_composite(frames)
    # Пол и круглый подиум-ковёр.
    floor = vgrad(W, int(H * 0.2), [(0, (190, 150, 146, 255)), (1, (160, 120, 120, 255))])
    img.paste(floor, (0, int(H * 0.8)))
    pd = ImageDraw.Draw(img)
    pd.rectangle((0, H * 0.8 - W * 0.006, W, H * 0.8), fill=(232, 206, 194, 255))
    pd.line((0, H * 0.8 - W * 0.006, W, H * 0.8 - W * 0.006), fill=GOLD + (220,), width=int(W * 0.0015))
    cx, cy = W * 0.5, H * 0.9

    # Виньетка.
    yy, xx = np.mgrid[0:H, 0:W]
    v = ((xx / W - 0.5) ** 2 + (yy / H - 0.5) ** 2) ** 0.5
    vig = (np.clip((v - 0.35) / 0.45, 0, 1) * 90).astype(np.uint8)
    vl = Image.fromarray(np.dstack([np.full_like(vig, 90), np.full_like(vig, 50), np.full_like(vig, 60), vig]), "RGBA")
    img.alpha_composite(vl)
    down(img, (w, h)).convert("RGB").save(os.path.join(OUT, name), quality=92)


# ---------------------------------------------------------------- панели и рамки

def glass_panel(name, fill_top, fill_bottom, size=192, radius=34, ornaments=True):
    S = size * SS
    img = vgrad(S, S, [(0, fill_top), (1, fill_bottom)])
    img.putalpha(Image.fromarray(np.minimum(np.array(img.split()[3]), np.array(rounded_mask(S, S, radius * SS)))))
    d = ImageDraw.Draw(img)
    # Блик сверху.
    img.alpha_composite(soft((S, S), (255, 255, 255, 36), SS * 6,
        lambda dd: dd.rounded_rectangle((SS * 6, SS * 4, S - SS * 6, S * 0.28), radius * SS, fill=255)))
    inset = 7 * SS
    gold_stroke(d, (inset, inset, S - inset, S - inset), (radius - 6) * SS, 2 * SS)
    d.rounded_rectangle((inset + 6 * SS, inset + 6 * SS, S - inset - 6 * SS, S - inset - 6 * SS), (radius - 11) * SS,
                        outline=GOLD + (90,), width=SS)
    if ornaments:
        o = 15 * SS
        for (x, y, fx, fy) in [(o, o, 1, 1), (S - o, o, -1, 1), (o, S - o, 1, -1), (S - o, S - o, -1, -1)]:
            flourish(d, x, y, 12 * SS, fx, fy)
    down(img, (size, size)).save(os.path.join(OUT, name))


RARITY_TINTS = {
    1: ((246, 240, 236), (226, 220, 228)),
    2: ((242, 246, 238), (204, 228, 212)),
    3: ((240, 244, 250), (196, 214, 240)),
    4: ((246, 240, 250), (220, 196, 238)),
    5: ((252, 244, 232), (246, 206, 160)),
}


def item_card(rarity, selected=False):
    w, h = 128, 150
    W, H = w * SS, h * SS
    top, bottom = RARITY_TINTS[rarity]
    img = vgrad(W, H, [(0, top + (255,)), (0.55, top + (255,)), (1, bottom + (255,))])
    img.putalpha(rounded_mask(W, H, 14 * SS))
    d = ImageDraw.Draw(img)
    # Внутренний ореол под предметом.
    img.alpha_composite(soft((W, H), (255, 255, 255, 170), W * 0.08,
        lambda dd: dd.ellipse((W * 0.18, H * 0.2, W * 0.82, H * 0.75), fill=255)))
    if selected:
        d.rounded_rectangle((2 * SS, 2 * SS, W - 2 * SS, H - 2 * SS), 13 * SS, outline=GOLD_HI + (255,), width=5 * SS)
        d.rounded_rectangle((2 * SS, 2 * SS, W - 2 * SS, H - 2 * SS), 13 * SS, outline=GOLD + (255,), width=3 * SS)
    else:
        d.rounded_rectangle((SS, SS, W - SS, H - SS), 13 * SS, outline=(214, 190, 170, 255), width=2 * SS)
    # Тонкая золотая полоска внизу с ромбом — как подставка.
    y = H - 16 * SS
    d.line((W * 0.2, y, W * 0.8, y), fill=GOLD + (200,), width=SS * 2)
    flourish(d, W / 2, y, 7 * SS)
    img = down(img, (w, h))
    if selected:
        glow = soft((w + 24, h + 24), (255, 214, 140, 170), 7,
            lambda dd: dd.rounded_rectangle((8, 8, w + 16, h + 16), 18, fill=255))
        glow.alpha_composite(img, (12, 12))
        img = glow
    img.save(os.path.join(OUT, f"card_r{rarity}{'_sel' if selected else ''}.png"))


def gold_button(name, top=(250, 226, 170), mid=(226, 186, 116), bottom=(190, 140, 76)):
    w, h = 220, 72
    W, H = w * SS, h * SS
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    body = vgrad(W, H, [(0, top + (255,)), (0.5, mid + (255,)), (1, bottom + (255,))])
    m = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(m)
    # Форма «картуша»: скругление + заострённые концы.
    r = H * 0.42
    md.rounded_rectangle((H * 0.32, H * 0.08, W - H * 0.32, H * 0.92), r, fill=255)
    md.polygon([(H * 0.06, H / 2), (H * 0.4, H * 0.14), (H * 0.4, H * 0.86)], fill=255)
    md.polygon([(W - H * 0.06, H / 2), (W - H * 0.4, H * 0.14), (W - H * 0.4, H * 0.86)], fill=255)
    img.paste(body, (0, 0), m)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((H * 0.4, H * 0.18, W - H * 0.4, H * 0.82), r * 0.8, outline=GOLD_HI + (230,), width=2 * SS)
    img.alpha_composite(soft((W, H), (255, 255, 255, 100), SS * 3,
        lambda dd: dd.rounded_rectangle((H * 0.5, H * 0.16, W - H * 0.5, H * 0.42), r * 0.5, fill=255)))
    for x in (H * 0.2, W - H * 0.2):
        flourish(d, x, H / 2, H * 0.22)
    shadow = soft((W, H), (110, 60, 50, 90), SS * 4, lambda dd: dd.bitmap((0, int(SS * 3)), m, fill=255))
    shadow.alpha_composite(img)
    down(shadow, (w, h)).save(os.path.join(OUT, name))


def medallion(name, selected):
    s = 96
    S = s * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    if selected:
        img.alpha_composite(soft((S, S), (255, 220, 150, 180), S * 0.05,
            lambda dd: dd.ellipse((S * 0.04, S * 0.04, S * 0.96, S * 0.96), fill=255)))
    d = ImageDraw.Draw(img)
    c = S / 2
    r = S * 0.4
    d.ellipse((c - r, c - r, c + r, c + r), fill=GOLD_LO + (255,))
    d.ellipse((c - r + 2 * SS, c - r + 2 * SS, c + r - 2 * SS, c + r - 2 * SS), fill=GOLD + (255,))
    inner = vgrad(S, S, [(0, (255, 246, 228, 255)), (1, (236, 214, 196, 255))] if selected else
                  [(0, (150, 112, 112, 235)), (1, (118, 84, 90, 235))])
    m = Image.new("L", (S, S), 0)
    ri = r - 6 * SS
    ImageDraw.Draw(m).ellipse((c - ri, c - ri, c + ri, c + ri), fill=255)
    img.paste(inner, (0, 0), m)
    d.ellipse((c - ri, c - ri, c + ri, c + ri), outline=GOLD_HI + (180,), width=SS)
    for a in range(4):
        ang = a * math.pi / 2 + math.pi / 4
        flourish(d, c + math.cos(ang) * r, c + math.sin(ang) * r, 7 * SS)
    down(img, (s, s)).save(os.path.join(OUT, name))


def ribbon(name):
    """Картуш-лента для заголовков (тянется по горизонтали)."""
    w, h = 300, 64
    W, H = w * SS, h * SS
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    body = vgrad(W, H, [(0, (140, 98, 100, 240)), (1, (110, 74, 80, 240))])
    m = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(m)
    md.polygon([(0, H * 0.12), (W * 0.06, H / 2), (0, H * 0.88), (W, H * 0.88), (W * 0.94, H / 2), (W, H * 0.12)], fill=255)
    img.paste(body, (0, 0), m)
    d = ImageDraw.Draw(img)
    d.line((W * 0.07, H * 0.2, W * 0.93, H * 0.2), fill=GOLD + (230,), width=SS * 2)
    d.line((W * 0.07, H * 0.8, W * 0.93, H * 0.8), fill=GOLD + (230,), width=SS * 2)
    flourish(d, W * 0.045, H / 2, H * 0.22)
    flourish(d, W * 0.955, H / 2, H * 0.22)
    down(img, (w, h)).save(os.path.join(OUT, name))


def divider(name):
    w, h = 400, 24
    W, H = w * SS, h * SS
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for x0, x1 in ((W * 0.04, W * 0.44), (W * 0.56, W * 0.96)):
        d.line((x0, H / 2, x1, H / 2), fill=GOLD + (220,), width=SS * 2)
    flourish(d, W / 2, H / 2, H * 0.7)
    flourish(d, W * 0.04, H / 2, H * 0.3)
    flourish(d, W * 0.96, H / 2, H * 0.3)
    down(img, (w, h)).save(os.path.join(OUT, name))


def round_button(name, selected=False):
    s = 80
    S = s * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    img.alpha_composite(soft((S, S), (100, 60, 60, 90), SS * 3,
        lambda dd: dd.ellipse((S * 0.1, S * 0.14, S * 0.9, S * 0.94), fill=255)))
    d = ImageDraw.Draw(img)
    c, r = S / 2, S * 0.4
    d.ellipse((c - r, c - r, c + r, c + r), fill=GOLD + (255,))
    inner = vgrad(S, S, [(0, (255, 248, 238, 255)), (1, (240, 222, 210, 255))] if not selected else
                  [(0, (255, 236, 190, 255)), (1, (232, 196, 132, 255))])
    m = Image.new("L", (S, S), 0)
    ri = r - 3 * SS
    ImageDraw.Draw(m).ellipse((c - ri, c - ri, c + ri, c + ri), fill=255)
    img.paste(inner, (0, 0), m)
    d.arc((c - ri + 3 * SS, c - ri + 3 * SS, c + ri - 3 * SS, c + ri - 3 * SS), 200, 340, fill=(255, 255, 255, 200), width=2 * SS)
    down(img, (s, s)).save(os.path.join(OUT, name))


def chip(name):
    """Небольшая плашка-«таблетка» с золотым ободком: монеты, сортировка, поиск, подсказки."""
    w, h = 160, 56
    W, H = w * SS, h * SS
    img = soft((W, H), (110, 60, 60, 70), SS * 3, lambda d: d.rounded_rectangle((SS * 3, SS * 6, W - SS * 3, H - SS), H / 2, fill=255))
    body = vgrad(W, H, [(0, (255, 252, 248, 250)), (1, (246, 234, 226, 250))])
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).rounded_rectangle((SS * 3, SS * 3, W - SS * 3, H - SS * 4), (H - SS * 7) / 2, fill=255)
    img.paste(body, (0, 0), m)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((SS * 3, SS * 3, W - SS * 3, H - SS * 4), (H - SS * 7) / 2, outline=GOLD + (255,), width=SS * 2)
    d.rounded_rectangle((SS * 7, SS * 7, W - SS * 7, H - SS * 8), (H - SS * 15) / 2, outline=GOLD + (90,), width=SS)
    down(img, (w, h)).save(os.path.join(OUT, name))


def main():
    os.makedirs(OUT, exist_ok=True)
    background(1920, 1080, "bg_wardrobe_wide.jpg", 3)
    background(1080, 1920, "bg_wardrobe_tall.jpg", 2)
    glass_panel("panel_glass.png", (150, 108, 110, 200), (118, 82, 90, 215))
    glass_panel("panel_light.png", (255, 250, 246, 238), (246, 234, 228, 238))
    glass_panel("panel_plain.png", (255, 250, 246, 245), (246, 236, 230, 245), ornaments=False)
    for r in range(1, 6):
        item_card(r)
        item_card(r, True)
    gold_button("button_gold.png")
    gold_button("button_rose.png", (246, 214, 222), (222, 166, 182), (184, 120, 140))
    medallion("medallion.png", False)
    medallion("medallion_sel.png", True)
    ribbon("ribbon.png")
    divider("divider.png")
    chip("chip.png")
    round_button("round.png")
    round_button("round_sel.png", True)
    print("ok", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
