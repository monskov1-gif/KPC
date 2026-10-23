"""Подготовка чужой базовой модели тела (CC-BY и т. п., автор — в art/characters/src/CREDITS.md) для конвейера KPC.

Запуск: tools/bpyenv/bin/python tools/art/prep_base.py <in.glb> <out.glb> <рост_м> [опускание_рук_°] [доля_граней]
        [морда_×] [уши_×] [лодыжки_x_м] [голова_вверх_°]  (Хотто: 2.35 66 0.12 1.75 1.6 0.26 12)
Что делает: склеивает меши, сливает дубли вершин, упрощает сетку (веб-версия), ставит модель на пол лицом к −Y
и масштабирует до роста, опускает руки из T-позы (поворот вокруг плеча с плавным переходом у дельты),
находит суставы по геометрии (таз, позвоночник, шея, голова, плечи, локти, запястья, бёдра, колени, лодыжки,
носки) и пишет их в <out>.joints.json — по ним строятся скелет, «оболочки» одежды, хвост и грива.
"""
import json
import math
import sys

import bpy
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
src, dst, height = args[0], args[1], float(args[2])
arm_down = float(args[3]) if len(args) > 3 else 66.0
ratio = float(args[4]) if len(args) > 4 else 0.12

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.data.objects if o.type == "MESH" and not o.name.startswith("Icosphere")]
for o in bpy.data.objects:
    o.select_set(o in meshes)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
body.name = "body"
for o in list(bpy.data.objects):
    if o is not body:
        bpy.data.objects.remove(o)
me = body.data
# слить дубли и упростить
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.remove_doubles(threshold=1e-5)
bpy.ops.object.mode_set(mode="OBJECT")
dec = body.modifiers.new("dec", "DECIMATE")
dec.ratio = ratio
bpy.ops.object.modifier_apply(modifier="dec")
me = body.data
vs = [v.co.copy() for v in me.vertices]

# на пол, по центру, рост
zmin = min(v.z for v in vs)
zmax = max(v.z for v in vs)
k = height / (zmax - zmin)
cx = sum(v.x for v in vs) / len(vs)
cy = sum(v.y for v in vs) / len(vs)
for v in me.vertices:
    v.co = Vector(((v.co.x - cx) * k, (v.co.y - cy) * k, (v.co.z - zmin) * k))
H = height
P = [v.co.copy() for v in me.vertices]
# лицо к −Y: морда/нос — самая выступающая часть у макушки
top = [p for p in P if p.z > H * 0.85]
if sum(p.y for p in top if abs(p.x) < H * 0.03) / max(1, len([p for p in top if abs(p.x) < H * 0.03])) > \
        sum(p.y for p in top) / len(top) and min(p.y for p in top) > -max(p.y for p in top):
    for v in me.vertices:
        v.co = Vector((-v.co.x, -v.co.y, v.co.z))
    P = [v.co.copy() for v in me.vertices]
# симметрия: ось — середина торса на уровне груди, затем зеркалим +X → −X (база была перекошена)
import bmesh  # noqa: E402
chest = [p for p in P if H * 0.55 < p.z < H * 0.68 and abs(p.x) < H * 0.12]
mid_x = sum(p.x for p in chest) / len(chest)
for v in me.vertices:
    v.co.x -= mid_x
bm = bmesh.new()
bm.from_mesh(me)
bmesh.ops.symmetrize(bm, input=bm.verts[:] + bm.edges[:] + bm.faces[:], direction="X", dist=1e-4)
bm.to_mesh(me)
bm.free()
me.update()
P = [v.co.copy() for v in me.vertices]


def slice_x(x0, x1, zlo=0.0, zhi=1e9):
    return [p for p in P if x0 <= p.x < x1 and zlo <= p.z < zhi]


def centroid(ps):
    return sum(ps, Vector()) / len(ps) if ps else None


# плечо (T-поза): по оси X — где вертикальный размах среза резко падает (торс → рука)
xr = max(p.x for p in P)
step = xr / 60
prev = None
px = None
ext = []
for i in range(10, 60):
    x = i * step
    sl = slice_x(x, x + step, H * 0.5)
    if not sl:
        continue
    e = max(p.z for p in sl) - min(p.z for p in sl)
    ext.append((x, e))
torso_e = ext[0][1]
for x, e in ext:
    if e < torso_e * 0.42:
        px = x
        break
