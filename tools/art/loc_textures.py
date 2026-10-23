"""Пиксельные текстуры локаций по правилам location-kit (docs/location-kit/SKILL.md, «Pixel register»):
1 тексель ≈ 1 см, фильтрация «ближайший» (в игре — шейдер toon_loc), сид у каждой текстуры свой.
Порт генераторов из docs/location-kit/location-kit.js (planks, paint, oak, …) + свои для японского пригорода
(асфальт, бетонные блоки, обшивка, черепица кавара, татами, сёдзи) и виды из окон по времени суток.

Запуск: python3 tools/art/loc_textures.py → art/locations/textures/*.png
Импортирует build_locations.py (имена файлов = ключи TEX)."""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "art", "locations", "textures")


def rng(seed):
    return random.Random(seed)


def C(r, g, b, a=255):
    return (max(0, min(255, int(r))), max(0, min(255, int(g))), max(0, min(255, int(b))), max(0, min(255, int(a))))


class Canvas:
    def __init__(self, w, h, bg=(0, 0, 0, 255)):
        self.w, self.h = w, h
        self.im = Image.new("RGBA", (w, h), bg)
        self.d = ImageDraw.Draw(self.im, "RGBA")

    def rect(self, x, y, w, h, c):
        """Прямоугольник с переносом по краям (текстура тайлится)."""
        x, y, w, h = int(x), int(y), max(1, int(round(w))), max(1, int(round(h)))
        for ox in (0, -self.w, self.w):
            for oy in (0, -self.h, self.h):
                x0, y0 = x + ox, y + oy
                if x0 + w <= 0 or y0 + h <= 0 or x0 >= self.w or y0 >= self.h:
                    continue
                self.d.rectangle([x0, y0, x0 + w - 1, y0 + h - 1], fill=c)

    def save(self, name):
        os.makedirs(OUT, exist_ok=True)
        self.im.save(os.path.join(OUT, name + ".png"))


TEX = {}


def tex(fn):
    TEX[fn.__name__] = fn
    return fn


# ---------------------------------------------------------------- порт из location-kit.js

@tex
def planks():
    """Половые доски вдоль x, разбежка стыков, волокна (медовый тон)."""
    c = Canvas(128, 128)
    r = rng(901)
    base = (170, 118, 72)
    bh = 14
    for y in range(0, 128, bh):
        x = -int(r.random() * 90)
        while x < 128:
            ln = 50 + r.random() * 70
            v, warm = (r.random() - 0.5) * 30, (r.random() - 0.5) * 10
            c.rect(x, y, ln, bh, C(base[0] + v + warm, base[1] + v, base[2] + v - warm))
            for _ in range(6):
                gy = y + 1 + int(r.random() * (bh - 2))
                c.rect(x + r.random() * 8, gy, ln * (0.3 + r.random() * 0.7), 1, C(base[0] + v - 28, base[1] + v - 24, base[2] + v - 20, 90))
            if r.random() < 0.25:
                c.rect(x + ln * r.random(), y + 4 + r.random() * 6, 3, 2, C(base[0] - 60, base[1] - 50, base[2] - 40, 150))
            c.rect(x, y, 1, bh, C(base[0] - 80, base[1] - 66, base[2] - 50, 230))
            x += int(ln)
        c.rect(0, y + bh - 1, 128, 1, C(base[0] - 90, base[1] - 72, base[2] - 56, 217))
        c.rect(0, y, 128, 1, C(base[0] + 30, base[1] + 26, base[2] + 20, 64))
    return c


def _paint(seed, col, w=64):
    c = Canvas(w, w, C(*col))
    r = rng(seed)
    for _ in range(int(700 * (w / 64) ** 2)):
        v = (r.random() - 0.5) * 12
        c.rect(r.random() * w, r.random() * w, 1 + r.random() * 2, 1, C(col[0] + v, col[1] + v, col[2] + v, 128))
    return c


@tex
def paint_cream():
    return _paint(11, (232, 222, 204))


@tex
def paint_warm():
    return _paint(12, (226, 210, 188))


@tex
def paint_mint():
    return _paint(13, (206, 222, 212))


@tex
def paint_white():
    return _paint(14, (236, 234, 226))


@tex
def paint_ceiling():
    return _paint(15, (238, 234, 226))


