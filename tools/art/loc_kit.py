"""Набор для сборки локаций в Blender: геометрия копится «пачками» (один объект на материал/назначение),
цвет — в цвете вершин, точки сцены — пустые объекты.

Соглашения для игры (src/gameplay/story_location.gd):
  • «<имя>-col» — меш со столкновениями, «<имя>-colonly» — невидимая стена;
  • «water» — уровень воды (режиссёр поднимает его по сценарию), «water_*» — декоративная вода;
  • «prop_*» — мелкие предметы с контуром; материал «glow_*» — окна и фонари (светятся вечером и ночью);
  • точки: spawn*, npc_*, int_*, reach_*, lamp_* (источник света).
Направление точки: «вперёд» персонажа — локальная ось +Y пустого объекта в Blender (в Godot это −Z).
"""
import math
import random

import bpy
from mathutils import Matrix, Vector


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color=(1, 1, 1, 1), rough=0.85):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    vn = nt.nodes.new("ShaderNodeVertexColor")
    vn.layer_name = "Col"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    mix.inputs[6].default_value = color
    nt.links.new(vn.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    return m


def hexc(h, a=1.0):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)) + (a,)


def jitter(c, amt, rnd):
    k = 1 + (rnd.random() - 0.5) * 2 * amt
    return tuple(min(1.0, max(0.0, c[i] * k)) for i in range(3)) + (1.0,)


