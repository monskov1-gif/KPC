"""Мебель, предметы, окна, двери, лампы и детали улицы для локаций (перенос строителей location-kit:
sofa, coffeeTable, bookcase, bed, desk, chair, windowUnit/brightWindow, panelDoor, pendant, fluorescent, radiator, …
+ японский пригород: дом с вальмовой крышей, бетонный забор, столб с проводами, переезд, автомат с напитками).
Координаты Blender: x — вдоль, y — вглубь, z — вверх; метры. Каждый строитель принимает Scene и рамку (x, y, rz)."""
import math

from mathutils import Matrix, Vector

from lockit import M, hexc, jitter, shade

# ---------------------------------------------------------------- материалы (ключ = текстура)

def mats():
    return {
        "oak": M("oak", "oak"), "oak_pale": M("oak_pale", "oak_pale"), "dark": M("darkwood", "darkwood"),
        "planks": M("floor_planks", "planks"), "fabric": M("fabric"), "cushion": M("cushion", "fabric_cushion"),
        "linen": M("linen", "linen"), "stripes": M("bedding", "stripes"), "quilt": M("quilt", "quilt"),
        "plaid": M("plaid", "plaid"), "metal": M("metal", None, rough=0.35), "paper": M("paper", "paper"),
        "leaves": M("leaves", "tree_leaves"), "hedge": M("hedge", "hedge_leaves"), "bark": M("bark", "bark"),
        "ceramic": M("ceramic", None, rough=0.3), "glow": M("glow_window"), "lamp": M("glow_lamp"),
        "signal": M("glow_signal"), "cork": M("cork", "cork"), "shag": M("rug_shag", "shag"), "rugrose": M("rug_rose", "rug_rose"),
        "jute": M("jute", "jute"), "tatami": M("tatami", "tatami"), "shoji": M("shoji", "shoji"),
        "siding": M("siding", "siding"), "plaster": M("plaster", "plaster_ext"), "kawara": M("kawara", "kawara"),
        "kawara_red": M("kawara_red", "kawara_red"), "slate": M("slate", "slate_roof"), "block": M("block_wall", "block_wall"),
        "concrete": M("concrete", "concrete"), "asphalt": M("asphalt", "asphalt"), "paving": M("paving", "paving"),
        "gravel": M("gravel", "gravel"), "grass": M("grass", "grass"), "snow": M("snow", "snow"),
        "metal_panel": M("metal_panel", "metal_panel"), "brick": M("brick", "brick"), "stone": M("stone", "stone_wall"),
        "lino": M("lino", "lino"), "wall_tiles": M("wall_tiles", "wall_tiles"), "ceil_tiles": M("ceiling_tiles", "ceiling_tiles"),
        "paint_cream": M("paint_cream", "paint_cream"), "paint_warm": M("paint_warm", "paint_warm"),
        "paint_mint": M("paint_mint", "paint_mint"), "paint_white": M("paint_white", "paint_white"),
        "paint_ceiling": M("paint_ceiling", "paint_ceiling"), "blinds": M("alpha_blinds", "blinds"),
        "sign": M("faded_sign", "faded_sign"), "stain": M("alpha_water_stain", "water_stain"),
        "shaft": M("add_shaft", "shaft"), "pool": M("add_pool", "pool"), "glare": M("add_glare"),
    }


class Frame:
    """Локальная рамка предмета: x, y, поворот rz, высота z0. box/cyl/blob/cushion в локальных координатах."""

    def __init__(self, x, y, rz=0.0, z0=0.0):
        self.x, self.y, self.rz, self.z0 = x, y, rz, z0
        self.M = Matrix.Translation((x, y, z0)) @ Matrix.Rotation(rz, 4, "Z")

    def p(self, lx, ly, lz=0.0):
        return tuple(self.M @ Vector((lx, ly, lz)))

    def box(self, b, c, size, color, rz=0.0, **kw):
        b.box(self.p(*c), size, color, rz=self.rz + rz, **kw)

    def cyl(self, b, c, r, h, color, **kw):
        b.cyl(self.p(*c), r, h, color, rz=self.rz, **kw)

    def blob(self, b, c, r, color, **kw):
        b.blob(self.p(*c), r, color, **kw)

    def cushion(self, b, c, size, color, rnd=None, puff=0.35):
        # подушки симметричны: при повороте 90° меняем ширину и глубину местами
        w, d, h = size
        if abs(math.sin(self.rz)) > 0.7:
            w, d = d, w
        b.cushion(self.p(*c), (w, d, h), color, puff=puff, rnd=rnd)


# ---------------------------------------------------------------- мебель

def sofa(S, Mt, x, y, rz=0.0, w=2.0, color="8fa6b8", seed=1, pillows=("f3e1c4", "d9877a")):
    """Диван: каркас со скруглением, надутые сиденья и спинки, подлокотники, ножки, подушки, плед."""
    f = Frame(x, y, rz)
    rnd = S.rnd
    c = hexc(color)
    frame = S.b("prop_sofa_frame-col", Mt["fabric"], bevel=0.03)
    soft = S.b("prop_sofa_soft", Mt["cushion"], smooth=True)
    legs = S.b("prop_wood_legs", Mt["dark"], bevel=0.004)
    d = 0.86
    f.box(frame, (0, 0, 0.1), (w, d, 0.3), shade(c, 0.9))
    f.box(frame, (0, -d / 2 + 0.1, 0.1), (w, 0.2, 0.78), shade(c, 0.85))
    for sx in (-1, 1):
        f.box(frame, (sx * (w / 2 - 0.1), 0, 0.1), (0.2, d, 0.58), shade(c, 0.92))
    n = max(1, round((w - 0.4) / 0.82))
    sw = (w - 0.4) / n
    for i in range(n):
        lx = -w / 2 + 0.2 + sw * (i + 0.5)
        f.cushion(soft, (lx, 0.06, 0.38), (sw - 0.02, d - 0.26, 0.18), jitter(c, 0.04, rnd), rnd=rnd)
        f.cushion(soft, (lx, -d / 2 + 0.26, 0.5), (sw - 0.04, 0.2, 0.42), jitter(shade(c, 1.04), 0.04, rnd), rnd=rnd, puff=0.5)
    for k, pc in enumerate(pillows):
        lx = -w / 2 + 0.38 + k * (w - 0.76)
        f.cushion(soft, (lx, -d / 2 + 0.42, 0.56), (0.4, 0.14, 0.36), hexc(pc), rnd=rnd, puff=0.6)
    for sx in (-1, 1):
        for sy in (-1, 1):
            f.cyl(legs, (sx * (w / 2 - 0.08), sy * (d / 2 - 0.08), 0), 0.025, 0.1, hexc("4a3428"), seg=10, r_top=0.018)
    throw = S.b("prop_throw", Mt["plaid"], tile=0.32, bevel=0.01)
    f.box(throw, (w / 2 - 0.1, 0.02, 0.68), (0.24, d * 0.7, 0.02), (1, 1, 1, 1))
    f.box(throw, (w / 2 + 0.01, 0.02, 0.2), (0.02, d * 0.7, 0.48), (1, 1, 1, 1))


def table(S, Mt, x, y, rz=0.0, w=1.6, d=0.9, h=0.74, wood="oak", round_legs=True):
    f = Frame(x, y, rz)
    top = S.b("prop_table_top-col", Mt[wood], tile=0.64, bevel=0.012)
    legs = S.b("prop_table_legs", Mt[wood], tile=0.32, bevel=0.006)
    f.box(top, (0, 0, h - 0.04), (w, d, 0.04), (1, 1, 1, 1))
    f.box(top, (0, 0, h - 0.11), (w - 0.12, d - 0.12, 0.07), shade((1, 1, 1, 1), 0.85))
    for sx in (-1, 1):
        for sy in (-1, 1):
            if round_legs:
                f.cyl(legs, (sx * (w / 2 - 0.08), sy * (d / 2 - 0.08), 0), 0.03, h - 0.08, (1, 1, 1, 1), seg=12, r_top=0.022)
            else:
                f.box(legs, (sx * (w / 2 - 0.08), sy * (d / 2 - 0.08), 0), (0.05, 0.05, h - 0.08), (1, 1, 1, 1))
    return h


