"""Причёска из крупных прядей-оболочек — метод игровых аниме-моделей (изучено: docs/MODEL_STUDY.md, раздел «Видео»):

• 2AM (стиль Zenless Zone Zero): волосы — немного крупных частей; каждая прядь — «плоскость», вытянутая назад
  и чуть уменьшенная → тонкая замкнутая оболочка: чистый силуэт, внутренний тёмный край («мини-контур») и
  контур инвертированной оболочкой работают сами;
• SunnyIsOnline / Bran Sculpts: прядь — кривая с сечением-«треугольником» (заострённая), сужается к концу,
  пряди раскладываются слоями вокруг головы; под ними — «шлем» цвета волос, чтобы не было просветов;
• Vertex Arcade (модель Wuthering Waves): толщина контура задаётся по вершинам — у кончиков и чёлки тоньше.

Сечение пряди — линза: лицевая сторона выпуклая, тыльная — ближе к оси; тыльная сторона и нижний край темнее
(цвет тени в вершинах). Цвет — по длине пряди (корни → кончики) и по высоте. В альфе цвета вершины — толщина
контура (1 — обычная, у кончиков тоньше). UV: u — поперёк пряди, v — вдоль (для блика «нимба» в шейдере).
"""
import math
import random

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def _lerp(a, b, t):
    return a + (b - a) * t


def _mix(c0, c1, t):
    return tuple(_lerp(c0[i], c1[i], t) for i in range(3))


def _smooth(pts, n):
    """Ломаная → гладкая (Catmull-Rom) из n точек."""
    P = [pts[0]] + list(pts) + [pts[-1]]
    seg = len(pts) - 1
    out = []
    for k in range(n):
        t = k / (n - 1) * seg
        i = min(int(t), seg - 1)
        u = t - i
        p0, p1, p2, p3 = P[i], P[i + 1], P[i + 2], P[i + 3]
        u2, u3 = u * u, u * u * u
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (-p0 + 3 * p1 - 3 * p2 + p3) * u3))
    return out


class HeadShape:
    """Голова: эллипсоид (rx, ry, rz) с центром (0, 0, cz) и настоящая поверхность (BVH) — для корней прядей."""

    def __init__(self, head_obj, hd):
        self.rx, self.ry, self.rz, self.cz = hd
        deps = bpy.context.evaluated_depsgraph_get()
        self.bvh = BVHTree.FromObject(head_obj, deps)
        self.c = Vector((0, 0, self.cz))

    def dir(self, theta, phi):
        """Направление от центра: theta — азимут (0 — вперёд, −Y; + — к левому плечу героя, +X), phi — от макушки."""
        return Vector((math.sin(phi) * math.sin(theta), -math.sin(phi) * math.cos(theta), math.cos(phi)))

    def surface(self, theta, phi, lift=0.0):
        """Точка на коже по направлению (theta, phi) + отступ наружу lift (м)."""
        d = self.dir(theta, phi)
        far = self.c + Vector((d.x * self.rx, d.y * self.ry, d.z * self.rz)) * 2.0
        hit = self.bvh.ray_cast(far, -d.normalized())
        p = hit[0] if hit[0] is not None else self.c + Vector((d.x * self.rx, d.y * self.ry, d.z * self.rz))
        n = (p - self.c).normalized()
        return p + n * lift, n

    def push_out(self, p, min_gap):
        """Не дать точке уйти под кожу: если ближе min_gap к поверхности — отодвинуть наружу."""
        loc, nrm, _i, dist = self.bvh.find_nearest(p)
        if loc is None:
            return p
        out = (p - loc)
        inside = out.dot(nrm) < 0
        if inside or dist < min_gap:
            return loc + nrm * min_gap
        return p