class Batch:
    """Набор граней одного объекта. Все примитивы добавляют вершины, грани и цвет вершин."""

    def __init__(self, name, mat_name="base", smooth=False):
        self.name, self.mat_name, self.smooth_default = name, mat_name, smooth
        self.v, self.f, self.c, self.s = [], [], [], []

    def face(self, pts, color, smooth=None):
        i0 = len(self.v)
        self.v.extend(pts)
        self.c.extend([color] * len(pts))
        self.f.append(list(range(i0, i0 + len(pts))))
        self.s.append(self.smooth_default if smooth is None else smooth)

    def box(self, c, size, color, rot=0.0, top=None, shade=0.9):
        """Параллелепипед: c — центр основания (x, y, z), size — (x, y, z). top — цвет верха, бока темнее снизу."""
        sx, sy, sz = size[0] / 2, size[1] / 2, size[2]
        co, si = math.cos(rot), math.sin(rot)

        def P(x, y, z):
            return (c[0] + x * co - y * si, c[1] + x * si + y * co, c[2] + z)
        b = [P(-sx, -sy, 0), P(sx, -sy, 0), P(sx, sy, 0), P(-sx, sy, 0)]
        t = [P(-sx, -sy, sz), P(sx, -sy, sz), P(sx, sy, sz), P(-sx, sy, sz)]
        low = tuple(color[i] * shade for i in range(3)) + (1.0,)
        self._quad_grad([b[0], b[1], t[1], t[0]], low, color)
        self._quad_grad([b[1], b[2], t[2], t[1]], low, color)
        self._quad_grad([b[2], b[3], t[3], t[2]], low, color)
        self._quad_grad([b[3], b[0], t[0], t[3]], low, color)
        self.face([t[0], t[1], t[2], t[3]], top or color, smooth=False)
        self.face([b[3], b[2], b[1], b[0]], low, smooth=False)

    def _quad_grad(self, q, low, high):
        i0 = len(self.v)
        self.v.extend(q)
        self.c.extend([low, low, high, high])
        self.f.append([i0, i0 + 1, i0 + 2, i0 + 3])
        self.s.append(False)

    def quad(self, pts, color):
        self.face(list(pts), color, smooth=False)

    def cyl(self, c, r, h, color, seg=12, r_top=None, smooth=True, caps=True, top_color=None):
        r_top = r if r_top is None else r_top
        ring_b = [(c[0] + r * math.cos(2 * math.pi * i / seg), c[1] + r * math.sin(2 * math.pi * i / seg), c[2]) for i in range(seg)]
        ring_t = [(c[0] + r_top * math.cos(2 * math.pi * i / seg), c[1] + r_top * math.sin(2 * math.pi * i / seg), c[2] + h) for i in range(seg)]
        i0 = len(self.v)
        self.v.extend(ring_b + ring_t)
        low = tuple(color[i] * 0.88 for i in range(3)) + (1.0,)
        self.c.extend([low] * seg + [color] * seg)
        for i in range(seg):
            j = (i + 1) % seg
            self.f.append([i0 + i, i0 + j, i0 + seg + j, i0 + seg + i])
            self.s.append(smooth)
        if caps:
            self.face(ring_t, top_color or color, smooth=False)
            self.face(ring_b[::-1], low, smooth=False)

    def blob(self, c, r, color, seg=10, rings=7, squash=1.0, rnd=None, wobble=0.0):
        """Сглаженный шар (кроны деревьев, кусты, сугробы)."""
        i0 = len(self.v)
        for j in range(rings + 1):
            th = math.pi * j / rings
            for i in range(seg):
                ph = 2 * math.pi * i / seg
                k = 1 + (rnd.uniform(-wobble, wobble) if rnd and 0 < j < rings else 0)
                self.v.append((c[0] + r * k * math.sin(th) * math.cos(ph), c[1] + r * k * math.sin(th) * math.sin(ph),
                               c[2] + r * squash * math.cos(th)))
                shade = 0.8 + 0.2 * (1 - j / rings)
                self.c.append(tuple(color[q] * shade for q in range(3)) + (1.0,))
        for j in range(rings):
            for i in range(seg):
                a = i0 + j * seg + i
                b = i0 + j * seg + (i + 1) % seg
                self.f.append([a, a + seg, b + seg, b])
                self.s.append(True)

    def prism_roof(self, x0, x1, y0, y1, z, h, color, along_x=True, overhang=0.3):
        """Двускатная крыша над прямоугольником."""
        x0 -= overhang; x1 += overhang; y0 -= overhang; y1 += overhang
        dark = tuple(color[i] * 0.85 for i in range(3)) + (1.0,)
        if along_x:
            ym = (y0 + y1) / 2
            self.quad([(x0, y0, z), (x1, y0, z), (x1, ym, z + h), (x0, ym, z + h)], color)
            self.quad([(x1, y1, z), (x0, y1, z), (x0, ym, z + h), (x1, ym, z + h)], dark)
            self.face([(x0, y1, z), (x0, y0, z), (x0, ym, z + h)], dark, smooth=False)
            self.face([(x1, y0, z), (x1, y1, z), (x1, ym, z + h)], dark, smooth=False)
        else:
            xm = (x0 + x1) / 2
            self.quad([(x1, y0, z), (x1, y1, z), (xm, y1, z + h), (xm, y0, z + h)], color)
            self.quad([(x0, y1, z), (x0, y0, z), (xm, y0, z + h), (xm, y1, z + h)], dark)
            self.face([(x0, y0, z), (x1, y0, z), (xm, y0, z + h)], dark, smooth=False)
            self.face([(x1, y1, z), (x0, y1, z), (xm, y1, z + h)], dark, smooth=False)

    def strip(self, pts_l, pts_r, color, thick=0.0, under=None):
        """Полоса между двумя ломаными (мост, дорожка, склон); thick — толщина вниз."""
        for i in range(len(pts_l) - 1):
            self.quad([pts_l[i], pts_r[i], pts_r[i + 1], pts_l[i + 1]], color)
        if thick > 0:
            dn = lambda p: (p[0], p[1], p[2] - thick)
            uc = under or tuple(color[i] * 0.8 for i in range(3)) + (1.0,)
            for i in range(len(pts_l) - 1):
                self.quad([dn(pts_l[i + 1]), dn(pts_r[i + 1]), dn(pts_r[i]), dn(pts_l[i])], uc)
                self.quad([pts_l[i + 1], dn(pts_l[i + 1]), dn(pts_l[i]), pts_l[i]], uc)
                self.quad([pts_r[i], dn(pts_r[i]), dn(pts_r[i + 1]), pts_r[i + 1]], uc)

    def finish(self):
        if not self.f:
            return None
        me = bpy.data.meshes.new(self.name)
        me.from_pydata(self.v, [], self.f)
        me.update()
        attr = me.color_attributes.new("Col", "BYTE_COLOR", "POINT")
        for i, col in enumerate(self.c):
            attr.data[i].color = col
        for p, sm in zip(me.polygons, self.s):
            p.use_smooth = sm
        me.materials.append(bpy.data.materials.get(self.mat_name) or material(self.mat_name))
        o = bpy.data.objects.new(self.name, me)
        bpy.context.collection.objects.link(o)
        return o


class Scene:
    """Пачки по имени + точки. finish() создаёт объекты; export() пишет glb."""

    def __init__(self, seed=1):
        self.batches = {}
        self.rnd = random.Random(seed)

    def b(self, name, mat_name="base", smooth=False):
        if name not in self.batches:
            self.batches[name] = Batch(name, mat_name, smooth)
        return self.batches[name]

    def marker(self, name, loc, face=(0, 1), up=None):
        """Пустой объект-точка. face — куда смотрит персонаж (x, y); up — для лежащих (вектор «к макушке»)."""
        o = bpy.data.objects.new(name, None)
        o.empty_display_type = "ARROWS"
        o.location = loc
        if up is None:
            o.rotation_euler = (0, 0, math.atan2(-face[0], face[1]))
        else:
            fy = Vector((face[0], face[1], face[2] if len(face) > 2 else 0)).normalized()
            uz = Vector(up).normalized()
            x = fy.cross(uz)
            o.matrix_world = Matrix.Translation(Vector(loc)) @ Matrix((x, fy, uz)).transposed().to_4x4()
        bpy.context.collection.objects.link(o)
        return o

    def export(self, path):
        for b in self.batches.values():
            b.finish()
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=True,
                                  export_extras=False)
        print("exported", path)


