"""Локации пролога (docs/STORY.md) — собираются скриптом в Blender, экспорт в art/locations/<id>.glb.

Запуск: /home/user/tools/bpyenv/bin/python tools/art/build_locations.py [city_street family_home ...]
Точки (spawn, npc_*, int_*, reach_*) — те, что ищет data/story/prologue.json (проверяет tests/test_story.gd).
Соглашения по именам — tools/art/loc_kit.py. Улица Кота: Blender X — вдоль улицы, Z — вверх.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import loc_kit as K  # noqa: E402
from loc_kit import hexc  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "art", "locations")


def water(S, x0, x1, y0, y1, z):
    """Уровень воды (одна плоскость с сеткой — волны в шейдере)."""
    w = S.b("water", "water")
    n = 24
    for i in range(n):
        for j in range(n):
            xa, xb = x0 + (x1 - x0) * i / n, x0 + (x1 - x0) * (i + 1) / n
            ya, yb = y0 + (y1 - y0) * j / n, y0 + (y1 - y0) * (j + 1) / n
            w.quad([(xa, ya, 0), (xb, ya, 0), (xb, yb, 0), (xa, yb, 0)], hexc("6fb1c0"))
    return z


def finish_water(S, z):
    o = S.batches["water"].finish()
    o.location.z = z
    del S.batches["water"]


# ---------------------------------------------------------------- 1, 8: улица Shizunda Taver City

def city_street():
    """Тихий приморский пригород (реф. пользователя 23.10 — японская улочка у переезда): узкая улица вдоль X,
    бетонные заборы и живые изгороди, двухэтажные дома с вальмовыми крышами, столбы с проводами, переезд,
    лавка с цветами и автоматом, сквер с фонтаном; на востоке — канал с горбатым мостом, набережная и море;
    за домами — зелёные холмы, вдали гора (на ней — будущий жилой комплекс тома I)."""
    K.reset()
    K._POLES.clear()
    S = K.Scene(seed=11)
    rnd = S.rnd
    LW = 2.6                         # полуширина улицы
    canal = (18.0, 24.0)
    g = S.b("ground-col", "ground")
    for xa, xb in ((-60, canal[0]), (canal[1], 33)):
        g.box(((xa + xb) / 2, 0, -2.0), (xb - xa, 60, 2.0), hexc("a8a294"))        # земля участков
    road = S.b("road-col", "ground")
    for xa, xb in ((-46, canal[0] - 1.8), (canal[1] + 1.8, 32.6)):
        road.box(((xa + xb) / 2, 0, -0.05), (xb - xa, 2 * LW, 0.06), hexc("8f8b94"))
        for sy in (-1, 1):
            road.box(((xa + xb) / 2, sy * (LW - 0.15), -0.05), (xb - xa, 0.3, 0.065), hexc("bdb8ae"))  # водосток
    marks = S.b("road_marks", "ground")
    for xa, xb in ((-46, -17.5), (-12.5, canal[0] - 1.8), (canal[1] + 1.8, 32.6)):
        for sy in (-1, 1):
            marks.box(((xa + xb) / 2, sy * (LW - 0.42), 0.0), (xb - xa, 0.1, 0.012), hexc("f2f0ea"))
    # ---- северная сторона: заборы, дома, лавка
    north = [(-46, -36), (-36, -27), (-27, -18.5), (-12.5, -5.5), (-5.5, 2.5), (2.5, 10), (10, 17.2)]
    for x0, x1 in north:
        if (x0, x1) == (-12.5, -5.5):
            K.jp_house(S, x0 + 0.3, x1 - 0.3, 4.3, 10.5, "-y", shop={"awning": ["5f7f6e", "efe6d6"], "sign": "f4ead8"})
            continue
        K.block_wall(S, x0, x1, LW + 0.15, gaps=[(x0 + 1.2, x0 + 2.4)])
        K.jp_house(S, x0 + 0.6, x1 - 0.6, 4.6, 11.0, "-y")
        if rnd.random() < 0.7:
            K.tree(S, x1 - 1.4, 3.6, h=rnd.uniform(3.2, 4.5))
        K.hedge(S, x0 + 2.6, x1 - 0.4, 3.3, h=1.5)
    # ---- южная сторона; сквер с фонтаном на x 0..12
    south = [(-46, -36), (-36, -27), (-27, -18.5), (-12.5, -6), (-6, 0), (12, 17.2)]
    for x0, x1 in south:
        K.block_wall(S, x0, x1, -LW - 0.15, gaps=[(x1 - 2.4, x1 - 1.2)])
        K.jp_house(S, x0 + 0.6, x1 - 0.6, -11.0, -4.6, "+y")
        if rnd.random() < 0.6:
            K.tree(S, x0 + 1.5, -3.7, h=rnd.uniform(3.2, 4.5))
    park = S.b("park_ground", "ground")
    park.box((6, -7.6, 0.0), (12, 10, 0.03), hexc("d9cdb4"))
    K.hedge(S, 0, 3, -LW - 0.3, h=1.1)
    K.hedge(S, 9, 12, -LW - 0.3, h=1.1)
    K.hedge(S, 0, 12, -12.4, h=1.4)
    for x in (0.0, 12.0):
        hb = S.b("prop_hedges", "leaves", smooth=True)
        for k in range(12):
            hb.blob((x, -3.4 - k * 0.75, 0.6), 0.5, K.jitter(hexc("6f9a62"), 0.1, rnd), seg=8, rings=6, squash=1.3, rnd=rnd, wobble=0.12)
    S.b("park_bounds-colonly", "base").box((0, -7.5, 0), (0.6, 10, 2.0), (1, 1, 1, 1))
    S.b("park_bounds-colonly", "base").box((12, -7.5, 0), (0.6, 10, 2.0), (1, 1, 1, 1))
    S.b("park_bounds-colonly", "base").box((6, -12.4, 0), (12, 0.6, 2.0), (1, 1, 1, 1))
    f = S.b("prop_fountain-col", "stone", smooth=True)
    f.cyl((6, -7.5, 0), 1.9, 0.5, hexc("d6d0c6"), seg=24)
    f.cyl((6, -7.5, 0), 0.28, 1.4, hexc("d6d0c6"), seg=12)
    f.cyl((6, -7.5, 1.4), 0.7, 0.2, hexc("e2ddd4"), seg=16, r_top=0.9)
    S.b("water_fountain", "water").cyl((6, -7.5, 0.45), 1.75, 0.02, hexc("8cc6d0"), seg=24, smooth=False)
    for x, y in ((2.0, -10.6), (10.4, -10.4), (1.6, -4.4)):
        K.tree(S, x, y, h=rnd.uniform(4.0, 5.0))
    K.bench(S, 10.2, -6.6, rot=math.pi / 2, color="9c7a62")
    K.bench(S, 6.0, -11.3, rot=0.0, color="9c7a62")
    # ---- переезд
    K.railway_crossing(S, -15.0, -LW, LW, track_len=50)
    fence = S.b("prop_fences-col", "metal")
    for x in (-17.6, -12.4):
        for sy in (-1, 1):
            fence.box((x, sy * 13.5, 0), (0.06, 21.6, 1.3), hexc("6b6f6a"))
            for k in range(36):
                fence.box((x, sy * (2.8 + k * 0.6), 0), (0.08, 0.08, 1.3), hexc("55595a"))
    K.hedge(S, -27.0, -18.6, -LW - 0.5, h=1.2)
    K.bollard(S, -18.0, -1.6); K.bollard(S, -18.0, 1.6); K.bollard(S, -12.0, -1.6); K.bollard(S, -12.0, 1.6)
    K.round_sign(S, -19.2, -LW - 0.05, face=(1, 0))
    sign = S.b("prop_signs", "metal")
    sign.box((-19.6, LW + 0.05, 0), (0.06, 0.06, 2.2), hexc("9a9a98"))
    sign.box((-19.6, LW + 0.05, 1.2), (0.5, 0.05, 1.2), hexc("f4f2ee"))
    sign.box((-19.6, LW + 0.02, 1.35), (0.3, 0.02, 0.85), hexc("d8564a"))    # вертикальная надпись (без текста)
    # ---- лавка: прилавок с цветами, автомат, велосипеды под чехлами
    st = S.b("prop_stall-col", "wood")
    st.box((-10.6, 3.7, 0), (2.2, 0.7, 0.85), hexc("a98468"))
    fl = S.b("prop_flowers", "leaves", smooth=True)
    for i in range(12):
        fl.blob((-11.5 + i * 0.17, 3.7 + rnd.uniform(-0.2, 0.2), 0.95), 0.12,
                hexc(rnd.choice(["e88fa4", "f6c560", "b7a4ea", "fdf2ee", "f08a6a"])), seg=6, rings=4)
    K.vending_machine(S, -6.2, 3.5, rot=math.pi)
    K.covered_bike(S, 30.0, 3.4, rot=0.1)
    K.covered_bike(S, -33.0, -3.4, rot=0.0)
    K.corner_mirror(S, -26.6, 2.9, face_a=-2.3)
    cone = S.b("prop_cones", "fabric", smooth=True)
    cone.cyl((29.0, 3.3, 0), 0.16, 0.5, hexc("e8592f"), seg=10, r_top=0.03)
    # ---- столбы и провода (северная сторона)
    for x in (-42, -31, -21, -10.2, -1, 8.5, 16.6):
        K.utility_pole(S, x, LW + 0.45, h=rnd.uniform(8.5, 9.5), transformer=x in (-31, 8.5))
    K.wires(S, list(K._POLES))
    poles_e = []
    K._POLES.clear()
    for x in (25.5, 31.5):
        K.utility_pole(S, x, LW + 0.45, h=8.6)
    K.wires(S, list(K._POLES))
    # ---- канал и горбатый мост
    cw = S.b("canal-col", "stone")
    cw.box(((canal[0] + canal[1]) / 2, 0, -3.2), (canal[1] - canal[0], 120, 0.5), hexc("6f8c94"))
    for x in canal:
        cw.box((x, 0, -3.2), (0.6, 120, 3.2), hexc("bfb6aa"))
    br = S.b("bridge-col", "stone")
    rail = S.b("prop_rails-col", "metal")
    b0, b1 = canal[0] - 1.8, canal[1] + 1.8
    xs = [b0 + i * 0.4 for i in range(int((b1 - b0) / 0.4) + 1)]
    zf = lambda x: 1.6 * math.sin(math.pi * min(1, max(0, (x - b0) / (b1 - b0))))
    br.strip([(x, LW, zf(x)) for x in xs], [(x, -LW, zf(x)) for x in xs], hexc("cfc6ba"), thick=0.5)
    for sy in (-1, 1):
        for x in xs[::2]:
            rail.box((x, sy * (LW - 0.1), zf(x)), (0.1, 0.1, 1.0), hexc("8e2f2a"))
        K.tube(rail, [(x, sy * (LW - 0.1), zf(x) + 1.0) for x in xs], 0.05, hexc("a8443a"))
    for x in (canal[0] - 0.4, canal[1] + 0.4):
        for sy in (-1, 1):
            rail.box((x, sy * 8, 0), (0.12, 10.8, 1.1), hexc("7a7a78"))
    # ---- восточный край: дома, набережная, море
    for x0, x1 in ((24.6, 31.6),):
        K.block_wall(S, x0, x1, LW + 0.15, gaps=[(x0 + 0.8, x0 + 2.0)])
        K.jp_house(S, x0 + 0.5, x1 - 0.5, 4.6, 10.5, "-y")
        K.block_wall(S, x0, x1, -LW - 0.15, gaps=[(x1 - 2.0, x1 - 0.8)])
        K.jp_house(S, x0 + 0.5, x1 - 0.5, -10.5, -4.6, "+y")
    rail.box((32.7, 0, 0), (0.2, 26, 1.0), hexc("9a9894"))
    emb = S.b("embankment", "stone")
    emb.box((32.9, 0, -3.0), (0.6, 60, 3.0), hexc("bfb6aa"))
    # ---- фон: второй ряд домов, холмы, гора с комплексом
    for x in range(-60, 34, 8):
        if canal[0] - 3 < x < canal[1]:
            continue
        for sy in (-1, 1):
            K.jp_house(S, x, x + 6.5, 13 if sy > 0 else -20, 20 if sy > 0 else -13, "-y" if sy > 0 else "+y", col=False,
                       floors=rnd.choice([2, 2, 3]), balcony=False)
    hills = S.b("far_hills", "leaves", smooth=True)
    for k in range(16):
        a = math.pi * 0.15 + k / 15 * math.pi * 1.2
        hills.blob((math.cos(a) * 95 - 20, math.sin(a) * 70, -8), rnd.uniform(26, 38),
                   K.jitter(hexc("7fa27a"), 0.12, rnd), seg=14, rings=8, squash=0.55, rnd=rnd, wobble=0.06)
    K.mountains(S, 0, 0, 300, 5, (60, 110), "9fa9c6", spread=math.pi * 0.6, start=math.pi * 0.6, complex_on=2)
    # невидимые границы: улица, ниша лавки (до её фасада), вход в сквер (сам сквер огорожен отдельно)
    bw = S.b("bounds-colonly", "base")
    def wall(x0, x1, y0, y1):
        bw.box(((x0 + x1) / 2, (y0 + y1) / 2, 0), (x1 - x0, y1 - y0, 4.0), (1, 1, 1, 1))
    wall(-46.5, -45.5, -LW, LW)
    wall(32.6, 33.6, -LW, LW)
    wall(-46, -12.5, LW + 0.4, LW + 0.8)
    wall(-5.5, 33, LW + 0.4, LW + 0.8)
    wall(-12.9, -12.5, LW + 0.4, 4.4)
    wall(-5.5, -5.1, LW + 0.4, 4.4)
    wall(-46, 3.0, -LW - 0.8, -LW - 0.4)
    wall(9.0, 33, -LW - 0.8, -LW - 0.4)
    # точки сцен
    S.marker("spawn", (-40, 0, 0.02), face=(1, 0))
    S.marker("int_shop_window", (-8.0, 2.2, 0.02), face=(0, 1))
    S.marker("int_passerby_a", (-9.2, 3.2, 0.02), face=(0, -1))
    S.marker("int_passerby_b", (2.2, -1.6, 0.02), face=(1, 0))
    S.marker("int_fountain", (6.0, -5.0, 0.04), face=(0, -1))
    S.marker("int_girl", (9.2, -6.0, 0.04), face=(-1, 0))
    S.marker("int_viewpoint", (31.8, 0, 0.02), face=(1, 0))
    S.marker("spawn_flood", (-38, 0.6, 0.02), face=(1, 0))
    S.marker("npc_resident_a", (-30, 1.2, 0.02), face=(1, 0))
    S.marker("npc_resident_b", (-22, -1.0, 0.02), face=(1, 0.2))
    S.marker("reach_evac_point", (21, 0, 1.6), face=(-1, 0))
    water(S, -400, 400, -400, 400, 0)
    finish_water(S, -0.8)
    S.export(os.path.join(OUT, "city_street.glb"))


# ---------------------------------------------------------------- 2: дом семьи (кухня-гостиная)

def room_walls(S, x0, x1, y0, y1, h, color, door=None, windows=()):
    """Стены комнаты со столкновениями; door=(сторона, центр, ширина), windows=[(сторона, центр, ширина, низ, высота)]."""
    w = S.b("room_walls-col", "wall")
    c = hexc(color)
    t = 0.2
    sides = {"-y": (x0, x1, y0), "+y": (x0, x1, y1), "-x": (y0, y1, x0), "+x": (y0, y1, x1)}
    for side, (a, b, k) in sides.items():
        holes = []
        if door and door[0] == side:
            holes.append((door[1] - door[2] / 2, door[1] + door[2] / 2, 0.0, 2.1))
        for ws in windows:
            if ws[0] == side:
                holes.append((ws[1] - ws[2] / 2, ws[1] + ws[2] / 2, ws[3], ws[3] + ws[4]))
        cuts = sorted(holes)
        u = a
        for h0, h1, z0, z1 in cuts:
            _wall_piece(w, side, k, u, h0, 0, h, c, t)
            _wall_piece(w, side, k, h0, h1, 0, z0, c, t)
            _wall_piece(w, side, k, h0, h1, z1, h, c, t)
            u = h1
        _wall_piece(w, side, k, u, b, 0, h, c, t)
    sk = S.b("skirting", "wood")
    for side, (a, b, k) in sides.items():
        _wall_piece(sk, side, k + (0.11 if side in ("-y", "-x") else -0.11), a, b, 0, 0.1, hexc("b08c6c"), 0.03)


def _wall_piece(b, side, k, u0, u1, z0, z1, c, t):
    if u1 - u0 < 0.01 or z1 - z0 < 0.01:
        return
    if side in ("-y", "+y"):
        b.box(((u0 + u1) / 2, k, z0), (u1 - u0, t, z1 - z0), c, shade=0.95)
    else:
        b.box((k, (u0 + u1) / 2, z0), (t, u1 - u0, z1 - z0), c, shade=0.95)


def chair(S, x, y, rot, color="b38a66"):
    b = S.b("prop_chairs-col", "wood")
    c = hexc(color)
    co, si = math.cos(rot), math.sin(rot)
    R = lambda dx, dy: (x + dx * co - dy * si, y + dx * si + dy * co)
    b.box((*R(0, 0), 0.42), (0.42, 0.42, 0.05), c, rot=rot)
    b.box((*R(0, -0.19), 0.47), (0.42, 0.04, 0.5), c, rot=rot)
    for dx in (-0.18, 0.18):
        for dy in (-0.18, 0.18):
            b.box((*R(dx, dy), 0), (0.04, 0.04, 0.42), tuple(q * 0.85 for q in c[:3]) + (1,), rot=rot)


def family_home():
    """Кухня-гостиная семьи (сцена 2): светлый деревянный пол, стол на пятерых, кухня, большое окно,
    угол Кота с рисунками на стене. Без потолка (камера сверху-сзади)."""
    K.reset()
    S = K.Scene(seed=21)
    rnd = S.rnd
    X0, X1, Y0, Y1, H = -5.0, 5.0, -3.6, 3.6, 2.7
    fl = S.b("floor-col", "wood")
    for i in range(20):
        fl.box((X0 + (i + 0.5) * 0.5, 0, -0.1), (0.49, Y1 - Y0, 0.1), K.jitter(hexc("dcc29e"), 0.04, rnd))
    room_walls(S, X0, X1, Y0, Y1, H, "f3ece0", door=("-x", -2.2, 1.0),
               windows=[("+y", -0.6, 2.6, 0.8, 1.5), ("+x", 1.2, 1.4, 1.0, 1.1)])
    glow = S.b("glow_windows", "glow_window")
    glow.box((-0.6, Y1, 0.8), (2.6, 0.05, 1.5), hexc("c4d9ea"))
    glow.box((X1, 1.2, 1.0), (0.05, 1.4, 1.1), hexc("c4d9ea"))
    fr = S.b("prop_window_frames", "wood")
    for k in range(5):     # переплёт как у сёдзи
        fr.box((-1.9 + k * 0.65, Y1 - 0.02, 0.8), (0.04, 0.08, 1.5), hexc("a88462"))
    for z in (0.8, 1.55, 2.3):
        fr.box((-0.6, Y1 - 0.02, z), (2.7, 0.08, 0.05), hexc("a88462"))
    # стол и стулья
    t = S.b("prop_table-col", "wood")
    t.box((1.0, 0.5, 0.72), (1.8, 1.0, 0.06), hexc("c79f74"))
    for dx in (-0.8, 0.8):
        for dy in (-0.42, 0.42):
            t.box((1.0 + dx, 0.5 + dy, 0), (0.07, 0.07, 0.72), hexc("a98058"))
    chair(S, 0.5, -0.25, 0.0); chair(S, 1.5, -0.25, 0.0)
    chair(S, 0.5, 1.25, math.pi); chair(S, 1.5, 1.25, math.pi)
    chair(S, 2.15, 0.5, math.pi / 2)
    # посуда на столе
    dish = S.b("prop_dishes", "fabric", smooth=True)
    for x, y in ((0.5, 0.15), (1.5, 0.15), (0.5, 0.85), (1.5, 0.85), (1.75, 0.5)):
        dish.cyl((x, y, 0.75), 0.13, 0.025, hexc("f6f4ee"), seg=14)
        dish.cyl((x, y, 0.77), 0.07, 0.05, hexc(rnd.choice(["e8b06a", "d86a5a", "9cc08a"])), seg=10)
    dish.cyl((1.0, 0.5, 0.75), 0.18, 0.18, hexc("6f8cab"), seg=14, r_top=0.15)    # кастрюля с супом
    # кухня вдоль восточной стены (+y) справа
    k = S.b("prop_kitchen-col", "wood")
    k.box((3.6, 3.15, 0), (2.6, 0.6, 0.9), hexc("efe9dd"))
    k.box((3.6, 3.15, 0.9), (2.7, 0.66, 0.05), hexc("9a9a9e"))
    k.box((3.6, 3.3, 1.5), (2.6, 0.35, 0.7), hexc("efe9dd"))
    for i in range(4):
        k.box((2.55 + i * 0.7, 2.84, 0.1), (0.6, 0.02, 0.7), hexc("e2dccc"))
    # диван и полка
    sofa = S.b("prop_sofa-col", "fabric", smooth=False)
    sofa.box((-2.3, -2.9, 0), (2.2, 0.8, 0.42), hexc("9fb4c6"))
    sofa.box((-2.3, -3.25, 0.42), (2.2, 0.2, 0.45), hexc("8ea4b8"))
    shelf = S.b("prop_shelf-col", "wood")
    shelf.box((4.65, -1.6, 0), (0.35, 1.6, 1.8), hexc("c7a27c"))
    for z in (0.5, 1.0, 1.5):
        for i in range(6):
            shelf.box((4.55, -2.3 + i * 0.26, z), (0.18, 0.2, 0.3), hexc(rnd.choice(["d86a5a", "6f8cab", "e8c46a", "8fb58a", "c49ac0"])))
    # угол Кота: столик, листы, рисунки на стене
    desk = S.b("prop_desk-col", "wood")
    desk.box((-3.9, 2.7, 0), (1.4, 0.7, 0.55), hexc("d8b892"))
    pap = S.b("prop_papers", "fabric")
    for i in range(7):
        pap.box((-4.4 + i * 0.16, 2.6 + rnd.uniform(-0.15, 0.15), 0.55), (0.21, 0.29, 0.005), hexc("fbf8f0"), rot=rnd.uniform(-0.5, 0.5))
    for i in range(9):
        x = -4.6 + (i % 3) * 0.48
        z = 1.0 + (i // 3) * 0.45
        pap.box((x, Y1 - 0.11, z), (0.36, 0.01, 0.3), hexc(rnd.choice(["fbe6d0", "dcebf6", "f6d6e0", "e6f2d8", "fbf3cf"])))
        pap.box((x + rnd.uniform(-0.08, 0.08), Y1 - 0.12, z + 0.08), (0.14, 0.01, 0.1),
                hexc(rnd.choice(["6fb1c0", "e88f6a", "8fb58a", "c49ac0"])))
    crayons = S.b("prop_crayons", "fabric")
    for i in range(8):
        crayons.box((-3.4 + i * 0.05, 2.9, 0.56), (0.03, 0.14, 0.03), hexc(["d84a3e", "f0b840", "4d9a5a", "3a74b8", "c49ac0", "e88f6a", "6fb1c0", "333333"][i]))
    rug = S.b("rug", "fabric")
    rug.box((-2.3, -1.4, 0.0), (2.6, 1.8, 0.01), hexc("e7c9b8"))
    plant = S.b("prop_plants", "leaves", smooth=True)
    S.b("prop_pots", "stone", smooth=True).cyl((4.4, 2.0, 0), 0.22, 0.4, hexc("c98a6a"), seg=10, r_top=0.26)
    plant.blob((4.4, 2.0, 0.85), 0.42, hexc("7fae8a"), rnd=rnd, wobble=0.15)
    # вид из окна: соседние дома и деревья (без столкновений)
    for x in (-8, -1, 6):
        K.jp_house(S, x, x + 5.5, 7, 12, "-y", col=False)
    K.tree(S, -3, 5.0); K.tree(S, 3.5, 5.4)
    S.b("yard", "ground").box((0, 8, -0.15), (30, 9, 0.1), hexc("9cb48a"))
    S.marker("spawn", (-2.8, -1.2, 0.0), face=(1, 0.3))
    S.marker("npc_mama", (3.4, 2.4, 0.0), face=(-0.6, -1))
    S.marker("npc_papa", (2.15, 0.5, 0.0), face=(-1, 0))
    S.marker("npc_sora", (1.5, 1.25, 0.0), face=(0, -1))
    S.marker("npc_gabi", (1.5, -0.25, 0.0), face=(0, 1))
    S.marker("int_family_table", (0.5, -0.4, 0.0), face=(0, 1))
    S.marker("int_window", (-0.6, 3.0, 0.0), face=(0, 1))
    S.marker("int_sketch_corner", (-3.9, 2.0, 0.0), face=(0, 1))
    for i, (x, y) in enumerate(((-2.5, 0), (2.5, 0))):
        S.marker("lamp_room_%d" % i, (x, y, 2.4))
    S.export(os.path.join(OUT, "family_home.glb"))


# ---------------------------------------------------------------- 2: зимний склон

def snow_slope():
    """Склон над городом (сцена 2, лыжи): спуск к домику у подножия, ели, сугробы; внизу вдали — город и море."""
    K.reset()
    S = K.Scene(seed=31)
    rnd = S.rnd
    xs = [-34 + i * 1.0 for i in range(53)]          # −34 … 18
    zf = lambda x: max(0.0, -x * 0.28) if x < 0 else 0.0
    g = S.b("snow-col", "snow")
    W = 9.0
    rows = [-W - 6, -W, -W / 2, 0, W / 2, W, W + 6]
    for j in range(len(rows) - 1):
        ya, yb = rows[j], rows[j + 1]
        def h(x, y):
            bump = 0.25 * math.sin(x * 0.7 + y * 0.9) * math.sin(y * 0.5)
            edge = max(0.0, abs(y) - W) * 0.6
            return zf(x) + bump * (0.3 if abs(y) < W else 1.0) + edge
        g.strip([(x, yb, h(x, yb)) for x in xs], [(x, ya, h(x, ya)) for x in xs], hexc("f4f6fb"), thick=1.5,
                under=hexc("dfe4f0"))
    # следы лыжни
    tr = S.b("ski_tracks", "snow")
    for dy in (-0.25, 0.25):
        tr.strip([(x, dy + 0.03 + 0.4 * math.sin(x * 0.15), zf(x) + 0.03) for x in xs[:40]],
                 [(x, dy - 0.03 + 0.4 * math.sin(x * 0.15), zf(x) + 0.03) for x in xs[:40]], hexc("dde4f2"))
    for i in range(34):
        x = rnd.uniform(-33, 14)
        y = rnd.choice([-1, 1]) * rnd.uniform(W - 1.0, W + 5)
        K.tree(S, x, y, z=zf(x) + max(0.0, abs(y) - W) * 0.6 - 0.2, h=rnd.uniform(3.5, 6.5), kind="pine")
    drifts = S.b("prop_drifts", "snow", smooth=True)
    for i in range(18):
        x = rnd.uniform(-30, 14)
        y = rnd.choice([-1, 1]) * rnd.uniform(4, W - 0.5)
        drifts.blob((x, y, zf(x) - 0.2), rnd.uniform(0.6, 1.4), hexc("f2f5fc"), squash=0.45, rnd=rnd, wobble=0.1)
    # домик у подножия
    K.jp_house(S, 13.5, 19.5, -4.5, 2.0, "-x" if False else "+y", floors=1, color="c99a7a", roof="5d6573", balcony=False)
    snowroof = S.b("prop_snowroof", "snow", smooth=True)
    snowroof.blob((16.5, -1.25, 3.6), 3.4, hexc("f6f8ff"), squash=0.25, rnd=rnd, wobble=0.05)
    rack = S.b("prop_skis", "wood")
    for i in range(5):
        rack.box((12.6, -3.5 + i * 0.35, 0), (0.06, 0.1, 1.7), hexc(["d84a3e", "3a74b8", "f0b840", "4d9a5a", "c49ac0"][i]))
    rack.box((12.6, -2.8, 1.3), (0.1, 2.0, 0.08), hexc("8d6e58"))
    # опоры подъёмника вдоль склона
    lift = S.b("prop_lift", "metal")
    for x in (-28, -16, -4, 8):
        lift.box((x, -W + 1.5, zf(x)), (0.3, 0.3, 7.0), hexc("6e6a80"))
        lift.box((x, -W + 1.5, zf(x) + 7.0), (0.3, 2.4, 0.3), hexc("6e6a80"))
    w = S.b("prop_lift_cable", "metal")
    for dy in (-1.0, 1.0):
        K.tube(w, [(x, -W + 1.5 + dy, zf(x) + 7.1 - 0.4 * math.sin((x + 28) / 12 * math.pi) ** 2) for x in range(-28, 9)], 0.02, hexc("3a3840"))
    # город внизу вдали и море
    for i in range(40):
        x = rnd.uniform(40, 120)
        y = rnd.uniform(-60, 60)
        K.jp_house(S, x, x + rnd.uniform(5, 8), y, y + rnd.uniform(5, 8), "+y", col=False, balcony=False,
                   floors=rnd.choice([2, 2, 3]))
    S.b("far_ground", "ground").box((80, 0, -8.2), (90, 160, 0.1), hexc("cfd6e0"))
    K.mountains(S, 0, 0, 260, 6, (50, 100), "b7c0da", spread=math.pi * 1.2, start=math.pi * 0.4)
    K.bounds(S, -33, 21, -W, W, h=30)
    S.marker("spawn", (-31, 0, zf(-31) + 0.1), face=(1, 0))
    S.marker("reach_slope_bottom", (8.5, 0, 0.05), face=(1, 0))
    S.marker("npc_papa", (11.0, 1.2, 0.0), face=(-1, 0))
    S.marker("npc_mama", (11.6, -0.6, 0.0), face=(-1, 0.3))
    S.marker("npc_sora", (10.4, 2.6, 0.0), face=(-1, -0.4))
    S.marker("npc_gabi", (10.6, -1.8, 0.0), face=(-1, 0.5))
    water(S, 40, 400, -400, 400, 0)
    finish_water(S, -8.0)
    S.export(os.path.join(OUT, "snow_slope.glb"))


# ---------------------------------------------------------------- 3, 4, 7: крыша

def rooftop():
    """Плоская крыша жилого дома (сцены 3, 4, 7): парапет, бак на опорах, сушилка с бельём, выход с лестницы,
    место Кота у края с пледом; вокруг — крыши города, столбы, канал и море."""
    K.reset()
    S = K.Scene(seed=41)
    rnd = S.rnd
    X0, X1, Y0, Y1 = -7.0, 7.0, -5.0, 5.0
    r = S.b("roof_floor-col", "stone")
    r.box((0, 0, -0.3), (X1 - X0, Y1 - Y0, 0.3), hexc("c9c3ba"))
    tiles = S.b("roof_tiles", "stone")
    for i in range(int(X1 - X0)):
        tiles.box((X0 + i + 0.5, 0, 0.0), (0.02, Y1 - Y0, 0.005), hexc("b5aea4"))
    par = S.b("parapet-col", "wall")
    for (cx, cy, sx, sy) in ((0, Y0, X1 - X0 + 0.3, 0.25), (0, Y1, X1 - X0 + 0.3, 0.25), (X0, 0, 0.25, Y1 - Y0), (X1, 0, 0.25, Y1 - Y0)):
        par.box((cx, cy, 0), (sx, sy, 1.1), hexc("ddd6ca"))
    # корпус дома под крышей (виден сверху, без столкновений)
    S.b("building_body", "wall").box((0, 0, -16), (X1 - X0 + 0.3, Y1 - Y0 + 0.3, 15.7), hexc("d6cfc2"), shade=0.7)
    # выход с лестницы
    hut = S.b("stair_hut-col", "wall")
    hut.box((-5.6, -3.4, 0), (2.4, 2.6, 2.6), hexc("e2dccf"))
    S.b("roofs", "roof").box((-5.6, -3.4, 2.6), (2.7, 2.9, 0.15), hexc("6b6f78"))
    S.b("doors", "metal").box((-4.38, -3.4, 0), (0.05, 0.95, 2.0), hexc("8a8f96"))
    # бак на опорах, кондиционеры
    tank = S.b("prop_tank-col", "metal", smooth=True)
    for dx in (-0.7, 0.7):
        for dy in (-0.7, 0.7):
            tank.box((4.8 + dx, -3.2 + dy, 0), (0.12, 0.12, 1.6), hexc("8a8f96"))
    tank.cyl((4.8, -3.2, 1.6), 1.0, 1.6, hexc("dfe6ea"), seg=16)
    for i in range(3):
        S.b("prop_ac-col", "metal").box((-1.5 + i * 1.3, -4.4, 0), (0.9, 0.5, 0.7), hexc("e8e6e0"))
    # сушилка с бельём
    poles = S.b("prop_laundry", "metal", smooth=True)
    for x in (-2.0, 2.4):
        poles.cyl((x, 1.0, 0), 0.04, 1.9, hexc("9a9894"), seg=6)
    K.tube(poles, [(-2.0 + 4.4 * k / 10, 1.0, 1.85 - 0.12 * math.sin(math.pi * k / 10)) for k in range(11)], 0.012, hexc("6e6c6a"))
    cl = S.b("prop_clothes", "fabric")
    for i, (x, c) in enumerate(((-1.4, "f6f2ea"), (-0.7, "a8c4e0"), (0.1, "f3b2b9"), (0.9, "f6f2ea"), (1.6, "c4dcae"))):
        z = 1.85 - 0.12 * math.sin(math.pi * (x + 2.0) / 4.4)
        cl.box((x, 1.0, z - 0.6), (0.5, 0.02, 0.6), hexc(c))
    # горшки с растениями
    for x, y in ((-6.2, 4.2), (-5.4, 4.3), (6.2, 0.6)):
        S.b("prop_pots", "stone", smooth=True).cyl((x, y, 0), 0.25, 0.45, hexc("c98a6a"), seg=10, r_top=0.3)
        S.b("prop_plants", "leaves", smooth=True).blob((x, y, 0.85), 0.45, K.jitter(hexc("7fae8a"), 0.1, rnd), rnd=rnd, wobble=0.15)
    # место Кота у края: плед и подушка
    S.b("blanket", "fabric").box((5.2, 3.0, 0.0), (1.6, 1.2, 0.04), hexc("f3c9a0"))
    S.b("prop_cushion", "fabric", smooth=True).blob((5.8, 3.5, 0.12), 0.28, hexc("a8c4e0"), squash=0.45)
    # город вокруг (ниже уровня крыши)
    base = -15.6
    for i in range(170):
        a = rnd.uniform(0, 2 * math.pi)
        d = rnd.uniform(11, 60)
        x, y = math.cos(a) * d, math.sin(a) * d
        if abs(x) < 10 and abs(y) < 9:
            continue
        hb = S.b("city_below", "wall")
        fl = rnd.choice([2, 2, 2, 3, 4, 5])
        w_, d_ = rnd.uniform(5, 9), rnd.uniform(5, 9)
        h_ = fl * 2.9
        c = hexc(rnd.choice(K.SIDING))
        hb.box((x, y, base), (w_, d_, h_), c, shade=0.75)
        K.hip_roof(S.b("roofs_below", "roof"), x - w_ / 2, x + w_ / 2, y - d_ / 2, y + d_ / 2, base + h_,
                   min(1.6, min(w_, d_) * 0.3), hexc(rnd.choice(K.TILES)), overhang=0.4)
        gw = S.b("glow_windows_far", "glow_window")
        for f in range(fl):
            for k in range(3):
                gw.box((x - w_ / 2 + (k + 0.5) * w_ / 3, y - d_ / 2 - 0.03, base + 0.9 + f * 2.9), (w_ / 3 * 0.55, 0.05, 1.2),
                       K.jitter(hexc("c4d9ea"), 0.06, rnd))
    S.b("ground_below", "ground").box((0, 0, base - 0.2), (200, 200, 0.2), hexc("9a968c"))
    for x in (-40, -25, -10, 12, 28):
        K.lamp(S, x, -12, z=base, h=5.0)
    K.mountains(S, 0, 0, 260, 7, (50, 100), "a7b0cf", spread=math.pi * 1.4, start=math.pi * 0.3, complex_on=3)
    S.marker("spawn", (-2.2, -0.6, 0.0), face=(1, 0.4))
    S.marker("reach_roof_spot", (4.7, 2.6, 0.0), face=(1, 0))
    S.marker("npc_gabi", (-1.2, -1.6, 0.0), face=(1, 0.6))
    S.marker("lamp_roof", (-4.3, -3.4, 2.3))
    water(S, -400, 400, 60, 400, 0)
    finish_water(S, base - 0.05)
    S.export(os.path.join(OUT, "rooftop.glb"))


# ---------------------------------------------------------------- 5, 6: больница

def hospital():
    """Коридор больницы (сцена 5) и палата Соры (сцена 6): двери палат, поручни, скамьи, лампы под потолком;
    в палате — кровать у окна, капельница, монитор, стул, цветы."""
    K.reset()
    S = K.Scene(seed=51)
    rnd = S.rnd
    L, Wc, H = 26.0, 2.2, 3.0
    fl = S.b("floor-col", "ground")
    fl.box((L / 2 + 4, 0, -0.1), (L + 10, 12, 0.1), hexc("cfdcd2"))
    tiles = S.b("floor_lines", "ground")
    for i in range(int(L / 0.6)):
        tiles.box((i * 0.6, 0, 0.0), (0.02, 2 * Wc, 0.004), hexc("bccbc0"))
    w = S.b("walls-col", "wall")
    wc = hexc("dfe4dc")
    for sy in (-1, 1):
        w.box((L / 2, sy * (Wc + 0.1), 0), (L, 0.2, H), wc, shade=0.92)
    w.box((-0.1, 0, 0), (0.2, 2 * Wc + 0.4, H), wc)
    # торец коридора — стена палаты с дверным проёмом
    for y0, y1 in ((-4.2, -0.75), (0.75, 4.2)):
        w.box((L, (y0 + y1) / 2, 0), (0.2, y1 - y0, H), wc)
    w.box((L, 0, 2.15), (0.2, 1.5, H - 2.15), wc)
    # палата
    RX1, RY = L + 8, 4.2
    for sy in (-1, 1):
        w.box(((L + RX1) / 2, sy * RY, 0), (RX1 - L, 0.2, H), hexc("f1ece4"), shade=0.92)
    w.box((RX1, 0, 0), (0.2, 2 * RY, 0.9), hexc("f1ece4"))
    w.box((RX1, 0, 2.5), (0.2, 2 * RY, H - 2.5), hexc("f1ece4"))
    w.box((RX1, -RY + 0.6, 0.9), (0.2, 1.2, 1.6), hexc("f1ece4"))
    w.box((RX1, RY - 0.6, 0.9), (0.2, 1.2, 1.6), hexc("f1ece4"))
    S.b("glow_windows", "glow_window").box((RX1, 0, 0.9), (0.06, 2 * RY - 2.4, 1.6), hexc("c4d9ea"))
    S.b("curtains", "fabric").box((RX1 - 0.15, RY - 1.3, 0.8), (0.08, 0.6, 2.0), hexc("dfe8d8"))
    # потолок (без столкновений и без теней) и лампы
    ce = S.b("ceiling", "wall")
    ce.box((L / 2, 0, H), (L, 2 * Wc + 0.4, 0.1), hexc("f6f6f2"))
    ce.box(((L + RX1) / 2, 0, H), (RX1 - L, 2 * RY, 0.1), hexc("f6f6f2"))
    lg = S.b("prop_ceiling_lights", "glow_lamp")
    for i in range(6):
        x = 2.0 + i * 4.4
        lg.box((x, 0, H - 0.06), (1.2, 0.35, 0.05), hexc("f8f8ff"))
        S.marker("lamp_c%d" % i, (x, 0, H - 0.4))
    lg.box((L + 4, 0, H - 0.06), (1.2, 0.35, 0.05), hexc("f8f8ff"))
    S.marker("lamp_ward", (L + 4, 0, H - 0.4))
    # двери палат, номера, поручни, скамьи
    dr = S.b("doors", "wood")
    for i in range(5):
        x = 3.0 + i * 5.0
        for sy in (-1, 1):
            if (i + (sy > 0)) % 2:
                continue
            dr.box((x, sy * (Wc - 0.02), 0), (1.1, 0.06, 2.1), hexc("c9b8a0"))
            S.b("door_signs", "fabric").box((x, sy * (Wc - 0.06), 2.25), (0.4, 0.02, 0.15), hexc("7fa6b8"))
    rail = S.b("handrails", "metal")
    for sy in (-1, 1):
        K.tube(rail, [(0.3, sy * (Wc - 0.08), 0.9), (L - 0.3, sy * (Wc - 0.08), 0.9)], 0.03, hexc("b8a890"))
    for x in (6.5, 16.5):
        K.bench(S, x, -Wc + 0.35, rot=0.0, color="9fb4c6")
    S.b("prop_pots", "stone", smooth=True).cyl((22.0, 1.85, 0), 0.22, 0.45, hexc("e6e2da"), seg=10)
    S.b("prop_plants", "leaves", smooth=True).blob((22.0, 1.85, 0.9), 0.4, hexc("7fae8a"), rnd=rnd, wobble=0.15)
    # кровать, капельница, монитор, стул, цветы
    bed = S.b("prop_bed-col", "metal")
    bx0, bx1, by = L + 3.4, L + 7.6, 2.2
    bed.box(((bx0 + bx1) / 2, by, 0), (bx1 - bx0, 1.0, 0.45), hexc("d8dde2"))
    S.b("bed_sheet", "fabric").box(((bx0 + bx1) / 2, by, 0.45), (bx1 - bx0 - 0.1, 1.05, 0.16), hexc("f6f6f2"))
    S.b("prop_pillow", "fabric", smooth=True).blob((bx1 - 0.35, by, 0.7), 0.3, hexc("ffffff"), squash=0.4)
    bed.box((bx1 + 0.05, by, 0), (0.08, 1.0, 1.0), hexc("c4c9cf"))
    iv = S.b("prop_iv", "metal", smooth=True)
    iv.cyl((bx1 - 0.3, by - 0.8, 0), 0.025, 1.9, hexc("c8ccd0"), seg=6)
    iv.blob((bx1 - 0.3, by - 0.8, 1.75), 0.1, hexc("e6f2f6"), squash=1.4)
    S.b("prop_monitor", "metal").box((bx1 - 0.2, by + 0.75, 0), (0.4, 0.3, 1.2), hexc("a8adb4"))
    S.b("prop_monitor_glow", "glow_signal").box((bx1 - 0.2, by + 0.59, 0.95), (0.3, 0.02, 0.2), hexc("6fd09a"))
    chair(S, L + 4.4, by - 1.4, 0.0, color="9fb4c6")
    S.b("prop_table-col", "wood").box((bx1 - 0.4, by - 1.4, 0), (0.6, 0.45, 0.75), hexc("d8c4a8"))
    S.b("prop_flowers", "leaves", smooth=True).blob((bx1 - 0.4, by - 1.4, 0.95), 0.2, hexc("f3a6b8"), rnd=rnd, wobble=0.25)
    S.marker("spawn", (3.6, 0, 0.0), face=(1, 0))
    S.marker("reach_corridor_mid", (12.5, 0, 0.0), face=(1, 0))
    S.marker("reach_ward_door", (L - 1.0, 0, 0.0), face=(1, 0))
    S.marker("npc_nurse", (8.0, 1.5, 0.0), face=(0, -1))
    S.marker("npc_doctor", (14.5, -1.5, 0.0), face=(-0.3, 1))
    S.marker("npc_gabi", (L - 2.4, 1.4, 0.0), face=(-1, -0.3))
    S.marker("spawn_ward", (L + 2.6, -1.6, 0.0), face=(1, 0.8))
    S.marker("npc_gabi_ward", (L + 5.4, 0.7, 0.0), face=(0.1, 1))
    # лежит на кровати лицом вверх, макушкой к изголовью (+X)
    S.marker("npc_sora_bed", (bx0 + 0.15, by, 0.66), face=(0, 0, 1), up=(1, 0, 0))
    S.export(os.path.join(OUT, "hospital.glb"))


# ---------------------------------------------------------------- 9: дом-отель родителей

def family_hotel():
    """Дом-отель родителей (сцена 9; ответ пользователя 23.10: дом и отель — одно здание): трёхэтажный, давно закрытый,
    после затопления — след воды на стене, ил, лужи, обломки; выцветшая вывеска без надписи (название не задано)."""
    K.reset()
    S = K.Scene(seed=61)
    rnd = S.rnd
    g = S.b("ground-col", "ground")
    g.box((0, 0, -1.0), (60, 50, 1.0), hexc("9c9888"))
    path = S.b("path", "stone")
    for i in range(14):
        path.box((rnd.uniform(-0.2, 0.2), -12 + i * 1.0, 0.0), (1.6, 0.85, 0.03), K.jitter(hexc("bdb6aa"), 0.06, rnd))
    mud = S.b("mud", "ground")
    for i in range(14):
        mud.box((rnd.uniform(-10, 10), rnd.uniform(-10, 3), 0.0), (rnd.uniform(1.5, 4), rnd.uniform(1, 2.5), 0.015),
                hexc("7d7466"), rot=rnd.uniform(0, 3))
    S.b("water_puddles", "water").box((3.5, -5, 0.0), (3.2, 1.8, 0.03), hexc("8cc6d0"))
    # здание: три этажа, крыльцо с колоннами, широкий навес
    X0, X1, Y0, Y1 = -7.0, 7.0, 3.6, 12.0
    c = hexc("d9c8b0")
    hb = S.b("hotel-col", "wall")
    hb.box((0, (Y0 + Y1) / 2, 0), (X1 - X0, Y1 - Y0, 9.0), c, shade=0.78)
    for z in (3.0, 6.0):
        hb.box((0, (Y0 + Y1) / 2, z - 0.08), (X1 - X0 + 0.1, Y1 - Y0 + 0.1, 0.16), hexc("bfae96"))
    K.hip_roof(S.b("roofs", "roof"), X0, X1, Y0, Y1, 9.0, 2.4, hexc("5d4a46"), overhang=0.7)
    stain = S.b("water_stain", "wall")
    stain.box((0, Y0 - 0.02, 0), (X1 - X0 + 0.02, 0.04, 1.3), hexc("9e8e78"))
    stain.box((0, Y0 - 0.03, 1.25), (X1 - X0 + 0.02, 0.05, 0.06), hexc("7d6f5e"))   # линия уровня воды
    gw = S.b("glow_windows", "glow_window")
    dark = S.b("broken_windows", "metal")
    frames = S.b("frames", "wood")
    for f in range(3):
        for i in range(5):
            x = X0 + 1.4 + i * 2.8
            if f == 0 and i == 2:
                continue
            z = 0.9 + f * 3.0
            (dark if rnd.random() < 0.35 else gw).box((x, Y0 - 0.03, z), (1.3, 0.05, 1.5), hexc("40454e") if rnd.random() < 1 else hexc("c4d9ea"))
            frames.box((x, Y0 - 0.06, z - 0.08), (1.5, 0.12, 0.1), hexc("8d6e58"))
            frames.box((x, Y0 - 0.06, z + 1.5), (1.5, 0.12, 0.1), hexc("8d6e58"))
            frames.box((x, Y0 - 0.06, z), (0.06, 0.1, 1.5), hexc("8d6e58"))
            # ставни, одна покосилась
            frames.box((x - 0.85, Y0 - 0.05, z), (0.3, 0.06, 1.5), hexc("6f8a7a"), rot=0.0)
    # вход, крыльцо, ступени, колонны
    S.b("doors", "wood").box((0, Y0 - 0.04, 0.45), (1.8, 0.06, 2.3), hexc("6e5446"))
    st = S.b("steps-col", "stone")
    for k in range(3):
        st.box((0, Y0 - 1.6 + k * 0.4, 0), (4.2, 1.6 - k * 0.4, 0.15 * (k + 1)), hexc("c4bcae"))
    col = S.b("prop_columns-col", "wall", smooth=True)
    for x in (-1.9, 1.9):
        col.cyl((x, Y0 - 1.3, 0.45), 0.16, 2.75, hexc("e2d8c6"), seg=12)
    S.b("roofs", "roof").box((0, Y0 - 1.1, 3.2), (4.8, 2.4, 0.18), hexc("5d4a46"))
    # вывеска над входом — выцветшая, надпись не читается (название в сценарии не дано)
    sign = S.b("prop_sign_board", "wood")
    sign.box((0, Y0 - 0.12, 3.5), (4.2, 0.1, 0.9), hexc("8a6a52"))
    faded = S.b("sign_faded", "fabric")
    for i in range(7):
        faded.box((-1.5 + i * 0.5, Y0 - 0.18, 3.7 + rnd.uniform(-0.05, 0.05)), (0.3, 0.02, 0.45), hexc("cdbb98"))
    # обломки, ящики, доски, ограда
    deb = S.b("prop_debris", "wood")
    for i in range(10):
        deb.box((rnd.uniform(-9, 9), rnd.uniform(-6, 2.8), 0.0), (rnd.uniform(0.8, 2.2), 0.18, 0.06), hexc("8d7a64"),
                rot=rnd.uniform(0, 3))
    for x, y in ((-5.5, 2.2), (-4.7, 2.5), (5.8, 1.8)):
        deb.box((x, y, 0), (0.7, 0.6, 0.55), hexc("a58c6e"), rot=rnd.uniform(-0.4, 0.4))
    fence = S.b("prop_fence-col", "wood")
    for x in range(-14, 15):
        if -1 <= x <= 1:
            continue
        fence.box((x, -2.0 if False else -1.5 + 0 * x, 0), (0.1, 0.1, 1.1), hexc("8d7a64"))
    fence.box((-7.5, -1.5, 0.85), (13, 0.06, 0.1), hexc("8d7a64"))
    fence.box((7.5, -1.5, 0.85), (13, 0.06, 0.1), hexc("8d7a64"))
    K.hedge(S, -14, -8, 3.0, h=1.6)
    K.hedge(S, 8, 14, 3.0, h=1.6)
    K.tree(S, -10, 6, h=6.0); K.tree(S, 10, 7, h=5.5)
    for x in (-12, -4, 4, 12):
        K.jp_house(S, x - 3, x + 3, -24, -18, "+y", col=False, balcony=False)
    # вода позади — затопленные кварталы
    K.utility_pole(S, -9, -2.6, h=8.0)
    K.utility_pole(S, 9, -2.6, h=8.0)
    K.wires(S, [(-9, -2.6, 8.0), (9, -2.6, 8.0)])
    K.mountains(S, 0, 0, 280, 6, (60, 100), "9fa9c6", spread=math.pi, start=0.2, complex_on=2)
    K.bounds(S, -14, 14, -13, 3.2)
    S.marker("spawn", (0, -11, 0.05), face=(0, 1))
    S.marker("npc_sora", (1.2, 2.3, 0.15), face=(-0.3, -1))
    S.marker("reach_talk_sora", (0.8, 0.6, 0.05), face=(0, 1))
    S.marker("int_hotel_sign", (-0.6, 1.6, 0.05), face=(0, 1))
    S.marker("int_water_line", (-5.0, 2.6, 0.05), face=(0, 1))
    S.marker("lamp_porch", (0, Y0 - 1.0, 2.9))
    water(S, -400, 400, -400, -14, 0)
    finish_water(S, -0.3)
    S.export(os.path.join(OUT, "family_hotel.glb"))


BUILDERS = {"city_street": city_street, "family_home": family_home, "snow_slope": snow_slope, "rooftop": rooftop,
            "hospital": hospital, "family_hotel": family_hotel}


# Локации, перестроенные по location-kit (tools/art/locs/<id>.py), заменяют старые строители.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "locs"))
for _id in ("family_home", "city_street", "snow_slope", "rooftop", "hospital", "family_hotel"):
    if os.path.exists(os.path.join(os.path.dirname(__file__), "locs", _id + ".py")):
        BUILDERS[_id] = (lambda m=_id: __import__(m).build())


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    ids = [a for a in sys.argv[1:] if a in BUILDERS] or list(BUILDERS)
    for i in ids:
        BUILDERS[i]()
