"""Сцены 3, 4, 7 — плоская крыша жилого дома: место Кота у края (плед, подушка, скетчбук, карандаши), гирлянда,
бак на опорах, кондиционеры, сушилка с бельём, горшки с цветами, выход с лестницы с лампой; вокруг —
крыши города ниже, столбы, море и гора. Точки камеры для кат-сцены засыпания (cam_*)."""
import math

from common import K, finish_water, hexc, out_path, water
import lockit_props as P


def build():
    K.reset()
    S = K.Scene(seed=41)
    Mt = P.mats()
    rnd = S.rnd
    X0, X1, Y0, Y1 = -7.0, 7.0, -5.0, 5.0
    fl = S.b("roof_floor-col", Mt["paving"], tile=0.4)
    fl.box((0, 0, -0.3), (X1 - X0, Y1 - Y0, 0.3), (0.95, 0.95, 0.95, 1), grad=1.0)
    par = S.b("parapet-col", Mt["concrete"], tile=0.64)
    cap = S.b("parapet_cap", Mt["concrete"], tile=0.64, bevel=0.01)
    for (cx, cy, sx, sy) in ((0, Y0, X1 - X0 + 0.3, 0.25), (0, Y1, X1 - X0 + 0.3, 0.25), (X0, 0, 0.25, Y1 - Y0), (X1, 0, 0.25, Y1 - Y0)):
        par.box((cx, cy, 0), (sx, sy, 1.05), (1, 1, 1, 1), grad=0.85)
        cap.box((cx, cy, 1.05), (sx + 0.06, sy + 0.06, 0.06), (1, 1, 1, 1))
    body = S.b("building_body", Mt["plaster"], tile=0.64)
    body.box((0, 0, -16), (X1 - X0 + 0.3, Y1 - Y0 + 0.3, 15.7), (0.9, 0.9, 0.9, 1), grad=0.7)
    # выход с лестницы: будка, дверь, лампа
    hut = S.b("stair_hut-col", Mt["plaster"], tile=0.64)
    hut.box((-5.6, -3.4, 0), (2.4, 2.6, 2.6), (1, 1, 1, 1), grad=0.85)
    S.b("hut_roof", Mt["slate"], tile=0.5, bevel=0.01).box((-5.6, -3.4, 2.6), (2.8, 3.0, 0.15), (1, 1, 1, 1))
    P.door(S, Mt, P.wall(-4.4, -3.4, -math.pi / 2), 0.0, 0.9, 2.0, color="6a7a88")
    lampb = S.b("prop_lamp_base", Mt["metal"], bevel=0.004)
    lampb.box((-4.36, -2.7, 2.15), (0.08, 0.2, 0.2), hexc("3a3a3e"))
    S.b("prop_lamp_shades", Mt["lamp"], smooth=True).blob((-4.28, -2.7, 2.2), 0.08, hexc("fff0c8"), seg=16, rings=12)
    S.marker("lamp_roof", (-4.0, -2.7, 2.0))
    # бак на опорах, кондиционеры с вентиляторами, трубы, антенна
    tank = S.b("prop_tank-col", Mt["metal"], smooth=True)
    for dx in (-0.7, 0.7):
        for dy in (-0.7, 0.7):
            tank.box((4.8 + dx, -3.2 + dy, 0), (0.12, 0.12, 1.6), hexc("8a8f96"))
    tank.cyl((4.8, -3.2, 1.6), 1.0, 1.6, hexc("dfe6ea"), seg=24)
    tank.cyl((4.8, -3.2, 3.2), 1.02, 0.06, hexc("c8d0d6"), seg=24)
    tank.tube([(4.8, -2.2, 2.0), (4.8, -1.6, 2.0), (4.8, -1.6, 0.05)], 0.05, hexc("8a8f96"))
    for i in range(3):
        acx = -1.5 + i * 1.3
        P.Frame(acx, -4.4, 0).box(S.b("prop_ac-col", Mt["fabric"], bevel=0.02), (0, 0, 0), (0.9, 0.5, 0.7), hexc("e8e6e0"))
        S.b("prop_ac_fans", Mt["metal"], smooth=True).cyl((acx, -4.14, 0.35), 0.24, 0.02, hexc("8a8a88"), seg=20, rx=math.pi / 2)
    ant = S.b("prop_antenna", Mt["metal"], smooth=True)
    ant.tube([(6.3, 4.3, 1.0), (6.3, 4.3, 3.6)], 0.03, hexc("8a8a88"))
    for k in range(5):
        ant.tube([(6.3 - 0.4 + k * 0.05, 4.3, 3.0 + k * 0.12), (6.3 + 0.4 - k * 0.05, 4.3, 3.0 + k * 0.12)], 0.012, hexc("8a8a88"))
    # сушилка с бельём
    poles = S.b("prop_laundry", Mt["metal"], smooth=True)
    for x in (-2.0, 2.4):
        poles.cyl((x, 1.0, 0), 0.04, 1.9, hexc("9a9894"), seg=10)
    poles.tube([(-2.0 + 4.4 * k / 10, 1.0, 1.85 - 0.12 * math.sin(math.pi * k / 10)) for k in range(11)], 0.012, hexc("6e6c6a"))
    cl = S.b("prop_clothes", Mt["linen"], tile=0.4, bevel=0.003)
    for i, (x, c) in enumerate(((-1.4, "f6f2ea"), (-0.7, "a8c4e0"), (0.1, "f3b2b9"), (0.9, "f6f2ea"), (1.6, "c4dcae"))):
        z = 1.85 - 0.12 * math.sin(math.pi * (x + 2.0) / 4.4)
        cl.box((x, 1.0, z - 0.62), (0.5, 0.02, 0.6), hexc(c))
    # цветы в горшках вдоль парапета
    for x, y, s in ((-6.2, 4.2, 1.1), (-5.5, 4.3, 0.8), (-4.8, 4.35, 0.9), (6.2, 0.6, 1.0), (6.25, -0.3, 0.8)):
        P.planter(S, Mt, x, y, s)
    # место Кота: плед, подушка, скетчбук, карандаши, кружка
    S.b("blanket", Mt["plaid"], tile=0.32, bevel=0.01).box((5.2, 3.0, 0.0), (1.6, 1.2, 0.03), (1, 1, 1, 1))
    cush = S.b("prop_cushion", Mt["cushion"], smooth=True)
    cush.cushion((5.75, 3.35, 0.03), (0.5, 0.4, 0.14), hexc("a8c4e0"), puff=0.6, rnd=rnd)
    book = S.b("prop_sketchbook", Mt["fabric"], bevel=0.003)
    book.box((4.75, 2.75, 0.03), (0.32, 0.24, 0.02), hexc("3a5a6a"), rz=0.3)
    S.b("prop_papers", Mt["paper"], tile=0.24).box((4.78, 2.75, 0.05), (0.3, 0.22, 0.003), (1, 1, 1, 1), rz=0.3)
    for k, col in enumerate(("d84a3e", "3a74b8", "f0b840")):
        book.box((5.0 + k * 0.05, 2.55, 0.035), (0.012, 0.16, 0.012), hexc(col), rz=0.5)
    P.mug(S, Mt, 5.95, 2.6, 0.03, "e8d0b0")
    # гирлянда вдоль парапета над пледом (светится вечером и ночью)
    pts = [(3.5 + k * 0.35, Y1 - 0.15, 1.15 - 0.12 * math.sin(math.pi * k / 10)) for k in range(11)]
    S.b("prop_cords", Mt["metal"], smooth=True).tube(pts, 0.006, hexc("2a2a2a"), sides=4)
    bulbs = S.b("prop_fairy_bulbs", Mt["lamp"], smooth=True)
    for p in pts[1:-1]:
        bulbs.blob((p[0], p[1], p[2] - 0.04), 0.035, hexc("ffe8b0"), seg=16, rings=12)
    S.marker("lamp_fairy", (5.2, 4.4, 1.0))
    # город вокруг (ниже уровня крыши): упрощённые дома, столбы, фонари
    base = -15.6
    for i in range(170):
        a = rnd.uniform(0, 2 * math.pi)
        d = rnd.uniform(11, 60)
        x, y = math.cos(a) * d, math.sin(a) * d
        if abs(x) < 10 and abs(y) < 9:
            continue
        w_, d_ = rnd.uniform(5, 9), rnd.uniform(5, 9)
        fl_ = rnd.choice([2, 2, 2, 3, 4])
        bx0, by0 = x - w_ / 2, y - d_ / 2
        P.jp_house(S, Mt, bx0, bx0 + w_, by0 + 0, by0 + d_, "+y" if y < 0 else "-y", floors=fl_, col=False, detail=False, seed=500 + i)
    # подвинуть город вниз: всё, что строил jp_house с col=False, — на уровень улицы base
    for name, b in S.batches.items():
        if name.endswith("_far") or name.startswith("glow_windows_far"):
            b.v = [(v[0], v[1], v[2] + base) for v in b.v]
    S.b("ground_below", Mt["asphalt"], tile=2.0).box((0, 0, base - 0.2), (200, 200, 0.2), (0.9, 0.9, 0.9, 1), grad=1.0)
    for x in (-40, -25, -10, 12, 28):
        S.marker("lamp_city_%d" % (x + 50), (x, -12, base + 4.5))
    far = S.b("far_mountains", Mt["concrete"], smooth=True, tile=4.0)
    for i in range(7):
        a = math.pi * 0.3 + math.pi * 1.4 * (i + 0.5) / 7
        x, y = math.cos(a) * 260, math.sin(a) * 260
        hh = rnd.uniform(50, 100)
        far.cyl((x, y, base - 5), hh * 1.5, hh + 5, (0.62, 0.66, 0.78, 1), seg=20, r_top=hh * 0.18)
    # точки сцен
    S.marker("spawn", (-2.2, -0.6, 0.0), face=(1, 0.4))
    S.marker("reach_roof_spot", (4.7, 3.05, 0.03), face=(0, 1))
    S.marker("spawn_sleep", (4.7, 3.05, 0.03), face=(0, 1))
    S.marker("npc_gabi", (-4.0, -2.4, 0.0), face=(1, 0.6))
    S.marker("npc_gabi_near", (5.0, 4.05, 0.0), face=(0, -1))
    # Кот сидит лицом к городу (+y), во сне лежит вдоль пледа головой на подушке (+x).
    # камеры кат-сцены: сбоку на сидящего Кота с городом за парапетом, общий план с огнями, крупно — спит
    S.marker("cam_roof_side", (3.4, 4.45, 1.35), face=(1, -1))
    S.marker("cam_roof_wide", (4.0, 0.6, 1.9), face=(1, 1))
    S.marker("look_roof_wide", (6.0, 8.0, 0.0), face=(1, 0))
    S.marker("cam_roof_sleep", (3.0, 1.2, 2.0), face=(1, 1))
    S.marker("look_city", (40, 25, -6), face=(1, 0))
    water(S, -400, 400, 60, 400)
    finish_water(S, base - 0.05)
    S.export(out_path("rooftop"))