# ---------------------------------------------------------------- готовые детали

PASTELS = ["f3dccb", "f6e7c8", "d8e6d8", "e3d9ef", "f4cfd4", "dce7f1", "efe2d2", "f7d9b9"]
ROOFS = ["c98a74", "8ea2b8", "b07d86", "9a8fae", "c6a07a"]


def building(S, x0, x1, y0, y1, h, facade_dir, color=None, roof=None, gable=True, shop=None, floors_h=3.0,
             glow_batch="glow_windows", col=True, windows=True):
    """Дом: стены, ряды окон на фасаде (facade_dir: '+y'/'-y'/'+x'/'-x'), карниз, крыша; shop — витрина на 1-м этаже."""
    rnd = S.rnd
    c = hexc(color or rnd.choice(PASTELS))
    walls = S.b("buildings-col" if col else "buildings_far", "wall")
    walls.box(((x0 + x1) / 2, (y0 + y1) / 2, 0), (x1 - x0, y1 - y0, h), c, top=jitter(c, 0.1, rnd), shade=0.82)
    trim = tuple(min(1, c[i] * 1.08 + 0.05) for i in range(3)) + (1,)
    walls.box(((x0 + x1) / 2, (y0 + y1) / 2, h - 0.25), (x1 - x0 + 0.3, y1 - y0 + 0.3, 0.3), trim)
    rc = hexc(roof or rnd.choice(ROOFS))
    roofs = S.b("roofs", "roof")
    if gable:
        roofs.prism_roof(x0, x1, y0, y1, h, min(3.0, (y1 - y0) * 0.35), rc, along_x=facade_dir in ("+y", "-y"))
    if not windows:
        return
    glow = S.b(glow_batch, "glow_window")
    sill = S.b("sills", "wall")
    # фасад: (координата плоскости, ось вдоль, наружу)
    if facade_dir in ("+y", "-y"):
        plane = y1 if facade_dir == "+y" else y0
        out = 1 if facade_dir == "+y" else -1
        span = (x0, x1)
    else:
        plane = x1 if facade_dir == "+x" else x0
        out = 1 if facade_dir == "+x" else -1
        span = (y0, y1)
    n = max(1, int((span[1] - span[0]) / 2.2))
    step = (span[1] - span[0]) / n
    floors = int((h - 0.6) / floors_h)
    wc = hexc("bcd3e6")
    for f in range(floors):
        z = 1.0 + f * floors_h
        for i in range(n):
            u = span[0] + step * (i + 0.5)
            if f == 0 and shop:
                continue
            w, wh = min(1.1, step * 0.55), 1.5
            _facade_box(glow, facade_dir, plane, out, u, z, w, wh, 0.06, jitter(wc, 0.05, rnd))
            _facade_box(sill, facade_dir, plane, out, u, z - 0.12, w + 0.25, 0.12, 0.16, trim)
            _facade_box(sill, facade_dir, plane, out, u, z + wh, w + 0.15, 0.14, 0.1, trim)
    if shop:
        u = (span[0] + span[1]) / 2
        sw = (span[1] - span[0]) * 0.7
        _facade_box(glow, facade_dir, plane, out, u, 0.35, sw, 2.0, 0.08, hexc("cfe2ec"))
        _facade_box(sill, facade_dir, plane, out, u, 2.45, sw + 0.4, 0.55, 0.14, hexc(shop.get("sign", "fff4e4")))
        stripes = shop.get("awning", ["f3b2b9", "fff6ee"])
        aw = S.b("prop_awnings", "fabric")
        k = 8
        for j in range(k):
            uu = u - sw / 2 - 0.2 + (sw + 0.4) * (j + 0.5) / k
            _awning(aw, facade_dir, plane, out, uu, (sw + 0.4) / k, 3.05, hexc(stripes[j % 2]))


def _facade_box(b, d, plane, out, u, z, w, h, depth, color):
    if d in ("+y", "-y"):
        b.box((u, plane + out * depth / 2, z), (w, depth, h), color)
    else:
        b.box((plane + out * depth / 2, u, z), (depth, w, h), color)