def chair(S, Mt, x, y, rz=0.0, wood="oak", pad="d9877a"):
    """Стул: сиденье с подушкой, спинка из реек, точёные ножки. Спинка — по −y рамки (сидящий смотрит в +y)."""
    f = Frame(x, y, rz)
    b = S.b("prop_chairs-col", Mt[wood], tile=0.32, bevel=0.008)
    f.box(b, (0, 0, 0.42), (0.42, 0.42, 0.04), (1, 1, 1, 1))
    for sx in (-1, 1):
        for sy in (-1, 1):
            f.cyl(b, (sx * 0.17, sy * 0.17, 0), 0.018, 0.42, (1, 1, 1, 1), seg=10, r_top=0.014)
        f.box(b, (sx * 0.17, -0.19, 0.42), (0.035, 0.035, 0.48), (1, 1, 1, 1))
    for k in range(3):
        f.box(b, (0, -0.19, 0.58 + k * 0.12), (0.34, 0.02, 0.05), (1, 1, 1, 1))
    soft = S.b("prop_chair_pads", Mt["cushion"], smooth=True)
    f.cushion(soft, (0, 0.01, 0.46), (0.38, 0.36, 0.05), hexc(pad), rnd=S.rnd)


def bookcase(S, Mt, x, y, rz=0.0, w=0.9, h=1.85, d=0.3, shelves=5, seed=40):
    f = Frame(x, y, rz)
    b = S.b("prop_bookcase-col", Mt["oak"], tile=0.32, bevel=0.006)
    for sx in (-1, 1):
        f.box(b, (sx * (w / 2 - 0.01), 0, 0), (0.02, d, h), (1, 1, 1, 1))
    f.box(b, (0, -d / 2 + 0.01, 0), (w, 0.01, h), shade((1, 1, 1, 1), 0.7))
    for k in range(shelves + 1):
        f.box(b, (0, 0, 0.06 + k * (h - 0.1) / shelves), (w - 0.02, d, 0.02), (1, 1, 1, 1))
    books(S, Mt, f, w, d, h, shelves, seed)


BOOK_COLS = ["7a2a24", "2a4a5a", "c8a050", "3a5a3a", "d8d0c0", "5a3a5a", "2a2a30", "9a5a2a", "4a6a8a", "c86a6a", "6a8aa8"]


def books(S, Mt, f, w, d, h, shelves, seed):
    import random
    r = random.Random(seed)
    bk = S.b("prop_books", Mt["fabric"], bevel=0.002)
    for k in range(shelves):
        z = 0.08 + k * (h - 0.1) / shelves
        x = -w / 2 + 0.03
        fill = r.uniform(0.55, 0.95)
        while x < -w / 2 + (w - 0.04) * fill:
            bw, bh = r.uniform(0.02, 0.05), r.uniform(0.18, 0.28)
            col = jitter(hexc(r.choice(BOOK_COLS)), 0.08, r)
            f.box(bk, (x + bw / 2, 0.01, z), (bw, d * 0.72, bh), col)
            f.box(bk, (x + bw / 2, d * 0.37, z + bh * 0.25), (bw * 0.9, 0.003, 0.02), (0.92, 0.86, 0.6, 1))
            x += bw + 0.002
        if r.random() < 0.6:   # стопка лёжа
            for j in range(r.randint(2, 4)):
                f.box(bk, (x + 0.1, 0.01, z + j * 0.035), (0.16, d * 0.6, 0.033), jitter(hexc(r.choice(BOOK_COLS)), 0.08, r))


def bed(S, Mt, x, y, rz=0.0, L=2.0, W=1.2, duvet="stripes"):
    """Кровать: изголовье к −y рамки, матрас, одеяло со складкой, подушки."""
    f = Frame(x, y, rz)
    fr = S.b("prop_bed_frame-col", Mt["oak"], tile=0.4, bevel=0.012)
    f.box(fr, (0, 0, 0.12), (W + 0.06, L, 0.2), (1, 1, 1, 1))
    f.box(fr, (0, -L / 2 + 0.03, 0.12), (W + 0.1, 0.06, 0.82), (1, 1, 1, 1))
    for sx in (-1, 1):
        for sy in (-1, 1):
            f.box(fr, (sx * (W / 2), sy * (L / 2 - 0.04), 0), (0.06, 0.06, 0.14), shade((1, 1, 1, 1), 0.8))
    soft = S.b("prop_bed_soft", Mt["linen"], smooth=True, tile=0.32)
    f.cushion(soft, (0, 0, 0.32), (W - 0.02, L - 0.06, 0.2), (1, 1, 1, 1), rnd=S.rnd, puff=0.15)
    du = S.b("prop_duvet", Mt[duvet], tile=0.64, bevel=0.03)
    f.box(du, (0, L * 0.12, 0.5), (W + 0.04, L * 0.7, 0.08), (1, 1, 1, 1))
    f.box(du, (0, -L * 0.22, 0.5), (W + 0.02, 0.14, 0.12), shade((1, 1, 1, 1), 0.95))   # отвёрнутый край
    for sx in (-1, 1):
        f.cushion(soft, (sx * W * 0.24, -L / 2 + 0.28, 0.5), (W * 0.42, 0.34, 0.13), (1, 1, 1, 1), rnd=S.rnd, puff=0.6)


def desk(S, Mt, x, y, rz=0.0, w=1.2, d=0.6, h=0.75, wood="oak_pale"):
    f = Frame(x, y, rz)
    b = S.b("prop_desk-col", Mt[wood], tile=0.4, bevel=0.008)
    f.box(b, (0, 0, h - 0.035), (w, d, 0.035), (1, 1, 1, 1))
    f.box(b, (w / 2 - 0.22, 0, 0), (0.42, d - 0.04, h - 0.035), shade((1, 1, 1, 1), 0.92))
    f.box(b, (-w / 2 + 0.03, 0, 0), (0.04, d - 0.04, h - 0.035), shade((1, 1, 1, 1), 0.92))
    hd = S.b("prop_handles", Mt["metal"], bevel=0.002)
    for k in range(3):
        f.box(b, (w / 2 - 0.22, d / 2 - 0.02, 0.06 + k * 0.22), (0.38, 0.01, 0.2), shade((1, 1, 1, 1), 1.04))
        f.box(hd, (w / 2 - 0.22, d / 2 + 0.0, 0.15 + k * 0.22), (0.12, 0.015, 0.015), hexc("8a8a88"))
    return h


