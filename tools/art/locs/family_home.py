"""Сцена 2 — кухня-гостиная семьи (японский дом): обеденный стол на пятерых с ужином, кухня с окном,
гостиная с диваном и книжным шкафом, прихожая с обувью, уголок Кота с рисунками и мелками.
Комната x −5…5, y −3.6…3.6, высота 2.6; окна на север (+y) и восток (+x)."""
import math

from common import K, Frame, hexc, out_path, room, shade
import lockit_props as P


def build():
    K.reset()
    S = K.Scene(seed=21)
    Mt = P.mats()
    rnd = S.rnd
    X0, X1, Y0, Y1, H = -5.0, 5.0, -3.6, 3.6, 2.6
    room(S, Mt, X0, X1, Y0, Y1, H, wall="paint_warm",
         holes={"+y": [(-1.85, 0.65, 0.8, 2.2)], "+x": [(0.6, 1.8, 1.05, 2.05)], "-x": [(-2.75, -1.75, 0.0, 2.1)]})
    # ---- окна (вид на соседние дома, лучи на пол днём)
    P.window(S, Mt, P.wall(-0.6, Y1, math.pi), 2.5, 0.8, 2.2, view="low", panes=4, curtains="f3e6cf", key="north")
    P.window(S, Mt, P.wall(X1, 1.2, math.pi / 2), 1.2, 1.05, 2.05, view="low", panes=2, blinds=True, key="east", shafts=False)
    # ---- прихожая (генкан): ступенька, обувь, зонты, дверь
    P.door(S, Mt, P.wall(X0, -2.25, -math.pi / 2), 0.0, 0.92, 2.05, color="7a5a42")
    gen = S.b("genkan-col", Mt["concrete"], tile=0.64, bevel=0.01)
    gen.box((X0 + 0.55, -2.25, -0.02), (1.1, 1.3, 0.05), hexc("d8d2c6"))
    shoes = S.b("prop_shoes", Mt["fabric"], bevel=0.01)
    for k, col in enumerate(("3a3a44", "8a5a4a", "d86a5a", "6a8aa8", "f0ece0")):
        y = -2.75 + k * 0.24
        for dx in (0, 0.11):
            shoes.box((X0 + 0.35 + dx, y, 0.03), (0.09, 0.2 if k < 2 else 0.16, 0.07), hexc(col))
    stand = S.b("prop_umbrella", Mt["ceramic"], smooth=True)
    stand.lathe((X0 + 0.2, -1.45, 0), [(0.11, 0), (0.12, 0.45)], hexc("5a6a78"))
    for k, col in enumerate(("2a4a6a", "d84a3e")):
        stand.tube([(X0 + 0.18 + k * 0.05, -1.45, 0.1), (X0 + 0.16 + k * 0.08, -1.42, 0.9)], 0.012, hexc(col))
    shelf = S.b("prop_shoe_shelf-col", Mt["oak"], tile=0.4, bevel=0.008)
    shelf.box((X0 + 0.2, -3.05, 0.0), (0.36, 0.9, 0.9), (1, 1, 1, 1))
    S.b("prop_plants", Mt["leaves"], smooth=True)
    P.plant(S, Mt, X0 + 0.2, -3.2, 0.9, 0.6, pot="e8e0d0")
    # ---- обеденный стол с ужином и стулья
    P.table(S, Mt, 1.0, 0.5, 0.0, w=1.8, d=0.95, h=0.72)
    for (cx, cy, rz) in ((0.5, -0.3, 0.0), (1.5, -0.3, 0.0), (0.5, 1.3, math.pi), (1.5, 1.3, math.pi), (2.25, 0.5, math.pi / 2)):
        P.chair(S, Mt, cx, cy, rz, pad=rnd.choice(("d9877a", "8fa6b8", "e8c48a")))
    z = 0.72
    for (cx, cy) in ((0.5, 0.18), (1.5, 0.18), (0.5, 0.82), (1.5, 0.82), (1.82, 0.5)):
        P.plate(S, Mt, cx, cy, z, food=rnd.choice(("e8b06a", "d86a5a", "9cc08a")))
        P.bowl(S, Mt, cx + 0.16, cy, z, 0.055, soup="e8c48a")
    P.bowl(S, Mt, 1.0, 0.5, z, 0.16, col="6f8cab", soup="e8b46a")       # суп в центре
    P.mug(S, Mt, 0.75, 0.55, z, "e8d0b0")
    P.mug(S, Mt, 1.3, 0.45, z, "a8c4e0")
    cloth = S.b("prop_table_runner", Mt["linen"], tile=0.32, bevel=0.002)
    cloth.box((1.0, 0.5, z + 0.002), (1.4, 0.3, 0.004), hexc("f0e2d0"))
    P.pendant(S, Mt, 1.0, 0.5, H, "lamp_table", drop=0.85)
    # ---- кухня у северной стены справа + холодильник
    P.kitchen(S, Mt, P.wall(3.45, Y1, math.pi), L=2.9)
    P.fridge(S, Mt, X1 - 0.38, 2.0, math.pi / 2)
    # ---- гостиная: диван у южной стены, ковёр, низкий столик, книжный шкаф, торшер, растение
    P.sofa(S, Mt, -2.5, Y0 + 0.5, 0.0, w=2.2, color="8fa6b8")
    P.rug(S, Mt, -2.5, -1.6, 3.0, 1.9, kind="rugrose")
    P.table(S, Mt, -2.5, -1.55, 0.0, w=1.0, d=0.55, h=0.42, wood="dark")
    P.mug(S, Mt, -2.7, -1.5, 0.42, "d8d0c0")
    bk = S.b("prop_books", Mt["fabric"], bevel=0.002)
    for j in range(3):
        bk.box((-2.25, -1.6, 0.42 + j * 0.03), (0.22, 0.16, 0.028), hexc(("c86a6a", "2a4a5a", "e8c48a")[j]))
    P.bookcase(S, Mt, -0.75, Y0 + 0.17, 0.0, w=0.9, h=1.8)
    P.torchiere(S, Mt, -4.4, Y0 + 0.4, "lamp_living")
    P.plant(S, Mt, -4.5, -1.2, 0.0, 1.1)
    # ---- стены: часы, семейные фото, календарь
    P.clock(S, Mt, P.wall(2.6, Y0, 0.0), 0.0, 1.9)
    P.framed(S, Mt, K.M("photo_family", "kid_family"), P.wall(1.0, Y0, 0.0), 0.0, 1.35, 0.6, 0.42, frame="2a2420")
    cal = S.b("prop_papers", Mt["paper"], tile=0.24)
    cal.box((3.6, Y0 + 0.01, 1.3), (0.34, 0.01, 0.46), (1, 1, 1, 1))
    # ---- уголок Кота: низкий столик, листы, мелки, рисунки на стене
    P.desk(S, Mt, -3.9, 3.0, math.pi, w=1.3, d=0.6, h=0.5)
    pap = S.b("prop_papers", Mt["paper"], tile=0.24)
    for i in range(7):
        pap.box((-4.45 + i * 0.17, 2.95 + rnd.uniform(-0.12, 0.12), 0.5), (0.21, 0.29, 0.004), (1, 1, 1, 1), rz=rnd.uniform(-0.5, 0.5))
    cr = S.b("prop_crayons", Mt["fabric"], bevel=0.002)
    for i, col in enumerate(("d84a3e", "f0b840", "4d9a5a", "3a74b8", "c49ac0", "e88f6a", "6fb1c0", "333333")):
        cr.box((-3.45 + i * 0.045, 2.85, 0.505), (0.03, 0.12, 0.03), hexc(col), rz=0.2)
    cush = S.b("prop_floor_cushion", Mt["cushion"], smooth=True)
    cush.cushion((-3.9, 2.35, 0.0), (0.5, 0.5, 0.12), hexc("e8c48a"), puff=0.5, rnd=rnd)
    kw = P.wall(-3.9, Y1, math.pi)
    for i, subj in enumerate(("sun_house", "cat", "family", "sea")):
        mat = K.M("kid_" + subj, "kid_" + subj)
        x = -0.75 + (i % 2) * 0.62 + (i // 2) * 0.12
        zz = 1.0 + (i // 2) * 0.5
        P.vquad(S.b("art_kid_" + subj, mat), kw, x, 0.012, zz, 0.42, 0.3, (1, 1, 1, 1), face=1)
        tape = S.b("prop_tape", Mt["linen"])
        kw.box(tape, (x, 0.016, zz + 0.28), (0.1, 0.004, 0.04), hexc("f3e6b0"))
    P.table_lamp(S, Mt, -4.4, 3.2, 0.5, "lamp_desk")
    # ---- свет по состояниям: дневная подсветка у окон, луна ночью, тёплый общий свет вечером — лампы
    S.marker("fill_north", (-0.6, 2.2, 1.8))
    S.marker("fill_east", (4.0, 1.2, 1.8))
    S.marker("moon_north", (-0.6, 2.4, 1.6))
    # ---- вид из окна снаружи (соседние дома, без столкновений) — для камеры сверху
    yard = S.b("yard", Mt["grass"], tile=0.64)
    yard.box((0, 8, -0.2), (30, 9, 0.1), (1, 1, 1, 1), grad=1.0)
    # ---- точки сцены (те же имена, что в data/story/prologue.json)
    S.marker("spawn", (-2.8, -1.2, 0.0), face=(1, 0.3))
    S.marker("npc_mama", (3.2, 2.6, 0.0), face=(-0.6, -1))
    S.marker("npc_papa", (2.25, 0.5, 0.0), face=(-1, 0))
    S.marker("npc_sora", (1.5, 1.3, 0.0), face=(0, -1))
    S.marker("npc_gabi", (1.5, -0.3, 0.0), face=(0, 1))
    S.marker("int_family_table", (0.5, -0.4, 0.0), face=(0, 1))
    S.marker("int_window", (-0.6, 2.9, 0.0), face=(0, 1))
    S.marker("int_sketch_corner", (-3.9, 2.0, 0.0), face=(0, 1))
    S.export(out_path("family_home"))
