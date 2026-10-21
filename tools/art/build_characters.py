"""3D-прототипы персонажей KPC, построенные скриптом в Blender (bpy).

Запуск: /home/user/tools/bpyenv/bin/python tools/art/build_characters.py [kot|gabi|sora ...]
Результат: art/characters/<id>.glb (меш + скелет + анимация idle).

Это прототипы для проверки пропорций, силуэта и гардероба, а не финальные модели художника:
тело — Skin-модификатор + сглаживание, лицо — рисованная текстура (gen_faces.py), волосы — пряди-ленты,
одежда — отдельные меши-шаблоны «garment__<слот>__<шаблон>», которые игра показывает по надетым вещам.
Внешность — по референсам пользователя (art/references/README.md); недостающее не выдумываем —
спорное отмечено в docs/OPEN_QUESTIONS.md.
"""
import math
import os
import random
import sys

import bpy  # noqa: E402 — bpy должен импортироваться раньше bmesh
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "art", "characters")
TEX = os.path.join(OUT, "textures")

SKIN = (0.97, 0.87, 0.82, 1)


# ------------------------------------------------------------------ общие утилиты

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, color, tex=None, vcol=False, rough=0.8):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    if tex:
        img = bpy.data.images.load(tex, check_existing=True)
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = img
        nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
    elif vcol:
        vn = nt.nodes.new("ShaderNodeVertexColor")
        vn.layer_name = "Col"
        nt.links.new(vn.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def new_obj(name, mesh):
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    return o


def apply_mods(o):
    bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def shade_smooth(o):
    for p in o.data.polygons:
        p.use_smooth = True


def skin_obj(name, verts, edges, radii, subdiv=2, material=None):
    """Органическая форма из «скелета» точек: Skin-модификатор + Subdivision, затем применяем."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([Vector(v) for v in verts], edges, [])
    o = new_obj(name, me)
    o.modifiers.new("skin", "SKIN")
    for i, r in enumerate(radii):
        sv = me.skin_vertices[0].data[i]
        sv.radius = (r[0], r[1]) if isinstance(r, tuple) else (r, r)
    # Skin-модификатору нужна корневая вершина в КАЖДОЙ несвязной части (обе ноги, обе руки).
    parent = list(range(len(verts)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for a, b in edges:
        parent[find(a)] = find(b)
    seen = set()
    for i in range(len(verts)):
        r = find(i)
        if r not in seen:
            seen.add(r)
            me.skin_vertices[0].data[i].use_root = True
    sub = o.modifiers.new("sub", "SUBSURF")
    sub.levels = subdiv
    sub.render_levels = subdiv
    apply_mods(o)
    shade_smooth(o)
    if material:
        o.data.materials.append(material)
    return o


def paint_gradient(o, top_z, bottom_z, c_top, c_bottom):
    """Вертикальный градиент цвета в вершинах (для волос: корни → кончики)."""
    me = o.data
    if not me.color_attributes.get("Col"):
        me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    col = me.color_attributes["Col"]
    for poly in me.polygons:
        for li in poly.loop_indices:
            z = me.vertices[me.loops[li].vertex_index].co.z
            t = 0.0 if top_z == bottom_z else min(1, max(0, (top_z - z) / (top_z - bottom_z)))
            col.data[li].color = tuple(c_top[i] * (1 - t) + c_bottom[i] * t for i in range(3)) + (1,)


# ------------------------------------------------------------------ тело

def body_skeleton(p):
    """Точки и рёбра скелета тела (Z вверх, персонаж смотрит в −Y). p — параметры пропорций."""
    s, sw, hw = p["s"], p["shoulder"], p["hip"]
    J = {
        "pelvis": (0, 0, 0.88), "spine": (0, 0, 1.00), "chest": (0, 0, 1.14), "neck": (0, 0, 1.29),
        "head": (0, 0, 1.36),
        "sh_l": (sw, 0, 1.25), "el_l": (sw + 0.05, 0.01, 1.04), "wr_l": (sw + 0.09, -0.01, 0.84), "ha_l": (sw + 0.1, -0.02, 0.76),
        "sh_r": (-sw, 0, 1.25), "el_r": (-sw - 0.05, 0.01, 1.04), "wr_r": (-sw - 0.09, -0.01, 0.84), "ha_r": (-sw - 0.1, -0.02, 0.76),
        "hip_l": (hw, 0, 0.84), "kn_l": (hw + 0.01, -0.01, 0.47), "an_l": (hw + 0.01, 0.01, 0.08), "to_l": (hw + 0.01, -0.1, 0.03),
        "hip_r": (-hw, 0, 0.84), "kn_r": (-hw - 0.01, -0.01, 0.47), "an_r": (-hw - 0.01, 0.01, 0.08), "to_r": (-hw - 0.01, -0.1, 0.03),
    }
    J = {k: Vector((v[0] * s, v[1] * s, v[2] * s)) for k, v in J.items()}
    return J


BODY_EDGES = [("pelvis", "spine"), ("spine", "chest"), ("chest", "neck"), ("neck", "head"),
              ("chest", "sh_l"), ("sh_l", "el_l"), ("el_l", "wr_l"), ("wr_l", "ha_l"),
              ("chest", "sh_r"), ("sh_r", "el_r"), ("el_r", "wr_r"), ("wr_r", "ha_r"),
              ("pelvis", "hip_l"), ("hip_l", "kn_l"), ("kn_l", "an_l"), ("an_l", "to_l"),
              ("pelvis", "hip_r"), ("hip_r", "kn_r"), ("kn_r", "an_r"), ("an_r", "to_r")]


def build_part(name, J, joints, edges, radius_fn, material, subdiv=2):
    idx = {j: i for i, j in enumerate(joints)}
    verts = [J[j] for j in joints]
    e = [(idx[a], idx[b]) for a, b in edges if a in idx and b in idx]
    radii = [radius_fn(j) for j in joints]
    return skin_obj(name, verts, e, radii, subdiv, material)


# ------------------------------------------------------------------ голова и лицо

def build_head(cid, J, p, skin_mat):
    s = p["s"]
    rx, ry, rz = 0.105 * s * p["head"], 0.11 * s * p["head"], 0.125 * s * p["head"]
    cz = J["head"].z + rz * 0.62
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=32, radius=1, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = "head"
    me = o.data
    for v in me.vertices:
        x, y, z = v.co
        # Аниме-пропорции: подбородок сужен и чуть вынесен вперёд, затылок округлый.
        if z < 0:
            k = min(1.0, -z)
            x *= 1 - 0.38 * k ** 1.6
            y *= 1 - 0.25 * k
            y -= 0.12 * k ** 2
            z *= 1 + 0.06 * k
        v.co = Vector((x * rx, y * ry, z * rz + cz))
    # UV: фронтальная проекция лица; задняя половина головы — в угол текстуры (там просто кожа).
    # У UV-сферы уже есть своя развёртка — перезаписываем её (второй слой игра не использует).
    uv = me.uv_layers.active or me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if co.y > 0.02 * s:
                uv.data[li].uv = (0.02, 0.02)
            else:
                uv.data[li].uv = (0.5 + co.x / (2 * rx), 0.5 + (co.z - cz) / (2 * rz))
    shade_smooth(o)
    face_mat = mat(f"face_{cid}", SKIN, tex=os.path.join(TEX, f"face_{cid}.png"))
    me.materials.append(face_mat)
    return o, (rx, ry, rz, cz)


# ------------------------------------------------------------------ волосы

def strand(points, w0, w1, thick, mat_hair, name="hair_strand"):
    """Прядь-лента с ромбовидным сечением, сужается к кончику."""
    bm = bmesh.new()
    rings = []
    n = len(points)
    for i, pt in enumerate(points):
        pt = Vector(pt)
        t = i / (n - 1)
        tan = (Vector(points[min(i + 1, n - 1)]) - Vector(points[max(i - 1, 0)])).normalized()
        out = Vector((pt.x, pt.y, 0)).normalized() if Vector((pt.x, pt.y, 0)).length > 1e-4 else Vector((0, 1, 0))
        side = tan.cross(out).normalized()
        nrm = side.cross(tan).normalized()
        w = (w0 * (1 - t) + w1 * t) / 2
        th = thick * (1 - 0.7 * t) / 2
        ring = [bm.verts.new(pt + side * w), bm.verts.new(pt + nrm * th), bm.verts.new(pt - side * w), bm.verts.new(pt - nrm * th)]
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    tip = bm.verts.new(Vector(points[-1]) + (Vector(points[-1]) - Vector(points[-2])) * 0.3)
    for k in range(4):
        bm.faces.new((rings[-1][k], rings[-1][(k + 1) % 4], tip))
    bm.faces.new(list(reversed(rings[0])))
    # Нормали наружу: иначе видна только обводка, и пряди выглядят как проволока.
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = new_obj(name, me)
    o.data.materials.append(mat_hair)
    sub = o.modifiers.new("sub", "SUBSURF")
    sub.levels = 1
    apply_mods(o)
    shade_smooth(o)
    return o


def on_scalp(head, theta, phi, lift=1.08):
    """Точка на (чуть увеличенной) поверхности головы. theta — азимут (0 = лицо, −Y), phi — от макушки."""
    rx, ry, rz, cz = head
    x = math.sin(phi) * math.sin(theta) * rx * lift
    y = -math.sin(phi) * math.cos(theta) * ry * lift
    z = math.cos(phi) * rz * lift + cz
    return Vector((x, y, z))


def flow(head, theta, phi0, length, droop, curl=0.0, steps=8, lift=1.08, out=0.0):
    """Путь пряди: начинается на скальпе и стекает вниз по голове, на конце может завиваться."""
    pts = []
    for i in range(steps):
        t = i / (steps - 1)
        phi = phi0 + droop * t
        p = on_scalp(head, theta, min(phi, 2.6), lift + out * t)
        if phi > 2.6:
            p.z -= (phi - 2.6) * head[2] * 0.9
        if curl and t > 0.6:
            c = (t - 0.6) / 0.4
            p += Vector((math.sin(theta), -math.cos(theta), 0)) * curl * head[0] * math.sin(c * math.pi) * 0.6
            p.z += curl * head[2] * 0.25 * c
        pts.append(p)
    # Удлинение вниз (для длинных волос).
    if length > 0:
        last = pts[-1]
        dirv = (pts[-1] - pts[-2]).normalized()
        for k in range(1, 6):
            q = last + Vector((dirv.x * 0.2, dirv.y * 0.2, -1)).normalized() * length * k / 5
            pts.append(q)
    return pts


def build_hair(cid, head, hp, mat_hair):
    rnd = random.Random(hash(cid) % 1000)
    rx, ry, rz, cz = head
    parts = []
    # Основная «шапка» волос.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=24, radius=1)
    cap = bpy.context.active_object
    cap.name = "hair_cap"
    for v in cap.data.vertices:
        x, y, z = v.co
        v.co = Vector((x * rx * 1.07, y * ry * 1.08, z * rz * 1.06 + cz + rz * 0.03))
    bm = bmesh.new()
    bm.from_mesh(cap.data)
    # Убираем переднюю нижнюю часть (лицо) и низ головы.
    kill = [v for v in bm.verts if (v.co.z < cz + rz * 0.05 and v.co.y < -ry * 0.25) or v.co.z < cz - rz * 0.6]
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(cap.data)
    bm.free()
    shade_smooth(cap)
    cap.data.materials.append(mat_hair)
    parts.append(cap)
    # Пряди по кругу.
    n = hp["count"]
    for i in range(n):
        theta = 2 * math.pi * i / n + rnd.uniform(-0.08, 0.08)
        front = math.cos(theta)          # 1 — над лицом
        if front > 0.55:                 # чёлка
            phi0, droop, length = 0.35, hp["bang"] + rnd.uniform(-0.1, 0.1), 0
            curl = hp["curl"] * 0.6
        else:
            phi0, droop = 0.5, hp["side_droop"] + rnd.uniform(-0.15, 0.15)
            length = hp["length"] * (0.6 + 0.4 * (1 - front)) * rnd.uniform(0.85, 1.1)
            curl = hp["curl"]
        pts = flow(head, theta, phi0, length, droop, curl, lift=1.09 + rnd.uniform(0, 0.03), out=0.05)
        parts.append(strand(pts, rx * hp["width"], rx * 0.08, rx * 0.22, mat_hair))
    # Чёлка, закрывающая один глаз (Кот), — отдельная крупная прядь.
    if hp.get("eye_bang"):
        th = -0.42
        pts = flow(head, th, 0.3, 0, 1.35, 0.4, lift=1.12, out=0.04)
        parts.append(strand(pts, rx * 0.75, rx * 0.12, rx * 0.16, mat_hair))
    # Хохолок.
    if hp.get("ahoge"):
        top = on_scalp(head, 0.3, 0.05, 1.05)
        pts = [top + Vector((0.0, -0.01 * k, 0.025 * k - 0.004 * k * k)) * (rx / 0.105) for k in range(7)]
        parts.append(strand(pts, rx * 0.12, rx * 0.03, rx * 0.06, mat_hair))
    # Пучки (Габи): шар + обмотка.
    for side in hp.get("buns", []):
        c = on_scalp(head, side * 1.2, 0.55, 1.15)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=16, radius=rx * 0.36, location=c)
        b = bpy.context.active_object
        b.name = "hair_bun"
        shade_smooth(b)
        b.data.materials.append(mat_hair)
        parts.append(b)
    # Хвост/пучок сзади (Сора).
    if hp.get("ponytail"):
        base = on_scalp(head, math.pi, 1.7, 1.05)
        pts = [base + Vector((0, 0.02 * k, -0.035 * k)) * (rx / 0.105) for k in range(7)]
        parts.append(strand(pts, rx * 0.5, rx * 0.15, rx * 0.4, mat_hair))
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    hair = bpy.context.active_object
    hair.name = "hair"
    paint_gradient(hair, cz + rz * 1.2, cz - rz * 1.0 - hp["length"], hp["c_root"], hp["c_tip"])
    return hair


def build_ears(head, color, inner):
    rx, ry, rz, cz = head
    objs = []
    for side in (-1, 1):
        base = on_scalp(head, side * 0.9, 0.55, 1.0)
        tipv = base + Vector((side * rx * 0.25, ry * 0.05, rz * 0.62))
        bm = bmesh.new()
        a = bm.verts.new(base + Vector((side * -rx * 0.18, -ry * 0.06, -rz * 0.05)))
        b = bm.verts.new(base + Vector((side * rx * 0.3, 0.02 * ry, -rz * 0.08)))
        c = bm.verts.new(base + Vector((0, ry * 0.18, 0)))
        t = bm.verts.new(tipv)
        bm.faces.new((a, b, t)); bm.faces.new((b, c, t)); bm.faces.new((c, a, t)); bm.faces.new((a, c, b))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        me = bpy.data.meshes.new("ear")
        bm.to_mesh(me)
        bm.free()
        o = new_obj("ear", me)
        o.data.materials.append(color)
        sub = o.modifiers.new("sub", "SUBSURF"); sub.levels = 2
        apply_mods(o)
        shade_smooth(o)
        objs.append(o)
        # Розовая внутренняя часть.
        bm = bmesh.new()
        mid = (a.co + b.co) / 2 if False else None
        bm.free()
        inner_o = new_obj("ear_inner", bpy.data.meshes.new("ear_inner"))
        ib = bmesh.new()
        p1 = ib.verts.new(base + Vector((side * -rx * 0.1, -ry * 0.085, rz * 0.02)))
        p2 = ib.verts.new(base + Vector((side * rx * 0.2, -ry * 0.06, rz * 0.0)))
        p3 = ib.verts.new(tipv + Vector((side * -rx * 0.04, -ry * 0.06, -rz * 0.12)))
        ib.faces.new((p1, p2, p3))
        ib.to_mesh(inner_o.data)
        ib.free()
        inner_o.data.materials.append(inner)
        objs.append(inner_o)
    return objs


# ------------------------------------------------------------------ одежда (шаблоны по слотам)

def garment_top(J, p, name, color, sleeve="long", neck=False, loose=0.0):
    joints = ["pelvis", "spine", "chest", "neck", "sh_l", "el_l", "wr_l", "sh_r", "el_r", "wr_r"]
    edges = [("pelvis", "spine"), ("spine", "chest"), ("chest", "sh_l"), ("sh_l", "el_l"), ("el_l", "wr_l"),
             ("chest", "sh_r"), ("sh_r", "el_r"), ("el_r", "wr_r")]
    if neck or sleeve == "none":
        edges.append(("chest", "neck"))
    if sleeve in ("short", "none"):
        cut = ("wr", "el") if sleeve == "short" else ("wr", "el", "sh")
        joints = [j for j in joints if not j.startswith(cut)]
        edges = [e for e in edges if not any(x.startswith(cut) for x in e)]
    s = p["s"]
    vest = sleeve == "none"
    R = {"pelvis": (p["waist"] + 0.025 + loose, 0.1), "spine": (p["waist"] + 0.02 + loose, 0.085),
         "chest": (p["chest"] + 0.02 + loose + (0.035 if vest else 0), 0.095), "neck": (0.05, 0.05),
         "sh_l": 0.058, "sh_r": 0.058, "el_l": 0.05 + loose * 0.5, "el_r": 0.05 + loose * 0.5,
         "wr_l": 0.048 + loose * 0.6, "wr_r": 0.048 + loose * 0.6}
    o = build_part(name, J, joints, edges, lambda j: _rs(R[j], s), color)
    return o


def garment_legs(J, p, name, color, kind="trousers"):
    s = p["s"]
    if kind == "trousers":
        joints = ["spine", "pelvis", "hip_l", "kn_l", "an_l", "hip_r", "kn_r", "an_r"]
        edges = [("spine", "pelvis"), ("pelvis", "hip_l"), ("hip_l", "kn_l"), ("kn_l", "an_l"),
                 ("pelvis", "hip_r"), ("hip_r", "kn_r"), ("kn_r", "an_r")]
        R = {"spine": (p["waist"] + 0.018, 0.08), "pelvis": (p["hip_r"] + 0.02, 0.095), "hip_l": 0.085, "hip_r": 0.085,
             "kn_l": 0.055, "kn_r": 0.055, "an_l": 0.05, "an_r": 0.05}
        return build_part(name, J, joints, edges, lambda j: _rs(R[j], s), color)
    if kind == "socks":
        joints = ["kn_l", "an_l", "to_l", "kn_r", "an_r", "to_r"]
        edges = [("kn_l", "an_l"), ("an_l", "to_l"), ("kn_r", "an_r"), ("an_r", "to_r")]
        R = {"kn_l": 0.048, "kn_r": 0.048, "an_l": 0.036, "an_r": 0.036, "to_l": 0.036, "to_r": 0.036}
        Jk = dict(J)
        Jk["kn_l"] = J["kn_l"] - Vector((0, 0, 0.03 * s)); Jk["kn_r"] = J["kn_r"] - Vector((0, 0, 0.03 * s))
        return build_part(name, Jk, joints, edges, lambda j: _rs(R[j], s), color)
    if kind == "shoes":
        joints = ["an_l", "to_l", "an_r", "to_r"]
        edges = [("an_l", "to_l"), ("an_r", "to_r")]
        R = {"an_l": (0.05, 0.045), "an_r": (0.05, 0.045), "to_l": (0.048, 0.035), "to_r": (0.048, 0.035)}
        Jk = dict(J)
        for k in ("an_l", "an_r"):
            Jk[k] = J[k] - Vector((0, 0, 0.02 * s))
        return build_part(name, Jk, joints, edges, lambda j: _rs(R[j], s), color)
    if kind == "gloves":
        joints = ["el_l", "wr_l", "ha_l", "el_r", "wr_r", "ha_r"]
        Jk = dict(J)
        Jk["el_l"] = J["wr_l"].lerp(J["el_l"], 0.35); Jk["el_r"] = J["wr_r"].lerp(J["el_r"], 0.35)
        edges = [("el_l", "wr_l"), ("wr_l", "ha_l"), ("el_r", "wr_r"), ("wr_r", "ha_r")]
        R = {"el_l": 0.04, "el_r": 0.04, "wr_l": 0.038, "wr_r": 0.038, "ha_l": 0.05, "ha_r": 0.05}
        return build_part(name, Jk, joints, edges, lambda j: _rs(R[j], s), color)


def _rs(r, s):
    return (r[0] * s, r[1] * s) if isinstance(r, tuple) else (r * s, r * s)


def lathe_skirt(J, p, name, color, top_z, bottom_z, r_top, r_bottom, pleats=14, depth=0.012):
    """Юбка-конус со складками."""
    s = p["s"]
    bm = bmesh.new()
    rings = []
    seg = pleats * 4
    for k, (z, r) in enumerate([(top_z, r_top), ((top_z + bottom_z) / 2, (r_top + r_bottom) / 2), (bottom_z, r_bottom)]):
        ring = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            rr = (r + depth * k * math.sin(a * pleats)) * s
            ring.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr * 0.85, z * s)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(seg):
            bm.faces.new((a[i], a[(i + 1) % seg], b[(i + 1) % seg], b[i]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = new_obj(name, me)
    sol = o.modifiers.new("sol", "SOLIDIFY"); sol.thickness = 0.006 * s
    sub = o.modifiers.new("sub", "SUBSURF"); sub.levels = 1
    apply_mods(o)
    shade_smooth(o)
    o.data.materials.append(color)
    return o


def flowers_on(target, count, seed, z_range, color_petal, color_core, scale):
    """Белые цветы на поверхности одежды (свитер Кота по референсу 04)."""
    from mathutils.bvhtree import BVHTree
    deps = bpy.context.evaluated_depsgraph_get()
    tree = BVHTree.FromObject(target, deps)
    rnd = random.Random(seed)
    objs = []
    for _ in range(count):
        x = rnd.uniform(-0.12, 0.12) * scale
        z = rnd.uniform(*z_range) * scale
        hit = tree.ray_cast(Vector((x, -1, z)), Vector((0, 1, 0)))
        if hit[0] is None:
            continue
        loc, nrm = hit[0], hit[1]
        r = rnd.uniform(0.012, 0.02) * scale
        bm = bmesh.new()
        center = bm.verts.new(loc + nrm * 0.002)
        up = nrm.cross(Vector((0, 0, 1))).normalized()
        if up.length < 0.1:
            up = Vector((1, 0, 0))
        side = nrm.cross(up).normalized()
        petals = []
        for k in range(10):
            a = 2 * math.pi * k / 10
            rr = r if k % 2 == 0 else r * 0.45
            petals.append(bm.verts.new(loc + nrm * 0.003 + (up * math.cos(a) + side * math.sin(a)) * rr))
        for k in range(10):
            bm.faces.new((center, petals[k], petals[(k + 1) % 10]))
        me = bpy.data.meshes.new("flower")
        bm.to_mesh(me)
        bm.free()
        o = new_obj("flower", me)
        o.data.materials.append(color_petal)
        objs.append(o)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=r * 0.25, location=loc + nrm * 0.004)
        c = bpy.context.active_object
        c.data.materials.append(color_core)
        objs.append(c)
    return objs


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    return o


# ------------------------------------------------------------------ скелет и анимация

BONES = [  # имя, от, до, родитель
    ("hips", "pelvis", "spine", None), ("spine", "spine", "chest", "hips"), ("chest", "chest", "neck", "spine"),
    ("neck", "neck", "head", "chest"), ("head", "head", "head_top", "neck"),
    ("upper_arm.L", "sh_l", "el_l", "chest"), ("forearm.L", "el_l", "wr_l", "upper_arm.L"), ("hand.L", "wr_l", "ha_l", "forearm.L"),
    ("upper_arm.R", "sh_r", "el_r", "chest"), ("forearm.R", "el_r", "wr_r", "upper_arm.R"), ("hand.R", "wr_r", "ha_r", "forearm.R"),
    ("thigh.L", "hip_l", "kn_l", "hips"), ("shin.L", "kn_l", "an_l", "thigh.L"), ("foot.L", "an_l", "to_l", "shin.L"),
    ("thigh.R", "hip_r", "kn_r", "hips"), ("shin.R", "kn_r", "an_r", "thigh.R"), ("foot.R", "an_r", "to_r", "shin.R"),
]


def build_armature(J, head_top):
    J = dict(J)
    J["head_top"] = head_top
    arm = bpy.data.armatures.new("rig")
    rig = new_obj("rig", arm)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.edit_bones
    for name, a, b, parent in BONES:
        bone = eb.new(name)
        bone.head = J[a]
        bone.tail = J[b]
        if parent:
            bone.parent = eb[parent]
            bone.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def _seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


def bind(rig, objs, rigid_bone=None):
    """Привязка к скелету. Веса считаем сами (две ближайшие кости, обратное расстояние):
    автоматические веса Blender (heat) не срабатывают на несвязных мешах вроде цветов и носков."""
    bones = [(b.name, b.head_local.copy(), b.tail_local.copy()) for b in rig.data.bones if b.name != "head"]
    for o in objs:
        o.parent = rig
        mod = o.modifiers.new("rig", "ARMATURE")
        mod.object = rig
        if rigid_bone:
            vg = o.vertex_groups.new(name=rigid_bone)
            vg.add(range(len(o.data.vertices)), 1.0, "REPLACE")
            continue
        groups = {name: o.vertex_groups.new(name=name) for name, _, _ in bones}
        mw = o.matrix_world
        for v in o.data.vertices:
            p = mw @ v.co
            d = sorted(((_seg_dist(p, h, t), name) for name, h, t in bones))[:2]
            w0, w1 = 1.0 / max(d[0][0], 1e-4) ** 2, 1.0 / max(d[1][0], 1e-4) ** 2
            # Вторая кость влияет только около суставов.
            if d[1][0] > d[0][0] * 1.8:
                w1 = 0.0
            tot = w0 + w1
            groups[d[0][1]].add([v.index], w0 / tot, "REPLACE")
            if w1 > 0:
                groups[d[1][1]].add([v.index], w1 / tot, "ADD")


def idle_animation(rig, frames=96):
    """Анимация покоя: дыхание грудью, лёгкое покачивание головы и рук."""
    rig.animation_data_create()
    act = bpy.data.actions.new("idle")
    rig.animation_data.action = act
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    pb = rig.pose.bones
    for pbone in pb:
        pbone.rotation_mode = "XYZ"
    for f in range(0, frames + 1, 12):
        t = f / frames * 2 * math.pi
        pb["chest"].rotation_euler = (math.sin(t) * 0.025, 0, 0)
        pb["chest"].scale = (1 + math.sin(t) * 0.008,) * 3
        pb["head"].rotation_euler = (math.sin(t + 0.6) * 0.03, math.sin(t * 0.5) * 0.04, 0)
        pb["upper_arm.L"].rotation_euler = (0, 0, math.sin(t) * 0.02)
        pb["upper_arm.R"].rotation_euler = (0, 0, -math.sin(t) * 0.02)
        for name in ("chest", "head", "upper_arm.L", "upper_arm.R"):
            pb[name].keyframe_insert("rotation_euler", frame=f)
        pb["chest"].keyframe_insert("scale", frame=f)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = frames


# ------------------------------------------------------------------ персонажи

CHARACTERS = {
    # Кот (реф. 04): 163 см, стройный; бирюзовые кудри → синие концы, чёлка на один глаз, уши, хохолок.
    "kot": {
        "body": {"s": 1.0, "shoulder": 0.145, "hip": 0.08, "head": 1.28, "waist": 0.085, "chest": 0.1, "hip_r": 0.1},
        "hair": {"count": 22, "bang": 1.05, "side_droop": 1.5, "length": 0.03, "curl": 0.45, "width": 0.62,
                 "eye_bang": True, "ahoge": True, "c_root": (0.25, 0.75, 0.66), "c_tip": (0.24, 0.48, 0.85)},
        "ears": (0.27, 0.68, 0.62), "ear_inner": (0.95, 0.7, 0.72),
        "garments": ["top_turtleneck_flowers", "top_tshirt", "top_long", "outer_jacket", "legs_trousers", "legs_skirt",
                     "dress", "socks", "shoes", "gloves", "head_clips", "face_eyepatch", "neck_necklace"],
    },
    # Габи (реф. 05–07): рост не задан (см. OPEN_QUESTIONS) — берём близко к Коту; два пучка + распущенные волосы.
    "gabi": {
        "body": {"s": 0.98, "shoulder": 0.135, "hip": 0.085, "head": 1.28, "waist": 0.078, "chest": 0.098, "hip_r": 0.11},
        "hair": {"count": 26, "bang": 0.95, "side_droop": 1.7, "length": 0.42, "curl": 0.15, "width": 0.6,
                 "buns": [-1, 1], "c_root": (0.78, 0.3, 0.42), "c_tip": (0.98, 0.62, 0.3)},
        "ears": None,
        "garments": ["top_tshirt", "top_long", "outer_jacket", "legs_trousers", "legs_skirt", "dress", "socks", "shoes",
                     "gloves_paws", "face_eyepatch", "neck_necklace", "head_clips"],
    },
    # Сора (реф. 12): 206 см, шире в плечах; растрёпанные бирюзовые волосы с хвостом, уши, хохолок.
    "sora": {
        "body": {"s": 206 / 163, "shoulder": 0.17, "hip": 0.085, "head": 1.05, "waist": 0.095, "chest": 0.115, "hip_r": 0.105},
        "hair": {"count": 22, "bang": 1.0, "side_droop": 1.5, "length": 0.05, "curl": 0.25, "width": 0.62,
                 "ahoge": True, "ponytail": True, "c_root": (0.22, 0.62, 0.62), "c_tip": (0.18, 0.46, 0.55)},
        "ears": (0.22, 0.6, 0.6), "ear_inner": (0.9, 0.68, 0.72),
        "garments": ["top_long", "top_tshirt", "outer_vest", "outer_jacket", "legs_trousers", "socks", "shoes",
                     "neck_tie", "face_eyepatch", "neck_necklace", "head_clips"],
    },
}


def build(cid):
    reset()
    c = CHARACTERS[cid]
    p = c["body"]
    J = body_skeleton(p)
    skin = mat("skin", SKIN, rough=0.6)
    hair_m = mat("hair", (1, 1, 1, 1), vcol=True, rough=0.5)
    s = p["s"]

    R = {"pelvis": (p["hip_r"], 0.085), "spine": (p["waist"], 0.07), "chest": (p["chest"], 0.08), "neck": 0.034, "head": 0.03,
         "sh_l": 0.045, "sh_r": 0.045, "el_l": 0.032, "el_r": 0.032, "wr_l": 0.024, "wr_r": 0.024, "ha_l": (0.03, 0.016),
         "ha_r": (0.03, 0.016), "hip_l": 0.075, "hip_r": 0.075, "kn_l": 0.043, "kn_r": 0.043, "an_l": 0.028, "an_r": 0.028,
         "to_l": (0.03, 0.022), "to_r": (0.03, 0.022)}
    body = build_part("body", J, list(J.keys()), BODY_EDGES, lambda j: _rs(R[j], s), skin)
    head, hd = build_head(cid, J, p, skin)
    hair = build_hair(cid, hd, c["hair"], hair_m)
    head_parts = [head, hair]
    if c.get("ears"):
        ears = build_ears(hd, mat("ear", c["ears"] + (1,)), mat("ear_inner", c["ear_inner"] + (1,)))
        head_parts += ears

    white = mat("garment_white", (1, 1, 1, 1))
    garments = []
    for g in c["garments"]:
        gname = None
        o = None
        if g == "top_turtleneck_flowers":
            o = garment_top(J, p, "tmp", white, "long", neck=True, loose=0.012)
            fl = flowers_on(o, 9, 4, (1.0, 1.24), mat("flower", (1, 1, 1, 1)), mat("flower_core", (0.95, 0.85, 0.55, 1)), s)
            gname = "garment__upper_body__turtleneck_flowers"
            o = join([o] + fl, gname)
        elif g == "top_long":
            o = garment_top(J, p, "garment__upper_body__long", white, "long", neck=False)
        elif g == "top_tshirt":
            o = garment_top(J, p, "garment__upper_body__tshirt", white, "short")
        elif g == "outer_jacket":
            o = garment_top(J, p, "garment__outerwear__jacket", white, "long", loose=0.022)
        elif g == "outer_vest":
            o = garment_top(J, p, "garment__outerwear__vest", white, "none", loose=0.012)
        elif g == "legs_trousers":
            o = garment_legs(J, p, "garment__lower_body__trousers", white, "trousers")
        elif g == "legs_skirt":
            o = lathe_skirt(J, p, "garment__lower_body__skirt", white, 0.98, 0.66, p["waist"] + 0.02, 0.2)
        elif g == "dress":
            top = garment_top(J, p, "tmp", white, "none", loose=0.006)
            sk = lathe_skirt(J, p, "tmp2", white, 0.95, 0.18, p["waist"] + 0.025, 0.3, pleats=10)
            o = join([top, sk], "garment__full_body__dress")
        elif g == "socks":
            o = garment_legs(J, p, "garment__socks__knee", white, "socks")
        elif g == "shoes":
            o = garment_legs(J, p, "garment__footwear__shoes", white, "shoes")
        elif g in ("gloves", "gloves_paws"):
            o = garment_legs(J, p, "garment__gloves__gloves", white, "gloves")
        elif g == "head_clips":
            # Заколки: рыбка и облачко (реф. 04) — как шаблон слота headwear.
            a = on_scalp(hd, -0.9, 0.75, 1.13)
            b = on_scalp(hd, 0.7, 0.55, 1.13)
            bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=hd[0] * 0.18, location=a)
            fish = bpy.context.active_object; fish.scale = (1.0, 0.5, 0.6)
            bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=hd[0] * 0.1, depth=hd[0] * 0.14, location=a + Vector((hd[0] * 0.2, 0, 0)), rotation=(0, math.pi / 2, 0))
            tail = bpy.context.active_object
            clouds = []
            for k in range(3):
                bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=hd[0] * (0.09 + 0.03 * (k == 1)), location=b + Vector(((k - 1) * hd[0] * 0.11, 0, 0)))
                clouds.append(bpy.context.active_object)
            for o2 in [fish, tail] + clouds:
                shade_smooth(o2)
                o2.data.materials.append(white)
            o = join([fish, tail] + clouds, "garment__headwear__clips")
        elif g == "face_eyepatch":
            # Повязка на правом глазу (снимаемый аксессуар; глаз под ней открыт) + тонкий ремешок наискось.
            rx, ry, rz, cz = hd
            ex = -0.38 * rx
            ez = cz - 0.09 * rz
            bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, radius=1, location=(ex, -ry * 0.9, ez))
            patch = bpy.context.active_object
            patch.scale = (rx * 0.19, ry * 0.07, rz * 0.16)
            bpy.ops.object.transform_apply(scale=True)
            shade_smooth(patch)
            patch.data.materials.append(white)
            ring = []
            for k in range(25):
                a = 2 * math.pi * k / 24
                # Наклонённое кольцо: через повязку спереди, над ухом, к затылку.
                x = math.sin(a) * rx * 1.04
                y = -math.cos(a) * ry * 1.04
                z = ez + (rz * 0.55) * (0.5 - 0.5 * math.cos(a)) + (rz * 0.25) * math.sin(a) * 0.3
                ring.append(Vector((x, y, z)))
            strap = strand(ring, rx * 0.045, rx * 0.045, rx * 0.02, white, "strap")
            o = join([patch, strap], "garment__face_accessory__eyepatch")
        elif g == "neck_necklace":
            beads = []
            nz = J["neck"].z - 0.02 * s
            for k in range(18):
                a = math.pi * (0.15 + 0.7 * k / 17)
                loc = Vector((math.cos(a) * 0.06 * s, -math.sin(a) * 0.065 * s - 0.01 * s, nz - math.sin(a) * 0.03 * s))
                bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=0.007 * s, location=loc)
                beads.append(bpy.context.active_object)
                beads[-1].data.materials.append(white)
            o = join(beads, "garment__neck_accessory__necklace")
        elif g == "neck_tie":
            nz = J["neck"].z - 0.02 * s
            bm = bmesh.new()
            pts = [(0, nz), (0.012, nz - 0.03), (0.02, nz - 0.2), (0, nz - 0.24), (-0.02, nz - 0.2), (-0.012, nz - 0.03)]
            vs = [bm.verts.new((x * s, -(p["chest"] + 0.03) * s, z)) for x, z in pts]
            bm.faces.new(vs)
            me = bpy.data.meshes.new("tie")
            bm.to_mesh(me); bm.free()
            o = new_obj("garment__neck_accessory__tie", me)
            sol = o.modifiers.new("sol", "SOLIDIFY"); sol.thickness = 0.006
            apply_mods(o)
            o.data.materials.append(white)
        if o is not None:
            garments.append(o)

    head_top = Vector((0, 0, hd[3] + hd[2]))
    rig = build_armature(J, head_top)
    bind(rig, [body] + [g for g in garments if not g.name.startswith(("garment__headwear", "garment__face"))])
    bind(rig, head_parts + [g for g in garments if g.name.startswith(("garment__headwear", "garment__face"))], rigid_bone="head")
    idle_animation(rig)

    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{cid}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_animations=True, export_skins=True,
                              export_yup=True, export_apply=False)
    print("exported", path, "garments:", [g.name for g in garments])


if __name__ == "__main__":
    ids = [a for a in sys.argv[1:] if a in CHARACTERS] or list(CHARACTERS)
    for cid in ids:
        build(cid)
