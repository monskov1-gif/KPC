"""Сцены 1 и 8 — улица Shizunda Taver City: тихий приморский пригород (реф. пользователя 23.10): узкая улица вдоль X,
бетонные заборы и живые изгороди, дома с черепичными вальмовыми крышами, столбы с проводами, переезд, лавка
с цветами и автоматом, сквер с фонтаном; на востоке — канал с горбатым мостом, набережная и море; за домами —
второй ряд домов, зелёные холмы, вдали гора (на ней — будущий жилой комплекс тома I)."""
import math

from common import K, finish_water, hexc, out_path, water
import lockit_props as P

LW = 2.6              # полуширина улицы
CANAL = (18.0, 24.0)


def build():
    K.reset()
    S = K.Scene(seed=11)
    Mt = P.mats()
    rnd = S.rnd
    # ---- земля, дорога, водостоки, разметка, люки
    g = S.b("ground-col", Mt["gravel"], tile=0.64)
    for xa, xb in ((-60, CANAL[0]), (CANAL[1], 33)):
        g.box(((xa + xb) / 2, 0, -2.0), (xb - xa, 60, 2.0), (0.92, 0.9, 0.86, 1), grad=1.0)
    road = S.b("road-col", Mt["asphalt"], tile=1.28)
    gut = S.b("gutters-col", Mt["concrete"], tile=0.64)
    for xa, xb in ((-46, CANAL[0] - 1.8), (CANAL[1] + 1.8, 32.6)):
        road.box(((xa + xb) / 2, 0, -0.05), (xb - xa, 2 * LW - 0.6, 0.06), (1, 1, 1, 1), grad=1.0)
        for sy in (-1, 1):
            gut.box(((xa + xb) / 2, sy * (LW - 0.15), -0.05), (xb - xa, 0.3, 0.062), (1, 1, 1, 1), grad=1.0)
    grates = S.b("prop_grates", Mt["metal"])
    for x in range(-44, 16, 6):
        for sy in (-1, 1):
            grates.box((x, sy * (LW - 0.15), 0.012), (0.5, 0.22, 0.004), hexc("4a4642"))
    marks = S.b("road_marks", Mt["paint_white"], tile=0.64)
    for xa, xb in ((-46, -17.5), (-12.5, CANAL[0] - 1.8), (CANAL[1] + 1.8, 32.6)):
        for sy in (-1, 1):
            marks.box(((xa + xb) / 2, sy * (LW - 0.42), 0.0), (xb - xa, 0.1, 0.014), (1, 1, 1, 1))
    for x in (-38, -8, 14):
        P.manhole(S, Mt, x, 0.6)
    # «止まれ»-полосы у переезда — без текста, белые блоки
    for x in (-19.5, -10.5):
        marks.box((x, 0, 0.0), (0.4, 2 * LW - 0.8, 0.014), (1, 1, 1, 1))
    # ---- северная сторона: заборы, дома, лавка
    north = [(-46, -36), (-36, -27), (-27, -18.5), (-12.5, -5.5), (-5.5, 2.5), (2.5, 10), (10, 17.2)]
    for i, (x0, x1) in enumerate(north):
        if (x0, x1) == (-12.5, -5.5):
            P.jp_house(S, Mt, x0 + 0.3, x1 - 0.3, 4.3, 10.5, "-y", seed=100 + i, shop={"awning": ["5f7f6e", "efe6d6"], "sign": "f4ead8"})
            continue
        P.block_wall(S, Mt, x0, x1, LW + 0.15, gaps=[(x0 + 1.2, x0 + 2.4)])
        P.jp_house(S, Mt, x0 + 0.6, x1 - 0.6, 4.6, 11.0, "-y", seed=100 + i, floors=rnd.choice((2, 2, 2, 3)))
        if rnd.random() < 0.75:
            P.tree(S, Mt, x1 - 1.4, 3.6, h=rnd.uniform(3.4, 4.6))
        P.hedge(S, Mt, x0 + 2.6, x1 - 0.4, 3.3, h=1.5)
        for k in range(rnd.randint(1, 3)):
            P.planter(S, Mt, x0 + 1.0 + k * 0.45, 3.0, s=rnd.uniform(0.8, 1.2))
    # ---- южная сторона; сквер с фонтаном на x 0..12
    south = [(-46, -36), (-36, -27), (-27, -18.5), (-12.5, -6), (-6, 0), (12, 17.2)]
    for i, (x0, x1) in enumerate(south):
        P.block_wall(S, Mt, x0, x1, -LW - 0.15, gaps=[(x1 - 2.4, x1 - 1.2)])
        P.jp_house(S, Mt, x0 + 0.6, x1 - 0.6, -11.0, -4.6, "+y", seed=200 + i, floors=rnd.choice((2, 2, 3)))
        if rnd.random() < 0.6:
            P.tree(S, Mt, x0 + 1.5, -3.7, h=rnd.uniform(3.4, 4.6))
        P.hedge(S, Mt, x0 + 0.4, x1 - 2.6, -3.3, h=1.4)
    park = S.b("park_ground", Mt["paving"], tile=0.4)
    park.box((6, -7.6, -0.04), (12, 10, 0.07), (1, 1, 1, 1), grad=1.0)
    lawn = S.b("park_lawn", Mt["grass"], tile=0.64)
    for cx in (2.2, 9.8):
        lawn.box((cx, -9.6, 0.0), (3.6, 4.2, 0.05), (1, 1, 1, 1), grad=1.0)
    P.hedge(S, Mt, 0, 3, -LW - 0.3, h=1.1)
    P.hedge(S, Mt, 9, 12, -LW - 0.3, h=1.1)
    P.hedge(S, Mt, 0, 12, -12.4, h=1.4)
    for x in (0.0, 12.0):
        P.hedge(S, Mt, -3.2, -12.0, x, h=1.2, along_x=False)
    bounds = S.b("park_bounds-colonly", K.M("base"))
    bounds.box((0, -7.5, 0), (0.6, 10, 2.0), (1, 1, 1, 1))
    bounds.box((12, -7.5, 0), (0.6, 10, 2.0), (1, 1, 1, 1))
    bounds.box((6, -12.4, 0), (12, 0.6, 2.0), (1, 1, 1, 1))
    f = S.b("prop_fountain-col", Mt["stone"], smooth=True, tile=0.64)
    f.cyl((6, -7.5, 0), 1.9, 0.5, (1, 1, 1, 1), seg=32)
    f.cyl((6, -7.5, 0.5), 2.0, 0.08, (1, 1, 1, 1), seg=32)
    f.cyl((6, -7.5, 0), 0.28, 1.4, (1, 1, 1, 1), seg=16)
    f.lathe((6, -7.5, 1.35), [(0.3, 0), (0.8, 0.12), (0.92, 0.22)], (1, 1, 1, 1), seg=24)
    S.b("water_fountain", K.M("water")).cyl((6, -7.5, 0.45), 1.75, 0.02, hexc("8cc6d0"), seg=32, smooth=False)
    for x, y in ((2.0, -10.6), (10.4, -10.4), (1.6, -4.4)):
        P.tree(S, Mt, x, y, h=rnd.uniform(4.2, 5.2))
    P.bench(S, Mt, 10.2, -6.6, math.pi / 2)
    P.bench(S, Mt, 6.0, -11.4, 0.0)
    P.bench(S, Mt, 1.8, -7.6, -math.pi / 2)
    for x, y in ((3.2, -3.4), (8.8, -3.4)):
        P.planter(S, Mt, x, y, 1.3)
    # ---- переезд
    P.railway_crossing(S, Mt, -15.0, -LW, LW, track_len=60)
    fence = S.b("prop_fences-col", Mt["metal"], bevel=0.003)
    for x in (-17.6, -12.4):
        for sy in (-1, 1):
            fence.box((x, sy * 16.5, 0), (0.06, 27.6, 1.3), hexc("6b6f6a"))
            for k in range(46):
                fence.box((x, sy * (2.8 + k * 0.6), 0), (0.08, 0.08, 1.3), hexc("55595a"))
    for x, y in ((-18.0, -1.6), (-18.0, 1.6), (-12.0, -1.6), (-12.0, 1.6)):
        P.bollard(S, Mt, x, y)
    P.street_sign(S, Mt, -19.2, -LW - 0.05, face=(1, 0))
    sign = S.b("prop_signs_boards", Mt["fabric"], bevel=0.004)
    sign.box((-19.6, LW + 0.05, 0), (0.06, 0.06, 2.2), hexc("9a9a98"))
    sign.box((-19.6, LW + 0.05, 1.2), (0.5, 0.05, 1.2), hexc("f4f2ee"))
    sign.box((-19.6, LW + 0.02, 1.35), (0.3, 0.02, 0.85), hexc("d8564a"))
    # ---- лавка: прилавок с цветами, автомат, велосипеды, зеркало, конус
    st = S.b("prop_stall-col", Mt["oak"], tile=0.32, bevel=0.01)
    st.box((-10.6, 3.7, 0), (2.2, 0.7, 0.85), (1, 1, 1, 1))
    st.box((-10.6, 3.95, 0.85), (2.2, 0.2, 0.25), (0.9, 0.9, 0.9, 1))
    fl = S.b("prop_flowers", Mt["fabric"], smooth=True)
    buckets = S.b("prop_buckets", Mt["metal"], smooth=True)
    for i in range(8):
        x = -11.5 + i * 0.26
        buckets.cyl((x, 3.55, 0.85), 0.1, 0.16, hexc("8a9aa8"), seg=14)
        for k in range(5):
            fl.blob((x + rnd.uniform(-0.08, 0.08), 3.55 + rnd.uniform(-0.08, 0.08), 1.06 + rnd.random() * 0.12), 0.06,
                    hexc(rnd.choice(["e88fa4", "f6c560", "b7a4ea", "fdf2ee", "f08a6a"])), seg=16, rings=12)
    P.vending_machine(S, Mt, -6.2, 3.5, math.pi)
    P.covered_bike(S, Mt, 30.0, 3.4, 0.1)
    P.covered_bike(S, Mt, -33.0, -3.4, 0.0)
    P.corner_mirror(S, Mt, -26.6, 2.9, face_a=-2.3)
    cone = S.b("prop_cones", Mt["fabric"], smooth=True)
    cone.cyl((29.0, 3.3, 0), 0.16, 0.5, hexc("e8592f"), seg=16, r_top=0.03)
    # ---- столбы, провода, фонари
    poles = [P.utility_pole(S, Mt, x, LW + 0.45, h=rnd.uniform(8.5, 9.5), transformer=x in (-31, 8.5))
             for x in (-42, -31, -21, -10.2, -1, 8.5, 16.6)]
    P.wires(S, Mt, poles)
    P.wires(S, Mt, [P.utility_pole(S, Mt, x, LW + 0.45, h=8.6) for x in (25.5, 31.5)])
    for x in (-37, -25, -4, 13, 28):
        P.street_lamp(S, Mt, x, -LW - 0.3, h=4.2, arm=(0, 0.7))
    # ---- канал и горбатый мост
    cw = S.b("canal-col", Mt["stone"], tile=0.64)
    cw.box(((CANAL[0] + CANAL[1]) / 2, 0, -3.2), (CANAL[1] - CANAL[0], 120, 0.5), (0.7, 0.8, 0.8, 1))
    for x in CANAL:
        cw.box((x, 0, -3.2), (0.6, 120, 3.2), (1, 1, 1, 1))
    br = S.b("bridge-col", Mt["concrete"], tile=0.64)
    rail = S.b("prop_bridge_rails-col", Mt["metal"], smooth=True)
    b0, b1 = CANAL[0] - 1.8, CANAL[1] + 1.8
    xs = [b0 + i * 0.4 for i in range(int((b1 - b0) / 0.4) + 1)]
    zf = lambda x: 1.6 * math.sin(math.pi * min(1, max(0, (x - b0) / (b1 - b0))))
    br.strip([(x, LW, zf(x)) for x in xs], [(x, -LW, zf(x)) for x in xs], (1, 1, 1, 1), thick=0.5)
    for sy in (-1, 1):
        for x in xs[::2]:
            rail.box((x, sy * (LW - 0.1), zf(x)), (0.1, 0.1, 1.0), hexc("8e2f2a"))
        rail.tube([(x, sy * (LW - 0.1), zf(x) + 1.0) for x in xs], 0.05, hexc("a8443a"))
    for x in (CANAL[0] - 0.4, CANAL[1] + 0.4):
        for sy in (-1, 1):
            rail.box((x, sy * 8, 0), (0.12, 10.8, 1.1), hexc("7a7a78"))
    # ---- восточный край: дома, набережная, море
    x0, x1 = 24.6, 31.6
    P.block_wall(S, Mt, x0, x1, LW + 0.15, gaps=[(x0 + 0.8, x0 + 2.0)])
    P.jp_house(S, Mt, x0 + 0.5, x1 - 0.5, 4.6, 10.5, "-y", seed=301)
    P.block_wall(S, Mt, x0, x1, -LW - 0.15, gaps=[(x1 - 2.0, x1 - 0.8)])
    P.jp_house(S, Mt, x0 + 0.5, x1 - 0.5, -10.5, -4.6, "+y", seed=302)
    rail.box((32.7, 0, 0), (0.2, 26, 1.0), hexc("9a9894"))
    emb = S.b("embankment", Mt["stone"], tile=0.64)
    emb.box((32.9, 0, -3.0), (0.6, 60, 3.0), (1, 1, 1, 1))
    # ---- фон: второй ряд домов (упрощённых), холмы, гора с комплексом
    for x in range(-60, 34, 8):
        if CANAL[0] - 3 < x < CANAL[1]:
            continue
        for sy in (-1, 1):
            P.jp_house(S, Mt, x, x + 6.5, 13 if sy > 0 else -20, 20 if sy > 0 else -13, "-y" if sy > 0 else "+y", col=False,
                       floors=rnd.choice([2, 2, 3]), detail=False, seed=400 + x * 3 + sy)
    hills = S.b("far_hills", Mt["leaves"], smooth=True, tile=2.0)
    for k in range(16):
        a = math.pi * 0.15 + k / 15 * math.pi * 1.2
        hills.blob((math.cos(a) * 95 - 20, math.sin(a) * 70, -8), rnd.uniform(26, 38), K.jitter((0.85, 0.9, 0.85, 1), 0.1, rnd),
                   seg=20, rings=12, squash=0.55, rnd=rnd, wobble=0.06)
    far = S.b("far_mountains", Mt["concrete"], smooth=True, tile=4.0)
    for i in range(5):
        a = math.pi * 0.6 + math.pi * 0.6 * (i + 0.5) / 5
        x, y = math.cos(a) * 300, math.sin(a) * 300
        hh = rnd.uniform(60, 110)
        far.cyl((x, y, -5), hh * 1.5, hh + 5, (0.62, 0.66, 0.78, 1), seg=20, r_top=hh * 0.18)
        if i == 2:
            cx_ = S.b("far_complex", Mt["paint_white"], tile=2.0)
            for k in range(5):
                cx_.box((x + (k - 2) * 7, y + rnd.uniform(-4, 4), hh - 1), (5, 5, rnd.uniform(6, 14)), (1, 1, 1, 1))
    # ---- невидимые границы: улица, ниша лавки, вход в сквер
    bw = S.b("bounds-colonly", K.M("base"))

    def wall(xa, xb, ya, yb):
        bw.box(((xa + xb) / 2, (ya + yb) / 2, 0), (xb - xa, yb - ya, 4.0), (1, 1, 1, 1))
    wall(-46.5, -45.5, -LW, LW)
    wall(32.6, 33.6, -LW, LW)
    wall(-46, -12.5, LW + 0.4, LW + 0.8)
    wall(-5.5, 33, LW + 0.4, LW + 0.8)
    wall(-12.9, -12.5, LW + 0.4, 4.4)
    wall(-5.5, -5.1, LW + 0.4, 4.4)
    wall(-46, 3.0, -LW - 0.8, -LW - 0.4)
    wall(9.0, 33, -LW - 0.8, -LW - 0.4)
    # ---- точки сцен (имена — data/story/prologue.json)
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
    # маршруты прохожих (живой мир): пары точек route_<n>_a / route_<n>_b
    for n, (a, b) in enumerate((((-44, -1.2), (16, -1.0)), ((15, 1.3), (-44, 1.1)), ((30, -0.8), (26, 0.9)))):
        S.marker(f"route_{n}_a", (a[0], a[1], 0.02), face=(1, 0))
        S.marker(f"route_{n}_b", (b[0], b[1], 0.02), face=(1, 0))
    water(S, -400, 400, -400, 400)
    finish_water(S, -0.8)
    S.export(out_path("city_street"))