def kitchen(S, Mt, f, L=2.8, depth=0.6, uppers=True, color="eef0ea"):
    """Кухня вдоль стены (рамка wall f, центр по длине): шкафы с дверцами и ручками, столешница, мойка,
    плита с конфорками и кастрюлей, верхние шкафы, вытяжка, банки."""
    c = hexc(color)
    b = S.b("prop_kitchen-col", Mt["fabric"], bevel=0.006)
    top = S.b("prop_counter", Mt["oak_pale"], tile=0.64, bevel=0.006)
    hd = S.b("prop_handles", Mt["metal"], bevel=0.002)
    met = S.b("prop_sink", Mt["metal"], bevel=0.004)
    y = depth / 2
    f.box(b, (0, y, 0.0), (L, depth, 0.08), hexc("3a3436"))
    f.box(b, (0, y - 0.02, 0.08), (L, depth - 0.04, 0.78), c)
    f.box(top, (0, y + 0.01, 0.86), (L + 0.02, depth + 0.02, 0.04), (1, 1, 1, 1))
    n = max(1, int(L / 0.5))
    for i in range(n):
        cx = -L / 2 + L * (i + 0.5) / n
        f.box(b, (cx, depth - 0.02, 0.12), (L / n - 0.02, 0.012, 0.7), shade(c, 1.03))
        f.box(hd, (cx + (0.11 if i % 2 else -0.11), depth - 0.005, 0.68), (0.012, 0.015, 0.12), hexc("8a8a88"))
    sx = -L * 0.2
    f.box(met, (sx, y + 0.02, 0.86), (0.6, 0.42, 0.012), hexc("c8ccd0"))
    f.box(met, (sx, y + 0.02, 0.73), (0.5, 0.34, 0.13), hexc("9aa0a6"))
    met.tube([f.p(sx, 0.08, 0.87), f.p(sx, 0.08, 1.12), f.p(sx, 0.24, 1.14)], 0.014, hexc("b8bcc0"))
    px = L * 0.25
    f.box(met, (px, y + 0.02, 0.87), (0.6, 0.52, 0.02), hexc("2a2a2e"))
    for dx in (-0.14, 0.14):
        for dy in (-0.11, 0.11):
            f.cyl(met, (px + dx, y + 0.02 + dy, 0.89), 0.08, 0.008, hexc("4a4a50"), seg=16)
    pot = S.b("prop_pots", Mt["ceramic"], smooth=True)
    pot.lathe(f.p(px - 0.14, y + 0.13, 0.9), [(0.11, 0), (0.12, 0.04), (0.12, 0.15), (0.125, 0.16)], hexc("6f8cab"))
    if uppers:
        f.box(b, (0, 0.17, 1.45), (L, 0.34, 0.72), c)
        for i in range(n):
            cx = -L / 2 + L * (i + 0.5) / n
            f.box(b, (cx, 0.345, 1.47), (L / n - 0.02, 0.012, 0.68), shade(c, 1.03))
            f.box(hd, (cx + (0.11 if i % 2 else -0.11), 0.36, 1.52), (0.012, 0.015, 0.12), hexc("8a8a88"))
        f.box(met, (px, 0.2, 1.3), (0.62, 0.4, 0.14), hexc("c8ccd0"))
    jar = S.b("prop_jars", Mt["ceramic"], smooth=True)
    for k, col in enumerate(("e8c48a", "c8d8e0", "d88a6a", "f0ece0")):
        f.cyl(jar, (-L / 2 + 0.15 + k * 0.13, 0.12, 0.88), 0.045, 0.14 + k % 2 * 0.06, hexc(col), seg=14)


def fridge(S, Mt, x, y, rz=0.0, color="f2f2ee"):
    f = Frame(x, y, rz)
    b = S.b("prop_fridge-col", Mt["fabric"], bevel=0.02)
    f.box(b, (0, 0, 0), (0.66, 0.66, 1.78), hexc(color))
    f.box(b, (0, 0.335, 1.14), (0.64, 0.01, 0.006), shade(hexc(color), 0.8))
    hd = S.b("prop_handles", Mt["metal"], bevel=0.002)
    f.box(hd, (0.26, 0.35, 0.8), (0.02, 0.03, 0.28), hexc("a8acb0"))
    f.box(hd, (0.26, 0.35, 1.3), (0.02, 0.03, 0.22), hexc("a8acb0"))
    mag = S.b("prop_papers", Mt["paper"], tile=0.32)
    for k in range(3):
        f.box(mag, (-0.12 + k * 0.1, 0.34, 1.35 + (k % 2) * 0.12), (0.08, 0.004, 0.11), (1, 1, 1, 1))


def plant(S, Mt, x, y, z=0.0, s=1.0, pot="c98a6a"):
    pb = S.b("prop_pots", Mt["ceramic"], smooth=True)
    pb.lathe((x, y, z), [(0.12 * s, 0), (0.16 * s, 0.05 * s), (0.18 * s, 0.3 * s), (0.2 * s, 0.32 * s)], hexc(pot))
    pb.cyl((x, y, z + 0.27 * s), 0.17 * s, 0.03 * s, hexc("5a4030"), seg=16, caps=True)
    lv = S.b("prop_plants", Mt["leaves"], smooth=True, tile=0.24)
    for k in range(7):
        a = k / 7 * 2 * math.pi + S.rnd.random()
        rr = 0.12 * s + S.rnd.random() * 0.1 * s
        lv.blob((x + math.cos(a) * rr, y + math.sin(a) * rr, z + (0.45 + S.rnd.random() * 0.4) * s), (0.13 + S.rnd.random() * 0.05) * s,
                (1, 1, 1, 1), seg=16, rings=12, squash=0.75, rnd=S.rnd, wobble=0.15)


def framed(S, Mt, img_mat, x, y, z, w, h, face=(0, 1), frame="3a2a20"):
    """Картина в раме на стене: face — наружу от стены. Холст — отдельный материал img_mat (рисунок)."""
    rz = math.atan2(-face[0], face[1])
    f = Frame(x, y, rz)
    fb = S.b("prop_frames", Mt["dark"], tile=0.2, bevel=0.004)
    for sx in (-1, 1):
        f.box(fb, (sx * (w / 2 + 0.015), 0.015, z - 0.03), (0.03, 0.03, h + 0.06), hexc(frame))
    for sz in (0, 1):
        f.box(fb, (0, 0.015, z - 0.03 + sz * (h + 0.03)), (w + 0.06, 0.03, 0.03), hexc(frame))
    cv = S.b("art_" + img_mat.name, img_mat)
    a, b_, c_, d_ = f.p(-w / 2, 0.012, z), f.p(w / 2, 0.012, z), f.p(w / 2, 0.012, z + h), f.p(-w / 2, 0.012, z + h)
    cv.quad([a, b_, c_, d_], (1, 1, 1, 1), uv=[(0, 0), (1, 0), (1, 1), (0, 1)])


def rug(S, Mt, x, y, w, d, kind="rugrose", rz=0.0):
    b = S.b("rug_" + kind, Mt[kind], tile=0.64, bevel=0.004)
    b.box((x, y, 0.0), (w, d, 0.012), (1, 1, 1, 1), rz=rz)


def mug(S, Mt, x, y, z, col="d8d0c0"):
    b = S.b("prop_dishes", Mt["ceramic"], smooth=True)
    b.lathe((x, y, z), [(0.035, 0), (0.04, 0.01), (0.04, 0.09), (0.042, 0.095)], hexc(col))
    b.tube([(x + 0.04, y, z + 0.07), (x + 0.065, y, z + 0.06), (x + 0.065, y, z + 0.03), (x + 0.04, y, z + 0.02)], 0.007, hexc(col))


def plate(S, Mt, x, y, z, food=None):
    b = S.b("prop_dishes", Mt["ceramic"], smooth=True)
    b.lathe((x, y, z), [(0.06, 0), (0.11, 0.012), (0.13, 0.02)], hexc("f6f4ee"))
    if food:
        b.blob((x, y, z + 0.02), 0.06, hexc(food), squash=0.4, seg=16, rings=12)


def bowl(S, Mt, x, y, z, r=0.07, col="e8e0d0", soup=None):
    b = S.b("prop_dishes", Mt["ceramic"], smooth=True)
    b.lathe((x, y, z), [(r * 0.5, 0), (r * 0.9, r * 0.45), (r, r * 0.75)], hexc(col))
    if soup:
        b.cyl((x, y, z + r * 0.5), r * 0.88, 0.004, hexc(soup), seg=18, smooth=False)


# ---------------------------------------------------------------- свет

def table_lamp(S, Mt, x, y, z, name, shade_col="ece4d4"):
    b = S.b("prop_lamp_base", Mt["ceramic"], smooth=True)
    b.lathe((x, y, z), [(0.06, 0), (0.07, 0.03), (0.04, 0.12), (0.02, 0.26)], hexc("c8c4bc"))
    g = S.b("prop_lamp_shades", Mt["lamp"], smooth=True)
    g.lathe((x, y, z + 0.24), [(0.14, 0), (0.1, 0.16)], hexc(shade_col))
    S.marker(name, (x, y, z + 0.32))


