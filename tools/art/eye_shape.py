"""Форма глаза (прорезь век) — общая для текстуры лица (gen_faces.py) и геометрии глаза (build_characters.py).

Отношения и форма сняты с изученной модели-подростка (docs/MODEL_STUDY.md, «Глаза»): по границе прорези
лицевой маски, склере, радужке, ресницам, складке века и брови. Единица — U = расстояние центр глаза – подбородок.
Начало координат — центр радужки, x — к ВНЕШНЕМУ углу, z — вверх.
Чистый Python (без bpy/numpy): модуль импортируют и Blender, и генератор текстур.
"""
import math

# Верхнее веко: от внешнего угла к внутреннему — пологая дуга, внешний угол на высоте центра радужки.
UPPER = [(0.242, -0.001), (0.221, 0.034), (0.193, 0.058), (0.154, 0.078), (0.103, 0.094), (0.041, 0.095),
         (-0.027, 0.087), (-0.096, 0.059), (-0.143, 0.028), (-0.162, -0.012)]
# Нижнее веко: от внутреннего угла к внешнему — почти прямое, ниже радужки (радужка им срезана).
LOWER = [(-0.149, -0.088), (-0.107, -0.14), (-0.021, -0.143), (0.071, -0.141), (0.134, -0.135), (0.179, -0.098),
         (0.215, -0.053)]
IRIS = (0.135, 0.152)          # полуоси радужки (x, z): 0.27 × 0.30 U — шире прорези по высоте
SCLERA = (-0.24, 0.28, -0.29, 0.2)   # склера (x0, x1, z0, z1) — с запасом за край прорези
BROW_Z = (0.2, 0.3)            # бровь над центром радужки
LASH_WING = 0.11               # «крыло» ресниц за внешним углом

# Формы глаза для сменных лиц (выражение + «немного форма глаз», просьба пользователя 24.10):
# (масштаб по x, масштаб по z, подъём внешнего угла на единицу x). Внешний угол — x > 0.
VARIANTS = {
    "default": (1.0, 1.0, 0.0),
    "round": (0.94, 1.24, -0.03),     # круглые, «милые»: выше, внешний угол ниже
    "sharp": (1.05, 0.76, 0.1),       # серьёзные: уже, внешний угол поднят
}


def _vt(p, variant):
    sx, sz, tilt = VARIANTS[variant]
    return (p[0] * sx, p[1] * sz + tilt * max(0.0, p[0]))


def _catmull(pts, n_per, closed):
    out = []
    m = len(pts)
    rng = range(m) if closed else range(m - 1)
    for i in rng:
        p0 = pts[(i - 1) % m] if closed else pts[max(i - 1, 0)]
        p1, p2 = pts[i], pts[(i + 1) % m]
        p3 = pts[(i + 2) % m] if closed else pts[min(i + 2, m - 1)]
        for k in range(n_per):
            t = k / n_per
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * (2 * p1[c] + (-p0[c] + p2[c]) * t + (2 * p0[c] - 5 * p1[c] + 4 * p2[c] - p3[c]) * t2
                                    + (-p0[c] + 3 * p1[c] - 3 * p2[c] + p3[c]) * t3) for c in (0, 1)))
    if not closed:
        out.append(pts[-1])
    return out


def contour(n_per=6, variant="default"):
    """Замкнутый гладкий контур прорези (в U): верхнее веко внешний→внутренний, затем нижнее."""
    return [_vt(p, variant) for p in _catmull(UPPER + LOWER, n_per, closed=True)]


def upper_lid(n_per=6, variant="default"):
    """Верхнее веко от ВНУТРЕННЕГО угла к внешнему (для ресниц и складки)."""
    return [_vt(p, variant) for p in _catmull(UPPER[::-1], n_per, closed=False)]


def lower_lid(n_per=6, variant="default"):
    """Нижнее веко от внутреннего угла к внешнему (внешний угол — общий с верхним)."""
    return [_vt(p, variant) for p in _catmull([UPPER[-1]] + LOWER + [UPPER[0]], n_per, closed=False)]


class Variant:
    """Тот же модуль, но с формой глаза variant (для build_characters: E.upper_lid(8) и т. п.)."""
    IRIS, SCLERA, BROW_Z, LASH_WING = IRIS, SCLERA, BROW_Z, LASH_WING

    def __init__(self, name="default"):
        self.name = name

    def contour(self, n_per=6):
        return contour(n_per, self.name)

    def upper_lid(self, n_per=6):
        return upper_lid(n_per, self.name)

    def lower_lid(self, n_per=6):
        return lower_lid(n_per, self.name)


def unit_m(fp):
    """U в метрах: центр глаза над подбородком по текущему eye_v (масштаб eye_shape.scale)."""
    es = fp["eye_shape"]
    return (2 - 2 * fp["eye_v"]) * es["head_rz"] * es.get("scale", 1.0)


def to_uv(p, fp, side, cu, cv):
    """Точка (в U) → UV текстуры лица (u вправо, v вниз); side — +1 глаз справа для зрителя."""
    es = fp["eye_shape"]
    um = unit_m(fp)
    return (cu + side * p[0] * um / (2 * es["head_rx"]), cv - p[1] * um / (2 * es["head_rz"]))


def ellipse(rx, rz, n=48):
    return [(rx * math.cos(2 * math.pi * i / n), rz * math.sin(2 * math.pi * i / n)) for i in range(n)]