@tex
def oak():
    c = Canvas(32, 128, C(168, 122, 74))
    r = rng(62)
    b = (168, 122, 74)
    for i in range(40):
        x, v = r.random() * 32, (r.random() - 0.5) * 40
        for y in range(0, 128, 2):
            c.rect(x + math.sin(y * 0.05 + i) * 1.5, y, 1, 2, C(b[0] + v, b[1] + v * 0.8, b[2] + v * 0.6, 90))
    for _ in range(3):
        c.rect(r.random() * 32, r.random() * 128, 2, 4, C(b[0] - 50, b[1] - 40, b[2] - 30, 128))
    return c


@tex
def oak_pale():
    c = Canvas(32, 128, C(196, 160, 116))
    r = rng(63)
    b = (196, 160, 116)
    for i in range(40):
        x, v = r.random() * 32, (r.random() - 0.5) * 34
        for y in range(0, 128, 2):
            c.rect(x + math.sin(y * 0.05 + i) * 1.5, y, 1, 2, C(b[0] + v, b[1] + v * 0.8, b[2] + v * 0.6, 80))
    return c


@tex
def darkwood():
    c = Canvas(32, 64, C(58, 34, 25))
    r = rng(71)
    for _ in range(30):
        c.rect(r.random() * 32, 0, 1, 64, (20, 10, 6, 100) if r.random() < 0.5 else (90, 56, 40, 64))
    return c


@tex
def blinds():
    c = Canvas(32, 32, (0, 0, 0, 0))
    for y in range(0, 32, 4):
        c.rect(0, y, 32, 2, C(239, 238, 232))
        c.rect(0, y + 2, 32, 1, C(200, 198, 190))
    c.rect(7, 0, 1, 32, C(220, 214, 200, 230))
    c.rect(24, 0, 1, 32, C(220, 214, 200, 230))
    return c


@tex
def stripes():
    c = Canvas(64, 32, C(233, 226, 208))
    r = rng(91)
    for x in range(4, 64, 16):
        c.rect(x, 0, 2, 32, C(58, 62, 82))
        c.rect(x + 4, 0, 1, 32, C(58, 62, 82))
        for y in range(0, 32, 4):
            c.rect(x + 8, y, 1, 2, C(42, 46, 64))
    for _ in range(120):
        c.rect(r.random() * 64, r.random() * 32, 2, 1, C(120, 110, 90, 30))
    return c


@tex
def shag():
    c = Canvas(64, 64, C(140, 133, 120))
    r = rng(101)
    for _ in range(1600):
        v = (r.random() - 0.5) * 50
        c.rect(r.random() * 64, r.random() * 64, 1, 2 + r.random() * 2, C(140 + v, 133 + v, 120 + v, 180))
    return c


@tex
def rug_rose():
    c = Canvas(64, 64, C(214, 170, 160))
    r = rng(102)
    for _ in range(1400):
        v = (r.random() - 0.5) * 36
        c.rect(r.random() * 64, r.random() * 64, 1, 2, C(214 + v, 170 + v, 160 + v, 170))
    for k in (4, 59):
        c.rect(0, k, 64, 2, C(150, 96, 92))
    return c


@tex
def carpet():
    c = Canvas(32, 32, C(126, 124, 122))
    r = rng(111)
    for _ in range(500):
        v = (r.random() - 0.5) * 30
        c.rect(r.random() * 32, r.random() * 32, 1, 1, C(126 + v, 124 + v, 122 + v))
    return c