def torchiere(S, Mt, x, y, name, h=1.7):
    b = S.b("prop_lamp_base", Mt["metal"], smooth=True)
    b.cyl((x, y, 0), 0.14, 0.03, hexc("3a3638"), seg=18)
    b.cyl((x, y, 0.03), 0.014, h - 0.2, hexc("3a3638"), seg=10)
    g = S.b("prop_lamp_shades", Mt["lamp"], smooth=True)
    g.lathe((x, y, h - 0.2), [(0.05, 0), (0.18, 0.18)], hexc("f0e6d2"))
    S.marker(name, (x, y, h - 0.05))


def pendant(S, Mt, x, y, ceil_z, name, drop=0.7, shade_col="e8dcc4"):
    b = S.b("prop_cords", Mt["metal"], smooth=True)
    b.tube([(x, y, ceil_z), (x, y, ceil_z - drop + 0.15)], 0.004, hexc("2a2420"), sides=5)
    b.cyl((x, y, ceil_z - 0.03), 0.05, 0.03, hexc("e8e4dc"), seg=16)
    g = S.b("prop_lamp_shades", Mt["lamp"], smooth=True)
    g.lathe((x, y, ceil_z - drop), [(0.24, 0), (0.24, 0.02), (0.1, 0.2), (0.04, 0.22)], hexc(shade_col))
    S.marker(name, (x, y, ceil_z - drop - 0.05))


def fluorescent(S, Mt, x, y, z, name, w=1.2, d=0.3):
    b = S.b("prop_fluo_frame", Mt["metal"], bevel=0.004)
    b.box((x, y, z - 0.06), (w + 0.06, d + 0.06, 0.06), hexc("d8dcdc"))
    g = S.b("prop_fluo", Mt["lamp"])
    g.box((x, y, z - 0.07), (w, d, 0.012), hexc("f6f8ff"))
    S.marker(name, (x, y, z - 0.4))


# ---------------------------------------------------------------- окна, двери, стены
# Настенные вещи строятся в рамке wall(x, y, rz): начало — на поверхности стены, локальная +y — В КОМНАТУ
# (к зрителю), −y — наружу. Стена вдоль x с комнатой в +y: wall(x, Y, 0); комната в −y: wall(x, Y, π);
# стена вдоль y с комнатой в +x: wall(X, y, −π/2); комната в −x: wall(X, y, π/2).

def wall(x, y, rz=0.0):
    return Frame(x, y, rz)


def vquad(b, f, cx, y, z0, w, h, color, face=1, uv=True, uvs=None):
    """Вертикальный прямоугольник в рамке f (плоскость local y), смотрит в +y (face=1) или −y; UV — без зеркала."""
    if face > 0:
        pts = [(cx + w / 2, y, z0), (cx - w / 2, y, z0), (cx - w / 2, y, z0 + h), (cx + w / 2, y, z0 + h)]
    else:
        pts = [(cx - w / 2, y, z0), (cx + w / 2, y, z0), (cx + w / 2, y, z0 + h), (cx - w / 2, y, z0 + h)]
    b.quad([f.p(*q) for q in pts], color, uv=(uvs or [(0, 0), (1, 0), (1, 1), (0, 1)]) if uv else None)


def hquad(b, f, cx, cy, z, w, d, color, uvs=None):
    pts = [(cx - w / 2, cy - d / 2, z), (cx + w / 2, cy - d / 2, z), (cx + w / 2, cy + d / 2, z), (cx - w / 2, cy + d / 2, z)]
    b.quad([f.p(*q) for q in pts], color, uv=uvs or [(0, 0), (1, 0), (1, 1), (0, 1)])


def window(S, Mt, f, w, z0, z1, view="low", panes=2, old=True, blinds=False, curtains=None, shafts=True, depth=0.16,
           frame="5a3c22", key=None):
    """Окно по набору (brightWindow) в рамке f (центр окна на стене): рама, переплёт, подоконник, вид за окном
    (три состояния), блик, днём — луч и пятно света на полу, вечером — тёплое пятно, ночью — лунное."""
    h = z1 - z0
    key = key or f"{int(f.x * 10)}_{int(f.y * 10)}"
    fr = S.b("prop_window_frames", Mt["oak"] if old else Mt["metal"], tile=0.32, bevel=0.008)
    fc = hexc(frame) if old else hexc("b8c0c4")
    f.box(fr, (0, 0, z1), (w + 0.14, depth, 0.07), fc)
    f.box(fr, (0, 0.06, z0 - 0.05), (w + 0.24, depth + 0.12, 0.05), shade(fc, 1.1))
    for xx in (-w / 2 - 0.035, w / 2 + 0.035):
        f.box(fr, (xx, 0, z0), (0.07, depth, h), fc)
    for k in range(1, panes):
        f.box(fr, (-w / 2 + w * k / panes, 0, z0), (0.035, depth * 0.5, h), fc)
    if old:
        f.box(fr, (0, 0, z0 + h * 0.62), (w, depth * 0.5, 0.03), fc)
    for st in ("day", "evening", "night"):
        vm = M(f"view_{view}_{st}", f"view_{view}_{st}")
        vquad(S.b(f"view_{key}__{st}", vm), f, 0, -1.6, z0 - 0.8, w + 2.6, h + 2.0, (1, 1, 1, 1), face=1)
    for st, col in (("day", (1.0, 0.96, 0.9, 0.16)), ("evening", (1.0, 0.8, 0.6, 0.08)), ("night", (0.5, 0.6, 0.9, 0.06))):
        vquad(S.b(f"glare_{key}__{st}", Mt["glare"]), f, 0, -0.01, z0, w, h, col, face=1, uv=False)
    if blinds:
        vquad(S.b("alpha_blinds_" + key, Mt["blinds"]), f, 0, 0.05, z1 - h * 0.35, w, h * 0.35, (1, 1, 1, 1),
              uvs=[(0, 0), (w / 0.32, 0), (w / 0.32, h * 0.35 / 0.08), (0, h * 0.35 / 0.08)])
    if curtains:
        drape(S, Mt, f, -w / 2 - 0.3, -w / 2 + 0.12, z1 + 0.15, 0.1, 0.12, curtains)
        drape(S, Mt, f, w / 2 - 0.12, w / 2 + 0.3, z1 + 0.15, 0.1, 0.12, curtains)
        rod = S.b("prop_cords", Mt["metal"], smooth=True)
        rod.tube([f.p(-w / 2 - 0.4, 0.12, z1 + 0.2), f.p(w / 2 + 0.4, 0.12, z1 + 0.2)], 0.012, hexc("6a5a4a"))
    if shafts:
        fall = 2.6
        for st, col in (("day", (1.0, 0.95, 0.84, 0.3)), ("night", (0.42, 0.52, 0.85, 0.14))):
            sb = S.b(f"shaft_{key}__{st}", Mt["shaft"])
            q = [(-w / 2, 0.06, z1), (w / 2, 0.06, z1), (w / 2 + 0.4, fall, 0.02), (-w / 2 + 0.4, fall, 0.02)]
            sb.quad([f.p(*p) for p in q], col, uv=[(0, 1), (1, 1), (1, 0), (0, 0)])
        for st, col in (("day", (1.0, 0.94, 0.8, 0.32)), ("evening", (1.0, 0.72, 0.46, 0.16)), ("night", (0.45, 0.55, 0.9, 0.18))):
            hquad(S.b(f"pool_{key}__{st}", Mt["pool"]), f, 0.3, fall * 0.62, 0.012, w + 0.9, 1.9, col)