arm_sl = slice_x(px + step * 2, px + step * 4, H * 0.5)
pz = centroid(arm_sl).z
py = centroid(arm_sl).y
hand_end = max(P, key=lambda p: p.x).x
J = {}
for sd, name in ((1, "l"), (-1, "r")):
    sh = Vector((sd * (px - step * 3), py, pz))
    L = hand_end - (px - step * 3)
    J["sh_" + name] = sh
    J["el_" + name] = sh + Vector((sd * L * 0.42, 0, 0))
    J["wr_" + name] = sh + Vector((sd * L * 0.76, 0, 0))
    J["palm_" + name] = sh + Vector((sd * L * 0.86, 0, 0))
# ось торса и ноги
crotch = None
for i in range(int(H * 0.3 / (H / 200)), 200):
    z = i * H / 200
    if any(abs(p.x) < H * 0.012 and abs(p.z - z) < H / 200 for p in P):
        crotch = z
        break
neck_z = pz + H * 0.045
pel = Vector((0, 0, crotch + H * 0.09))          # таз — на уровне тазобедренных суставов, выше промежности
mid = [p for p in P if abs(p.x) < H * 0.05 and abs(p.z - pel.z) < H * 0.02]
pel.y = centroid(mid).y
J["pelvis"] = pel
nk = [p for p in P if abs(p.x) < H * 0.05 and abs(p.z - neck_z) < H * 0.015]
J["neck"] = Vector((0, centroid(nk).y if nk else pel.y, neck_z))
for nm, f in (("spine", 0.28), ("chest", 0.58), ("upchest", 0.83)):
    z = pel.z + (neck_z - pel.z) * f
    sl = [p for p in P if abs(p.x) < H * 0.05 and abs(p.z - z) < H * 0.015]
    J[nm] = Vector((0, centroid(sl).y, z))
J["head"] = J["neck"] + Vector((0, 0, H * 0.055))
for sd, name in ((1, "l"), (-1, "r")):
    def leg_c(z):
        sl = [p for p in P if p.x * sd > H * 0.01 and abs(p.z - z) < H * 0.012 and abs(p.x) < H * 0.25]
        return centroid(sl)
    hip = leg_c(crotch - H * 0.02)
    an_z = H * 0.045
    an = leg_c(an_z)
    kn = leg_c(an_z + (hip.z - an_z) * 0.47)
    J["hip_" + name] = Vector((hip.x, hip.y, crotch + H * 0.03))
    J["kn_" + name] = kn
    J["an_" + name] = an
    feet = [p for p in P if p.x * sd > 0 and p.z < H * 0.04]
    toe = min(feet, key=lambda p: p.y)
    J["to_" + name] = Vector((an.x, toe.y * 0.85 + an.y * 0.15, H * 0.012))

# стойка: ноги к центру (лодыжки на ±stance_x), стопы обратно ровно (аргумент 8)
stance_x = float(args[7]) if len(args) > 7 else 0.0
if stance_x:
    for sd, name in ((1, "l"), (-1, "r")):
        hip, an = J["hip_" + name], J["an_" + name]
        ang = math.atan2(abs(an.x) - stance_x, hip.z - an.z)
        R = Matrix.Rotation(sd * ang, 3, "Y")
        for v in me.vertices:
            p = v.co
            if p.x * sd <= 0 or p.z > hip.z + H * 0.02:
                continue
            w = max(0.0, min(1.0, (hip.z + H * 0.02 - p.z) / (H * 0.06)))
            w = w * w * (3 - 2 * w)
            v.co = hip + Matrix.Rotation(sd * ang * w, 3, "Y") @ (p - hip)
            if v.co.z < an.z + H * 0.03:                     # стопа — обратно горизонтально
                a2 = R @ (an - hip) + hip
                f = max(0.0, min(1.0, (an.z + H * 0.03 - v.co.z) / (H * 0.03)))
                v.co = a2 + Matrix.Rotation(-sd * ang * f, 3, "Y") @ (v.co - a2)
        for jn in ("kn_", "an_", "to_"):
            J[jn + name] = hip + R @ (J[jn + name] - hip)
# голова чуть поднята (на базе опущена): поворот выше шеи вокруг шеи (аргумент 9, градусы)
head_up = float(args[8]) if len(args) > 8 else 0.0
if head_up:
    nk = J["neck"]
    for v in me.vertices:
        w = max(0.0, min(1.0, (v.co.z - nk.z) / (H * 0.03)))
        if w > 0:
            v.co = nk + Matrix.Rotation(-math.radians(head_up) * w, 3, "X") @ (v.co - nk)
