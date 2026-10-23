"""Набор для локаций в Blender по правилам location-kit (docs/location-kit/SKILL.md) — перенос приёмов three.js-набора
в наш конвейер Blender → glb → Godot:
  • геометрия копится «пачками» (один объект на материал) — мало вызовов отрисовки (правило «Batch static»);
  • UV в мировых координатах (tile — метров на повтор текстуры): текстуры никогда не растягиваются;
  • пиксельные текстуры 1 тексель ≈ 1 см (tools/art/loc_textures.py), в игре — фильтр «ближайший» (toon_loc);
  • рёбра скругляются модификатором Bevel (правило «No raw primitives»), мягкие вещи — «надутые» (cushion);
  • окна: рама, переплёт, подоконник, вид за окном по времени суток, луч и пятно света на полу;
  • свет по состояниям: объекты с суффиксом «__day», «__evening», «__night» (можно «__evening_night») видны только
    в этих состояниях; точки lamp_* (тёплый свет вечером/ночью), fill_* (дневная подсветка), moon_* (лунный свет).
Соглашения для игры (src/gameplay/story_location.gd):
  «<имя>-col» — столкновения, «<имя>-colonly» — невидимая стена; «water» — уровень воды;
  материалы: glow_* — окна/лампы, add_* — аддитивные лучи и пятна, view_* — вид за окном (без освещения),
  alpha_* — вырез по альфе (жалюзи, листья); «prop_*» — объекты с контуром.
Направление точки: «вперёд» персонажа — локальная ось +Y пустого объекта в Blender (в Godot это −Z).
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEXDIR = os.path.join(ROOT, "art", "locations", "textures")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def hexc(h, a=1.0):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)) + (a,)


def jitter(c, amt, rnd):
    k = 1 + (rnd.random() - 0.5) * 2 * amt
    return tuple(min(1.0, max(0.0, c[i] * k)) for i in range(3)) + (1.0,)


def shade(c, k):
    return tuple(min(1.0, c[i] * k) for i in range(3)) + (1.0,)


WHITE = (1, 1, 1, 1)


def material(name, tex=None, color=WHITE, rough=0.8):
    """Материал: (текстура) × цвет вершин × цвет. Текстура — ключ из loc_textures (art/locations/textures/<tex>.png).
    Интерполяция «Closest» — пиксельный регистр сохраняется и в Blender-превью."""
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Base Color"].default_value = color
    vn = nt.nodes.new("ShaderNodeVertexColor")
    vn.layer_name = "Col"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(vn.outputs["Color"], mix.inputs[7])
    if tex:
        img = bpy.data.images.load(os.path.join(TEXDIR, tex + ".png"), check_existing=True)
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = img
        tn.interpolation = "Closest"
        nt.links.new(tn.outputs["Color"], mix.inputs[6])
        if name.startswith(("alpha_", "add_")):
            nt.links.new(tn.outputs["Alpha"], bsdf.inputs["Alpha"])
    else:
        mix.inputs[6].default_value = color
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    return m


class Batch:
    """Грани одного объекта. Примитивы добавляют вершины, грани, цвет вершин; UV — в finish() по мировым координатам."""

    def __init__(self, name, mat, tile=1.28, smooth=False, bevel=0.0):
        self.name, self.mat, self.tile, self.smooth_default, self.bevel = name, mat, tile, smooth, bevel
        self.v, self.f, self.c, self.s, self.uv = [], [], [], [], []
        self.T = Matrix.Identity(4)     # локальная рамка (with_t)

    # ---- рамки (как kit.withT): x, y — позиция, rz — поворот вокруг вертикали, z — высота
    def with_t(self, x, y, rz=0.0, z=0.0):
        outer = self

        class _Ctx:
            def __enter__(self_):
                self_.prev = outer.T
                outer.T = outer.T @ Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, "Z")
                return outer

            def __exit__(self_, *a):
                outer.T = self_.prev
        return _Ctx()

    def P(self, p):
        return tuple(self.T @ Vector(p))

    def face(self, pts, color, smooth=None, uv=None):
        if self.mat and self.mat.name.startswith("add_") and len(color) == 4 and not isinstance(color[0], tuple):
            # аддитивные лучи/пятна: альфа цвета вершин при экспорте теряется — запекаем её в яркость
            color = (color[0] * color[3], color[1] * color[3], color[2] * color[3], 1.0)
        i0 = len(self.v)
        self.v.extend(self.P(p) for p in pts)
        self.c.extend([color] * len(pts) if len(color) == 4 and not isinstance(color[0], tuple) else color)
        self.f.append(list(range(i0, i0 + len(pts))))
        self.s.append(self.smooth_default if smooth is None else smooth)
        self.uv.append(uv)

    def quad(self, pts, color, uv=None):
        self.face(list(pts), color, smooth=False, uv=uv)

    def box(self, c, size, color, rz=0.0, top=None, grad=0.88, rx=0.0, ry=0.0):
        """Брусок: c — центр ОСНОВАНИЯ (x, y, z), size — (x, y, z). Низ боковых граней темнее (grad) — мягкая «окклюзия»."""
        sx, sy, sz = size[0] / 2, size[1] / 2, size[2]
        R = Matrix.Translation(c) @ Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X")
        P = lambda x, y, z: tuple(R @ Vector((x, y, z)))
        b = [P(-sx, -sy, 0), P(sx, -sy, 0), P(sx, sy, 0), P(-sx, sy, 0)]
        t = [P(-sx, -sy, sz), P(sx, -sy, sz), P(sx, sy, sz), P(-sx, sy, sz)]
        low = shade(color, grad)
        for a, bb in ((0, 1), (1, 2), (2, 3), (3, 0)):
            self.face([b[a], b[bb], t[bb], t[a]], [low, low, color, color], smooth=False)
        self.face(t, top or color, smooth=False)
        self.face([b[3], b[2], b[1], b[0]], low, smooth=False)

    def cyl(self, c, r, h, color, seg=16, r_top=None, smooth=True, caps=True, top_color=None, rx=0.0, ry=0.0, rz=0.0):
        r_top = r if r_top is None else r_top
        R = Matrix.Translation(c) @ Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X")
        rb = [tuple(R @ Vector((r * math.cos(2 * math.pi * i / seg), r * math.sin(2 * math.pi * i / seg), 0))) for i in range(seg)]
        rt = [tuple(R @ Vector((r_top * math.cos(2 * math.pi * i / seg), r_top * math.sin(2 * math.pi * i / seg), h))) for i in range(seg)]
        low = shade(color, 0.86)
        for i in range(seg):
            j = (i + 1) % seg
            self.face([rb[i], rb[j], rt[j], rt[i]], [low, low, color, color], smooth=smooth)
        if caps:
            self.face(rt, top_color or color, smooth=False)
            self.face(rb[::-1], low, smooth=False)

    def blob(self, c, r, color, seg=16, rings=12, squash=1.0, rnd=None, wobble=0.0, sx=1.0, sy=1.0):
        """Сглаженный эллипсоид (кроны, подушки, сугробы). Сегментов ≥ 16×12 — правило набора."""
        rows = []
        for j in range(rings + 1):
            th = math.pi * j / rings
            row = []
            for i in range(seg):
                ph = 2 * math.pi * i / seg
                k = 1 + (rnd.uniform(-wobble, wobble) if rnd and 0 < j < rings else 0)
                row.append((c[0] + r * sx * k * math.sin(th) * math.cos(ph), c[1] + r * sy * k * math.sin(th) * math.sin(ph),
                            c[2] + r * squash * math.cos(th)))
            rows.append(row)
        for j in range(rings):
            k0, k1 = 0.78 + 0.22 * (1 - j / rings), 0.78 + 0.22 * (1 - (j + 1) / rings)
            for i in range(seg):
                ii = (i + 1) % seg
                self.face([rows[j][i], rows[j + 1][i], rows[j + 1][ii], rows[j][ii]],
                          [shade(color, k0), shade(color, k1), shade(color, k1), shade(color, k0)], smooth=True)

    def cushion(self, c, size, color, puff=0.35, rnd=None, seg=10):
        """Подушка/сиденье: брусок с «надутыми» гранями (центр выпирает, края — мягкий шов)."""
        w, d, h = size
        rows = []
        n = seg
        for j in range(n + 1):
            v = j / n
            th = math.pi * v
            row = []
            for i in range(n * 2):
                ph = 2 * math.pi * i / (n * 2)
                cx, cy = math.cos(ph), math.sin(ph)
                # суперэллипс в плане: почти прямоугольник со скруглёнными углами
                q = 6.0
                k = (abs(cx) ** q + abs(cy) ** q) ** (-1 / q)
                bulge = 1 + puff * 0.15 * math.sin(th) * (1 + (rnd.uniform(-0.2, 0.2) if rnd else 0))
                x = cx * k * w / 2 * (0.86 + 0.14 * math.sin(th)) * bulge
                y = cy * k * d / 2 * (0.86 + 0.14 * math.sin(th)) * bulge
                z = h / 2 + (h / 2) * math.cos(th) * (1 + puff * 0.4 * (1 - abs(cx * k) ** 4) * (1 - abs(cy * k) ** 4))
                row.append((c[0] + x, c[1] + y, c[2] + z))
            rows.append(row)
        m = n * 2
        for j in range(n):
            kk = 0.8 + 0.2 * (1 - j / n)
            for i in range(m):
                ii = (i + 1) % m
                self.face([rows[j][i], rows[j + 1][i], rows[j + 1][ii], rows[j][ii]], shade(color, kk), smooth=True)

    def strip(self, pts_l, pts_r, color, thick=0.0, under=None):
        for i in range(len(pts_l) - 1):
            self.quad([pts_l[i], pts_r[i], pts_r[i + 1], pts_l[i + 1]], color)
        if thick > 0:
            dn = lambda p: (p[0], p[1], p[2] - thick)
            uc = under or shade(color, 0.8)
            for i in range(len(pts_l) - 1):
                self.quad([dn(pts_l[i + 1]), dn(pts_r[i + 1]), dn(pts_r[i]), dn(pts_l[i])], uc)
                self.quad([pts_l[i + 1], dn(pts_l[i + 1]), dn(pts_l[i]), pts_l[i]], uc)
                self.quad([pts_r[i], dn(pts_r[i]), dn(pts_r[i + 1]), pts_r[i + 1]], uc)

    def tube(self, pts, r, color, sides=6):
        for i in range(len(pts) - 1):
            a, c = Vector(pts[i]), Vector(pts[i + 1])
            d = c - a
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
                self.face([tuple(ra[k]), tuple(ra[j]), tuple(rc[j]), tuple(rc[k])], color, smooth=True)

    def lathe(self, c, prof, color, seg=20):
        """Тело вращения по профилю [(r, z), ...] снизу вверх (горшки, абажуры, вазы)."""
        rings = [[(c[0] + r * math.cos(2 * math.pi * i / seg), c[1] + r * math.sin(2 * math.pi * i / seg), c[2] + z)
                  for i in range(seg)] for r, z in prof]
        for j in range(len(rings) - 1):
            for i in range(seg):
                ii = (i + 1) % seg
                self.face([rings[j][i], rings[j][ii], rings[j + 1][ii], rings[j + 1][i]], color, smooth=True)

    def finish(self):
        if not self.f:
            return None
        me = bpy.data.meshes.new(self.name)
        me.from_pydata(self.v, [], self.f)
        me.update()
        # цвет и UV — на углах граней: после сшивания вершин у соседних граней остаются свои значения
        attr = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        uvl = me.uv_layers.new(name="UV")
        for poly, sm, uvs in zip(me.polygons, self.s, self.uv):
            poly.use_smooth = sm
            n = poly.normal
            ax = max(range(3), key=lambda k: abs(n[k]))
            for k, li in enumerate(poly.loop_indices):
                vi = me.loops[li].vertex_index
                attr.data[li].color = self.c[vi]
                if uvs:
                    uvl.data[li].uv = uvs[k]
                    continue
                p = me.vertices[vi].co
                if ax == 2:
                    u, v = p.x, p.y * (1 if n.z > 0 else -1)
                elif ax == 0:
                    u, v = p.y * (1 if n.x > 0 else -1), p.z
                else:
                    u, v = p.x * (-1 if n.y > 0 else 1), p.z
                uvl.data[li].uv = (u / self.tile, v / self.tile)
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0004)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(self.mat)
        o = bpy.data.objects.new(self.name, me)
        bpy.context.collection.objects.link(o)
        if self.bevel > 0:
            bpy.context.view_layer.objects.active = o
            md = o.modifiers.new("bevel", "BEVEL")
            md.width = self.bevel
            md.segments = 2
            md.limit_method = "ANGLE"
            md.angle_limit = math.radians(35)
            try:
                md.harden_normals = True
            except AttributeError:
                pass
            bpy.ops.object.modifier_apply(modifier="bevel")
        return o


class Scene:
    """Пачки по имени + точки. export() пишет glb."""

    def __init__(self, seed=1):
        self.batches = {}
        self.rnd = random.Random(seed)

    def b(self, name, mat, tile=1.28, smooth=False, bevel=0.0):
        """Пачка «name». mat — bpy-материал (material(...)). bevel — радиус скругления рёбер (м)."""
        if name not in self.batches:
            self.batches[name] = Batch(name, mat, tile, smooth, bevel)
        return self.batches[name]

    def marker(self, name, loc, face=(0, 1), up=None):
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
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=True)
        print("exported", path)


# ---------------------------------------------------------------- материалы набора (кэш по ключу)

def M(key, tex=None, color=WHITE, rough=0.8):
    return material(key, tex, color, rough)