def drape(S, Mt, f, x0, x1, ztop, zbot, y, color, folds=5):
    """Штора: волнистая полоса с толщиной (не плоскость ребром — правило набора)."""
    b = S.b("prop_curtains", Mt["linen"], smooth=True, tile=0.4)
    c = hexc(color)
    n = folds * 4
    for k in range(2):
        yy = y + k * 0.02
        pts_t = [(x0 + (x1 - x0) * i / n, yy + 0.04 * math.sin(i / n * folds * 2 * math.pi), ztop) for i in range(n + 1)]
        pts_b = [(p[0], p[1], zbot) for p in pts_t]
        for i in range(n):
            q = [pts_b[i + 1], pts_b[i], pts_t[i], pts_t[i + 1]] if k == 0 else [pts_b[i], pts_b[i + 1], pts_t[i + 1], pts_t[i]]
            b.face([f.p(*p) for p in q], c if i % 4 < 2 else shade(c, 0.86), smooth=True)


def framed(S, Mt, img_mat, f, x, z, w, h, frame="3a2a20"):
    """Картина в раме на стене (рамка wall). Холст — материал img_mat (например, рисунок Кота)."""
    fb = S.b("prop_frames", Mt["dark"], tile=0.2, bevel=0.004)
    for sx in (-1, 1):
        f.box(fb, (x + sx * (w / 2 + 0.015), 0.015, z - 0.03), (0.03, 0.03, h + 0.06), hexc(frame))
    for sz in (0, 1):
        f.box(fb, (x, 0.015, z - 0.03 + sz * (h + 0.03)), (w + 0.06, 0.03, 0.03), hexc(frame))
    vquad(S.b("art_" + img_mat.name, img_mat), f, x, 0.012, z, w, h, (1, 1, 1, 1), face=1)


def notice_board(S, Mt, f, x, z, w=0.9, h=0.6):
    fb = S.b("prop_frames", Mt["dark"], tile=0.2, bevel=0.004)
    f.box(fb, (x, 0.015, z - 0.03), (w + 0.06, 0.03, h + 0.06), hexc("6a4a2a"))
    vquad(S.b("cork_board", Mt["cork"]), f, x, 0.032, z, w, h, (1, 1, 1, 1), face=1)


def door(S, Mt, f, x=0.0, w=0.9, h=2.05, color="8a6a48"):
    """Филёнчатая дверь в проёме (рамка wall): полотно, филёнки, наличники, ручка."""
    b = S.b("prop_doors", Mt["oak"], tile=0.4, bevel=0.006)
    c = hexc(color)
    f.box(b, (x, 0.0, 0), (w, 0.05, h), c)
    for zz, hh in ((0.15, 0.75), (1.05, 0.85)):
        f.box(b, (x, 0.03, zz), (w - 0.22, 0.012, hh), shade(c, 0.9))
    fr = S.b("prop_door_frames", Mt["oak"], tile=0.4, bevel=0.006)
    for sx in (-1, 1):
        f.box(fr, (x + sx * (w / 2 + 0.04), 0.02, 0), (0.08, 0.06, h + 0.06), shade(c, 1.15))
    f.box(fr, (x, 0.02, h), (w + 0.16, 0.06, 0.08), shade(c, 1.15))
    hd = S.b("prop_handles", Mt["metal"], bevel=0.002)
    f.box(hd, (x + w / 2 - 0.1, 0.06, 1.0), (0.12, 0.03, 0.02), hexc("c8b070"))


def radiator(S, Mt, f, x, z, w=1.0, h=0.55):
    b = S.b("prop_radiators", Mt["metal"], bevel=0.006)
    n = int(w / 0.08)
    for k in range(n):
        f.box(b, (x - w / 2 + 0.04 + k * w / n, 0.06, z), (0.05, 0.08, h), hexc("e8e6e0"))
    f.box(b, (x, 0.06, z + 0.02), (w, 0.03, 0.03), hexc("d8d6d0"))


def clock(S, Mt, f, x, z):
    b = S.b("prop_clock", Mt["ceramic"], smooth=True)
    f.cyl(b, (x, 0.0, z), 0.16, 0.04, hexc("2a2a2c"), seg=28, rx=-math.pi / 2)
    f.cyl(b, (x, 0.035, z), 0.14, 0.012, hexc("f0eee6"), seg=28, rx=-math.pi / 2)
    hb = S.b("prop_clock_hands", Mt["metal"])
    f.box(hb, (x, 0.05, z), (0.012, 0.006, 0.1), hexc("141414"))
    f.box(hb, (x + 0.02, 0.05, z - 0.01), (0.07, 0.006, 0.012), hexc("141414"))


# ---------------------------------------------------------------- улица японского пригорода

SIDING_TINTS = ["f2ece0", "e6dfd2", "f0e4d6", "dcdcd4", "efe2cf", "e2d6c4", "d6dcda", "ecdcd0"]
ROOF_KINDS = ["kawara", "kawara", "kawara_red", "slate"]


def _hip(b, x0, x1, y0, y1, z, h, color, overhang=0.55):
    x0 -= overhang; x1 += overhang; y0 -= overhang; y1 += overhang
    dark = shade(color, 0.8)
    w, d = x1 - x0, y1 - y0
    if w >= d:
        r0, r1 = (x0 + d / 2, (y0 + y1) / 2, z + h), (x1 - d / 2, (y0 + y1) / 2, z + h)
        b.quad([(x0, y0, z), (x1, y0, z), r1, r0], color)
        b.quad([(x1, y1, z), (x0, y1, z), r0, r1], dark)
        b.face([(x1, y0, z), (x1, y1, z), r1], dark, smooth=False)
        b.face([(x0, y1, z), (x0, y0, z), r0], color, smooth=False)
        ridge = (r0, r1)
    else:
        r0, r1 = ((x0 + x1) / 2, y0 + w / 2, z + h), ((x0 + x1) / 2, y1 - w / 2, z + h)
        b.quad([(x1, y0, z), (x1, y1, z), r1, r0], color)
        b.quad([(x0, y1, z), (x0, y0, z), r0, r1], dark)
        b.face([(x0, y0, z), (x1, y0, z), r0], color, smooth=False)
        b.face([(x1, y1, z), (x0, y1, z), r1], dark, smooth=False)
        ridge = (r0, r1)
    b.quad([(x0, y1, z - 0.02), (x1, y1, z - 0.02), (x1, y0, z - 0.02), (x0, y0, z - 0.02)], shade(color, 0.45))
    return ridge, (x0, x1, y0, y1)