def _awning(b, d, plane, out, u, w, z, color):
    depth, drop = 1.2, 0.45
    if d in ("+y", "-y"):
        p = [(u - w / 2, plane, z), (u + w / 2, plane, z), (u + w / 2, plane + out * depth, z - drop), (u - w / 2, plane + out * depth, z - drop)]
    else:
        p = [(plane, u - w / 2, z), (plane, u + w / 2, z), (plane + out * depth, u + w / 2, z - drop), (plane + out * depth, u - w / 2, z - drop)]
    if out < 0:
        p = p[::-1]
    if d in ("+x", "-x"):
        p = p[::-1]
    b.quad(p, color)
    b.quad(p[::-1], tuple(color[i] * 0.85 for i in range(3)) + (1,))


def tree(S, x, y, z=0.0, h=None, kind="round"):
    rnd = S.rnd
    h = h or rnd.uniform(3.5, 5.0)
    trunk = S.b("prop_trees_trunk", "bark", smooth=True)
    trunk.cyl((x, y, z), 0.16, h * 0.55, hexc("9b7a68"), seg=8, r_top=0.11)
    leaves = S.b("prop_trees", "leaves", smooth=True)
    if kind == "pine":
        for i, (r, zz) in enumerate([(1.3, 0.25), (1.0, 0.5), (0.7, 0.72)]):
            leaves.cyl((x, y, z + h * zz), r, h * 0.32, jitter(hexc("7fae9a"), 0.08, rnd), seg=10, r_top=0.05, caps=False)
        snow = S.b("prop_snowcaps", "snow", smooth=True)
        snow.cyl((x, y, z + h * 0.72 + h * 0.2), 0.35, h * 0.12, hexc("f6f8ff"), seg=10, r_top=0.03, caps=False)
        return
    g = hexc(rnd.choice(["9cc79a", "a7d1a0", "8fbf98", "b3d4a2"]))
    for i in range(3):
        a = 2 * math.pi * i / 3 + rnd.random()
        leaves.blob((x + math.cos(a) * 0.5, y + math.sin(a) * 0.5, z + h * 0.7 + rnd.uniform(-0.2, 0.3)),
                    rnd.uniform(0.9, 1.2), jitter(g, 0.06, rnd), rnd=rnd, wobble=0.08)
    leaves.blob((x, y, z + h * 0.95), 1.0, jitter(g, 0.05, rnd), rnd=rnd, wobble=0.08)


_LAMP_N = [0]


def lamp(S, x, y, z=0.0, h=3.6, arm=(0, 0)):
    poles = S.b("prop_lamps", "metal", smooth=True)
    poles.cyl((x, y, z), 0.07, h, hexc("6e6a80"), seg=8)
    poles.cyl((x, y, z), 0.14, 0.4, hexc("6e6a80"), seg=8)
    head = (x + arm[0], y + arm[1], z + h)
    if arm != (0, 0):
        poles.box(((x + head[0]) / 2, (y + head[1]) / 2, z + h - 0.05), (abs(arm[0]) + 0.08, abs(arm[1]) + 0.08, 0.08), hexc("6e6a80"))
    glow = S.b("prop_lamp_glow", "glow_lamp", smooth=True)
    glow.blob((head[0], head[1], head[2] - 0.25), 0.22, hexc("fff0c8"), seg=8, rings=6)
    poles.cyl((head[0], head[1], head[2] - 0.08), 0.26, 0.12, hexc("6e6a80"), seg=8, r_top=0.08)
    _LAMP_N[0] += 1
    S.marker("lamp_%d" % _LAMP_N[0], (head[0], head[1], head[2] - 0.45))


def bench(S, x, y, rot=0.0, z=0.0, color="b98e72"):
    b = S.b("prop_benches-col", "wood")
    c = hexc(color)
    co, si = math.cos(rot), math.sin(rot)
    R = lambda dx, dy: (x + dx * co - dy * si, y + dx * si + dy * co)
    b.box((*R(0, 0), z + 0.42), (1.6, 0.45, 0.07), c, rot=rot)
    b.box((*R(0, 0.22), z + 0.5), (1.6, 0.06, 0.45), c, rot=rot)
    for dx in (-0.7, 0.7):
        b.box((*R(dx, 0), z), (0.08, 0.4, 0.42), hexc("6e6a80"), rot=rot)


def bounds(S, x0, x1, y0, y1, h=4.0):
    """Невидимые стены по краю игровой зоны."""
    w = S.b("bounds-colonly", "base")
    t = 0.4
    w.box(((x0 + x1) / 2, y0 - t / 2, 0), (x1 - x0, t, h), (1, 1, 1, 1))
    w.box(((x0 + x1) / 2, y1 + t / 2, 0), (x1 - x0, t, h), (1, 1, 1, 1))
    w.box((x0 - t / 2, (y0 + y1) / 2, 0), (t, y1 - y0, h), (1, 1, 1, 1))
    w.box((x1 + t / 2, (y0 + y1) / 2, 0), (t, y1 - y0, h), (1, 1, 1, 1))