def lock_spine(H, spec, rnd):
    """Ось пряди: от корня по «оболочке» причёски вниз, затем свободно свисает; конец — завиток (curl)."""
    th0 = spec["theta"]
    ph0 = spec["phi0"]
    ph1 = spec["phi1"]
    lift0, lift1 = spec.get("lift", (0.006, 0.03))
    sway = spec.get("sway", 0.0)
    pts = []
    n = 9
    for k in range(n):
        t = k / (n - 1)
        th = th0 + sway * t * t
        ph = _lerp(ph0, ph1, t)
        p, nrm = H.surface(th, ph, _lerp(lift0, lift1, math.sin(t * math.pi * 0.5)))
        pts.append(p)
    # свисающая часть: от последней точки вниз (и чуть наружу)
    drop = spec.get("drop", 0.0)
    if drop > 0:
        last = pts[-1]
        out = (last - H.c)
        out.z = 0
        out = out.normalized() if out.length > 1e-6 else Vector((0, -1, 0))
        for k in range(1, 4):
            t = k / 3
            pts.append(last + Vector((0, 0, -drop * t)) + out * spec.get("flare", 0.01) * t)
    pts = _smooth([Vector(p) for p in pts], spec.get("rings", 22))
    # завиток: последние curl_frac длины закручиваются наружу вокруг оси «вбок»
    curl = spec.get("curl", 0.0)
    if curl:
        frac = spec.get("curl_frac", 0.3)
        k0 = int(len(pts) * (1 - frac))
        base = pts[k0]
        tan = (pts[k0] - pts[k0 - 1]).normalized()
        out = (base - H.c)
        out = (out - tan * out.dot(tan)).normalized()
        side = tan.cross(out).normalized() * spec.get("curl_dir", 1)
        seg = sum((pts[i + 1] - pts[i]).length for i in range(k0, len(pts) - 1))
        r = min(seg / max(0.5, math.radians(abs(curl))) * 1.2, spec["w"] * spec.get("curl_r", 1.3))
        if curl < 0:
            out = -out                      # завиток под себя, к голове
        m = len(pts) - k0
        for i in range(m):
            a = math.radians(abs(curl)) * i / max(1, m - 1)
            rr = r * (1 - 0.35 * i / max(1, m - 1))
            # окружность: начинается вдоль tan, загибается наружу (out) и вверх
            pts[k0 + i] = base + tan * (math.sin(a) * rr) + out * ((1 - math.cos(a)) * rr)
    return pts