def jp_house(S, Mt, x0, x1, y0, y1, front, floors=2, seed=0, col=True, shop=None, balcony=True, detail=True):
    """Японский дом 1–3 этажа: обшивка (siding) или штукатурка, цоколь, межэтажный пояс, окна с рамами и
    раздвижными створками (днём — стекло, вечером — свет), ставни-амадо, балкон с перилами и бельём,
    козырёк и дверь, табличка, почтовый ящик, кондиционер, водосточные трубы, вальмовая черепичная крыша с коньком.
    front: '+y' или '-y' — сторона улицы."""
    import random
    r = random.Random(seed)
    fh = 2.8
    h = floors * fh + 0.3
    tint = hexc(r.choice(SIDING_TINTS))
    wall_m = Mt["siding"] if r.random() < 0.65 else Mt["plaster"]
    walls = S.b(("houses_" + wall_m.name) + ("-col" if col else "_far"), wall_m, tile=0.6)
    walls.box(((x0 + x1) / 2, (y0 + y1) / 2, 0.35), (x1 - x0, y1 - y0, h - 0.35), tint, grad=0.9)
    base = S.b("house_plinth" + ("-col" if col else "_far"), Mt["concrete"], tile=0.64)
    base.box(((x0 + x1) / 2, (y0 + y1) / 2, 0), (x1 - x0 + 0.06, y1 - y0 + 0.06, 0.38), (1, 1, 1, 1))
    trim = S.b("house_trim" + ("" if col else "_far"), Mt["fabric"], bevel=0.01 if detail else 0.0)
    trim.box(((x0 + x1) / 2, (y0 + y1) / 2, fh - 0.06), (x1 - x0 + 0.1, y1 - y0 + 0.1, 0.14), shade(tint, 0.82))
    rk = r.choice(ROOF_KINDS)
    rb = S.b("roofs_" + rk + ("" if col else "_far"), Mt[rk], tile=0.5)
    (ra, rb_), _ = _hip(rb, x0, x1, y0, y1, h, min(1.9, min(x1 - x0, y1 - y0) * 0.34), (1, 1, 1, 1))
    ridge = S.b("roof_ridges" + ("" if col else "_far"), Mt["metal"], smooth=True)
    ridge.tube([ra, rb_], 0.07, hexc("4a505a") if rk != "kawara_red" else hexc("6a3a34"), sides=8)
    if not detail:
        glow = S.b("glow_windows_far", Mt["glow"])
        out = 1 if front == "+y" else -1
        plane = y1 if front == "+y" else y0
        n = max(1, int((x1 - x0) / 2.6))
        for fl in range(floors):
            for i in range(n):
                glow.box((x0 + (x1 - x0) * (i + 0.5) / n, plane + out * 0.03, 1.0 + fl * fh), (1.2, 0.05, 1.2), (1, 1, 1, 1))
        return
    out = 1 if front == "+y" else -1
    plane = y1 if front == "+y" else y0
    rz = 0.0 if out > 0 else math.pi
    n = max(1, int((x1 - x0) / 2.4))
    step = (x1 - x0) / n
    glow = S.b("glow_windows", Mt["glow"])
    fr = S.b("prop_house_frames", Mt["metal"], bevel=0.004)
    ama = S.b("prop_amado", Mt["metal_panel"], tile=0.32, bevel=0.006)
    for fl in range(floors):
        z = 0.95 + fl * fh
        for i in range(n):
            u = x0 + step * (i + 0.5)
            if fl == 0 and (i == 0 or shop):
                continue
            w, wh = min(1.55, step * 0.62), 1.15 if fl else 1.3
            fwin = Frame(u, plane, rz)
            fwin.box(glow, (0, 0.02, z), (w, 0.05, wh), jitter((1, 1, 1, 1), 0.05, r))
            for xx in (-w / 2 - 0.03, w / 2 + 0.03, 0.0):
                fwin.box(fr, (xx, 0.05, z), (0.05 if xx else 0.03, 0.06, wh), hexc("9a9894"))
            fwin.box(fr, (0, 0.05, z + wh), (w + 0.12, 0.08, 0.06), hexc("9a9894"))
            fwin.box(fr, (0, 0.08, z - 0.06), (w + 0.18, 0.14, 0.05), hexc("bab8b2"))
            if r.random() < 0.35:   # ставень-амадо в кожухе
                fwin.box(ama, (w / 2 + 0.36, 0.06, z - 0.05), (0.5, 0.12, wh + 0.12), hexc("c8c4bc"))
    # вход: дверь, козырёк, табличка, ящик
    u0 = x0 + step * 0.5
    fdoor = Frame(u0, plane, rz)
    door_b = S.b("prop_house_doors", Mt["oak"], tile=0.4, bevel=0.006)
    fdoor.box(door_b, (0, 0.02, 0.38), (1.0, 0.06, 2.0), hexc(r.choice(("7a5a42", "5a4a42", "8a6a4a"))))
    fdoor.box(door_b, (0, 0.06, 1.2), (0.12, 0.02, 0.5), hexc("c8d8e0"))
    can = S.b("prop_canopies", Mt["slate"], tile=0.5, bevel=0.01)
    fdoor.box(can, (0, 0.45, 2.55), (1.7, 0.95, 0.07), (1, 1, 1, 1))
    small = S.b("prop_house_bits", Mt["metal"], bevel=0.004)
    fdoor.box(small, (0.75, 0.04, 1.5), (0.22, 0.03, 0.1), hexc("e8e0c8"))          # табличка
    fdoor.box(small, (0.75, 0.08, 1.05), (0.26, 0.12, 0.3), hexc(r.choice(("b8484a", "3a5a6a", "e8e4dc"))))  # ящик
    fdoor.box(small, (-0.8, 0.04, 1.75), (0.08, 0.03, 0.16), hexc("eae0b0"))      # лампа у двери
    S.marker("lamp_door_%d_%d" % (int(u0 * 10), int(plane * 10)), fdoor.p(-0.8, 0.3, 1.8))
    # кондиционер, водостоки
    fac = Frame(x1 - 0.7, plane, rz)
    fac.box(small, (0, 0.18, 0.45), (0.8, 0.3, 0.6), hexc("e8e6e0"))
    fac.box(small, (0, 0.34, 0.5), (0.5, 0.02, 0.4), hexc("b8b6b0"))
    pipe = S.b("prop_pipes", Mt["metal"], smooth=True)
    for xx in (x0 + 0.08, x1 - 0.08):
        pipe.tube([(xx, plane + out * 0.08, 0.2), (xx, plane + out * 0.08, h + 0.1)], 0.04, hexc("8a8a84"), sides=8)
    pipe.tube([(x0 - 0.5, plane + out * 0.62, h - 0.02), (x1 + 0.5, plane + out * 0.62, h - 0.02)], 0.06, hexc("8a8a84"), sides=8)
    if balcony and floors > 1 and not shop:
        bx = (x0 + x1) / 2 + step * 0.35
        bw = min(x1 - x0 - 1.2, 4.0)
        fb = Frame(bx, plane, rz)
        rail = S.b("prop_balconies", Mt["metal"], bevel=0.004)
        fb.box(rail, (0, 0.45, fh), (bw, 0.9, 0.12), hexc("b0aea8"))
        for k in range(int(bw / 0.11) + 1):
            fb.box(rail, (-bw / 2 + k * 0.11, 0.88, fh + 0.12), (0.025, 0.025, 0.95), hexc("7a7876"))
        fb.box(rail, (0, 0.88, fh + 1.05), (bw, 0.06, 0.05), hexc("7a7876"))
        if r.random() < 0.7:   # бельё на шесте
            pole = S.b("prop_laundry", Mt["metal"], smooth=True)
            pole.tube([fb.p(-bw / 2 + 0.2, 0.5, fh + 1.9), fb.p(bw / 2 - 0.2, 0.5, fh + 1.9)], 0.02, hexc("a8b0b8"))
            cl = S.b("prop_clothes", Mt["linen"], tile=0.4, bevel=0.003)
            for k in range(r.randint(3, 6)):
                xx = -bw / 2 + 0.5 + k * 0.5
                fb.box(cl, (xx, 0.5, fh + 1.25), (0.4, 0.02, 0.6), hexc(r.choice(("f6f2ea", "a8c4e0", "f3b2b9", "c4dcae", "e8d8a0"))))
    if shop:
        fs = Frame((x0 + x1) / 2 + step * 0.3, plane, rz)
        sw = (x1 - x0) * 0.62
        fs.box(glow, (0, 0.03, 0.4), (sw, 0.05, 2.0), (1, 1, 1, 1))
        for k in range(5):
            fs.box(fr, (-sw / 2 + k * sw / 4, 0.06, 0.4), (0.05, 0.06, 2.0), hexc("6a6a68"))
        signb = S.b("prop_shop_signs", Mt["fabric"], bevel=0.01)
        fs.box(signb, (0, 0.08, 2.5), (sw + 0.4, 0.14, 0.5), hexc(shop.get("sign", "f4ead8")))
        aw = S.b("prop_awnings", Mt["fabric"], bevel=0.005)
        stripes = shop.get("awning", ["5f7f6e", "efe6d6"])
        kk = 10
        for j in range(kk):
            xx = -sw / 2 - 0.2 + (sw + 0.4) * (j + 0.5) / kk
            fs.box(aw, (xx, 0.65, 2.75), ((sw + 0.4) / kk, 1.2, 0.04), hexc(stripes[j % 2]), rx=-0.35)