def mountains(S, cx, cy, dist, count, h_range, color, spread=math.pi, start=0.0, complex_on=None):
    """Дальние горы-конусы по дуге; complex_on — индекс горы с жилым комплексом на вершине."""
    rnd = S.rnd
    m = S.b("far_mountains", "far")
    for i in range(count):
        a = start + spread * (i + 0.5) / count + rnd.uniform(-0.05, 0.05)
        x, y = cx + math.cos(a) * dist, cy + math.sin(a) * dist
        h = rnd.uniform(*h_range)
        r = h * rnd.uniform(1.3, 1.8)
        m.cyl((x, y, -5), r, h + 5, jitter(hexc(color), 0.06, rnd), seg=14, r_top=r * 0.12)
        zs = h * 0.72                                   # снежная шапка: верх конуса
        rs = (r + (r * 0.12 - r) * (zs + 5) / (h + 5)) * 1.02
        m.cyl((x, y, zs), rs, h - zs + 0.05, hexc("f4f2fa"), seg=14, r_top=r * 0.13)
        if complex_on == i:
            far = S.b("far_complex", "far")
            for k in range(5):
                far.box((x + (k - 2) * 7, y + rnd.uniform(-4, 4), h - 1), (5, 5, rnd.uniform(6, 14)), hexc("f6f3ee"))


# ---------------------------------------------------------------- японский пригород (реф. пользователя 23.10:
# узкая улица, двухэтажные дома с черепичными вальмовыми крышами, бетонные заборы, столбы с проводами, переезд)

def tube(b, pts, r, color, sides=4):
    """Тонкая труба по ломаной (провода, перила, рельсы)."""
    for i in range(len(pts) - 1):
        a, c = Vector(pts[i]), Vector(pts[i + 1])
        d = (c - a)
        if d.length < 1e-6:
            continue
        d.normalize()
        up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        u = d.cross(up).normalized()
        v = u.cross(d).normalized()
        ra = [a + (u * math.cos(2 * math.pi * k / sides) + v * math.sin(2 * math.pi * k / sides)) * r for k in range(sides)]
        rc = [c + (u * math.cos(2 * math.pi * k / sides) + v * math.sin(2 * math.pi * k / sides)) * r for k in range(sides)]
        for k in range(sides):
            j = (k + 1) % sides
            b.quad([tuple(ra[k]), tuple(ra[j]), tuple(rc[j]), tuple(rc[k])], color)


def hip_roof(b, x0, x1, y0, y1, z, h, color, overhang=0.6):
    """Вальмовая крыша с широким свесом (как у японских домов), снизу — тёмный подшив."""
    x0 -= overhang; x1 += overhang; y0 -= overhang; y1 += overhang
    dark = tuple(color[i] * 0.78 for i in range(3)) + (1.0,)
    w, d = x1 - x0, y1 - y0
    if w >= d:
        r0, r1 = (x0 + d / 2, (y0 + y1) / 2, z + h), (x1 - d / 2, (y0 + y1) / 2, z + h)
        b.quad([(x0, y0, z), (x1, y0, z), r1, r0], color)
        b.quad([(x1, y1, z), (x0, y1, z), r0, r1], dark)
        b.face([(x1, y0, z), (x1, y1, z), r1], dark, smooth=False)
        b.face([(x0, y1, z), (x0, y0, z), r0], color, smooth=False)
    else:
        r0, r1 = ((x0 + x1) / 2, y0 + w / 2, z + h), ((x0 + x1) / 2, y1 - w / 2, z + h)
        b.quad([(x1, y0, z), (x1, y1, z), r1, r0], color)
        b.quad([(x0, y1, z), (x0, y0, z), r0, r1], dark)
        b.face([(x0, y0, z), (x1, y0, z), r0], color, smooth=False)
        b.face([(x1, y1, z), (x0, y1, z), r1], dark, smooth=False)
    soffit = tuple(color[i] * 0.5 for i in range(3)) + (1.0,)
    b.quad([(x0, y1, z), (x1, y1, z), (x1, y0, z), (x0, y0, z)], soffit)


SIDING = ["e9e1d3", "d9d3c6", "efe6d6", "cfc8bc", "e6d3c8", "d8ccb8", "c9cfd0", "e3d6c4"]
TILES = ["5d6573", "4f5866", "6b6f78", "8e5148", "7a4a44", "596270"]