def lock_mesh(name, H, pts, spec, colors, mat):
    """Прядь-оболочка вдоль оси pts. Ширина: корень w0 → середина w → кончик 0 (заострённый, «треугольник»)."""
    w_root, w_mid = spec.get("w0", spec["w"] * 0.7), spec["w"]
    thick = spec.get("thick", 0.35)            # толщина оболочки — доля ширины
    bulge = spec.get("bulge", 0.35)
    taper = spec.get("taper", 0.75)            # где начинается сужение к кончику
    U = 7
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rows = []
    n = len(pts)
    c_root, c_tip, c_shadow = colors
    lift_dir = None
    for i, p in enumerate(pts):
        t = i / (n - 1)
        tan = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        out = (p - H.c)
        out = (out - tan * out.dot(tan))
        if out.length < 1e-6:
            out = lift_dir or Vector((0, -1, 0))
        out.normalize()
        # для завитка ориентация не должна резко переворачиваться
        if lift_dir is not None and out.dot(lift_dir) < 0:
            out = -out
        lift_dir = out
        side = tan.cross(out).normalized()
        if t < 0.2:
            w = _lerp(w_root, w_mid, t / 0.2)
        elif t < taper:
            w = w_mid
        else:
            k = (t - taper) / (1 - taper)
            w = w_mid * (1 - k) ** 1.4
        w = max(w, 0.0004)
        ring = []
        # лицевая сторона: u от −1 до 1, выпукло наружу
        for j in range(U):
            u = -1 + 2 * j / (U - 1)
            ring.append((p + side * (u * w) + out * (bulge * (1 - u * u) * w * 0.5), u, 0))
        # тыльная сторона: обратно, ближе к оси и чуть уже
        for j in range(U - 2, 0, -1):
            u = -1 + 2 * j / (U - 1)
            ring.append((p + side * (u * w * 0.86) - out * (thick * w * (1 - 0.5 * u * u)), u, 1))
        rows.append([(bm.verts.new(H.push_out(q, 0.002) if t < 0.85 else q), u, back) for q, u, back in ring])
    bm.verts.ensure_lookup_table()
    col = bm.loops.layers.color.new("Col")
    uvl = bm.loops.layers.uv.new("UVMap")
    R = len(rows[0])
    for i in range(n - 1):
        t0, t1 = i / (n - 1), (i + 1) / (n - 1)
        for j in range(R):
            a, b = rows[i][j], rows[i][(j + 1) % R]
            c, d = rows[i + 1][(j + 1) % R], rows[i + 1][j]
            try:
                f = bm.faces.new((a[0], b[0], c[0], d[0]))
            except ValueError:
                continue
            for loop, (vv, uu, back), tt in zip(f.loops, (a, b, c, d), (t0, t0, t1, t1)):
                # цвет: корни → кончики; тыльная сторона и самый корень — цвет тени
                zn = (vv.co.z - H.cz) / H.rz          # +1 макушка … −1 подбородок
                base = _mix(c_root, c_tip, max(0.0, min(1.0, (0.35 - zn) / 1.25)) ** 1.3)
                if back:
                    base = _mix(base, c_shadow, 0.65)
                if tt < 0.08:
                    base = _mix(base, c_shadow, 0.5 * (1 - tt / 0.08))
                # альфа — толщина контура: к кончику тоньше
                aw = 1.0 if tt < 0.7 else max(0.25, 1.0 - (tt - 0.7) / 0.3 * 0.75)
                loop[col] = (base[0], base[1], base[2], aw)
                loop[uvl].uv = ((uu + 1) * 0.5, tt)
    # крышка у корня (под другими прядями её не видно, но оболочка замкнута — контур не «дырявый»)
    try:
        f = bm.faces.new([r[0] for r in reversed(rows[0])])
        for loop in f.loops:
            loop[col] = (*c_shadow, 1.0)
    except ValueError:
        pass
    # оболочка замкнута — нормали наружу (иначе видна изнанка: тёмная тыльная сторона вместо лицевой)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    me.materials.append(mat)
    for poly in me.polygons:
        poly.use_smooth = True
    return obj


def hair_cap(head_obj, H, hp, colors, mat):
    """«Шлем» под прядями: копия головы без лица, отодвинутая наружу; цвет — тень волос (просветы не светлые)."""
    rx, ry, rz, cz = H.rx, H.ry, H.rz, H.cz
    me = head_obj.data.copy()
    cap = bpy.data.objects.new("hair_cap", me)
    bpy.context.scene.collection.objects.link(cap)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    hl, nape = hp.get("cap_hairline", hp.get("hairline", 0.3)), hp.get("nape", 0.9)
    face_x = hp.get("face_open_x", 0.7) * rx
    kill = [v for v in bm.verts if (v.co.y < -0.05 * ry and v.co.z < cz + rz * hl and
                                    (abs(v.co.x) < face_x or v.co.y < -0.75 * ry)) or v.co.z < cz - rz * nape]
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    smooth_boundary(bm)
    for v in bm.verts:
        v.co += v.normal * hp.get("cap_lift", 0.006)
    col = bm.loops.layers.color.new("Col")
    c_root, c_tip, c_shadow = colors
    for f in bm.faces:
        for loop in f.loops:
            # шлем — цвет волос чуть темнее (в просветах между прядями — «глубина», а не чёрная дыра);
            # у шлема контура нет (альфа 0): его всегда закрывают пряди
            z = (loop.vert.co.z - cz) / rz
            base = _mix(c_tip, c_root, max(0.0, min(1.0, (z + 0.6) / 1.4)))
            loop[col] = (*_mix(base, c_shadow, 0.3), 0.0)
    bm.to_mesh(me)
    bm.free()
    me.materials.clear()
    me.materials.append(mat)
    return cap