def block_wall(S, Mt, x0, x1, y, h=1.3, gaps=(), gate=True):
    """Бетонный блочный забор с шапкой; в проёмах — калитка из металлических прутьев."""
    w = S.b("block_walls-col", Mt["block"], tile=0.8)
    cap = S.b("wall_caps", Mt["concrete"], tile=0.64, bevel=0.01)
    segs = [(x0, x1)]
    for g0, g1 in gaps:
        nxt = []
        for a, b in segs:
            if g1 <= a or g0 >= b:
                nxt.append((a, b))
            else:
                if g0 > a:
                    nxt.append((a, g0))
                if g1 < b:
                    nxt.append((g1, b))
        segs = nxt
    for a, b in segs:
        if b - a < 0.05:
            continue
        w.box(((a + b) / 2, y, 0), (b - a, 0.16, h), (1, 1, 1, 1), grad=0.82)
        cap.box(((a + b) / 2, y, h), (b - a + 0.02, 0.22, 0.07), (1, 1, 1, 1))
    if gate:
        g = S.b("prop_gates", Mt["metal"], bevel=0.003)
        for g0, g1 in gaps:
            for k in range(int((g1 - g0) / 0.1) + 1):
                g.box((g0 + 0.05 + k * 0.1, y, 0.05), (0.02, 0.02, 1.05), hexc("4a4a48"))
            for zz in (0.12, 1.05):
                g.box(((g0 + g1) / 2, y, zz), (g1 - g0, 0.03, 0.04), hexc("4a4a48"))


def hedge(S, Mt, x0, x1, y, h=1.2, w=0.8, along_x=True):
    r = S.rnd
    b = S.b("prop_hedges", Mt["hedge"], smooth=True, tile=0.48)
    n = max(1, int(abs(x1 - x0) / 0.55))
    for i in range(n):
        t = (i + 0.5) / n
        x = x0 + (x1 - x0) * t
        c = (x, y + r.uniform(-0.08, 0.08), h * 0.52) if along_x else (y + r.uniform(-0.08, 0.08), x, h * 0.52)
        b.blob(c, w * 0.55, jitter((1, 1, 1, 1), 0.08, r), seg=16, rings=12, squash=h / w * 0.95, rnd=r, wobble=0.1)


def tree(S, Mt, x, y, z=0.0, h=None, kind="round"):
    r = S.rnd
    h = h or r.uniform(3.6, 5.2)
    trunk = S.b("prop_tree_trunks", Mt["bark"], smooth=True, tile=0.32)
    trunk.cyl((x, y, z), 0.15, h * 0.55, (1, 1, 1, 1), seg=12, r_top=0.1)
    for k in range(3):   # ветви
        a = k * 2.1 + r.random()
        trunk.tube([(x, y, z + h * 0.45), (x + math.cos(a) * 0.55, y + math.sin(a) * 0.55, z + h * 0.62)], 0.05, (1, 1, 1, 1), sides=6)
    lv = S.b("prop_trees", Mt["leaves"], smooth=True, tile=0.48)
    if kind == "pine":
        for i, (rr, zz) in enumerate([(1.4, 0.22), (1.1, 0.45), (0.75, 0.68)]):
            lv.cyl((x, y, z + h * zz), rr, h * 0.32, shade((0.8, 0.92, 0.86, 1), 1 - i * 0.05), seg=14, r_top=0.06, caps=False)
        sn = S.b("prop_snowcaps", Mt["snow"], smooth=True)
        sn.cyl((x, y, z + h * 0.88), 0.32, h * 0.14, (1, 1, 1, 1), seg=12, r_top=0.03, caps=False)
        return
    for k in range(5):
        a = 2 * math.pi * k / 5 + r.random()
        lv.blob((x + math.cos(a) * 0.6, y + math.sin(a) * 0.6, z + h * 0.68 + r.uniform(-0.2, 0.35)), r.uniform(0.75, 1.05),
                jitter((1, 1, 1, 1), 0.08, r), seg=16, rings=12, rnd=r, wobble=0.1)
    lv.blob((x, y, z + h * 0.95), 0.95, jitter((1.05, 1.05, 1.05, 1), 0.05, r), seg=16, rings=12, rnd=r, wobble=0.1)


def utility_pole(S, Mt, x, y, h=9.0, transformer=False):
    p = S.b("prop_poles-col", Mt["concrete"], smooth=True, tile=0.64)
    p.cyl((x, y, 0), 0.17, h, (1, 1, 1, 1), seg=16, r_top=0.12)
    arm = S.b("prop_pole_arms", Mt["metal"], bevel=0.004)
    for z in (h - 0.4, h - 1.3):
        arm.box((x, y, z), (0.09, 1.7, 0.09), hexc("6a6a68"))
        for dy in (-0.7, 0.0, 0.7):
            arm.cyl((x, y + dy, z + 0.09), 0.035, 0.1, hexc("e8e8e0"), seg=10)
    plate = S.b("prop_pole_plates", Mt["fabric"], bevel=0.003)
    plate.box((x + 0.18, y, 2.2), (0.02, 0.18, 0.5), hexc("f0ece0"))
    plate.box((x + 0.19, y, 2.35), (0.01, 0.12, 0.2), hexc("3a6a9a"))
    for k in range(6):   # жёлто-чёрная защита внизу
        plate.box((x, y, 0.3 + k * 0.25), (0.37, 0.37, 0.12), hexc("f2c230") if k % 2 else hexc("1f1d1f"))
    if transformer:
        t = S.b("prop_transformers", Mt["metal"], smooth=True)
        t.cyl((x + 0.38, y, h - 3.3), 0.28, 1.0, hexc("9fa3a6"), seg=16)
        t.cyl((x + 0.38, y, h - 2.3), 0.3, 0.06, hexc("8a8e90"), seg=16)
    return (x, y, h)


def wires(S, Mt, poles, sag=0.6):
    w = S.b("prop_wires", Mt["metal"], smooth=True)
    for (xa, ya, ha), (xb, yb, hb) in zip(poles, poles[1:]):
        for z_off, dy in ((0.31, -0.7), (0.31, 0.0), (0.31, 0.7), (1.21, -0.7), (1.21, 0.7)):
            pts = []
            for k in range(13):
                t = k / 12
                pts.append((xa + (xb - xa) * t, ya + dy + (yb - ya) * t, ha - z_off + (hb - ha) * t - sag * 4 * t * (1 - t)))
            w.tube(pts, 0.012, hexc("2e2c30"), sides=4)


def railway_crossing(S, Mt, x, y0, y1, track_len=50):
    g = S.b("track_bed", Mt["gravel"], tile=0.64)
    g.box((x, 0, -0.03), (3.4, track_len, 0.09), (1, 1, 1, 1))
    rails = S.b("prop_rails_track", Mt["metal"], bevel=0.004)
    for dx in (-0.72, 0.72):
        rails.box((x + dx, 0, 0.06), (0.07, track_len, 0.1), hexc("6a6664"))
        rails.box((x + dx, 0, 0.15), (0.05, track_len, 0.015), hexc("c8ccd0"))
    sl = S.b("sleepers", Mt["concrete"], tile=0.32, bevel=0.01)
    for k in range(int(track_len / 0.6)):
        sl.box((x, -track_len / 2 + k * 0.6, 0.0), (2.2, 0.22, 0.08), (1, 1, 1, 1))
    pad = S.b("crossing_pad-col", Mt["asphalt"], tile=1.28)
    pad.box((x, (y0 + y1) / 2, 0.0), (3.4, y1 - y0, 0.12), (1, 1, 1, 1))
    for yy, side in ((y0 - 0.5, -1), (y1 + 0.5, 1)):
        sx = x - 2.0 * side
        post = S.b("prop_crossing", Mt["metal"], smooth=True)
        for k in range(12):
            post.cyl((sx, yy, k * 0.3), 0.08, 0.3, hexc("1f1d1f") if k % 2 else hexc("f2c230"), seg=12, caps=False)
        cz = 3.5
        for a in (0.62, -0.62):
            for k in range(6):
                t = -0.75 + (k + 0.5) * 0.25
                post.box((sx - 0.12 * side, yy + t * math.cos(a), cz + t * math.sin(a) - 0.07), (0.06, 0.25, 0.14),
                         hexc("f2c230") if k % 2 else hexc("1f1d1f"), rx=a)
        lamps = S.b("prop_signal_lamps", Mt["metal"], smooth=True)
        for dy in (-0.32, 0.32):
            lamps.cyl((sx - 0.15 * side, yy + dy, 2.45), 0.2, 0.08, hexc("2a282a"), seg=16, ry=math.pi / 2)
        glow = S.b("prop_signal_glow", Mt["signal"], smooth=True)
        for dy in (-0.32, 0.32):
            glow.blob((sx - 0.25 * side, yy + dy, 2.5), 0.12, hexc("d0443a"), seg=16, rings=12)
        arm = S.b("prop_crossing_box", Mt["metal"], bevel=0.01)
        arm.box((sx + 0.25 * side, yy, 0), (0.4, 0.4, 1.0), hexc("2a282a"))
        for k in range(8):
            arm.box((sx + 0.25 * side, yy, 1.0 + k * 0.4), (0.07, 0.07, 0.4), hexc("f2c230") if k % 2 else hexc("1f1d1f"))