def jp_house(S, x0, x1, y0, y1, front, floors=2, color=None, roof=None, balcony=True, col=True, shop=None):
    """Двухэтажный японский дом: обшивка, окна с рамами, балкон с перилами на 2-м этаже, навес над входом,
    кондиционер на стене, вальмовая крыша. front: '+y'/'-y' — к улице."""
    rnd = S.rnd
    c = hexc(color or rnd.choice(SIDING))
    fh = 2.8
    h = floors * fh + 0.3
    walls = S.b("houses-col" if col else "houses_far", "wall")
    walls.box(((x0 + x1) / 2, (y0 + y1) / 2, 0), (x1 - x0, y1 - y0, h), c, shade=0.8)
    # пояс между этажами
    band = tuple(c[i] * 0.86 for i in range(3)) + (1,)
    walls.box(((x0 + x1) / 2, (y0 + y1) / 2, fh - 0.05), (x1 - x0 + 0.08, y1 - y0 + 0.08, 0.16), band)
    hip_roof(S.b("roofs", "roof"), x0, x1, y0, y1, h, min(2.0, (min(x1 - x0, y1 - y0)) * 0.32),
             hexc(roof or rnd.choice(TILES)), overhang=0.55)
    plane = y1 if front == "+y" else y0
    out = 1 if front == "+y" else -1
    glow = S.b("glow_windows" if col else "glow_windows_far", "glow_window")
    frame = S.b("frames", "metal")
    fc = hexc("8a8a88")
    n = max(1, int((x1 - x0) / 2.4))
    step = (x1 - x0) / n
    for f in range(floors):
        z = 0.9 + f * fh
        for i in range(n):
            u = x0 + step * (i + 0.5)
            if f == 0 and i == 0:
                continue      # вход
            if f == 0 and shop:
                continue
            w, wh = min(1.5, step * 0.62), 1.2 if f else 1.3
            _facade_box(glow, front, plane, out, u, z, w, wh, 0.05, jitter(hexc("b9cbd6"), 0.05, rnd))
            _facade_box(frame, front, plane, out, u, z - 0.06, w + 0.12, 0.06, 0.09, fc)
            _facade_box(frame, front, plane, out, u, z + wh, w + 0.12, 0.06, 0.09, fc)
            _facade_box(frame, front, plane, out, u, z, 0.05, wh, 0.08, fc)       # раздвижные створки
    # вход: дверь и козырёк
    u0 = x0 + step * 0.5
    door = S.b("doors", "wood")
    _facade_box(door, front, plane, out, u0, 0.0, 1.0, 2.0, 0.06, hexc("8d6e58"))
    _facade_box(S.b("canopies", "roof"), front, plane, out, u0, 2.25, 1.6, 0.08, 0.9, hexc("6f7480"))
    if balcony and floors > 1 and not shop:
        bx = (x0 + x1) / 2 + step * 0.4
        bw = min(x1 - x0 - 1.0, 4.2)
        rail = S.b("prop_balconies", "metal")
        _facade_box(rail, front, plane, out, bx, fh, bw, 0.12, 0.9, hexc("9a9894"))
        rp = plane + out * 0.88
        for k in range(int(bw / 0.12) + 1):
            xx = bx - bw / 2 + k * 0.12
            rail.box((xx, rp, fh + 0.12), (0.025, 0.025, 0.95), hexc("6e6c6a"))
        rail.box((bx, rp, fh + 1.05), (bw, 0.06, 0.05), hexc("6e6c6a"))
    # кондиционер
    ac = S.b("prop_ac", "metal")
    _facade_box(ac, front, plane, out, x1 - 0.7, 0.2, 0.8, 0.6, 0.3, hexc("e8e6e0"))
    if shop:
        u = (x0 + x1) / 2 + step * 0.3
        sw = (x1 - x0) * 0.6
        _facade_box(glow, front, plane, out, u, 0.3, sw, 2.0, 0.08, hexc("cfe2ec"))
        _facade_box(S.b("signs", "wall"), front, plane, out, u, 2.45, sw + 0.4, 0.5, 0.12, hexc(shop.get("sign", "f4ead8")))
        stripes = shop.get("awning", ["5f7f6e", "efe6d6"])
        aw = S.b("prop_awnings", "fabric")
        k = 8
        for j in range(k):
            uu = u - sw / 2 - 0.2 + (sw + 0.4) * (j + 0.5) / k
            _awning(aw, front, plane, out, uu, (sw + 0.4) / k, 2.95, hexc(stripes[j % 2]))


def block_wall(S, x0, x1, y, h=1.3, color="c9c4b8", gaps=()):
    """Бетонный блочный забор вдоль X (с проёмами-калитками)."""
    w = S.b("walls-col", "stone")
    c = hexc(color)
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
        w.box(((a + b) / 2, y, 0), (b - a, 0.16, h), c, shade=0.85)
        w.box(((a + b) / 2, y, h), (b - a, 0.22, 0.07), tuple(c[i] * 0.92 for i in range(3)) + (1,))
        lines = S.b("wall_lines", "stone")
        for k in range(1, int(h / 0.2)):
            lines.box(((a + b) / 2, y, k * 0.2), (b - a, 0.17, 0.012), tuple(c[i] * 0.86 for i in range(3)) + (1,))


