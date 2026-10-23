"""Общие части локаций: комнаты (стены с проёмами, плинтусы, карнизы, потолок), вода, экспорт."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import lockit as K  # noqa: E402
from lockit import hexc, shade  # noqa: E402
from lockit_props import Frame  # noqa: E402

OUT = os.path.join(K.ROOT, "art", "locations")


def room(S, Mt, X0, X1, Y0, Y1, H, wall="paint_warm", holes=None, floor="planks", ceiling="paint_ceiling",
         skirt="oak", crown=True, floor_tile=1.28, wall_tile=0.64):
    """Коробка комнаты: пол (столкновения), четыре стены с проёмами (столкновения), плинтус, карниз, потолок
    (без столкновений и без теней — имя ceiling). holes = {"-y"|"+y"|"-x"|"+x": [(u0, u1, z0, z1), ...]}
    — u вдоль стены (x для стен ±y, y для стен ±x)."""
    holes = holes or {}
    fl = S.b("floor-col", Mt[floor], tile=floor_tile)
    fl.box(((X0 + X1) / 2, (Y0 + Y1) / 2, -0.1), (X1 - X0 + 0.4, Y1 - Y0 + 0.4, 0.1), (1, 1, 1, 1), grad=1.0)
    wb = S.b("room_walls-col", Mt[wall], tile=wall_tile)
    t = 0.16
    sides = {"-y": (X0, X1, Y0 - t / 2), "+y": (X0, X1, Y1 + t / 2), "-x": (Y0, Y1, X0 - t / 2), "+x": (Y0, Y1, X1 + t / 2)}
    sk = S.b("prop_skirting", Mt[skirt], tile=0.32, bevel=0.004)
    for side, (a, b, k) in sides.items():
        cuts = sorted(holes.get(side, []))
        u = a - (t if side in ("-y", "+y") else 0)
        end = b + (t if side in ("-y", "+y") else 0)
        for h0, h1, z0, z1 in cuts:
            _piece(wb, side, k, u, h0, 0, H, t)
            _piece(wb, side, k, h0, h1, 0, z0, t)
            _piece(wb, side, k, h0, h1, z1, H, t)
            u = h1
        _piece(wb, side, k, u, end, 0, H, t)
        # плинтус и карниз — по внутренней стороне, с разрывами у дверей
        inner = k + (t / 2 + 0.008) * (1 if side in ("-y", "-x") else -1)
        u = a
        for h0, h1, z0, z1 in cuts + [(b, b, 0, 0)]:
            if z0 < 0.05:          # дверь — плинтус прерывается
                _piece(sk, side, inner, u, h0, 0, 0.09, 0.016, col=hexc("c8a07a"))
                u = h1
        if u < b:
            _piece(sk, side, inner, u, b, 0, 0.09, 0.016, col=hexc("c8a07a"))
        if crown:
            _piece(sk, side, inner, a, b, H - 0.06, H, 0.03, col=hexc("efe8dc"))
    if ceiling:
        ce = S.b("ceiling", Mt[ceiling], tile=0.64)
        ce.box(((X0 + X1) / 2, (Y0 + Y1) / 2, H), (X1 - X0 + 0.4, Y1 - Y0 + 0.4, 0.08), (1, 1, 1, 1), grad=1.0)


def _piece(b, side, k, u0, u1, z0, z1, t, col=(1, 1, 1, 1)):
    if u1 - u0 < 0.01 or z1 - z0 < 0.01:
        return
    if side in ("-y", "+y"):
        b.box(((u0 + u1) / 2, k, z0), (u1 - u0, t, z1 - z0), col, grad=0.96)
    else:
        b.box((k, (u0 + u1) / 2, z0), (t, u1 - u0, z1 - z0), col, grad=0.96)


def water(S, x0, x1, y0, y1, n=24):
    w = S.b("water", K.M("water"))
    for i in range(n):
        for j in range(n):
            xa, xb = x0 + (x1 - x0) * i / n, x0 + (x1 - x0) * (i + 1) / n
            ya, yb = y0 + (y1 - y0) * j / n, y0 + (y1 - y0) * (j + 1) / n
            w.quad([(xa, ya, 0), (xb, ya, 0), (xb, yb, 0), (xa, yb, 0)], hexc("6fb1c0"))


def finish_water(S, z):
    o = S.batches["water"].finish()
    o.location.z = z
    del S.batches["water"]


def out_path(name):
    os.makedirs(OUT, exist_ok=True)
    return os.path.join(OUT, name + ".glb")