@tex
def jute():
    c = Canvas(32, 32)
    r = rng(121)
    for y in range(0, 32, 2):
        for x in range(0, 32, 2):
            v = (r.random() - 0.5) * 24 + (10 if ((x + y) // 2) % 2 else -10)
            c.rect(x, y, 2, 2, C(176 + v, 150 + v, 104 + v))
    return c


@tex
def plaid():
    c = Canvas(32, 32, C(200, 184, 154))
    c.rect(0, 10, 32, 6, C(138, 58, 42, 180))
    c.rect(10, 0, 6, 32, C(138, 58, 42, 180))
    c.rect(0, 24, 32, 1, C(58, 46, 40, 204))
    c.rect(24, 0, 1, 32, C(58, 46, 40, 204))
    return c


@tex
def quilt():
    c = Canvas(32, 32)
    r = rng(131)
    cols = [(184, 90, 58), (224, 192, 112), (74, 106, 138), (122, 154, 90), (216, 208, 192), (138, 58, 74), (90, 138, 138)]
    for j in range(4):
        for i in range(4):
            c.rect(i * 8, j * 8, 8, 8, C(*r.choice(cols)))
            c.rect(i * 8 + 2, j * 8 + 2, 2, 2, (255, 255, 255, 64))
    for k in range(4):
        c.rect(k * 8, 0, 1, 32, (40, 30, 20, 90))
        c.rect(0, k * 8, 32, 1, (40, 30, 20, 90))
    return c


@tex
def paper():
    c = Canvas(24, 32, C(238, 236, 230))
    r = rng(151)
    for y in range(4, 29, 2):
        c.rect(3, y, 6 + r.random() * 14, 1, (40, 40, 50, 140))
    return c


@tex
def lino():
    """Линолеум больницы: плитки 30 см с разным оттенком, вкрапления, потёртости, тёмные швы."""
    c = Canvas(60, 60)
    r = rng(5)
    for j in range(2):
        for i in range(2):
            v, warm = (r.random() - 0.5) * 16, (6 if (i + j) % 2 else -4)
            c.rect(i * 30, j * 30, 30, 30, C(136 + v + warm, 150 + v, 140 + v - warm))
            for _ in range(120):
                q = (r.random() - 0.5) * 34
                c.rect(i * 30 + r.random() * 30, j * 30 + r.random() * 30, 1, 1, C(136 + v + q, 150 + v + q, 140 + v + q, 150))
    for _ in range(5):
        c.rect(r.random() * 60, r.random() * 60, 4 + r.random() * 8, 1, (40, 40, 40, 46))
    for t in (0, 30):
        c.rect(0, t, 60, 1, (40, 50, 50, 128))
        c.rect(t, 0, 1, 60, (40, 50, 50, 128))
    return c


@tex
def wall_tiles():
    c = Canvas(32, 32, C(184, 196, 188))
    r = rng(9)
    for j in range(2):
        for i in range(2):
            c.rect(i * 16 + 1, j * 16 + 1, 15, 15, C(170 + r.random() * 14, 196 + r.random() * 14, 186 + r.random() * 10))
            c.rect(i * 16 + 3, j * 16 + 3, 4, 1, (255, 255, 255, 90))
    return c


@tex
def ceiling_tiles():
    c = Canvas(60, 60, C(212, 214, 208))
    r = rng(13)
    for _ in range(300):
        c.rect(r.random() * 60, r.random() * 60, 1, 1, (80, 80, 70, int(r.random() * 64)))
    c.rect(0, 0, 60, 1, C(154, 156, 150))
    c.rect(0, 0, 1, 60, C(154, 156, 150))
    return c


@tex
def cork():
    c = Canvas(90, 60, C(168, 128, 78))
    r = rng(17)
    for _ in range(400):
        c.rect(r.random() * 90, r.random() * 60, 1, 1, (70, 44, 20, 100) if r.random() < 0.5 else (210, 170, 110, 100))
    cols = [(238, 236, 230), (240, 224, 160), (208, 224, 240), (240, 200, 200)]
    for i in range(14):
        x, y = 2 + (i % 5) * 17 + r.random() * 4, 3 + (i // 5) * 19 + r.random() * 3
        c.rect(x, y, 14, 18, C(*cols[i % 4]))
        for k in range(4, 16, 2):
            c.rect(x + 2, y + k, 6 + r.random() * 6, 1, (40, 40, 50, 128))
        c.rect(x + 6, y + 1, 2, 2, C(200, 32, 32))
    return c


# ---------------------------------------------------------------- японский пригород (реф. пользователя)

@tex
def asphalt():
    """Асфальт 1.28 м: зерно, светлые камешки, заплатки, трещины."""
    c = Canvas(128, 128, C(122, 118, 126))
    r = rng(401)
    for _ in range(5200):
        v = (r.random() - 0.5) * 34
        c.rect(r.random() * 128, r.random() * 128, 1, 1, C(122 + v, 118 + v, 126 + v))
    for _ in range(260):
        c.rect(r.random() * 128, r.random() * 128, 1, 1, C(176, 172, 170, 160))
    for _ in range(2):
        x, y = r.random() * 128, r.random() * 128
        c.rect(x, y, 18 + r.random() * 20, 10 + r.random() * 14, C(106, 102, 110, 150))
    for _ in range(3):   # трещины
        x, y = r.random() * 128, r.random() * 128
        for k in range(30):
            x += r.choice((-1, 0, 1, 1))
            y += r.choice((0, 1, 1))
            c.rect(x, y, 1, 1, C(70, 66, 74, 200))
    return c


@tex
def block_wall():
    """Бетонный блочный забор: блоки 39×19 см, растворные швы, пятна, мох у низа."""
    c = Canvas(80, 40, C(160, 156, 146))
    r = rng(411)
    for j in range(2):
        for i in range(2):
            x0 = i * 40 + (20 if j % 2 else 0)
            v = (r.random() - 0.5) * 16
            c.rect(x0, j * 20, 39, 19, C(196 + v, 192 + v, 182 + v))
            for _ in range(70):
                q = (r.random() - 0.5) * 26
                c.rect(x0 + r.random() * 39, j * 20 + r.random() * 19, 1, 1, C(196 + v + q, 192 + v + q, 182 + v + q, 170))
            if r.random() < 0.5:
                c.rect(x0 + r.random() * 30, j * 20 + 12 + r.random() * 5, 6 + r.random() * 6, 2, C(140, 150, 120, 110))
    return c


@tex
def siding():
    """Обшивка дома: горизонтальные панели 15 см с тенью под кромкой, лёгкая грязь от дождя."""
    c = Canvas(64, 60, C(226, 218, 200))
    r = rng(421)
    for y in range(0, 60, 15):
        v = (r.random() - 0.5) * 8
        c.rect(0, y, 64, 15, C(230 + v, 222 + v, 204 + v))
        c.rect(0, y + 13, 64, 2, C(176, 168, 152))
        c.rect(0, y, 64, 1, C(246, 240, 228))
        for _ in range(30):
            c.rect(r.random() * 64, y + r.random() * 12, 1, 1 + r.random() * 3, C(200, 192, 176, 90))
    return c


@tex
def plaster_ext():
    c = _paint(431, (222, 214, 198))
    r = rng(432)
    for _ in range(40):
        x = r.random() * 64
        c.rect(x, r.random() * 64, 1, 4 + r.random() * 10, C(190, 182, 168, 70))
    return c


@tex
def kawara():
    """Черепица кавара: волнистые ряды 25 см, блики по гребням, тёмные желобки."""
    c = Canvas(50, 50, C(84, 92, 104))
    r = rng(441)
    for y in range(0, 50, 25):
        for x in range(0, 50, 25):
            v = (r.random() - 0.5) * 12
            for k in range(25):
                t = math.sin(k / 25 * math.pi)
                c.rect(x + k, y, 1, 25, C(76 + v + t * 30, 84 + v + t * 30, 98 + v + t * 30))
            c.rect(x, y + 22, 25, 3, C(48, 54, 64))
    return c


@tex
def kawara_red():
    c = Canvas(50, 50, C(140, 70, 60))
    r = rng(442)
    for y in range(0, 50, 25):
        for x in range(0, 50, 25):
            v = (r.random() - 0.5) * 14
            for k in range(25):
                t = math.sin(k / 25 * math.pi)
                c.rect(x + k, y, 1, 25, C(128 + v + t * 34, 62 + v + t * 20, 54 + v + t * 16))
            c.rect(x, y + 22, 25, 3, C(84, 40, 36))
    return c


@tex
def slate_roof():
    c = Canvas(40, 40, C(96, 100, 112))
    r = rng(443)
    for j in range(4):
        for i in range(2):
            x0 = i * 20 + (10 if j % 2 else 0)
            v = (r.random() - 0.5) * 18
            c.rect(x0, j * 10, 19, 9, C(104 + v, 108 + v, 120 + v))
            c.rect(x0, j * 10 + 8, 19, 1, C(62, 64, 72))
    return c


@tex
def concrete():
    c = Canvas(64, 64, C(186, 182, 172))
    r = rng(451)
    for _ in range(1800):
        v = (r.random() - 0.5) * 22
        c.rect(r.random() * 64, r.random() * 64, 1, 1, C(186 + v, 182 + v, 172 + v))
    for _ in range(6):
        c.rect(r.random() * 64, r.random() * 64, 1, 1, C(110, 108, 100))
    c.rect(0, 0, 64, 1, C(150, 146, 138))
    return c


@tex
def paving():
    """Плитка тротуара/сквера 20×20 см."""
    c = Canvas(40, 40, C(150, 140, 126))
    r = rng(452)
    for j in range(2):
        for i in range(2):
            v = (r.random() - 0.5) * 22
            c.rect(i * 20 + 1, j * 20 + 1, 19, 19, C(206 + v, 194 + v, 174 + v))
            for _ in range(30):
                q = (r.random() - 0.5) * 20
                c.rect(i * 20 + 1 + r.random() * 18, j * 20 + 1 + r.random() * 18, 1, 1, C(206 + v + q, 194 + v + q, 174 + v + q))
    return c


@tex
def gravel():
    c = Canvas(64, 64, C(186, 176, 156))
    r = rng(453)
    for _ in range(900):
        v = (r.random() - 0.5) * 60
        c.rect(r.random() * 64, r.random() * 64, 1 + r.random() * 2, 1 + r.random() * 2, C(186 + v, 176 + v, 156 + v))
    return c


@tex
def grass():
    c = Canvas(64, 64, C(112, 150, 92))
    r = rng(461)
    for _ in range(1500):
        v = (r.random() - 0.5) * 50
        c.rect(r.random() * 64, r.random() * 64, 1, 2 + r.random() * 3, C(112 + v * 0.6, 150 + v, 92 + v * 0.5))
    for _ in range(14):
        c.rect(r.random() * 64, r.random() * 64, 2, 2, C(240, 236, 200) if r.random() < 0.5 else C(236, 180, 190))
    return c


@tex
def hedge_leaves():
    c = Canvas(48, 48, C(78, 112, 70))
    r = rng(462)
    for _ in range(420):
        v = (r.random() - 0.5) * 60
        x, y = r.random() * 48, r.random() * 48
        c.rect(x, y, 3, 2, C(88 + v * 0.6, 128 + v, 74 + v * 0.5))
        c.rect(x + 1, y, 1, 1, C(150, 186, 120, 120))
    return c


@tex
def tree_leaves():
    c = Canvas(48, 48, C(108, 150, 98))
    r = rng(463)
    for _ in range(480):
        v = (r.random() - 0.5) * 60
        c.rect(r.random() * 48, r.random() * 48, 3, 3, C(112 + v * 0.6, 156 + v, 102 + v * 0.5))
    for _ in range(60):
        c.rect(r.random() * 48, r.random() * 48, 2, 1, C(196, 224, 160, 160))
    return c


@tex
def bark():
    c = Canvas(32, 64, C(116, 94, 80))
    r = rng(464)
    for i in range(24):
        x, v = r.random() * 32, (r.random() - 0.5) * 40
        c.rect(x, 0, 1 + r.random() * 2, 64, C(116 + v, 94 + v, 80 + v, 170))
    for _ in range(10):
        c.rect(r.random() * 32, r.random() * 64, 3, 1, C(70, 56, 48))
    return c


@tex
def snow():
    c = Canvas(64, 64, C(240, 243, 250))
    r = rng(471)
    for _ in range(900):
        v = (r.random() - 0.5) * 16
        c.rect(r.random() * 64, r.random() * 64, 1, 1, C(232 + v, 236 + v, 248 + v))
    for _ in range(40):
        c.rect(r.random() * 64, r.random() * 64, 1, 1, C(255, 255, 255))
    return c


@tex
def tatami():
    c = Canvas(90, 90, C(196, 186, 128))
    r = rng(481)
    for y in range(90):
        v = (r.random() - 0.5) * 18 + (6 if y % 2 else -6)
        c.rect(0, y, 90, 1, C(196 + v, 186 + v, 128 + v * 0.6))
    c.rect(0, 0, 90, 4, C(70, 80, 66))
    return c


@tex
def shoji():
    """Бумага сёдзи с решёткой (на окна дома семьи)."""
    c = Canvas(40, 40, C(244, 238, 224))
    for k in (0, 20):
        c.rect(k, 0, 2, 40, C(150, 116, 80))
        c.rect(0, k, 40, 2, C(150, 116, 80))
    return c


@tex
def metal_panel():
    c = Canvas(32, 32, C(168, 172, 178))
    r = rng(491)
    for y in range(32):
        v = (r.random() - 0.5) * 10
        c.rect(0, y, 32, 1, C(168 + v, 172 + v, 178 + v))
    c.rect(0, 0, 32, 1, C(120, 124, 130))
    c.rect(2, 2, 1, 1, C(90, 92, 96))
    c.rect(29, 2, 1, 1, C(90, 92, 96))
    return c


@tex
def brick():
    c = Canvas(48, 24, C(170, 160, 150))
    r = rng(492)
    for j in range(4):
        for i in range(2):
            x0 = i * 24 + (12 if j % 2 else 0)
            v = (r.random() - 0.5) * 26
            c.rect(x0, j * 6, 23, 5, C(160 + v, 92 + v * 0.6, 74 + v * 0.5))
    return c


@tex
def stone_wall():
    c = Canvas(64, 64, C(150, 146, 136))
    r = rng(493)
    for _ in range(26):
        x, y, w, h = r.random() * 64, r.random() * 64, 10 + r.random() * 16, 8 + r.random() * 10
        v = (r.random() - 0.5) * 30
        c.rect(x, y, w, h, C(176 + v, 170 + v, 158 + v))
        c.rect(x, y + h - 1, w, 1, C(110, 106, 98))
    return c


@tex
def fabric_cushion():
    c = Canvas(16, 16, C(150, 170, 190))
    r = rng(494)
    for y in range(0, 16, 2):
        c.rect(0, y, 16, 1, C(140, 160, 182))
    for _ in range(20):
        c.rect(r.random() * 16, r.random() * 16, 1, 1, C(176, 194, 210))
    return c


@tex
def linen():
    c = Canvas(32, 32, C(240, 238, 230))
    r = rng(495)
    for y in range(0, 32, 2):
        c.rect(0, y, 32, 1, C(230, 228, 220, 160))
    for _ in range(40):
        c.rect(r.random() * 32, r.random() * 32, 2, 1, C(214, 212, 204, 140))
    return c


@tex
def faded_sign():
    """Выцветшая вывеска отеля: облупившаяся краска, следы букв без читаемого названия (название не задано)."""
    c = Canvas(128, 32, C(138, 106, 82))
    r = rng(496)
    for _ in range(500):
        v = (r.random() - 0.5) * 40
        c.rect(r.random() * 128, r.random() * 32, 2, 1, C(138 + v, 106 + v, 82 + v))
    for i in range(7):
        x = 12 + i * 16
        for k in range(12):
            if r.random() < 0.55:
                c.rect(x + r.random() * 8, 8 + r.random() * 16, 2, 2, C(214, 196, 150, 200))
    c.rect(0, 0, 128, 2, C(90, 66, 50))
    c.rect(0, 30, 128, 2, C(90, 66, 50))
    return c


@tex
def water_stain():
    """Пятно от воды на стене: тёмная полоса снизу, неровная верхняя кромка (наложение с альфой)."""
    c = Canvas(64, 64, (0, 0, 0, 0))
    r = rng(497)
    top = 30
    for x in range(64):
        top += r.choice((-1, 0, 0, 1))
        top = max(24, min(36, top))
        for y in range(top, 64):
            c.rect(x, y, 1, 1, (90, 76, 58, 70 + int((y - top) * 1.2)))
        c.rect(x, top, 1, 1, (70, 58, 44, 170))
    return c


@tex
def shaft():
    """Мягкий световой столб (солнечный луч из окна): альфа-градиент по ширине, затухание к полу."""
    w, h = 64, 256
    im = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    px = im.load()
    for y in range(h):
        for x in range(w):
            u = abs(x / w - 0.5) * 2
            v = y / h
            a = (1 - u) ** 2.2 * math.sin(math.pi * min(1, v * 1.15)) * (0.8 + 0.2 * math.sin(x * 0.4 + y * 0.05))
            px[x, y] = (255, 255, 255, int(max(0, a) * 255))
    c = Canvas(w, h)
    c.im = im
    return c


@tex
def pool():
    """Пятно света на полу: мягкий овал (альфа)."""
    w, h = 64, 64
    im = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    px = im.load()
    for y in range(h):
        for x in range(w):
            d = math.hypot((x - 32) / 32, (y - 32) / 32)
            px[x, y] = (255, 255, 255, int(max(0.0, 1 - d) ** 1.6 * 255))
    c = Canvas(w, h)
    c.im = im
    return c


# ---------------------------------------------------------------- виды из окон (японский пригород, по времени суток)

def _view(time, variant, seed):
    """Вид из окна: соседние дома с черепичными крышами, столбы и провода, зелень; 'high' — поверх крыш к морю.
    Не ярче #E4DCCC (правило location-kit), пикселизация ×3."""
    w, h = 768, 512
    sky = {"day": ((176, 200, 222), (222, 220, 212)), "evening": ((136, 128, 176), (238, 176, 140)),
           "night": ((26, 32, 64), (58, 62, 104))}[time]
    im = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)], fill=tuple(int(sky[0][k] * (1 - t) + sky[1][k] * t) for k in range(3)))
    r = rng(seed)
    hz = int(h * (0.62 if variant == "high" else 0.78))
    # дальние холмы с лесом и гора с комплексом
    hill = {"day": (120, 150, 120), "evening": (110, 96, 120), "night": (30, 38, 58)}[time]
    pts = [(0, hz)]
    for x in range(0, w + 40, 40):
        pts.append((x, hz - 40 - int(r.random() * 50) - (90 if 300 < x < 420 else 0)))
    pts.append((w, hz))
    d.polygon(pts + [(w, h), (0, h)], fill=hill)
    for k in range(5):   # белые корпуса на вершине
        x = 330 + k * 16
        d.rectangle([x, hz - 150 - (k % 2) * 10, x + 12, hz - 120], fill=(228, 224, 214) if time != "night" else (90, 96, 120))
        if time != "day":
            d.rectangle([x + 3, hz - 140, x + 6, hz - 136], fill=(240, 200, 130))
    if variant == "high":
        sea = {"day": (150, 184, 200), "evening": (176, 150, 170), "night": (34, 44, 78)}[time]
        d.rectangle([0, hz, w, hz + 50], fill=sea)
    # дома: стены + черепичные крыши
    base_y = h if variant == "low" else hz + 50
    x = -20
    while x < w:
        bw, bh = 90 + int(r.random() * 80), 110 + int(r.random() * 90)
        if variant == "high":
            bh = 60 + int(r.random() * 70)
        wall = r.choice([(222, 214, 196), (206, 200, 188), (226, 206, 190), (198, 204, 200)])
        k = {"day": 1.0, "evening": 0.78, "night": 0.32}[time]
        wall = tuple(int(c * k) for c in wall)
        y0 = base_y - bh
        d.rectangle([x, y0, x + bw, base_y], fill=wall)
        roof = r.choice([(78, 86, 100), (124, 64, 56), (92, 98, 110)])
        roof = tuple(int(c * k) for c in roof)
        d.polygon([(x - 12, y0), (x + bw + 12, y0), (x + bw - 18, y0 - 34), (x + 18, y0 - 34)], fill=roof)
        for j in range(2 if variant == "low" else 1):
            for i in range(max(1, bw // 40)):
                wx, wy = x + 10 + i * 40, y0 + 18 + j * 52
                lit = time != "day" and r.random() < (0.75 if time == "night" else 0.5)
                win = (232, 196, 132) if lit else {"day": (150, 170, 186), "evening": (110, 104, 130), "night": (30, 34, 56)}[time]
                d.rectangle([wx, wy, wx + 22, wy + 26], fill=win)
                d.line([(wx + 11, wy), (wx + 11, wy + 26)], fill=tuple(int(c * 0.7) for c in wall))
        x += bw + 6 + int(r.random() * 20)
    # столбы и провода
    pole = {"day": (120, 118, 112), "evening": (70, 64, 76), "night": (16, 18, 30)}[time]
    for px_ in (120, 470):
        d.rectangle([px_, int(h * 0.12), px_ + 8, h], fill=pole)
        d.rectangle([px_ - 30, int(h * 0.16), px_ + 38, int(h * 0.16) + 5], fill=pole)
    for k in range(4):
        y1 = int(h * 0.17) + k * 6
        d.line([(0, y1 + 30), (124, y1), (300, y1 + 40), (474, y1), (w, y1 + 30)], fill=pole, width=2)
    # зелень впереди
    leaf = {"day": (96, 134, 86), "evening": (84, 84, 92), "night": (20, 28, 34)}[time]
    for _ in range(14):
        cx, cy, rr = r.random() * w, base_y - r.random() * 60, 20 + r.random() * 40
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=leaf)
    if time == "night":
        for _ in range(40):
            d.point((r.random() * w, r.random() * h * 0.4), fill=(200, 210, 240))
        d.ellipse([620, 60, 650, 90], fill=(226, 228, 236))
    # пикселизация ×3 и ограничение яркости (#E4DCCC)
    im = im.resize((w // 3, h // 3), Image.BILINEAR).resize((w, h), Image.NEAREST)
    px = im.load()
    for y in range(h):
        for x in range(w):
            r_, g_, b_ = px[x, y]
            px[x, y] = (min(r_, 228), min(g_, 220), min(b_, 204))
    c = Canvas(w, h)
    c.im = im.convert("RGBA")
    return c


for _t in ("day", "evening", "night"):
    for _v in ("low", "high"):
        def _mk(t=_t, v=_v):
            return _view(t, v, 700 + len(t) * 7 + len(v))
        _mk.__name__ = f"view_{_v}_{_t}"
        TEX[_mk.__name__] = _mk


# ---------------------------------------------------------------- детские рисунки Кота (мелки) — на стену дома семьи

def _kid(seed, subject):
    w, h = 42, 30
    im = Image.new("RGBA", (w, h), (246, 242, 230, 255))
    d = ImageDraw.Draw(im)
    r = rng(seed)
    crayon = [(220, 70, 60), (60, 120, 200), (240, 190, 40), (80, 160, 90), (150, 90, 170), (240, 140, 60), (90, 170, 200)]
    if subject == "sun_house":
        d.ellipse([30, 2, 39, 11], fill=(248, 200, 60))
        d.rectangle([8, 14, 22, 26], outline=(200, 80, 60))
        d.polygon([(6, 14), (15, 6), (24, 14)], outline=(150, 70, 50))
        d.line([(0, 27), (42, 27)], fill=(80, 160, 90))
    elif subject == "cat":
        d.ellipse([12, 10, 30, 26], outline=(70, 150, 140))
        d.polygon([(13, 12), (15, 4), (19, 10)], outline=(70, 150, 140))
        d.polygon([(23, 10), (27, 4), (29, 12)], outline=(70, 150, 140))
        d.point([(18, 16), (24, 16)], fill=(40, 40, 60))
    elif subject == "family":
        for k in range(5):
            x = 4 + k * 8
            col = crayon[k % len(crayon)]
            hh = [10, 11, 8, 6, 5][k]
            d.ellipse([x, 26 - hh * 2 - 4, x + 4, 26 - hh * 2], outline=col)
            d.line([(x + 2, 26 - hh * 2), (x + 2, 26)], fill=col)
            d.line([(x - 1, 26 - hh * 1.5), (x + 5, 26 - hh * 1.5)], fill=col)
    elif subject == "sea":
        for y in range(18, 30, 3):
            d.line([(0, y), (42, y + r.choice((-1, 1)))], fill=(60, 120, 200))
        d.ellipse([4, 3, 12, 11], fill=(240, 160, 60))
        d.polygon([(20, 17), (34, 17), (31, 21), (23, 21)], outline=(200, 80, 60))
    for _ in range(18):   # штрихи мелков
        c = r.choice(crayon)
        x, y = r.random() * w, r.random() * h
        d.line([(x, y), (x + r.random() * 4, y + r.random() * 2)], fill=c + (90,))
    c = Canvas(w, h)
    c.im = im
    return c


for _i, _s in enumerate(("sun_house", "cat", "family", "sea")):
    def _mk(i=_i, subj=_s):
        return _kid(900 + i, subj)
    _mk.__name__ = f"kid_{_s}"
    TEX[_mk.__name__] = _mk


def build_all():
    for name, fn in TEX.items():
        fn().save(name)
    return sorted(TEX)


if __name__ == "__main__":
    names = build_all()
    print(len(names), "textures →", os.path.abspath(OUT))