def hedge(S, x0, x1, y, h=1.2, w=0.8):
    rnd = S.rnd
    b = S.b("prop_hedges", "leaves", smooth=True)
    n = max(1, int((x1 - x0) / 0.7))
    for i in range(n):
        x = x0 + (x1 - x0) * (i + 0.5) / n
        b.blob((x, y + rnd.uniform(-0.1, 0.1), h * 0.55), w * 0.6, jitter(hexc("6f9a62"), 0.1, rnd), seg=8, rings=6,
               squash=h / w * 0.9, rnd=rnd, wobble=0.12)


_POLES = []


def utility_pole(S, x, y, h=9.0, transformer=False):
    p = S.b("prop_poles-col", "stone", smooth=True)
    p.cyl((x, y, 0), 0.17, h, hexc("b8b6b0"), seg=10, r_top=0.12)
    arm = S.b("prop_pole_arms", "metal")
    for z in (h - 0.4, h - 1.3):
        arm.box((x, y, z), (0.1, 1.6, 0.1), hexc("7a7a78"))
    if transformer:
        p.cyl((x + 0.35, y, h - 3.2), 0.28, 1.0, hexc("9fa3a6"), seg=10)
    _POLES.append((x, y, h))


def wires(S, poles, sag=0.6):
    """Провода между соседними столбами: по три на каждой поперечине, с провисом."""
    w = S.b("prop_wires", "metal")
    for (xa, ya, ha), (xb, yb, hb) in zip(poles, poles[1:]):
        for z_off, dy in ((0.4, -0.7), (0.4, 0.7), (0.4, 0.0), (1.3, -0.6), (1.3, 0.6)):
            pts = []
            for k in range(11):
                t = k / 10
                pts.append((xa + (xb - xa) * t, ya + dy + (yb - ya) * t, ha - z_off + (hb - ha) * t - sag * 4 * t * (1 - t)))
            tube(w, pts, 0.012, hexc("2e2c30"), sides=3)


def railway_crossing(S, x, y0, y1, track_len=40):
    """Железнодорожный переезд поперёк улицы: рельсы на щебне, сигналы с крестом и фонарями, полосатые столбы."""
    g = S.b("track_bed", "ground")
    g.box((x, 0, -0.02), (3.4, track_len, 0.08), hexc("8e8a86"))
    rails = S.b("prop_rails_track", "metal")
    for dx in (-0.72, 0.72):
        rails.box((x + dx, 0, 0.06), (0.08, track_len, 0.1), hexc("5a5654"))
    sl = S.b("sleepers", "wood")
    for k in range(int(track_len / 0.6)):
        sl.box((x, -track_len / 2 + k * 0.6, 0.0), (2.2, 0.2, 0.07), hexc("6e5e52"))
    # белые полосы перед переездом
    m = S.b("road_marks", "ground")
    for dx in (-2.4, 2.4):
        m.box((x + dx, (y0 + y1) / 2, 0.0), (0.3, y1 - y0, 0.012), hexc("f2f0ea"))
    for yy, side in ((y0 - 0.5, -1), (y1 + 0.5, 1)):
        sx = x - 2.0 * side
        post = S.b("prop_crossing", "metal")
        n = 12
        for k in range(n):
            post.cyl((sx, yy, k * 0.3), 0.08, 0.3, hexc("1f1d1f") if k % 2 else hexc("f2c230"), seg=8, caps=False)
        post.cyl((sx, yy, n * 0.3), 0.08, 0.05, hexc("1f1d1f"), seg=8)
        # крест (андреевский)
        cz = 3.5
        xb = S.b("prop_crossbuck", "metal")
        for a in (0.62, -0.62):
            ca, sa = math.cos(a), math.sin(a)
            for k in range(6):
                t = -0.75 + (k + 0.5) * 0.25
                c = hexc("f2c230") if k % 2 else hexc("1f1d1f")
                _rot_box_yz(xb, (sx - 0.12 * side, yy + t * ca, cz + t * sa), 0.06, 0.25, 0.14, a, c)
        # фонари-сигналы
        lamps = S.b("prop_signal_lamps", "metal", smooth=True)
        for dy in (-0.32, 0.32):
            lamps.cyl((sx - 0.15 * side, yy + dy, 2.45), 0.2, 0.08, hexc("2a282a"), seg=12)
        glow = S.b("prop_signal_glow", "glow_signal", smooth=True)
        for dy in (-0.32, 0.32):
            glow.blob((sx - 0.25 * side, yy + dy, 2.5), 0.12, hexc("d0443a"), seg=8, rings=6)
        # шлагбаум (поднят)
        arm = S.b("prop_crossing", "metal")
        arm.box((sx + 0.2 * side, yy, 1.0), (0.4, 0.4, 0.6), hexc("2a282a"))
        for k in range(8):
            arm.box((sx + 0.2 * side, yy, 1.6 + k * 0.4), (0.08, 0.08, 0.4), hexc("f2c230") if k % 2 else hexc("1f1d1f"))