def smooth_boundary(bm, iters=10, k=0.55, clamp=0.01):
    """Край после удаления вершин — «лесенка» по рёбрам сетки (на затылке и висках шлема видна ступеньками):
    сглаживаем петлю края, не дальше clamp от исходного положения, и подтягиваем за ней соседний ряд."""
    bnd = [v for v in bm.verts if v.is_boundary]
    nb = {v: [e.other_vert(v) for e in v.link_edges if e.is_boundary] for v in bnd}
    start = {v: v.co.copy() for v in bnd}
    for _ in range(iters):
        new = {v: v.co.lerp((a[0].co + a[1].co) * 0.5, k) for v, a in nb.items() if len(a) == 2}
        for v, co in new.items():
            d = co - start[v]
            v.co = start[v] + d * min(1.0, clamp / max(d.length, 1e-9))
    ring = {e.other_vert(v) for v in bnd for e in v.link_edges} - set(bnd)
    for _ in range(2):
        new = {v: v.co.lerp(sum((e.other_vert(v).co for e in v.link_edges), Vector()) / len(v.link_edges), 0.5)
               for v in ring}
        for v, co in new.items():
            v.co = co
    bm.normal_update()


def kot_locks(H):
    """Раскладка прядей Кота (реф. 16): мятная макушка; прямая острая чёлка до глаз (над повязкой — длиннее);
    по бокам и сзади — широкие кудрявые пряди: от макушки вниз и наружу (объём растёт к щекам), концы
    подкручены наружу тугим завитком; силуэт «грибом» шире головы, к подбородку сужается."""
    L = []
    # чёлка: от передней части макушки до глаз; заострённые, разобраны веером, концы чуть внутрь
    for k, th in enumerate((-0.7, -0.5, -0.32, -0.15, 0.0, 0.16, 0.33, 0.5, 0.68)):
        over_patch = 0.15 <= th <= 0.55        # левый глаз героя (+X) под повязкой — чёлка длиннее
        L.append({"theta": th * 0.55, "phi0": 0.12, "phi1": 1.52 if over_patch else 1.36, "sway": th * 0.55,
                  "lift": (0.012, 0.03), "w": 0.034, "w0": 0.026, "thick": 0.32, "taper": 0.5, "rings": 22,
                  "bulge": 0.4})
    # макушка: веер от вихра назад и вбок
    for k in range(12):
        th = math.pi * (0.32 + 1.36 * k / 11)
        L.append({"theta": th, "phi0": 0.04, "phi1": 0.85, "sway": 0.2, "lift": (0.012, 0.035), "w": 0.06, "w0": 0.04,
                  "thick": 0.32, "taper": 0.72, "rings": 20})
    # бока и затылок: два ряда широких прядей; объём растёт к щекам, концы — тугой завиток наружу
    rows = ((0.42, 1.5, 17, 0.046, (0.02, 0.055)), (0.8, 1.78, 19, 0.04, (0.028, 0.06)), (1.2, 1.95, 15, 0.034, (0.03, 0.05)))
    for row, (ph0, ph1, n, w, lift) in enumerate(rows):
        for k in range(n):
            th = math.pi * (0.3 + (2 - 0.6) * (k + 0.37 * row) / n)
            if math.cos(th) > 0.6:             # спереди — открытое лицо
                continue
            var = ((k * 7 + row * 3) % 5) / 4.0            # детерминированный разброс длины и завитка
            L.append({"theta": th, "phi0": ph0, "phi1": ph1 + 0.12 * (var - 0.5), "sway": 0.12 * (1 if k % 2 else -1),
                      "lift": lift, "w": w, "w0": w * 0.65, "thick": 0.45, "drop": 0.01 + 0.015 * var, "flare": 0.01,
                      "taper": 0.62, "rings": 26, "bulge": 0.5,
                      # верхний ряд кончиками уходит под нижние (без завитка), нижние ряды — завиток наружу по краю
                      "curl": 0 if row == 0 else 220 + 90 * var, "curl_frac": 0.34, "curl_r": 0.95,
                      "curl_dir": 1 if (k + row) % 2 else -1})
    # височные пряди обрамляют лицо до щёк, кончик подкручен к лицу
    for side in (-1, 1):
        L.append({"theta": side * 1.0, "phi0": 0.4, "phi1": 1.6, "sway": -side * 0.1, "lift": (0.014, 0.025),
                  "w": 0.036, "w0": 0.026, "thick": 0.35, "drop": 0.02, "taper": 0.6, "rings": 22,
                  "curl": 120, "curl_frac": 0.25, "curl_r": 0.9, "curl_dir": side})
    return L