def bollard(S, Mt, x, y):
    b = S.b("prop_bollards-col", Mt["metal"], smooth=True)
    for k in range(4):
        b.cyl((x, y, k * 0.22), 0.06, 0.22, hexc("e0703a") if k % 2 == 0 else hexc("2a2628"), seg=12, caps=k == 3)


def vending_machine(S, Mt, x, y, rz=0.0):
    f = Frame(x, y, rz)
    b = S.b("prop_vending-col", Mt["fabric"], bevel=0.02)
    f.box(b, (0, 0, 0), (1.0, 0.75, 1.85), hexc("e9ecef"))
    g = S.b("prop_vending_glow", Mt["lamp"])
    f.box(g, (0, 0.38, 0.95), (0.8, 0.02, 0.75), hexc("f6f8ff"))
    cans = S.b("prop_cans", Mt["fabric"], bevel=0.003)
    r = S.rnd
    for row in range(3):
        for k in range(6):
            f.box(cans, ((k - 2.5) * 0.12, 0.4, 1.02 + row * 0.22), (0.07, 0.03, 0.14),
                  hexc(r.choice(["d8463e", "3a74b8", "f0b840", "4d9a5a", "f4f2ee"])))
    f.box(b, (0, 0.38, 0.25), (0.6, 0.06, 0.25), hexc("2a2c30"))
    S.marker("lamp_vending_%d" % int(x * 10), f.p(0, 0.9, 1.2))


def covered_bike(S, Mt, x, y, rz=0.0):
    b = S.b("prop_bikes", Mt["linen"], smooth=True, tile=0.4)
    for dx, rr, z in ((-0.45, 0.42, 0.45), (0.0, 0.5, 0.55), (0.45, 0.42, 0.5)):
        b.blob((x + dx * math.cos(rz), y + dx * math.sin(rz), z), rr, hexc("8c8f96"), seg=16, rings=12, squash=1.05, rnd=S.rnd, wobble=0.12)


def corner_mirror(S, Mt, x, y, face_a=0.0):
    b = S.b("prop_mirror", Mt["metal"], smooth=True)
    b.cyl((x, y, 0), 0.05, 2.6, hexc("e0703a"), seg=10)
    m = S.b("prop_mirror_glass", Mt["glow"], smooth=True)
    m.blob((x + 0.2 * math.cos(face_a), y + 0.2 * math.sin(face_a), 2.75), 0.3, (1, 1, 1, 1), seg=16, rings=12, squash=1.0, sx=0.4)
    b.cyl((x + 0.12 * math.cos(face_a), y + 0.12 * math.sin(face_a), 2.38), 0.33, 0.05, hexc("e0703a"), seg=20)


def street_sign(S, Mt, x, y, h=2.4, color="d84a3e", face=(0, -1)):
    b = S.b("prop_signs", Mt["metal"], smooth=True)
    b.cyl((x, y, 0), 0.04, h, hexc("9a9a98"), seg=8)
    rz = math.atan2(-face[0], face[1])
    disc = S.b("prop_sign_faces", Mt["fabric"], smooth=False)
    disc.cyl((x + face[0] * 0.05, y + face[1] * 0.05, h + 0.3), 0.3, 0.02, hexc(color), seg=24, rx=math.pi / 2, rz=rz)
    disc.cyl((x + face[0] * 0.07, y + face[1] * 0.07, h + 0.3), 0.22, 0.01, hexc("f4f2ee"), seg=24, rx=math.pi / 2, rz=rz)


def street_lamp(S, Mt, x, y, h=4.0, arm=(0, -0.6)):
    p = S.b("prop_street_lamps", Mt["metal"], smooth=True)
    p.cyl((x, y, 0), 0.06, h, hexc("6e6a70"), seg=10)
    head = (x + arm[0], y + arm[1], h)
    p.tube([(x, y, h - 0.1), head], 0.035, hexc("6e6a70"))
    p.cyl((head[0], head[1], head[2] - 0.1), 0.18, 0.1, hexc("5a565a"), seg=16, r_top=0.08)
    g = S.b("prop_street_lamp_glow", Mt["lamp"], smooth=True)
    g.blob((head[0], head[1], head[2] - 0.14), 0.12, hexc("fff0c8"), seg=16, rings=12, squash=0.5)
    S.marker("lamp_street_%d_%d" % (int(x * 10), int(y * 10)), (head[0], head[1], head[2] - 0.5))


def bench(S, Mt, x, y, rz=0.0, color="9c7a62"):
    f = Frame(x, y, rz)
    b = S.b("prop_benches-col", Mt["oak"], tile=0.32, bevel=0.008)
    for k in range(3):
        f.box(b, (0, -0.15 + k * 0.15, 0.42), (1.6, 0.12, 0.04), hexc(color))
    for k in range(2):
        f.box(b, (0, -0.24, 0.55 + k * 0.16), (1.6, 0.04, 0.11), hexc(color), rx=-0.15)
    leg = S.b("prop_bench_legs", Mt["metal"], bevel=0.004)
    for dx in (-0.68, 0.68):
        f.box(leg, (dx, 0, 0), (0.06, 0.46, 0.42), hexc("4a4a48"))
        f.box(leg, (dx, -0.23, 0.42), (0.06, 0.05, 0.42), hexc("4a4a48"))


def manhole(S, Mt, x, y):
    b = S.b("prop_manholes", Mt["metal"], smooth=False)
    b.cyl((x, y, 0.0), 0.32, 0.012, hexc("5a5652"), seg=24)
    for k in range(4):
        b.box((x, y, 0.012), (0.5 - k * 0.1, 0.02, 0.004), hexc("4a4642"), rz=k * 0.8)


def planter(S, Mt, x, y, s=1.0):
    pb = S.b("prop_pots", Mt["ceramic"], smooth=True)
    pb.lathe((x, y, 0), [(0.14 * s, 0), (0.18 * s, 0.05 * s), (0.2 * s, 0.32 * s), (0.22 * s, 0.34 * s)], hexc(S.rnd.choice(("c98a6a", "8a9aa8", "e8e0d0", "6a7a5a"))))
    lv = S.b("prop_plants", Mt["leaves"], smooth=True, tile=0.24)
    for k in range(5):
        a = k / 5 * 2 * math.pi + S.rnd.random()
        lv.blob((x + math.cos(a) * 0.1 * s, y + math.sin(a) * 0.1 * s, (0.45 + S.rnd.random() * 0.25) * s), 0.14 * s, (1, 1, 1, 1),
                seg=16, rings=12, squash=0.8, rnd=S.rnd, wobble=0.15)