def _rot_box_yz(b, c, sx, sy, sz, a, color):
    """Брусок, повёрнутый в плоскости YZ на угол a (крест переезда)."""
    ca, sa = math.cos(a), math.sin(a)
    corners = []
    for dx in (-sx / 2, sx / 2):
        for dy, dz in ((-sy / 2, -sz / 2), (sy / 2, -sz / 2), (sy / 2, sz / 2), (-sy / 2, sz / 2)):
            corners.append((c[0] + dx, c[1] + dy * ca - dz * sa, c[2] + dy * sa + dz * ca))
    A, B = corners[:4], corners[4:]
    b.quad([A[3], A[2], A[1], A[0]], color)
    b.quad(B, color)
    for i in range(4):
        j = (i + 1) % 4
        b.quad([A[i], A[j], B[j], B[i]], color)


def bollard(S, x, y):
    b = S.b("prop_bollards-col", "metal", smooth=True)
    for k in range(4):
        b.cyl((x, y, k * 0.22), 0.06, 0.22, hexc("e0703a") if k % 2 == 0 else hexc("2a2628"), seg=8, caps=k == 3)


def vending_machine(S, x, y, rot=0.0, color="e9ecef"):
    b = S.b("prop_vending-col", "metal")
    b.box((x, y, 0), (1.0, 0.75, 1.85), hexc(color), rot=rot)
    co, si = math.cos(rot), math.sin(rot)
    fx, fy = x - si * 0.39, y + co * 0.39   # лицевая сторона — по +Y повернутой коробки
    g = S.b("prop_vending_glow", "glow_lamp")
    g.box((fx, fy, 0.95), (0.8, 0.04, 0.75), hexc("f6f8ff"), rot=rot)
    rnd = S.rnd
    cans = S.b("prop_cans", "fabric")
    for r in range(3):
        for k in range(6):
            cx = (k - 2.5) * 0.12
            cans.box((fx + co * cx - si * 0.03, fy + si * cx + co * 0.03, 1.05 + r * 0.22), (0.07, 0.03, 0.13),
                     hexc(rnd.choice(["d8463e", "3a74b8", "f0b840", "4d9a5a", "f4f2ee"])), rot=rot)


def covered_bike(S, x, y, rot=0.0):
    b = S.b("prop_bikes", "fabric", smooth=True)
    co, si = math.cos(rot), math.sin(rot)
    for k, (dx, r, z) in enumerate(((-0.45, 0.42, 0.45), (0.0, 0.48, 0.55), (0.45, 0.42, 0.5))):
        b.blob((x + dx * co, y + dx * si, z), r, hexc("8c8f96"), seg=8, rings=6, squash=1.1, rnd=S.rnd, wobble=0.15)


def corner_mirror(S, x, y, face_a=0.0):
    b = S.b("prop_mirror", "metal", smooth=True)
    b.cyl((x, y, 0), 0.05, 2.6, hexc("e0703a"), seg=8)
    m = S.b("prop_mirror_glass", "glow_window", smooth=True)
    m.blob((x + 0.2 * math.cos(face_a), y + 0.2 * math.sin(face_a), 2.75), 0.32, hexc("c8d8e0"), seg=10, rings=6, squash=1.0)
    b.cyl((x + 0.18 * math.cos(face_a), y + 0.18 * math.sin(face_a), 2.38), 0.36, 0.04, hexc("e0703a"), seg=12)


def round_sign(S, x, y, h=2.4, color="d84a3e", face=(0, -1)):
    b = S.b("prop_signs", "metal", smooth=True)
    b.cyl((x, y, 0), 0.04, h, hexc("9a9a98"), seg=6)
    c = (x + face[0] * 0.05, y + face[1] * 0.05, h + 0.3)
    disc = S.b("prop_sign_faces", "fabric")
    k = 16
    pts = [(c[0] - face[1] * 0.3 * math.cos(2 * math.pi * i / k), c[1] + face[0] * 0.3 * math.cos(2 * math.pi * i / k),
            c[2] + 0.3 * math.sin(2 * math.pi * i / k)) for i in range(k)]
    disc.face(pts, hexc(color), smooth=False)
    disc.face(pts[::-1], hexc("c8c8c4"), smooth=False)
    inner = [(c[0] + face[0] * 0.01 - face[1] * 0.22 * math.cos(2 * math.pi * i / k), c[1] + face[1] * 0.01 + face[0] * 0.22 * math.cos(2 * math.pi * i / k),
              c[2] + 0.22 * math.sin(2 * math.pi * i / k)) for i in range(k)]
    disc.face(inner, hexc("f4f2ee"), smooth=False)
