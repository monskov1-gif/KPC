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
    S.marker("int_girl", (9.6, -6.6, 0.04), face=(-1, 0))
    S.marker("int_viewpoint", (31.8, 0, 0.02), face=(1, 0))
    S.marker("spawn_flood", (-38, 0.6, 0.02), face=(1, 0))
    S.marker("npc_resident_a", (-30, 1.2, 0.02), face=(1, 0))
    S.marker("npc_resident_b", (-22, -1.0, 0.02), face=(1, 0.2))
    S.marker("reach_evac_point", (21, 0, 1.6), face=(-1, 0))
    water(S, -400, 400, -400, 400, 0)
    finish_water(S, -0.8)
    S.export(os.path.join(OUT, "city_street.glb"))


BUILDERS = {"city_street": city_street}


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    ids = [a for a in sys.argv[1:] if a in BUILDERS] or list(BUILDERS)
    for i in ids:
        BUILDERS[i]()