def style_locks(H, style, hp):
    """Универсальные причёски NPC и семьи: short — короткая (чёлка до середины лба, виски, затылок до шеи),
    bob — каре до челюсти (чёлка до бровей, концы чуть внутрь), long — длинные распущенные до лопаток."""
    L = []
    part = hp.get("part", 0.25)                # куда разобрана чёлка (−1…1: влево/вправо)
    bang_to = {"short": 1.05, "bob": 1.33, "long": 1.3}[style]
    n_bang = 7 if style == "short" else 9
    for k in range(n_bang):
        th = -0.75 + 1.5 * k / (n_bang - 1)
        # концы чёлки разной длины и формы (острые и «рубленые»), иначе ровный ряд одинаковых зубцов
        # читался расчёской (docs/MODEL_STUDY.md «Видео»: split faces → chopped/pointy ends)
        var = ((k * 5 + 2) % 7) / 6.0
        L.append({"theta": th * 0.5 + part * 0.15, "phi0": 0.14,
                  "phi1": bang_to - 0.08 * abs(th - part * 0.5) + 0.07 * (var - 0.5),
                  "sway": (th - part) * 0.45, "lift": (0.01, 0.025),
                  "w": (0.036 if style != "short" else 0.04) * (0.9 + 0.25 * var),
                  "w0": 0.027, "thick": 0.3, "taper": 0.62 if k % 3 else 0.8, "rings": 20, "bulge": 0.4})
    # макушка: веер от вихра назад и вбок
    for k in range(12):
        th = math.pi * (0.32 + 1.36 * k / 11)
        L.append({"theta": th, "phi0": 0.04, "phi1": 0.9 if style == "short" else 0.95, "sway": 0.15,
                  "lift": (0.01, 0.028 if style == "short" else 0.035), "w": 0.06, "w0": 0.04, "thick": 0.3,
                  "taper": 0.72, "rings": 18})
    # бока и затылок
    if style == "short":
        rows = ((0.5, 1.45, 14, 0.05, (0.014, 0.03), 0.0), (0.9, 1.75, 14, 0.042, (0.012, 0.022), 0.0))
    elif style == "bob":
        rows = ((0.45, 1.6, 15, 0.055, (0.018, 0.045), 0.02), (0.85, 1.95, 16, 0.046, (0.02, 0.045), 0.03))
    else:
        rows = ((0.45, 1.65, 15, 0.055, (0.016, 0.04), 0.18), (0.85, 1.95, 17, 0.048, (0.018, 0.04), 0.24))
    for row, (ph0, ph1, n, w, lift, drop) in enumerate(rows):
        for k in range(n):
            th = math.pi * (0.3 + (2 - 0.6) * (k + 0.4 * row) / n)
            if math.cos(th) > 0.62:
                continue
            var = ((k * 7 + row * 3) % 5) / 4.0
            spec = {"theta": th, "phi0": ph0, "phi1": ph1 + 0.08 * (var - 0.5), "sway": 0.08 * (1 if k % 2 else -1),
                    "lift": lift, "w": w, "w0": w * 0.65, "thick": 0.4, "drop": drop * (0.85 + 0.3 * var),
                    "flare": 0.012 if style != "long" else 0.02, "taper": 0.7 if style == "short" else 0.82,
                    "rings": 24 if style == "long" else 20, "bulge": 0.45}
            if style == "bob":
                spec.update({"curl": -70, "curl_frac": 0.2, "curl_r": 1.2})      # концы каре — чуть внутрь
            L.append(spec)
    # пряди у лица: у короткой — височки до уха, у каре и длинных — обрамляют лицо
    for side in (-1, 1):
        if style == "short":
            L.append({"theta": side * 1.2, "phi0": 0.5, "phi1": 1.55, "sway": 0.0, "lift": (0.01, 0.014), "w": 0.03,
                      "w0": 0.024, "thick": 0.3, "taper": 0.55, "rings": 16})
        else:
            L.append({"theta": side * 0.98, "phi0": 0.35, "phi1": 1.65, "sway": -side * 0.1, "lift": (0.014, 0.022),
                      "w": 0.034, "w0": 0.026, "thick": 0.35, "taper": 0.6, "rings": 22,
                      "drop": 0.04 if style == "bob" else 0.22, "flare": 0.006})
    return L


