"""Рисунки скетчбука Кота — нарисованы кодом «от руки»: дрожащие карандашные линии, штриховка цветными
карандашами по зерну бумаги, заливка «за контур», как рисуют дети. Не рендеры 3D и не фото с фильтром.

Пролог, сцена 3: Коту 6 лет — детский рисунок цветными карандашами (крупные головы, солнце в углу, кошачьи уши).
Сцена 7 («годы идут»): Кот старше — увереннее линия, штриховка тени, лёгкая акварельная подложка.
Цвета героев — как у 3D-моделей (tools/art/build_characters.py, data/story/looks.json).

Запуск: python3 tools/art/draw_sketches.py → art/story/sketches/*.png (1024×666, как страница альбома).
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "art", "story", "sketches")
W, H = 2048, 1332          # рисуем в 2× и уменьшаем — мягкий край штриха
FINAL = (1024, 666)


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


class Paper:
    """Лист: тёплая бумага с зерном; слои карандаша накладываются умножением (как графит и пигмент)."""

    def __init__(self, seed, tone="fbf7ee", skill=0.0):
        self.rng = np.random.default_rng(seed)
        self.skill = skill                         # 0 — ребёнок, 1 — уверенная рука
        base = np.array(hexc(tone))
        g = self.rng.standard_normal((H // 4, W // 4))
        g = np.array(Image.fromarray(((g - g.min()) / (np.ptp(g) + 1e-9) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)) / 255.0
        fine = self.rng.random((H, W))
        self.grain = 0.55 * fine + 0.45 * g        # 0…1: «бугорки» бумаги ловят карандаш
        shade = 1.0 - 0.025 * (g - 0.5)
        yy, xx = np.mgrid[0:H, 0:W]
        vign = 1.0 - 0.05 * (((xx - W / 2) / W) ** 2 + ((yy - H / 2) / H) ** 2) * 4
        self.img = np.ones((H, W, 3)) * base * (shade * vign)[..., None]
        self.blank = self.img.copy()

    def erase(self, mask):
        """Ластик: вернуть чистую бумагу под маской (то, что «за» фигурой, не просвечивает)."""
        a = (np.array(mask.filter(ImageFilter.GaussianBlur(2)), float) / 255.0)[..., None]
        self.img = self.img * (1 - a) + self.blank * a

    # ---------- линии ----------

    def wobble(self, pts, amp=None, step=6.0):
        """Ресэмплинг ломаной и плавное дрожание поперёк линии (у ребёнка сильнее)."""
        amp = (3.2 - 2.4 * self.skill) if amp is None else amp
        pts = [np.array(p, float) for p in pts]
        out = []
        for a, b in zip(pts[:-1], pts[1:]):
            n = max(1, int(np.linalg.norm(b - a) / step))
            for k in range(n):
                out.append(a + (b - a) * k / n)
        out.append(pts[-1])
        out = np.array(out)
        if len(out) < 3:
            return out
        d = np.gradient(out, axis=0)
        nrm = np.stack([-d[:, 1], d[:, 0]], 1)
        nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-9
        t = np.arange(len(out))
        ph = self.rng.uniform(0, 6.28, 3)
        off = amp * (0.6 * np.sin(t * 0.05 + ph[0]) + 0.3 * np.sin(t * 0.17 + ph[1]) + 0.1 * np.sin(t * 0.6 + ph[2]))
        return out + nrm * off[:, None]

    def layer(self):
        return Image.new("L", (W, H), 0)

    def stroke(self, lay, pts, width=5.0, value=230, closed=False, amp=None):
        if closed:
            pts = list(pts) + [pts[0]]
        p = self.wobble(pts, amp)
        dr = ImageDraw.Draw(lay)
        n = len(p)
        for i in range(n - 1):
            # нажим: тоньше в начале и конце штриха
            k = min(i, n - 1 - i) / max(1, min(12, n // 3))
            w = width * (0.55 + 0.45 * min(1.0, k))
            dr.line([tuple(p[i]), tuple(p[i + 1])], fill=value, width=max(1, int(round(w))))
            dr.ellipse([p[i][0] - w / 2, p[i][1] - w / 2, p[i][0] + w / 2, p[i][1] + w / 2], fill=value)

    def ink(self, lay, color, strength=1.0, grain=0.6):
        """Наложить слой карандаша цветом color: умножение, с пропусками по зерну бумаги."""
        a = np.array(lay, float) / 255.0
        a = a * np.clip((1 - grain) + grain * 1.4 * self.grain, 0, 1) * strength
        c = np.array(color)
        self.img *= 1 - a[..., None] * (1 - c)

    def wash(self, lay, color, strength=0.5):
        """Акварельная подложка: мягкий край, пятнистость, темнее у границы."""
        m = lay.filter(ImageFilter.GaussianBlur(10))
        a = np.array(m, float) / 255.0
        edge = np.array(lay.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.GaussianBlur(6)), float) / 255.0
        a = np.clip(a * (0.75 + 0.35 * self.grain) + edge * 0.6, 0, 1) * strength
        c = np.array(color)
        self.img *= 1 - a[..., None] * (1 - c)

    # ---------- фигуры ----------

    def poly_mask(self, pts, grow=0):
        m = Image.new("L", (W, H), 0)
        ImageDraw.Draw(m).polygon([tuple(map(float, p)) for p in pts], fill=255)
        if grow > 0:
            m = m.filter(ImageFilter.MaxFilter(int(grow) * 2 + 1))
        return m

    def hatch(self, mask, color, angle=None, spacing=None, width=None, strength=1.0, scribble=None):
        """Заливка штрихом внутри маски: параллельные дрожащие штрихи; у ребёнка — зигзаг «за контур»."""
        child = self.skill < 0.5 if scribble is None else scribble
        angle = self.rng.uniform(0.5, 1.1) if angle is None else angle
        spacing = (11 if child else 7) if spacing is None else spacing
        width = (7 if child else 3.2) if width is None else width
        box = mask.getbbox()
        if not box:
            return
        x0, y0, x1, y1 = box
        lay = self.layer()
        dr_dir = np.array([math.cos(angle), math.sin(angle)])
        nrm = np.array([-dr_dir[1], dr_dir[0]])
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        r = math.hypot(x1 - x0, y1 - y0) / 2 + 20
        k = -r
        pts_z = []
        while k < r:
            c = np.array([cx, cy]) + nrm * k
            a, b = c - dr_dir * r, c + dr_dir * r
            if child:
                pts_z += [a, b] if len(pts_z) % 4 == 0 else [b, a]
            else:
                self.stroke(lay, [a, b], width, value=int(200 + 40 * self.rng.random()), amp=1.2)
            k += spacing * self.rng.uniform(0.8, 1.2)
        if child and pts_z:
            self.stroke(lay, pts_z, width, value=245, amp=4.0)
        # выход за контур у ребёнка: маска чуть шире и неровная
        m = mask.filter(ImageFilter.MaxFilter(9 if child else 3)) if child else mask
        lay = Image.fromarray((np.array(lay, float) * np.array(m, float) / 255).astype(np.uint8))
        self.ink(lay, color, strength, grain=0.45)

    def outline(self, pts, color="3a3438", width=None, closed=True, strength=0.9, amp=None):
        lay = self.layer()
        w = (6.5 if self.skill < 0.5 else 3.4) if width is None else width
        self.stroke(lay, pts, w, closed=closed, amp=amp)
        if self.skill >= 0.5 and self.rng.random() < 0.6:
            # уверенная рука — второй, чуть смещённый проход линии
            self.stroke(lay, [np.array(p) + self.rng.normal(0, 1.5, 2) for p in pts], w * 0.6, value=150, closed=closed, amp=amp)
        self.ink(lay, hexc(color), strength, grain=0.5)

    def shape(self, pts, fill, line="3a3438", width=None, strength=1.0, angle=None):
        if fill:
            self.hatch(self.poly_mask(pts), hexc(fill), angle=angle, strength=strength)
        if line:
            self.outline(pts, line, width)

    def ellipse_pts(self, c, rx, ry, n=48, a0=0.0, a1=None):
        a1 = a0 + 2 * math.pi if a1 is None else a1
        return [(c[0] + rx * math.cos(a0 + (a1 - a0) * k / n), c[1] + ry * math.sin(a0 + (a1 - a0) * k / n)) for k in range(n + 1)]

    def save(self, name):
        img = Image.fromarray((np.clip(self.img, 0, 1) * 255).astype(np.uint8)).resize(FINAL, Image.LANCZOS)
        os.makedirs(OUT, exist_ok=True)
        img.save(os.path.join(OUT, name + ".png"), optimize=True)
        print("рисунок", name)


# ------------------------------------------------------------------ детали


def sun(P, c, r):
    P.shape(P.ellipse_pts(c, r, r), "f6c445", "e09a2a")
    for k in range(11):
        a = k / 11 * 2 * math.pi + 0.2
        P.outline([(c[0] + math.cos(a) * r * 1.3, c[1] + math.sin(a) * r * 1.3),
                   (c[0] + math.cos(a) * r * 1.85, c[1] + math.sin(a) * r * 1.85)], "e8a030", closed=False)


def sky_band(P, depth):
    """Небо, как рисуют дети: голубая полоса вдоль верхнего края с неровным низом."""
    pts = [(0, 0), (W, 0)]
    for k in range(13):
        x = W - k * W / 12
        pts.append((x, depth + P.rng.uniform(-35, 35)))
    P.hatch(P.poly_mask(pts), hexc("8cc4ee"), angle=0.08, spacing=13, strength=0.8)


def cloud(P, c, s):
    pts = []
    for k, (dx, r) in enumerate(((-1.0, 0.55), (-0.35, 0.8), (0.4, 0.7), (1.0, 0.5))):
        pts += P.ellipse_pts((c[0] + dx * s, c[1] - 0.1 * s), r * s, r * s * 0.8, n=14, a0=math.pi * 0.9, a1=math.pi * 2.1)
    pts.append((c[0] + 1.4 * s, c[1] + 0.3 * s))
    pts.append((c[0] - 1.4 * s, c[1] + 0.3 * s))
    P.shape(pts, "ffffff", "6a90b8", strength=0.5)


def house(P, x, ground, w, h, wall, roof, door="9a5a3a", windows=2, roof_h=None, kid=True):
    roof_h = roof_h or h * 0.55
    P.shape([(x, ground), (x, ground - h), (x + w, ground - h), (x + w, ground)], wall)
    P.shape([(x - w * 0.08, ground - h), (x + w * 0.5, ground - h - roof_h), (x + w * 1.08, ground - h)], roof)
    dw = w * 0.2
    P.shape([(x + w * 0.4, ground), (x + w * 0.4, ground - h * 0.45), (x + w * 0.4 + dw, ground - h * 0.45), (x + w * 0.4 + dw, ground)], door)
    for k in range(windows):
        wx = x + w * (0.12 if k == 0 else 0.68)
        wy = ground - h * 0.8
        ws = w * 0.2
        P.shape([(wx, wy), (wx + ws, wy), (wx + ws, wy + ws), (wx, wy + ws)], "a8d4f0")
        P.outline([(wx + ws / 2, wy), (wx + ws / 2, wy + ws)], closed=False)
        P.outline([(wx, wy + ws / 2), (wx + ws, wy + ws / 2)], closed=False)


def kid_person(P, x, ground, height, skin="f7d9c4", hair="5a3a2a", hair_style="short", top="e0e0e0", bottom="4a5a7a",
               dress=False, cat_ears=False, ahoge=False, bow=None, smile=True, shoes="6a4a3a"):
    """Человечек «как рисуют дети»: большая голова, тело-трапеция, палочки-ноги, ладошки-кружки."""
    head_r = height * 0.15
    hy = ground - height + head_r
    body_top = hy + head_r * 0.95
    body_bot = ground - height * 0.34
    bw = height * 0.13
    # ноги
    for dx in (-0.4, 0.4):
        P.outline([(x + dx * bw, body_bot), (x + dx * bw * 1.1, ground - 6)], "3a3438", closed=False)
        P.shape(P.ellipse_pts((x + dx * bw * 1.3, ground - 4), bw * 0.42, bw * 0.2, n=16), shoes)
    # тело
    if dress:
        body = [(x - bw * 0.7, body_top), (x + bw * 0.7, body_top), (x + bw * 1.5, body_bot + height * 0.05), (x - bw * 1.5, body_bot + height * 0.05)]
        P.shape(body, top)
    else:
        P.shape([(x - bw, body_top), (x + bw, body_top), (x + bw * 1.05, body_bot - height * 0.12), (x - bw * 1.05, body_bot - height * 0.12)], top)
        P.shape([(x - bw * 1.05, body_bot - height * 0.12), (x + bw * 1.05, body_bot - height * 0.12),
                 (x + bw * 0.9, body_bot + 4), (x - bw * 0.9, body_bot + 4)], bottom)
    # руки и ладошки (машут в стороны)
    for side in (-1, 1):
        sx, sy = x + side * bw * 0.95, body_top + height * 0.04
        ex, ey = x + side * bw * 2.3, body_top + height * 0.2 - (height * 0.12 if side > 0 else 0)
        P.outline([(sx, sy), (ex, ey)], "3a3438", closed=False)
        P.shape(P.ellipse_pts((ex, ey), bw * 0.28, bw * 0.28, n=14), skin)
    # уши-кошачьи под волосами
    if cat_ears:
        for side in (-1, 1):
            P.shape([(x + side * head_r * 0.35, hy - head_r * 0.75), (x + side * head_r * 0.95, hy - head_r * 1.45),
                     (x + side * head_r * 0.95, hy - head_r * 0.45)], hair)
    # голова
    P.shape(P.ellipse_pts((x, hy), head_r, head_r * 1.02), skin, strength=0.55)
    # волосы
    if hair_style == "long":
        pts = P.ellipse_pts((x, hy - head_r * 0.15), head_r * 1.12, head_r * 1.05, n=24, a0=math.pi * 0.95, a1=math.pi * 2.05)
        pts += [(x + head_r * 1.15, hy + head_r * 1.9), (x + head_r * 0.75, hy + head_r * 1.9), (x + head_r * 0.8, hy - head_r * 0.2),
                (x - head_r * 0.8, hy - head_r * 0.2), (x - head_r * 0.75, hy + head_r * 1.9), (x - head_r * 1.15, hy + head_r * 1.9)]
        P.shape(pts, hair)
    elif hair_style == "curly":
        pts = []
        for k in range(10):
            a = math.pi * (0.95 + 1.1 * k / 9)
            pts += P.ellipse_pts((x + math.cos(a) * head_r * 0.95, hy - head_r * 0.1 + math.sin(a) * head_r * 0.9),
                                 head_r * 0.32, head_r * 0.32, n=8, a0=a - 1.4, a1=a + 1.4)
        pts += [(x + head_r * 1.1, hy + head_r * 0.2), (x + head_r * 0.6, hy - head_r * 0.35), (x - head_r * 0.6, hy - head_r * 0.35),
                (x - head_r * 1.1, hy + head_r * 0.2)]
        P.shape(pts, hair)
    else:
        pts = P.ellipse_pts((x, hy - head_r * 0.12), head_r * 1.08, head_r * 0.98, n=24, a0=math.pi * 0.98, a1=math.pi * 2.02)
        pts += [(x + head_r * 0.7, hy - head_r * 0.3), (x - head_r * 0.7, hy - head_r * 0.3)]
        P.shape(pts, hair)
    if ahoge:
        P.outline([(x, hy - head_r * 1.05), (x + head_r * 0.15, hy - head_r * 1.5), (x + head_r * 0.42, hy - head_r * 1.45),
                   (x + head_r * 0.35, hy - head_r * 1.25)], hair if hair != "8fdcc8" else "3aa08a", closed=False)
    if bow:
        P.shape([(x + head_r * 0.5, hy - head_r * 0.85), (x + head_r * 1.1, hy - head_r * 1.2), (x + head_r * 1.05, hy - head_r * 0.6)], bow)
        P.shape([(x + head_r * 0.5, hy - head_r * 0.85), (x - head_r * 0.05, hy - head_r * 1.2), (x - head_r * 0.0, hy - head_r * 0.55)], bow)
    # лицо: точки-глаза, щёчки, улыбка
    for side in (-1, 1):
        P.shape(P.ellipse_pts((x + side * head_r * 0.36, hy + head_r * 0.12), head_r * 0.07, head_r * 0.1, n=10), "2a2428", line=None, strength=1.0)
        P.hatch(P.poly_mask(P.ellipse_pts((x + side * head_r * 0.55, hy + head_r * 0.42), head_r * 0.14, head_r * 0.09, n=12)),
                hexc("f29a9a"), strength=0.6)
    if smile:
        P.outline(P.ellipse_pts((x, hy + head_r * 0.35), head_r * 0.28, head_r * 0.2, n=12, a0=0.3, a1=math.pi - 0.3), "a04848", closed=False)


# ------------------------------------------------------------------ страницы


def sketch_street():
    """Улица у переезда (Кот, 6 лет): дома, столб с проводами, переезд с крестом и красными огнями, рельсы, солнце."""
    P = Paper(11, skill=0.0)
    ground = H * 0.74
    # небо — неровная штриховка голубым
    sky_band(P, 230)
    sun(P, (W * 0.86, H * 0.16), 85)
    cloud(P, (W * 0.3, H * 0.15), 70)
    cloud(P, (W * 0.58, H * 0.1), 55)
    # дорога и земля
    P.shape([(0, ground), (W, ground), (W, H), (0, H)], "c8c2bc", line=None, strength=0.55, angle=0.05)
    P.outline([(0, ground), (W, ground)], closed=False)
    # дома
    house(P, 90, ground, 420, 330, "f4e3c0", "5f86c2")
    house(P, 1310, ground, 380, 300, "f1d6d6", "c95b4a")
    house(P, 1700, ground, 300, 380, "e6ecd8", "7a6a5a", windows=2)
    # дерево
    P.shape([(560, ground), (575, ground - 210), (610, ground - 210), (625, ground)], "8a5a3a")
    P.shape(P.ellipse_pts((592, ground - 290), 130, 110), "7cc070", "3e7a3a")
    # столб и провода
    P.shape([(700, ground), (712, ground - 560), (734, ground - 560), (742, ground)], "a8a098")
    P.outline([(640, ground - 520), (800, ground - 520)], closed=False)
    for k, yy in enumerate((ground - 515, ground - 490)):
        pts = [(0, yy + 30), (360, yy + 70 + 12 * k), (722, yy), (1100, yy + 60 + 10 * k), (1500, yy + 20), (W, yy + 50)]
        P.outline(pts, "4a4448", width=3.5, closed=False, amp=1.2)
    # переезд: рельсы по дороге, шпалы, столбик с крестом и двумя красными огнями, шлагбаум в полоску
    for yy in (ground + 120, ground + 190):
        P.outline([(0, yy), (W, yy + 10)], "6a6468", closed=False)
    for k in range(18):
        x = 40 + k * 115
        P.outline([(x, ground + 100), (x + 10, ground + 215)], "8a6a4a", width=9, closed=False)
    px = 1080
    P.shape([(px - 12, ground + 60), (px - 10, ground - 400), (px + 12, ground - 400), (px + 14, ground + 60)], "f0f0f0")
    for k in range(6):
        y = ground - 380 + k * 70
        P.shape([(px - 11, y), (px + 12, y), (px + 12, y + 35), (px - 11, y + 35)], "2a2628", line=None, strength=0.9)
    for s in (-1, 1):
        P.shape([(px - 110, ground - 520 + 0), (px - 90, ground - 540), (px + 110, ground - 400), (px + 90, ground - 380)] if s < 0 else
                [(px + 110, ground - 520), (px + 90, ground - 540), (px - 110, ground - 400), (px - 90, ground - 380)], "f6d23a")
    for dx in (-60, 60):
        P.shape(P.ellipse_pts((px + dx, ground - 330), 40, 40, n=20), "e8443a")
        P.outline([(px, ground - 330), (px + dx * 0.6, ground - 330)], closed=False)
    arm = [(px + 30, ground - 120), (px + 520, ground - 110), (px + 520, ground - 90), (px + 30, ground - 98)]
    P.shape(arm, "f6d23a")
    for k in range(5):
        x = px + 70 + k * 95
        P.shape([(x, ground - 118), (x + 45, ground - 117), (x + 45, ground - 94), (x, ground - 96)], "2a2628", line=None)
    # подпись ребёнка
    sign(P, (W - 360, H - 90), "КОТ 6")
    P.save("sketch_street")


def sign(P, pos, text):
    """Подпись печатными буквами — палочками, как пишут дети (только нужные буквы)."""
    x, y = pos
    s = 46
    letters = {
        "К": [[(0, 0), (0, 1)], [(0, 0.5), (0.6, 0)], [(0.15, 0.4), (0.6, 1)]],
        "О": "circle",
        "Т": [[(0, 0), (0.7, 0)], [(0.35, 0), (0.35, 1)]],
        "6": "six",
        " ": [],
    }
    for ch in text:
        L = letters.get(ch, [])
        if L == "circle":
            P.outline(P.ellipse_pts((x + s * 0.32, y + s * 0.5), s * 0.32, s * 0.5, n=20), "3a6ab0", width=5)
        elif L == "six":
            P.outline([(x + s * 0.55, y), (x + s * 0.1, y + s * 0.55)] + P.ellipse_pts((x + s * 0.32, y + s * 0.72), s * 0.26, s * 0.28, n=16, a0=math.pi, a1=3 * math.pi), "3a6ab0", width=5, closed=False)
        else:
            for seg in L:
                P.outline([(x + a * s, y + b * s) for a, b in seg], "3a6ab0", width=5, closed=False)
        x += s * 0.9


def sketch_family():
    """Мама, папа, Сора, Габриэль (Кот, 6 лет): семья в ряд у дома, держатся за руки, солнце и сердечки."""
    P = Paper(22, skill=0.05)
    ground = H * 0.86
    P.hatch(P.poly_mask([(0, ground), (W, ground), (W, H), (0, H)]), hexc("9cd08a"), angle=0.1, spacing=14, strength=0.6)
    for k in range(40):
        gx = P.rng.uniform(0, W)
        P.outline([(gx, ground + 4), (gx + 8, ground - 22), (gx + 16, ground + 4)], "4e8a3e", width=4, closed=False)
    sky_band(P, 190)
    sun(P, (180, 170), 95)
    cloud(P, (W * 0.55, 150), 65)
    house(P, W - 560, ground, 460, 360, "f4e3c0", "c95b4a")
    # семья: цвета волос и одежды — как у моделей (мама рыжая, папа и Сора — бирюзовые с ушами, Габи рыжая с бантом)
    fam = [
        (360, 760, dict(hair="b0584a", hair_style="long", top="f6efe4", bottom="c98a7a", dress=True)),                       # мама
        (640, 830, dict(hair="2a6a70", hair_style="short", top="6e7d8c", bottom="4a4e5a", cat_ears=True, ahoge=True)),        # папа
        (920, 780, dict(hair="3a9a92", hair_style="short", top="3f5d6a", bottom="2f3440", cat_ears=True)),                     # Сора, 18
        (1180, 560, dict(hair="e8763a", hair_style="long", top="f2b6c3", dress=True, bow="e8505a")),                         # Габриэль, 12
    ]
    for x, h, kw in fam:
        kid_person(P, x, ground, h, **kw)
    for c in ((520, 260), (1060, 300), (800, 200)):
        heart(P, c, 34)
    sign(P, (W - 380, 80), "КОТ 6")
    P.save("sketch_family")


def heart(P, c, s):
    x, y = c
    pts = P.ellipse_pts((x - s * 0.5, y), s * 0.55, s * 0.55, n=12, a0=math.pi * 0.8, a1=math.pi * 2.0) + \
        P.ellipse_pts((x + s * 0.5, y), s * 0.55, s * 0.55, n=12, a0=math.pi * 1.0, a1=math.pi * 2.2) + [(x, y + s * 1.3)]
    P.shape(pts, "f0607a", "c0384a")


def sketch_city(skill=0.0, name="sketch_city", seed=33):
    """Город сверху (с крыши): ряды крыш, столбы, море и гора, вечернее солнце."""
    P = Paper(seed, tone="fbf5ea", skill=skill)
    hor = H * 0.36
    sky = P.poly_mask([(0, 0), (W, 0), (W, hor), (0, hor)])
    if skill > 0.5:
        P.wash(P.poly_mask([(0, hor * 0.4), (W, hor * 0.35), (W, hor), (0, hor)]), hexc("f6d6b8"), 0.6)
        P.wash(P.poly_mask([(0, 0), (W, 0), (W, hor * 0.35), (0, hor * 0.4)]), hexc("dfe2f2"), 0.4)
    else:
        P.hatch(sky, hexc("f8c890"), angle=0.15, spacing=15, strength=0.5)
    # гора и море
    P.shape([(W * 0.45, hor + 10), (W * 0.62, hor - 250), (W * 0.7, hor - 210), (W * 0.82, hor - 120), (W * 0.98, hor + 10)], "9aa6c8", line="5a6688", strength=0.55)
    P.shape([(0, hor), (W, hor), (W, hor + 90), (0, hor + 100)], "7ab0d8", line=None, strength=0.6, angle=0.02)
    P.outline([(0, hor), (W, hor)], "5a6688", closed=False)
    if skill <= 0.5:
        sun(P, (W * 0.25, hor - 60), 70)
    else:
        P.shape(P.ellipse_pts((W * 0.25, hor - 40), 60, 60), "f6b070", "d07848", strength=0.5)
    # ряды домов: от дальних (мелкие) к ближним (крупные)
    rows = [(hor + 150, 70, 60, 26), (hor + 290, 110, 90, 18), (hor + 470, 170, 130, 12), (hor + 700, 260, 190, 8)]
    roof_cols = ["c95b4a", "5f86c2", "7a6a5a", "4a6a8a", "b06a5a", "6a8aa0"]
    wall_cols = ["f4e3c0", "f1e0d8", "e6ecd8", "eae4f0", "f6ead4"]
    for gy, w, h, n in rows:
        x = -w * 0.3
        while x < W:
            ww = w * P.rng.uniform(0.8, 1.2)
            hh = h * P.rng.uniform(0.8, 1.2)
            if skill > 0.5 and P.rng.random() < 0.18:
                # многоэтажка: плоская крыша, ряды окон
                bh = hh * P.rng.uniform(1.8, 2.8)
                P.shape([(x, gy), (x, gy - bh), (x + ww * 0.9, gy - bh), (x + ww * 0.9, gy)], P.rng.choice(wall_cols), strength=0.45)
                for r_ in range(int(bh / (hh * 0.35))):
                    yy = gy - bh + hh * 0.18 + r_ * hh * 0.35
                    P.outline([(x + ww * 0.12, yy), (x + ww * 0.78, yy)], "6a6070", width=2.4, closed=False, strength=0.6)
                x += ww * P.rng.uniform(1.0, 1.2)
                continue
            if skill > 0.5:
                P.shape([(x, gy), (x, gy - hh), (x + ww, gy - hh), (x + ww, gy)], P.rng.choice(wall_cols), strength=0.4)
                P.shape([(x - ww * 0.05, gy - hh), (x + ww * 0.5, gy - hh - hh * 0.5), (x + ww * 1.05, gy - hh)], P.rng.choice(roof_cols), strength=0.55)
                # окна: короткие штрихи; вечером тёплые
                for k in range(2):
                    wx = x + ww * (0.2 + 0.45 * k)
                    P.shape([(wx, gy - hh * 0.7), (wx + ww * 0.18, gy - hh * 0.7), (wx + ww * 0.18, gy - hh * 0.45), (wx, gy - hh * 0.45)], "f6c87a", line="5a5058", strength=0.6)
            else:
                house(P, x, gy, ww, hh, P.rng.choice(wall_cols), P.rng.choice(roof_cols), windows=2)
            x += ww * P.rng.uniform(1.05, 1.3)
    # столбы и провода
    for px in (260, 980, 1700):
        P.outline([(px, H), (px + 6, hor + 200)], "4a4448", width=8 if skill < 0.5 else 5, closed=False)
        P.outline([(px - 60, hor + 230), (px + 70, hor + 232)], "4a4448", closed=False)
    for k in range(2):
        P.outline([(0, hor + 260 + k * 22), (260, hor + 232 + k * 4), (980, hor + 300 + k * 20), (1700, hor + 232 + k * 4), (W, hor + 290 + k * 20)],
                  "4a4448", width=3, closed=False, amp=1.0)
    if skill > 0.5:
        # тень штрихом по ближнему ряду и подпись карандашом
        P.hatch(P.poly_mask([(0, H * 0.84), (W, H * 0.8), (W, H), (0, H)]), hexc("8a8098"), angle=-0.7, spacing=9, strength=0.35, scribble=False)
    else:
        sign(P, (W - 380, H - 100), "КОТ 6")
    P.save(name)


def bez(p0, p1, p2, n=12):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0], (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1])
            for t in (k / n for k in range(n + 1))]


def back_figure(P, x, seat, u, hair, style, top, ears=False, ahoge=False):
    """Сидит спиной к нам на парапете: плавные плечи, голова на плечах, уши; тень — мягкой акварелью справа."""
    y0 = seat - 2.5 * u                      # линия плеч у шеи
    torso = [(x - 0.95 * u, seat), (x - 1.1 * u, y0 + 0.9 * u)] + bez((x - 1.15 * u, y0 + 0.55 * u), (x - 1.05 * u, y0), (x - 0.3 * u, y0)) + \
        bez((x + 0.3 * u, y0), (x + 1.05 * u, y0), (x + 1.15 * u, y0 + 0.55 * u)) + [(x + 1.1 * u, y0 + 0.9 * u), (x + 0.95 * u, seat)]
    P.erase(P.poly_mask(torso, grow=4))
    P.erase(P.poly_mask(P.ellipse_pts((x, y0 - 0.5 * u), 0.85 * u, 0.82 * u), grow=3))
    P.hatch(P.poly_mask(torso), hexc(top), angle=1.25, spacing=6, width=3, strength=0.7, scribble=False)
    shade = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shade).polygon([(x + 0.25 * u, y0 - u), (x + 1.5 * u, y0 - u), (x + 1.5 * u, seat), (x + 0.4 * u, seat)], fill=255)
    P.wash(Image.fromarray(np.minimum(np.array(P.poly_mask(torso)), np.array(shade))), hexc("8a7e9a"), 0.35)
    P.outline(torso, "3a3438")
    # складки ткани у плеч и лопаток
    for sd in (-1, 1):
        P.outline(bez((x + sd * 0.55 * u, y0 + 0.5 * u), (x + sd * 0.35 * u, y0 + 1.0 * u), (x + sd * 0.5 * u, y0 + 1.5 * u), n=8),
                  "5a5058", width=2.2, closed=False, strength=0.45)
        P.outline([(x + sd * 1.1 * u, y0 + 0.9 * u), (x + sd * 1.0 * u, seat - 0.15 * u)], "3a3438", width=2.6, closed=False, strength=0.6)
    hx, hr = x, 0.74 * u
    hy = y0 - 0.5 * u
    if ears:
        for sd in (-1, 1):
            P.shape([(hx + sd * 0.25 * hr, hy - 0.8 * hr), (hx + sd * 0.85 * hr, hy - 1.55 * hr), (hx + sd * 0.95 * hr, hy - 0.45 * hr)], hair)
    if style == "long":
        pts = P.ellipse_pts((hx, hy), hr * 1.08, hr * 1.05, n=24, a0=math.pi, a1=math.pi * 2) + \
            bez((hx + hr * 1.08, hy), (hx + hr * 1.3, y0 + 0.8 * u), (hx + hr * 0.9, y0 + 1.3 * u)) + \
            bez((hx - hr * 0.9, y0 + 1.3 * u), (hx - hr * 1.3, y0 + 0.8 * u), (hx - hr * 1.08, hy))
    elif style == "curly":
        pts = []
        for k in range(12):
            a = math.pi * (0.8 + 1.4 * k / 11)
            pts += P.ellipse_pts((hx + math.cos(a) * hr * 0.92, hy + math.sin(a) * hr * 0.92), hr * 0.3, hr * 0.3, n=8, a0=a - 1.5, a1=a + 1.5)
        pts += [(hx + hr * 0.8, hy + hr * 0.95), (hx - hr * 0.8, hy + hr * 0.95)]
    else:
        pts = P.ellipse_pts((hx, hy), hr * 1.05, hr * 1.02, n=24, a0=math.pi * 0.85, a1=math.pi * 2.15) + \
            [(hx + hr * 0.7, hy + hr * 0.95), (hx - hr * 0.7, hy + hr * 0.95)]
    P.hatch(P.poly_mask(pts), hexc(hair), angle=1.4, spacing=5, width=2.8, strength=0.9, scribble=False)
    P.outline(pts, "3a3438")
    # пряди: пара дуг от макушки по форме головы
    for sd in (-1, 0, 1):
        P.outline(bez((hx + sd * hr * 0.1, hy - hr * 0.85), (hx + sd * hr * 0.75, hy - hr * 0.3), (hx + sd * hr * 0.55, hy + hr * 0.6), n=8),
                  "3a3438", width=2.0, closed=False, strength=0.35)
    if ahoge:
        P.outline([(hx, hy - hr), (hx + hr * 0.2, hy - hr * 1.5), (hx + hr * 0.5, hy - hr * 1.4), (hx + hr * 0.38, hy - hr * 1.2)], "2a7a6a", closed=False)


def sketch_three():
    """Сора, Габриэль и я (Кот старше): трое сидят спиной на парапете крыши и смотрят на город.
    Уверенный карандаш, тень штрихом, акварельная подложка неба."""
    P = Paper(44, tone="fbf6ec", skill=0.85)
    hor = H * 0.5
    P.wash(P.poly_mask([(0, hor * 0.35), (W, hor * 0.3), (W, hor + 60), (0, hor + 60)]), hexc("f6d6b8"), 0.6)
    P.wash(P.poly_mask([(0, 0), (W, 0), (W, hor * 0.3), (0, hor * 0.35)]), hexc("dfe2f2"), 0.4)
    P.shape(P.ellipse_pts((W * 0.84, hor * 0.55), 60, 60), "f6a868", "c87a48", strength=0.5)
    # дальний город — лёгкий контур крыш
    x = 0
    sky = [(0, hor + 40)]
    while x < W:
        w = P.rng.uniform(60, 160)
        h = P.rng.uniform(30, 130) if P.rng.random() < 0.8 else P.rng.uniform(150, 230)
        sky += [(x, hor + 40 - h), (x + w, hor + 40 - h)]
        x += w
    sky += [(W, hor + 40), (W, hor + 120), (0, hor + 120)]
    P.shape(sky, "b4b0c4", "7a7088", width=2.2, strength=0.45)
    # парапет
    seat = H * 0.74
    P.shape([(0, seat), (W, seat), (W, seat + 90), (0, seat + 90)], "d8d0c8", "5a5058", strength=0.55)
    P.hatch(P.poly_mask([(0, seat + 90), (W, seat + 90), (W, H), (0, H)]), hexc("a89cac"), angle=-0.6, spacing=8, width=2.6, strength=0.45, scribble=False)
    # трое: Сора (выше), Габриэль, Кот
    back_figure(P, W * 0.32, seat, 130, "3a9a92", "short", "3f5d6a", ears=True)
    back_figure(P, W * 0.5, seat, 108, "e8763a", "long", "8a6a5a")
    back_figure(P, W * 0.66, seat, 100, "8fdcc8", "curly", "f4d98c", ears=True, ahoge=True)
    P.save("sketch_three")


PAGES = {"sketch_street": sketch_street, "sketch_family": sketch_family, "sketch_city": sketch_city,
         "sketch_city_later": lambda: sketch_city(0.85, "sketch_city_later", 55), "sketch_three": sketch_three}

if __name__ == "__main__":
    for n in sys.argv[1:] or PAGES:
        PAGES[n]()
