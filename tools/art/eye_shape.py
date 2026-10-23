"""Форма глаза (прорезь век) — общая для текстуры лица (gen_faces.py) и геометрии глаза (build_characters.py).

Контур снят по сетке с арта Кота (art/references/characters/16_kot_turnaround.jpg, портрет) и сверен
с Meshy-листом; построение глаза — как у изученной модели-подростка (docs/MODEL_STUDY.md): прорезь в лице,
за ней вогнутая склера, перед склерой выпуклая радужка, блики отдельно, ресницы — отдельной геометрией.

Координаты контура: в долях ширины глаза, начало — центр радужки, x — к ВНЕШНЕМУ углу, z — вверх.
Чистый Python (без bpy/numpy): модуль импортируют и Blender, и генератор текстур.
"""
import math

# Верхнее веко: от внешнего угла к внутреннему (пик дуги ближе к внутреннему углу, внешний угол чуть ниже).
# Внешняя половина сжата на 0.82: на арте за внешним углом — «крыло» ресниц, а не прорезь (сверено по
# ориентиру eye_vis_outer в 16_kot_landmarks.json).
_K = 0.82
UPPER = [(0.555 * _K, -0.024), (0.432 * _K, 0.111), (0.272 * _K, 0.21), (0.086 * _K, 0.259), (-0.099, 0.247), (-0.259, 0.197),
         (-0.381, 0.123), (-0.445, 0.038)]
# Нижнее веко: от внутреннего угла к внешнему (почти ровное, ниже радужки).
LOWER = [(-0.381, -0.038), (-0.283, -0.123), (-0.136, -0.186), (0.024, -0.21), (0.21 * _K, -0.186), (0.381 * _K, -0.111)]


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


def contour(n_per=8):
    """Замкнутый гладкий контур прорези (в долях ширины): верхнее веко внешний→внутренний, затем нижнее."""
    return _catmull(UPPER + LOWER, n_per, closed=True)


def upper_lid(n_per=8):
    """Только верхнее веко, от ВНУТРЕННЕГО угла к внешнему (для ресниц и складки)."""
    return _catmull(UPPER[::-1], n_per, closed=False)


def lower_lid(n_per=8):
    """Нижнее веко от внутреннего угла к внешнему (внешний угол — общий с верхним)."""
    return _catmull(LOWER + [UPPER[0]], n_per, closed=False)


def to_uv(p, es, side, cu, cv):
    """Точка контура (доли ширины) → UV текстуры лица (u вправо, v вниз).
    es — face_params[...]['eye_shape'] (width_m, head_rx, head_rz); side — +1 глаз справа для зрителя."""
    w = es["width_m"]
    return (cu + side * p[0] * w / (2 * es["head_rx"]), cv - p[1] * w / (2 * es["head_rz"]))


def scaled(pts, k):
    """Контур, раздутый от центра в k раз (запас под ресницы / край склеры)."""
    return [(x * k, z * k) for x, z in pts]


def iris_points(r, n=48):
    return [(r * math.cos(2 * math.pi * i / n), r * math.sin(2 * math.pi * i / n)) for i in range(n)]