LAYOUTS = {"kot": kot_locks, "kot_child": kot_locks}


def build_hair_clumps(cid, head_obj, hd, hp, mat_hair, mat_cap):
    """Собрать причёску: шлем + пряди по раскладке персонажа. Возвращает список объектов."""
    H = HeadShape(head_obj, hd)
    rnd = random.Random(sum(map(ord, cid)) + 7)
    c_root = tuple(hp.get("c_lock_root", hp.get("c_root", (0.56, 0.86, 0.78))))
    c_tip = tuple(hp.get("c_lock_tip", hp.get("c_tip", (0.42, 0.55, 0.86))))
    c_shadow = tuple(hp.get("c_shadow", (c_tip[0] * 0.72, c_tip[1] * 0.76, c_tip[2] * 0.9)))
    colors = (c_root, c_tip, c_shadow)
    objs = [hair_cap(head_obj, H, hp, colors, mat_cap)]
    style = hp.get("clump_style")
    specs = style_locks(H, style, hp) if style else LAYOUTS[cid](H)
    for i, spec in enumerate(specs):
        spec = dict(spec)
        spec["w"] *= rnd.uniform(0.9, 1.12)
        pts = lock_spine(H, spec, rnd)
        objs.append(lock_mesh("hair_lock_%02d" % i, H, pts, spec, colors, mat_hair))
    if hp.get("ahoge_spiral") or hp.get("ahoge"):
        objs.append(ahoge(H, hp, colors, mat_hair, spiral=bool(hp.get("ahoge_spiral"))))
    for side in hp.get("buns", []):
        objs += bun(H, side, colors, mat_hair)
    if hp.get("ponytail"):
        objs += ponytail(H, hp, colors, mat_hair)
    return objs