# голова по референсу: морда длиннее и уже к носу, уши крупнее (параметры — аргументы 6–7)
muzzle_k = float(args[5]) if len(args) > 5 else 1.0
ear_k = float(args[6]) if len(args) > 6 else 1.0
hz0 = J["neck"].z + H * 0.03
HV = [v for v in me.vertices if v.co.z > hz0]
y_nose = min(v.co.y for v in HV)
y_back = max(v.co.y for v in HV)
zt = max(v.co.z for v in HV)
y_stop = y_nose + (y_back - y_nose) * 0.36          # «стоп» — переход лба в морду
if muzzle_k != 1.0:
    for v in HV:
        f = max(0.0, min(1.0, (v.co.z - hz0) / (H * 0.02)))   # у шеи плавно
        if v.co.y < y_stop:
            t = (y_stop - v.co.y) / (y_stop - y_nose)
            v.co.y = y_stop - (y_stop - v.co.y) * (1 + (muzzle_k - 1) * f)
            v.co.x *= 1 - 0.22 * t * f
for nm in ("neck",):
    pass
if ear_k != 1.0:
    for sd in (1, -1):
        ear = [v for v in HV if v.co.z > zt - H * 0.055 and v.co.x * sd > H * 0.008]
        if not ear:
            continue
        zb = min(v.co.z for v in ear)
        base = sum((v.co for v in ear if v.co.z < zb + H * 0.01), Vector()) / max(1, len([v for v in ear if v.co.z < zb + H * 0.01]))
        rad = max(math.hypot(v.co.x - base.x, v.co.y - base.y) for v in ear) * 1.3
        for v in HV:
            if v.co.x * sd <= 0 or math.hypot(v.co.x - base.x, v.co.y - base.y) > rad:
                continue                                   # только само ухо (не вихор между ушами)
            w = max(0.0, min(1.0, (v.co.z - (zb - H * 0.012)) / (H * 0.02)))
            if w <= 0:
                continue
            k = 1 + (ear_k - 1) * w
            d = v.co - base
            v.co = base + Vector((d.x * (1 + (k - 1) * 0.7), d.y * (1 + (k - 1) * 0.5), d.z * k))

# руки вниз: поворот вокруг плеча (ось Y), у дельты — плавный переход
th = math.radians(arm_down)
for sd, name in ((1, "l"), (-1, "r")):
    sh = J["sh_" + name]
    R = Matrix.Rotation(sd * th, 3, "Y")
    for v in me.vertices:
        p = v.co
        if p.x * sd <= 0 or p.z < sh.z - H * 0.13:     # ниже подмышки (бёдра, ноги) — не рука
            continue
        d_ax = math.hypot(p.y - sh.y, p.z - sh.z)
        u = (abs(p.x) - (abs(sh.x) - H * 0.035)) / (H * 0.07)
        w = max(0.0, min(1.0, u))
        w = w * w * (3 - 2 * w)
        if u < 1.0:                                     # только в переходе у плеча: бок торса под мышкой не тянем
            if p.z < sh.z - H * 0.075:
                w *= max(0.0, 1 - (sh.z - H * 0.075 - p.z) / (H * 0.04))
            if d_ax > H * 0.09:
                w *= max(0.0, 1 - (d_ax - H * 0.09) / (H * 0.05))
        if w <= 0:
            continue
        Rw = Matrix.Rotation(sd * th * w, 3, "Y")
        v.co = sh + Rw @ (p - sh)
    for jn in ("el_", "wr_", "palm_"):
        J[jn + name] = sh + R @ (J[jn + name] - sh)
me.update()
# UV для плиточной текстуры меха: развёртка по островам, масштаб ×6 (плитка повторяется)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004)
bpy.ops.object.mode_set(mode="OBJECT")
for d in me.uv_layers.active.data:
    d.uv = d.uv * 6.0
bpy.ops.object.shade_smooth()
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_apply=True)
json.dump({k: list(v) for k, v in J.items()}, open(dst + ".joints.json", "w"), indent=1)
print("faces", len(me.polygons), "H", H, "shoulder", round(px, 3), "crotch", round(crotch, 3))