def bun(H, side, colors, mat):
    """Пучок сбоку на затылке: несколько прядей-дуг, намотанных вокруг центра в разных плоскостях."""
    p0, n0 = H.surface(side * 1.95, 0.62, 0.0)
    r = H.rx * 0.36
    c = p0 + n0 * (r * 0.75)
    out = []
    c_root, c_tip, c_shadow = colors
    for k in range(6):
        a0 = k * math.pi / 6
        ax1 = Vector((math.cos(a0), math.sin(a0) * 0.6, math.sin(a0) * 0.8)).normalized()
        ax2 = n0.cross(ax1).normalized()
        if ax2.length < 0.1:
            ax2 = Vector((0, 0, 1))
        pts = [c + (ax1 * math.cos(t) + ax2 * math.sin(t)) * r * (1 - 0.15 * math.sin(t * 0.5))
               for t in (2 * math.pi * 0.85 * i / 20 for i in range(21))]
        spec = {"w": r * 0.55, "w0": r * 0.5, "thick": 0.5, "taper": 0.85, "bulge": 0.5}
        mid = _mix(c_root, c_tip, 0.4)
        out.append(lock_mesh("hair_bun_%d_%d" % (side, k), H, pts, spec, (mid, c_tip, c_shadow), mat))
    return out


def ponytail(H, hp, colors, mat):
    """Хвост как у ZZZ-моделей (docs/MODEL_STUDY.md «Видео»): один объёмный ствол овального сечения — не веер
    тонких прядей (читался «расчёской») — и три накладные пряди по нему; кончики расходятся двумя-тремя
    остриями."""
    g, n = H.surface(math.pi, 0.95, 0.02)
    length = H.rz * hp.get("ponytail_len", 2.2)

    def spine(dx, dn, scale):
        pts = [g + n * 0.01 + Vector((dx * 0.3, 0, 0))]
        for i in range(1, 9):
            t = i / 8
            pts.append(g + n * (0.03 + dn + 0.04 * math.sin(t * math.pi)) + Vector((dx * (0.3 + 0.7 * t), 0.0, -length * scale * t)))
        return _smooth(pts, 24)
    out = [lock_mesh("hair_tail_0", H, spine(0.0, 0.0, 1.0),
                     {"w": H.rx * 0.3, "w0": H.rx * 0.2, "thick": 0.95, "taper": 0.62, "bulge": 0.9}, colors, mat)]
    for k, (dx, sc) in enumerate(((-0.022, 0.9), (0.0, 1.06), (0.024, 0.95))):
        out.append(lock_mesh("hair_tail_%d" % (k + 1), H, spine(dx, 0.012, sc),
                             {"w": H.rx * 0.17, "w0": H.rx * 0.12, "thick": 0.5, "taper": 0.55, "bulge": 0.6}, colors, mat))
    return out


def ahoge(H, hp, colors, mat, spiral=True):
    """Хохолок: спираль (Кот, реф. 16) — вверх и завиток колечком; иначе — одна прядь дугой вверх-вперёд."""
    base, n = H.surface(0.0, 0.12, 0.02)
    h = H.rz * hp.get("ahoge_h", 0.5)
    pts = [base + n * (h * k / 6) for k in range(7)]
    top = pts[-1]
    if not spiral:
        pts = _smooth([base, base + n * h * 0.5, top + Vector((0, -h * 0.25, h * 0.15)), top + Vector((0, -h * 0.55, -h * 0.05))], 18)
        spec = {"w": H.rx * 0.1, "w0": H.rx * 0.12, "thick": 0.5, "taper": 0.5, "bulge": 0.3}
        c_root, _c_tip, c_shadow = colors
        return lock_mesh("hair_ahoge", H, pts, spec, (c_root, c_root, c_shadow), mat)
    r0 = H.rx * 0.22
    c0 = top + Vector((r0, 0, 0))
    for k in range(1, 22):
        a = math.pi - k / 21 * 2 * math.pi * 1.25
        rr = r0 * (1 - 0.55 * k / 21)
        pts.append(c0 + Vector((math.cos(a) * rr, -0.0005 * k, math.sin(a) * rr)))
    pts = _smooth(pts, 30)
    spec = {"w": H.rx * 0.11, "w0": H.rx * 0.12, "thick": 0.6, "taper": 0.7, "bulge": 0.3}
    c_root, _c_tip, c_shadow = colors
    return lock_mesh("hair_ahoge", H, pts, spec, (c_root, c_root, c_shadow), mat)
