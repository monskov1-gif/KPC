"""3D-прототипы персонажей KPC (версия 2), построенные скриптом в Blender (bpy).

Запуск:
  python3 tools/art/gen_faces.py                                   # текстуры лица, глаз, волос, тканей
  /home/user/tools/bpyenv/bin/python tools/art/build_characters.py [kot|gabi|sora ...]
Результат: art/characters/<id>.glb (меш + скелет + анимация idle).

Ориентир качества — модель-образец из art/references/3d/ (только для изучения пропорций и устройства;
её геометрия и текстуры НЕ используются). Что взято как принцип:
  • пропорции ~1/7 роста на голову, вытянутые ноги, узкая талия;
  • лицо — вылепленная голова + рисованная текстура; глаза — отдельные глазные яблоки за прорезями век;
  • волосы — слои полупрозрачных «карт» прядей с цветом от корней к кончикам;
  • одежда — отдельные слои с фактурой ткани.
Одежда — меши-шаблоны «garment__<слот>__<шаблон>» (игра показывает их по надетым вещам).
Бельё — «underwear__*»: всегда на персонаже, раздеть полностью нельзя.
Внешность — по референсам пользователя (art/references/README.md); спорное — docs/OPEN_QUESTIONS.md.
"""
import math
import os
import random
import sys

import bpy  # noqa: E402 — bpy должен импортироваться раньше bmesh
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "art", "characters")
TEX = os.path.join(OUT, "textures")

SKIN = (0.98, 0.88, 0.83, 1)
import json  # noqa: E402
_FACE = json.load(open(os.path.join(os.path.dirname(__file__), "face_params.json"), encoding="utf-8"))
FP = dict(_FACE["default"])   # параметры лица текущего персонажа (face_params.json; задаются в build())


def set_face(cid):
    global FP
    FP = dict(_FACE["default"])
    FP.update(_FACE.get(cid, {}))


# ------------------------------------------------------------------ утилиты

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, color, tex=None, vcol=False, rough=0.8, clip=False, double=False):
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
        if vcol:
            vn = nt.nodes.new("ShaderNodeVertexColor")
            vn.layer_name = "Col"
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            nt.links.new(tn.outputs["Color"], mix.inputs[6])
            nt.links.new(vn.outputs["Color"], mix.inputs[7])
            nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        else:
            nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
        if clip:
            nt.links.new(tn.outputs["Alpha"], bsdf.inputs["Alpha"])
    elif vcol:
        vn = nt.nodes.new("ShaderNodeVertexColor")
        vn.layer_name = "Col"
        nt.links.new(vn.outputs["Color"], bsdf.inputs["Base Color"])
    if clip:
        m.blend_method = "CLIP" if hasattr(m, "blend_method") else m.blend_method
        try:
            m.surface_render_method = "DITHERED"
        except AttributeError:
            pass
    m.use_backface_culling = not double
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


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    return o


def skin_obj(name, verts, edges, radii, subdiv=2, material=None):
    """Органическая форма по «скелету» точек: Skin-модификатор + Subdivision, затем применяем."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([Vector(v) for v in verts], edges, [])
    o = new_obj(name, me)
    o.modifiers.new("skin", "SKIN")
    for i, r in enumerate(radii):
        sv = me.skin_vertices[0].data[i]
        sv.radius = (r[0], r[1]) if isinstance(r, tuple) else (r, r)
    # Корневая вершина нужна в КАЖДОЙ несвязной части (обе ноги, обе руки).
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
        if find(i) not in seen:
            seen.add(find(i))
            me.skin_vertices[0].data[i].use_root = True
    sub = o.modifiers.new("sub", "SUBSURF")
    sub.levels = subdiv
    sub.render_levels = subdiv
    apply_mods(o)
    shade_smooth(o)
    if material:
        o.data.materials.append(material)
    return o


def cylinder_uv(o, scale_u=3.0, scale_v=5.0):
    """Цилиндрическая развёртка вокруг вертикали — для фактуры ткани (вязка, плетение)."""
    me = o.data
    uv = me.uv_layers.active or me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        us = []
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            us.append((li, (math.atan2(co.x, -co.y) / (2 * math.pi) + 0.5) * scale_u, co.z * scale_v))
        # Шов сзади: грань, перескакивающую через u=0/1, «разворачиваем» (масштаб u — целый, фактура повторяется).
        wrap = max(u for _, u, _ in us) - min(u for _, u, _ in us) > scale_u / 2
        for li, u, v in us:
            uv.data[li].uv = (u + scale_u if wrap and u < scale_u / 2 else u, v)


def paint_gradient(o, top_z, bottom_z, c_top, c_bottom, by_uv=False, strand_jitter=0.0):
    """Цвет в вершинах: корни → кончики (по высоте или по UV-v карты пряди).
    strand_jitter — у каждой отдельной пряди (связного куска меша) свой оттенок ± доля: пряди читаются по отдельности."""
    me = o.data
    tint = {}
    if strand_jitter:
        parent = list(range(len(me.vertices)))

        def find(i):
            while parent[i] != i:
                parent[i] = parent[parent[i]]
                i = parent[i]
            return i
        for e in me.edges:
            a, b = find(e.vertices[0]), find(e.vertices[1])
            if a != b:
                parent[a] = b
        rnd = random.Random(5)
        for poly in me.polygons:
            r = find(poly.vertices[0])
            if r not in tint:
                tint[r] = 1 + rnd.uniform(-strand_jitter, strand_jitter)
            tint[poly.index] = tint[r]
    if not me.color_attributes.get("Col"):
        me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    col = me.color_attributes["Col"]
    uvl = me.uv_layers.active
    for poly in me.polygons:
        for li in poly.loop_indices:
            if by_uv and uvl:
                t = 1.0 - uvl.data[li].uv[1]
            else:
                z = me.vertices[me.loops[li].vertex_index].co.z
                t = 0.0 if top_z == bottom_z else min(1, max(0, (top_z - z) / (top_z - bottom_z)))
            t = t ** 1.4
            k = tint.get(poly.index, 1.0) if tint else 1.0
            col.data[li].color = tuple(min(1.0, (c_top[i] * (1 - t) + c_bottom[i] * t) * k) for i in range(3)) + (1,)


def _rs(r, s):
    return (r[0] * s, r[1] * s) if isinstance(r, tuple) else (r * s, r * s)


# ------------------------------------------------------------------ тело

def body_joints(p):
    """Точки скелета (Z вверх, персонаж смотрит в −Y). Пропорции ~1/7 роста на голову."""
    s, sw, hw = p["s"], p["shoulder"], p["hip"]
    ao = p.get("arm_out", (0.035, 0.06))       # насколько локоть и запястье отведены от плеча (А-поза)
    J = {
        "pelvis": (0, 0, 0.90), "spine": (0, 0.005, 1.02), "chest": (0, 0, 1.15), "upchest": (0, 0.006, 1.255), "neck": (0, 0.008, 1.335),
        "head": (0, 0.01, 1.39), "throat": (0, 0.014, 1.46),   # шея уходит внутрь головы — без зазора под подбородком
        "sh_l": (sw, 0.01, 1.295), "el_l": (sw + ao[0], 0.02, 1.05), "wr_l": (sw + ao[1], 0.0, 0.83),
        "sh_r": (-sw, 0.01, 1.295), "el_r": (-sw - ao[0], 0.02, 1.05), "wr_r": (-sw - ao[1], 0.0, 0.83),
        "hip_l": (hw, 0, 0.86), "kn_l": (hw - 0.005, -0.012, 0.47), "an_l": (hw - 0.004, 0.012, 0.075), "to_l": (hw - 0.002, -0.095, 0.022),
        "hip_r": (-hw, 0, 0.86), "kn_r": (-hw + 0.005, -0.012, 0.47), "an_r": (-hw + 0.004, 0.012, 0.075), "to_r": (-hw + 0.002, -0.095, 0.022),
    }
    J = {k: Vector(v) * s for k, v in J.items()}
    # Кисть: ладонь + 4 пальца + большой палец (руки в A-позе, ладонь к бедру).
    for side, sx in (("l", 1), ("r", -1)):
        wr = J["wr_" + side]
        palm = wr + Vector((0.006 * sx, -0.004, -0.045)) * s
        J["palm_" + side] = palm
        for k, dy in enumerate((-0.016, -0.005, 0.006, 0.016)):
            ln = (0.026, 0.03, 0.028, 0.022)[k]
            base = palm + Vector((0.002 * sx, dy, -0.022)) * s
            J[f"f{k}a_{side}"] = base
            J[f"f{k}b_{side}"] = base + Vector((0.0, dy * 0.12, -ln * 0.55)) * s
            J[f"f{k}c_{side}"] = base + Vector((-0.003 * sx, dy * 0.2, -ln)) * s
        J["tha_" + side] = wr + Vector((0.0, -0.016, -0.02)) * s
        J["thb_" + side] = wr + Vector((-0.004 * sx, -0.032, -0.045)) * s
    return J


def build_mh_body(p, sex, skin_mat):
    """Тело на базовой модели MakeHuman (CC0): см. tools/art/mh_body.py. Возвращает (объект, J)."""
    sys.path.insert(0, os.path.dirname(__file__))
    import mh_body
    s = p["s"]
    mh = p["mh"]
    vs, faces, groups = mh_body.shape(sex, teen=mh.get("teen", 0.45), thin=mh.get("thin", 0.7), bust=mh.get("bust", 0.0))
    sk = mh_body.pose_arms(vs, groups, mh.get("arms_down", 15))
    mh_body.lengthen(vs, groups, sk, arm=mh.get("arm_len", 1.2), foot=mh.get("foot_len", 1.12))
    verts, fcs, M = mh_body.to_character(vs, faces, groups, neck_z=mh["neck_z"] * s, pelvis_z=mh["pelvis_z"] * s,
                                          slim=mh.get("slim", 1.0), legw=mh_body.leg_weights(sk))
    me = bpy.data.meshes.new("body")
    me.from_pydata([Vector(v) for v in verts], [], fcs)
    me.validate()
    o = new_obj("body", me)
    # Шея продлевается вверх внутрь нашей головы (голова MakeHuman срезана).
    bm = bmesh.new()
    bm.from_mesh(me)
    top = [e for e in bm.edges if e.is_boundary and all(v.co.z > mh["neck_z"] * s - 0.03 * s for v in e.verts)]
    for step in range(3):
        res = bmesh.ops.extrude_edge_only(bm, edges=top)
        nv = [g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)]
        c = sum((v.co for v in nv), Vector()) / len(nv)
        for v in nv:
            d = v.co - c
            v.co = c + Vector((d.x * 0.93, d.y * 0.93, 0)) + Vector((0, 0.004 * s, 0.03 * s))
        top = [g for g in res["geom"] if isinstance(g, bmesh.types.BMEdge) and g.is_boundary]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    # Без subdivision: у базовой сетки ~13k граней — достаточно для гладкого тела, а одежда-оболочки
    # (копии тела) остаются лёгкими для веб-версии.
    shade_smooth(o)
    me.materials.append(skin_mat)
    V = lambda k: Vector(M[k])
    spines = sorted([k for k in M if k.startswith("spine-")], key=lambda k: M[k][2])
    J = {"pelvis": V("pelvis"), "spine": V(spines[0]), "chest": V(spines[1]), "upchest": V(spines[-1]), "neck": V("neck")}
    J["head"] = J["neck"] + Vector((0, 0.002, 0.055)) * s
    for side, mk in (("l", "l"), ("r", "r")):
        J["sh_" + side] = V(f"{mk}-shoulder")
        J["el_" + side] = V(f"{mk}-elbow")
        J["wr_" + side] = V(f"{mk}-hand")
        J["palm_" + side] = V(f"{mk}-finger-3-1")
        J["hip_" + side] = V(f"{mk}-upper-leg")
        J["kn_" + side] = V(f"{mk}-knee")
        J["an_" + side] = V(f"{mk}-ankle")
        J["to_" + side] = V(f"{mk}-toe-3-1")
    return o, J


def body_edges():
    e = [("pelvis", "spine"), ("spine", "chest"), ("chest", "upchest"), ("upchest", "neck"), ("neck", "head"), ("head", "throat"),
         ("pelvis", "hip_l"), ("hip_l", "kn_l"), ("kn_l", "an_l"), ("an_l", "to_l"),
         ("pelvis", "hip_r"), ("hip_r", "kn_r"), ("kn_r", "an_r"), ("an_r", "to_r")]
    for s in ("l", "r"):
        e += [("upchest", "sh_" + s), ("sh_" + s, "el_" + s), ("el_" + s, "wr_" + s), ("wr_" + s, "palm_" + s),
              ("wr_" + s, "tha_" + s), ("tha_" + s, "thb_" + s)]
        for k in range(4):
            e += [("palm_" + s, f"f{k}a_{s}"), (f"f{k}a_{s}", f"f{k}b_{s}"), (f"f{k}b_{s}", f"f{k}c_{s}")]
    return e


def body_radii(p):
    R = {"pelvis": (p["hip_r"], 0.078), "spine": (p["waist"], 0.066), "chest": (p["chest"], p.get("chest_d", 0.072)),
         "upchest": (p["chest"] * 0.95, p.get("chest_d", 0.072) * 0.82), "neck": p.get("neck", 0.03), "head": p.get("neck", 0.03) * 0.9, "throat": p.get("neck", 0.03) * 0.75, "sh_l": 0.043, "sh_r": 0.043, "el_l": 0.03, "el_r": 0.03, "wr_l": 0.021, "wr_r": 0.021,
         "hip_l": 0.072, "hip_r": 0.072, "kn_l": 0.042, "kn_r": 0.042, "an_l": 0.026, "an_r": 0.026,
         "to_l": (0.028, 0.018), "to_r": (0.028, 0.018)}
    for s in ("l", "r"):
        R["palm_" + s] = (0.012, 0.026)
        R["tha_" + s] = 0.009
        R["thb_" + s] = 0.007
        for k in range(4):
            R[f"f{k}a_{s}"] = 0.0075
            R[f"f{k}b_{s}"] = 0.0065
            R[f"f{k}c_{s}"] = 0.0055
    return R


def build_part(name, J, joints, edges, radius_fn, material, subdiv=2):
    idx = {j: i for i, j in enumerate(joints)}
    verts = [J[j] for j in joints]
    e = [(idx[a], idx[b]) for a, b in edges if a in idx and b in idx]
    return skin_obj(name, verts, e, [radius_fn(j) for j in joints], subdiv, material)


# ------------------------------------------------------------------ голова, лицо, глаза

def gauss(x):
    return math.exp(-x * x)


def _pw(z, pts):
    """Кусочно-линейная функция по точкам [(z, значение)], z по убыванию."""
    if z >= pts[0][0]:
        return pts[0][1]
    for (z0, v0), (z1, v1) in zip(pts, pts[1:]):
        if z0 >= z >= z1:
            return v0 + (v1 - v0) * (z - z0) / (z1 - z0)
    return pts[-1][1]


# Силуэт лица в нормированных координатах головы (z: +1 макушка, −1 низ подбородка); полуширина челюсти — FP["jaw"].
FACE_DEPTH = [(0.3, 0.954), (0.1, 0.975), (-0.1, 0.985), (-0.4, 0.94), (-0.6, 0.88), (-0.75, 0.83), (-0.88, 0.76),
              (-0.96, 0.55), (-1.0, 0.25)]                                                                  # глубина по средней линии


def sculpt_head(x, y, z):
    """Лепка головы из единичной сферы (персонаж смотрит в −Y): V-образная челюсть с углом, острый
    подбородок, плоская передняя часть лица, виски, скулы, глазницы, надбровья, нос (спинка, кончик,
    крылья), губы, ямка под губой, подбородок. Без этого голова — «яйцо»."""
    g = math.exp
    front = max(0.0, -y)
    fw = min(1.0, max(0.0, (0.3 - y) / 0.6))          # 1 — лицо, 0 — затылок
    if z < 0.1:                                          # челюсть сужается к подбородку
        nat = math.sqrt(max(1e-4, 1 - z * z))
        f = min(1.0, _pw(z, [tuple(q) for q in FP["jaw"]]) / nat)
        x *= 1 - (1 - f) * fw
    if y < 0 and z < 0.3:                                # профиль: подбородок вперёд, лицо ровнее
        nat = math.sqrt(max(1e-4, 1 - z * z))
        gk = _pw(z, FACE_DEPTH) / nat
        blend = min(1.0, (0.3 - z) / 0.3)
        y *= 1 + (gk - 1) * blend
    if z < -0.2:                                         # линия челюсти: низ затылка уходит в шею, а не в «шар»
        b = min(1.0, (-0.2 - z) / 0.8) ** 1.2
        k = 1 - 0.5 * b * (1 - fw)
        x *= k
        if y > -0.35:
            y = -0.35 + (y + 0.35) * (1 - 0.45 * b)
    if y > 0:                                            # объёмный затылок
        y *= 1.06
        z += 0.04 * y
    # Черепная коробка (шаблон аниме-головы): виски и затылок шире и длиннее лица, макушка выше —
    # лицо лежит на передней части головы, а не шире её.
    sx, sy, sz = FP.get("cranium", (1.0, 1.0, 1.0))

    def sstep(a, b, v):
        t_ = min(1.0, max(0.0, (v - a) / (b - a)))
        return t_ * t_ * (3 - 2 * t_)
    side_w = sstep(-0.65, 0.05, y)
    vert_w = sstep(-0.6, 0.05, z)
    top_w = sstep(0.0, 0.55, z)
    w_cr = max(side_w * vert_w, top_w)
    x *= 1 + (sx - 1) * w_cr
    if y > 0:
        y *= 1 + (sy - 1) * vert_w
    if z > 0:
        z *= 1 + (sz - 1) * sstep(0.0, 0.6, z)
    return sculpt_features(x, y, z, temples=True)


def sculpt_features(x, y, z, temples=False):
    """Черты лица поверх формы головы: виски, скулы, глазницы, надбровья, нос, губы, подбородок."""
    g = math.exp
    front = max(0.0, -y)
    ax = abs(x)
    if not temples:
        front = min(1.0, front)
    # Виски чуть уже, скулы чуть выпуклее.
    x *= 1 - 0.035 * g(-((ax - 0.9) / 0.15) ** 2) * g(-((z - 0.2) / 0.25) ** 2)
    y -= 0.03 * front * g(-((ax - 0.5) / 0.2) ** 2) * g(-((z + 0.28) / 0.15) ** 2)
    NOSE_TIP_Z, MOUTH_Z = FP["nose_z"], FP["mouth_z"]
    ex, ez = 2 * FP["eye_u"], 1 - 2 * FP["eye_v"]          # центр глаза в нормированных координатах
    ew, eh = 2 * FP["eye_w"], 2 * FP["eye_h"]
    mw = 2 * FP["mouth_w"]
    # Глазницы и надбровья.
    y += 0.045 * front * g(-((ax - ex) / (ew * 0.9)) ** 2) * g(-((z - ez) / (eh * 1.6)) ** 2)
    y -= 0.022 * front * g(-((ax - ex) / (ew * 1.1)) ** 2) * g(-((z - ez - eh * 2.0) / 0.07) ** 2)
    # Нос: спинка от переносицы к кончику, кончик, крылья.
    top = ez + 0.03
    t = min(1.0, max(0.0, (top - z) / (top - NOSE_TIP_Z)))
    amt = 0.014 + 0.1 * t ** 1.7
    if z < NOSE_TIP_Z:
        amt *= g(-((z - NOSE_TIP_Z) / 0.045) ** 2)
    y -= front * amt * g(-(x / (0.045 + 0.04 * t)) ** 2)
    y -= 0.022 * front * g(-((ax - 0.075) / 0.035) ** 2) * g(-((z - NOSE_TIP_Z + 0.015) / 0.03) ** 2)
    # Губы: верхняя, линия рта, нижняя, ямка под губой, подбородок.
    y -= 0.026 * front * g(-(x / (mw * 2.2)) ** 2) * g(-((z - MOUTH_Z - 0.05) / 0.045) ** 2)
    y += 0.014 * front * g(-(x / (mw * 1.5)) ** 2) * g(-((z - MOUTH_Z) / 0.02) ** 2)
    y -= 0.022 * front * g(-(x / (mw * 1.3)) ** 2) * g(-((z - MOUTH_Z + 0.045) / 0.032) ** 2)
    y += 0.01 * front * g(-(x / (mw * 2.0)) ** 2) * g(-((z - MOUTH_Z + 0.12) / 0.03) ** 2)
    y -= 0.016 * front * g(-(x / 0.16) ** 2) * g(-((z + 0.86) / 0.06) ** 2)
    return x, y, z


def loft_head_mesh(rx, ry, rz, cz, L):
    """Голова «лофтом» по сечениям (как моделят по видам спереди и сбоку): на каждой высоте — полуширина,
    передняя и задняя точка профиля (таблицы в U = глаз–подбородок, от подбородка; см. docs/MODEL_STUDY.md).
    Возвращает вершины/грани в нормированных координатах головы (x/rx, y/ry, (z−cz)/rz)."""
    U = (1 - 2 * FP["eye_v"] + 1) * rz      # глаз над подбородком: z_eye − (−1)
    lv = [q[0] for q in L["halfw"]]
    def tab(name, z):
        return _pw(z, [(q[0], q[1]) for q in sorted(L[name], key=lambda q: -q[0])])
    top = max(lv)
    n_lv, n_a = 72, 96
    rings = []
    for i in range(n_lv + 1):
        z = top * (i / n_lv) ** 1.0
        hw, fr, bk = tab("halfw", z), tab("front", z), tab("back", z)
        mid = tab("mid", z) if "mid" in L else (fr + bk) / 2
        ring = []
        for k in range(n_a):
            a = 2 * math.pi * k / n_a                     # 0 — спереди (−Y), π/2 — +X
            sx, cy = math.sin(a), math.cos(a)
            if cy >= 0:                                   # передняя половина: «плоскость лица»
                yy = mid + (fr - mid) * cy ** L.get("front_p", 0.75)
            else:
                yy = mid + (bk - mid) * (-cy) ** L.get("back_p", 1.0)
            xx = hw * (abs(sx) ** L.get("side_p", 0.9)) * (1 if sx >= 0 else -1)
            # Ширина/глубина: глаза Кота крупнее, чем у изученной модели — голова шире, чтобы внешний угол глаза
            # остался на ~80% ширины лица (как у неё), а не у края головы.
            ring.append((xx * L.get("w_scale", 1.0) * U, (yy + L.get("y_off", 0.0)) * L.get("d_scale", 1.0) * U, z * U))
        rings.append(ring)
    verts, faces = [], []
    for ring in rings:
        verts += ring
    for i in range(n_lv):
        for k in range(n_a):
            a0, a1 = i * n_a + k, i * n_a + (k + 1) % n_a
            faces.append((a0, a1, a1 + n_a, a0 + n_a))
    # крышка макушки и низ подбородка
    tc = len(verts); verts.append((0, rings[-1][0][1] * 0 + sum(q[1] for q in rings[-1]) / n_a, top * U))
    for k in range(n_a):
        faces.append(((n_lv) * n_a + k, (n_lv) * n_a + (k + 1) % n_a, tc))
    bc = len(verts); verts.append((0, sum(q[1] for q in rings[0]) / n_a, 0))
    for k in range(n_a):
        faces.append(((k + 1) % n_a, k, bc))
    chin_z = cz - rz
    return [(x / rx, y / ry, (z + chin_z - cz) / rz) for x, y, z in verts], faces


def build_head(cid, J, p):
    """Вылепленная голова (sculpt_head) с плотной сеткой; лицо — рисованная текстура во фронтальной проекции.
    Если в face_params есть «loft» — форма головы строится по сечениям (шаблон по изученной модели)."""
    s = p["s"]
    rx, ry, rz = 0.08 * s * p["head"], 0.094 * s * p["head"], 0.106 * s * p["head"]
    cz = J["head"].z + rz * 1.12
    if FP.get("loft"):
        vs, fs = loft_head_mesh(rx, ry, rz, cz, FP["loft"])
        me = bpy.data.meshes.new("head")
        me.from_pydata([Vector(v) for v in vs], [], fs)
        me.validate()
        o = new_obj("head", me)
        bpy.context.view_layer.objects.active = o
        sub = o.modifiers.new("sub", "SUBSURF")
        sub.levels = 1
        apply_mods(o)
        me = o.data
        for v in me.vertices:
            x, y, z = sculpt_features(*v.co)
            v.co = Vector((x * rx, y * ry, z * rz + cz))
        bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.to_mesh(me); bm.free()
        uv = me.uv_layers.active or me.uv_layers.new(name="UVMap")
        for poly in me.polygons:
            for li in poly.loop_indices:
                co = me.vertices[me.loops[li].vertex_index].co
                if co.y > -0.15 * ry:
                    uv.data[li].uv = (0.02, 0.02)
                else:
                    uv.data[li].uv = (0.5 + co.x / (2 * rx), 0.5 + (co.z - cz) / (2 * rz))
        shade_smooth(o)
        me.materials.append(mat(f"face_{cid}", SKIN, tex=os.path.join(TEX, f"face_{cid}.png"), clip=True))
        return o, (rx, ry, rz, cz)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=160, ring_count=128, radius=1)
    o = bpy.context.active_object
    o.name = "head"
    me = o.data
    for v in me.vertices:
        x, y, z = sculpt_head(*v.co)
        v.co = Vector((x * rx, y * ry, z * rz + cz))
    uv = me.uv_layers.active or me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if co.y > -0.15 * ry:
                uv.data[li].uv = (0.02, 0.02)        # затылок и бока — просто кожа
            else:
                uv.data[li].uv = (0.5 + co.x / (2 * rx), 0.5 + (co.z - cz) / (2 * rz))
    shade_smooth(o)
    me.materials.append(mat(f"face_{cid}", SKIN, tex=os.path.join(TEX, f"face_{cid}.png"), clip=True))
    return o, (rx, ry, rz, cz)


def almond(cx, cy, w, h, steps=40, lift=0.18):
    """Контур прорези глаза в координатах текстуры лица — тот же, что в gen_faces.py."""
    pts = []
    for i in range(steps + 1):
        a = math.pi * i / steps
        x = cx - w * math.cos(a)
        pts.append((x, cy - h * math.sin(a) + (x - cx) / w * h * lift))
    for i in range(steps + 1):
        a = math.pi * i / steps
        x = cx + w * math.cos(a)
        pts.append((x, cy + h * math.sin(a) * 0.62 + (x - cx) / w * h * lift * 0.5))
    return pts


def _strip(rows, m, name, thick=0.0002):
    """Лента из пар точек (край1, край2) → меш с толщиной (видна с обеих сторон)."""
    bm = bmesh.new()
    vs = [(bm.verts.new(a), bm.verts.new(b)) for a, b in rows]
    for (a1, b1), (a2, b2) in zip(vs, vs[1:]):
        bm.faces.new((a1, b1, b2, a2))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = new_obj(name, me)
    o.modifiers.new("sol", "SOLIDIFY").thickness = thick
    apply_mods(o)
    shade_smooth(o)
    o.data.materials.append(m)
    return o


MARKS = {}   # ориентиры для наложения на референс (экспортируются как пустые узлы lm_<имя>)


def landmarks_head(head_obj, hd, hair):
    """Ориентиры лица и причёски: подбородок, видимый глаз и его углы, повязка, нос, рот, макушка, края копны.
    vl / vr — левый / правый край для зрителя (−X / +X)."""
    rx, ry, rz, cz = hd
    tree = BVHTree.FromObject(head_obj, bpy.context.evaluated_depsgraph_get())

    def front(x, z):
        hit = tree.ray_cast(Vector((x, -1, z)), Vector((0, 1, 0)))
        return hit[0] if hit[0] else Vector((x, -ry, z))

    def tex(px, py):
        return front((px - 0.5) * 2 * rx, cz - (py - 0.5) * 2 * rz)
    ps = FP["patch_side"]
    vis = -ps
    ez = cz - (FP["eye_v"] - 0.5) * 2 * rz
    fr = [v.co for v in head_obj.data.vertices if v.co.y < -0.5 * ry]
    m = {"chin": min(fr, key=lambda c: c.z).copy(),
         "eye_vis": front(vis * FP["eye_u"] * 2 * rx, ez),
         "patch": front(ps * (FP["eye_u"] * 2 + FP.get("patch_dx", 0.0)) * rx, ez + rz * FP.get("patch_dz", 0.06)),
         "nose": front(0, cz + FP["nose_z"] * rz),
         "mouth": front(0, cz + FP["mouth_z"] * rz),
         "mouth_vl": front(-FP["mouth_w"] * 2 * rx, cz + FP["mouth_z"] * rz),
         "mouth_vr": front(FP["mouth_w"] * 2 * rx, cz + FP["mouth_z"] * rz)}
    pts = almond(0.5 + vis * FP["eye_u"], FP["eye_v"], FP["eye_w"], FP["eye_h"], lift=-FP["eye_lift"] * vis)
    a, b = tex(*pts[0]), tex(*pts[40])
    m["eye_vis_outer"], m["eye_vis_inner"] = (a, b) if abs(a.x) > abs(b.x) else (b, a)
    # Контур лица (для зрителя слева) на высоте носа и рта — по самой левой вершине передней половины головы.
    for name, zn in (("cheek_vl", FP["nose_z"]), ("jaw_vl", FP["mouth_z"])):
        zz = cz + zn * rz
        band = [v.co for v in head_obj.data.vertices if abs(v.co.z - zz) < rz * 0.02 and v.co.y < 0]
        m[name] = min(band, key=lambda c: c.x).copy()
    hv = [o.matrix_world @ v.co for o in hair for v in o.data.vertices]
    m["crown"] = max((q for q in hv if abs(q.x) < rx * 0.15), key=lambda q: q.z).copy()
    m["hair_vl"] = min(hv, key=lambda q: q.x).copy()
    m["hair_vr"] = max(hv, key=lambda q: q.x).copy()
    MARKS.clear()
    MARKS.update(m)
    return MARKS


# Уровни силуэта для вида «во весь рост» (в U ниже подбородка; U — глаз–подбородок), см. 16_kot_landmarks.json.
SIL_LEVELS = {"sil_118": 1.18, "sil_350": 3.5, "sil_584": 5.84, "sil_1020": 10.2, "sil_1410": 14.1}


def landmarks_body(body, garments):
    """Ширина силуэта в образе по умолчанию на заданных уровнях + пол (низ подошвы) + ширина ремня."""
    names = {g.name: g for g in garments}
    look = [names.get(n) for n in ("garment__upper_body__turtleneck_flowers", "garment__lower_body__cargo",
                                   "garment__footwear__boots")]
    if None in look or "chin" not in MARKS:
        return
    chin, eye = MARKS["chin"], MARKS["eye_vis"]
    u = eye.z - chin.z
    objs = look + [body]

    def extremes(obs, z, band=None):
        """Крайние x сечения мешей плоскостью z (по пересечению рёбер — точно даже на редкой сетке)."""
        xs = []
        for o in obs:
            mw = o.matrix_world
            co = [mw @ v.co for v in o.data.vertices]
            for e in o.data.edges:
                a, b = co[e.vertices[0]], co[e.vertices[1]]
                if (a.z - z) * (b.z - z) <= 0 and a.z != b.z:
                    t = (z - a.z) / (b.z - a.z)
                    xs.append(a.x + (b.x - a.x) * t)
        return min(xs), max(xs)
    for name, lv in SIL_LEVELS.items():
        z = chin.z - lv * u
        a, b = extremes(objs, z)
        MARKS[name + "_vl"], MARKS[name + "_vr"] = Vector((a, 0, z)), Vector((b, 0, z))
    belt_z = chin.z - 5.0 * u
    a, b = extremes([look[1]], belt_z, 0.004)
    MARKS["belt_vl"], MARKS["belt_vr"] = Vector((a, 0, belt_z)), Vector((b, 0, belt_z))
    MARKS["floor"] = Vector((0, 0, min((look[2].matrix_world @ v.co).z for v in look[2].data.vertices)))


def export_landmarks():
    for name, co in MARKS.items():
        e = bpy.data.objects.new("lm_" + name, None)
        e.location = co
        bpy.context.collection.objects.link(e)


def build_lashes(head_obj, hd, c):
    """Объёмные ресницы, складка века и брови (реф. 16): густая линия верхних ресниц с «крылом»
    у внешнего угла, отдельные ресницы, торчащие вперёд, короткие нижние ресницы."""
    rx, ry, rz, cz = hd
    k = rx / 0.08 * (FP["eye_w"] / 0.097) ** 0.7          # масштаб под размер головы и глаза
    tree = BVHTree.FromObject(head_obj, bpy.context.evaluated_depsgraph_get())
    m_lash = mat("lash", c["lash"] + (1,), rough=0.4)
    m_brow = mat("brow", c["brow"] + (1,), rough=0.6)
    m_crease = mat("crease", (0.66, 0.44, 0.46, 1), rough=0.7)

    def to3d(px, py, push=0.0):
        x, z = (px - 0.5) * 2 * rx, cz - (py - 0.5) * 2 * rz
        hit = tree.ray_cast(Vector((x, -1, z)), Vector((0, 1, 0)))
        if hit[0] is None:
            return Vector((x, -ry, z)), Vector((0, -1, 0))
        return hit[0] + hit[1] * push, hit[1]

    out = []
    for side in (-1, 1):
        cx, cy, w, h = 0.5 + side * FP["eye_u"], FP["eye_v"], FP["eye_w"], FP["eye_h"]
        pts = almond(cx, cy, w, h, lift=-FP["eye_lift"] * side)
        up = pts[:41] if side > 0 else pts[:41][::-1]           # от внутреннего угла к внешнему
        low = pts[41:][::-1] if side > 0 else pts[41:]          # тоже от внутреннего к внешнему
        o_dir = Vector((side, 0, 0))
        # Верхняя линия ресниц + «крыло».
        rows, tips = [], []
        P = [to3d(*q) for q in up]
        for i, (pt, n) in enumerate(P):
            t = i / (len(P) - 1)
            u_dir = (Vector((0, 0, 1)) - n * n.z).normalized()
            th = (0.0007 + 0.0026 * t ** 1.4) * k
            base = pt + n * 0.0003 - u_dir * 0.0004 * k
            top = pt + u_dir * th + n * (0.0006 + 0.5 * th)
            rows.append((base, top))
            tips.append((top, n, u_dir, t))
        end, n_end = P[-1]
        u_end = (Vector((0, 0, 1)) - n_end * n_end.z).normalized()
        for j in range(1, 5):
            f = j / 4
            c_pt = end + o_dir * 0.0019 * k * j - u_end * 0.00045 * k * j * j * 0.3 + n_end * 0.0006 * j
            th = 0.0033 * k * (1 - f) ** 1.2 + 0.0002
            rows.append((c_pt - u_end * 0.0002 * k, c_pt + u_end * th + n_end * th * 0.4))
        out.append(_strip(rows, m_lash, "lash_upper"))
        # Отдельные ресницы — к внешнему углу длиннее, торчат вперёд и вверх.
        for j in range(11):
            t = 0.25 + 0.75 * j / 10
            top, n, u_dir, _ = tips[int(t * (len(tips) - 1))]
            d = (u_dir * 0.6 + o_dir * (0.25 + 0.6 * t) + n * 0.55).normalized()
            L = (0.0016 + 0.0034 * t) * k
            wd = 0.0007 * k
            tan = (d.cross(n)).normalized()
            mid = top + d * L * 0.5 + n * L * 0.12
            tip = top + d * L + u_dir * L * 0.15
            out.append(_strip([(top - tan * wd, top + tan * wd), (mid - tan * wd * 0.6, mid + tan * wd * 0.6), (tip, tip + tan * 0.00005)],
                              m_lash, "lash_spike"))
        # Нижние ресницы: тонкая линия по внешней части и несколько коротких ресничек вниз.
        rows = []
        Q = [to3d(*q) for q in low]
        for i, (pt, n) in enumerate(Q):
            t = i / (len(Q) - 1)
            if t < 0.2:
                continue
            u_dir = (Vector((0, 0, 1)) - n * n.z).normalized()
            th = (0.00025 + 0.0007 * t) * k
            rows.append((pt + n * 0.0003 + u_dir * 0.0002 * k, pt - u_dir * th + n * 0.0004))
            if i % 7 == 3 and t > 0.4:
                d = (-u_dir * 0.7 + o_dir * 0.5 + n * 0.4).normalized()
                L = 0.0014 * k * (0.6 + 0.6 * t)
                tan = d.cross(n).normalized()
                b = pt - u_dir * th
                out.append(_strip([(b - tan * 0.0004 * k, b + tan * 0.0004 * k), (b + d * L, b + d * L + tan * 0.00005)], m_lash, "lash_low"))
        out.append(_strip(rows, m_lash, "lash_lower"))
        # Складка века (двойное веко) — над линией ресниц.
        rows = []
        for i, (px, py) in enumerate(up[6:36]):
            t = (i + 6) / 40
            pt, n = to3d(px, py - h * 0.5, push=0.0003)
            u_dir = (Vector((0, 0, 1)) - n * n.z).normalized()
            wd = (0.00025 + 0.0004 * math.sin(math.pi * t)) * k
            rows.append((pt - u_dir * wd, pt + u_dir * wd))
        out.append(_strip(rows, m_crease, "crease"))
        # Бровь: тонкая, от переносицы толще, к виску тоньше и ниже.
        rows = []
        for j in range(15):
            t = j / 14
            ang = math.radians(200 + 130 * t) if side > 0 else math.radians(340 - 130 * t)
            px = cx + side * 0.004 + w * 1.2 * math.cos(ang)
            py = cy - h * 2.05 + h * 1.0 * math.sin(ang)
            pt, n = to3d(px, py, push=0.0005)
            u_dir = (Vector((0, 0, 1)) - n * n.z).normalized()
            inner = (1 - t) if side > 0 else t
            wd = (0.0003 + 0.0009 * inner) * k
            rows.append((pt - u_dir * wd, pt + u_dir * wd))
        out.append(_strip(rows, m_brow, "brow"))
    return out


def build_eyes(cid, head_obj, hd):
    """Глазные яблоки за прорезями век: плоские эллипсоиды по нормали лица чуть позади прорези (не выпирают
    из лица); радужка ≈ половина ширины глаза и почти во всю высоту прорези (как на реф. 16)."""
    rx, ry, rz, cz = hd
    deps = bpy.context.evaluated_depsgraph_get()
    tree = BVHTree.FromObject(head_obj, deps)
    eyes = []
    em = mat(f"eye_{cid}", (1, 1, 1, 1), tex=os.path.join(TEX, f"eye_{cid}.png"), rough=0.2)
    ew, eh = FP["eye_w"], FP["eye_h"]
    ax = ew * 2 * rx * 1.12                    # полуширина прорези (+запас)
    az = 1.62 * eh / 2 * 2 * rz * 1.25         # полувысота прорези (+запас)
    ay = ax * 0.32                             # глубина — плоское яблоко
    d_iris = 2.08 * ew * rx                    # диаметр радужки ≈ 0.52 ширины глаза
    for side in (-1, 1):
        ex = side * FP["eye_u"] * 2 * rx
        ez = cz - (FP["eye_v"] - 0.5) * 2 * rz + 0.19 * eh * 2 * rz     # центр прорези (миндаль выше внизу)
        hit = tree.ray_cast(Vector((ex, -1, ez)), Vector((0, 1, 0)))
        loc, nrm = (hit[0], hit[1]) if hit[0] else (Vector((ex, -ry, ez)), Vector((0, -1, 0)))
        nrm = (nrm * 0.6 + Vector((0, -1, 0)) * 0.4).normalized()
        M = basis_at(loc, nrm)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=24, radius=1)
        e = bpy.context.active_object
        e.name = "eye"
        me = e.data
        me.transform(Matrix.Diagonal((ax, az, ay, 1)))
        me.transform(Matrix.Translation((0, 0, -ay * 1.08)))
        uv = me.uv_layers.active
        for poly in me.polygons:
            for li in poly.loop_indices:
                co = me.vertices[me.loops[li].vertex_index].co
                uv.data[li].uv = ((0.5 + co.x * 0.72 / d_iris, 0.5 + co.y * 0.72 / (d_iris * 1.08)) if co.z > -ay * 1.08
                                  else (0.02, 0.5))
        me.transform(M)
        shade_smooth(e)
        me.materials.append(em)
        eyes.append(e)
    return eyes


# ------------------------------------------------------------------ волосы: «карты» прядей

def on_scalp(hd, theta, phi, lift=1.0):
    rx, ry, rz, cz = hd
    x = math.sin(phi) * math.sin(theta) * rx * lift
    y = -math.sin(phi) * math.cos(theta) * ry * lift
    z = math.cos(phi) * rz * lift + cz
    return Vector((x, y, z))


def card(points, w_root, w_tip, hd, mat_hair, curve=0.25):
    """Карта пряди: полоса из 3 вершин в ширину (слегка выгнута вокруг головы), UV: u поперёк, v от корня (1) к кончику (0)."""
    rx, ry, rz, cz = hd
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    rows = []
    n = len(points)
    for i, pt in enumerate(points):
        t = i / (n - 1)
        tan = (points[min(i + 1, n - 1)] - points[max(i - 1, 0)]).normalized()
        out = (pt - Vector((0, 0, cz))).normalized()
        side = tan.cross(out).normalized()
        nrm = side.cross(tan).normalized()
        w = (w_root * (1 - t) + w_tip * t) / 2
        rows.append(([bm.verts.new(pt + side * w - nrm * w * curve), bm.verts.new(pt + nrm * w * curve * 0.5),
                      bm.verts.new(pt - side * w - nrm * w * curve)], 1 - t))
    for (a, va), (b, vb) in zip(rows, rows[1:]):
        for k in range(2):
            f = bm.faces.new((a[k], a[k + 1], b[k + 1], b[k]))
            for loop, (u, vv) in zip(f.loops, ((k / 2, va), ((k + 1) / 2, va), ((k + 1) / 2, vb), (k / 2, vb))):
                loop[uv_layer].uv = (u, vv)
    me = bpy.data.meshes.new("hair_card")
    bm.to_mesh(me)
    bm.free()
    o = new_obj("hair_card", me)
    o.data.materials.append(mat_hair)
    shade_smooth(o)
    return o


def clump(points, w_root, w_tip, hd, m, curve=0.0, flat=0.6, seg=8, v_tip=0.0):
    """Объёмная прядь-«клок» (аниме-причёска, как у реф. 16): сплюснутая трубка, сужается к кончику.
    UV v идёт от 1 (корень) к v_tip — по нему красится градиент корни → кончики."""
    rx, ry, rz, cz = hd
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    n = len(points)
    rings = []
    for i, pt in enumerate(points):
        t = i / (n - 1)
        tan = (points[min(i + 1, n - 1)] - points[max(i - 1, 0)]).normalized()
        out = (pt - Vector((0, 0, cz))).normalized()
        side = tan.cross(out)
        side = side.normalized() if side.length > 1e-3 else Vector((1, 0, 0))
        nrm = side.cross(tan).normalized()
        w = (w_root * (1 - t) + w_tip * t) / 2 * (1 - 0.85 * t ** 4)
        ring = [bm.verts.new(pt + side * math.cos(a) * w + nrm * (math.sin(a) * w * flat - w * curve * math.cos(a) ** 2))
                for a in (2 * math.pi * k / seg for k in range(seg))]
        rings.append((ring, 1 - t * (1 - v_tip)))
    for (a, va), (b, vb) in zip(rings, rings[1:]):
        for k in range(seg):
            k2 = (k + 1) % seg
            f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
            for loop, (u, vv) in zip(f.loops, ((k / seg, va), ((k + 1) / seg, va), ((k + 1) / seg, vb), (k / seg, vb))):
                loop[uv_layer].uv = (u, vv)
    tip = bm.verts.new(points[-1] + (points[-1] - points[-2]) * 0.4)
    for k in range(seg):
        f = bm.faces.new((rings[-1][0][k], rings[-1][0][(k + 1) % seg], tip))
        for loop in f.loops:
            loop[uv_layer].uv = (0.5, v_tip)
    # Нормали наружу от оси пряди (recalc на открытой трубке иногда выворачивает прядь — видна изнанка контура).
    bm.normal_update()
    mid = len(points) // 2
    f0 = next(f for f in bm.faces if all(v in rings[mid][0] or v in rings[mid + 1][0] for v in f.verts))
    if f0.normal.dot(f0.calc_center_median() - points[mid]) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    me = bpy.data.meshes.new("hair_clump")
    bm.to_mesh(me)
    bm.free()
    o = new_obj("hair_clump", me)
    o.data.materials.append(m)
    shade_smooth(o)
    return o


CONFORM = None   # (BVH головы, центр, rx, cz, rz): пряди «рисуются поверх» настоящего черепа, а не сферы


def conform(p, lift):
    """Прижать точку к поверхности головы по лучу из центра: отступ (lift − 1)·rx (не меньше 2 мм).
    Ниже челюсти (висящие концы прядей) — плавно без прижатия."""
    if CONFORM is None:
        return p
    tree, c, rx, cz, rz = CONFORM
    d = p - Vector((0, 0, c.z))
    if d.length < 1e-6:
        return p
    hit = tree.ray_cast(Vector((0, 0, c.z)), d.normalized())
    if hit[0] is None:
        return p
    q = hit[0] + d.normalized() * max(0.002, (lift - 1.0) * rx)
    w = min(1.0, max(0.0, (p.z - (cz - 0.75 * rz)) / (0.35 * rz)))
    return p.lerp(q, w)


def flow_path(hd, theta, phi0, phi1, lift0, lift1, steps=9, curl=0.0, drop=0.0, rnd=None):
    """Путь пряди по поверхности головы от (theta, phi0) вниз до phi1; curl — завиток кончика наружу/вверх."""
    rx, ry, rz, cz = hd
    pts = []
    for i in range(steps):
        t = i / (steps - 1)
        phi = phi0 + (phi1 - phi0) * t
        lift = lift0 + (lift1 - lift0) * t
        p = conform(on_scalp(hd, theta + (rnd.uniform(-0.04, 0.04) if rnd else 0), min(phi, 2.5), lift), lift)
        if phi > 2.5:
            p.z -= (phi - 2.5) * rz
        p.z -= drop * t ** 2
        if curl and t > 0.55:
            c = (t - 0.55) / 0.45
            outward = Vector((math.sin(theta), -math.cos(theta), 0))
            p += outward * curl * rx * 0.35 * math.sin(c * math.pi * 0.9)
            p.z += curl * rz * 0.22 * c * c
        pts.append(p)
    return pts


def curve_tube(pts, r, m, taper=0.4):
    """Трубка по точкам (кривая с фаской → меш), радиус сужается к концу."""
    cu = bpy.data.curves.new("tube", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = r
    cu.bevel_resolution = 3
    cu.use_fill_caps = True
    sp = cu.splines.new("POLY")
    sp.points.add(len(pts) - 1)
    for i, q in enumerate(pts):
        sp.points[i].co = (q.x, q.y, q.z, 1)
        sp.points[i].radius = 1 - (1 - taper) * i / (len(pts) - 1)
    o = new_obj("tube", cu)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.convert(target="MESH")
    o = bpy.context.active_object
    shade_smooth(o)
    o.data.materials.clear()
    o.data.materials.append(m)
    return o


def hair_cap(hdc, face_cut, cap_low, scale, mat_cap):
    """Непрозрачная «шапка» под прядями (чтобы не просвечивала кожа головы); спереди вырез под лицо."""
    rx, ry, rz, cz = hdc
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=32, radius=1)
    cap = bpy.context.active_object
    cap.name = "hair_cap"
    for v in cap.data.vertices:
        x, y, z = v.co
        v.co = Vector((x * rx * scale, y * ry * scale, z * rz * (scale - 0.01) + cz + rz * 0.02))
    bm = bmesh.new()
    bm.from_mesh(cap.data)
    kill = [v for v in bm.verts if (v.co.z < cz + rz * face_cut and v.co.y < -ry * 0.25) or v.co.z < cz - rz * cap_low]
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(cap.data)
    bm.free()
    shade_smooth(cap)
    cap.data.materials.append(mat_cap)
    return cap


def head_shell_cap(cf, hp, mat_cap):
    """Основа причёски — копия поверхности головы на 2.5 мм выше кожи (лоб открыт под чёлку, лицо — вырезано)."""
    tree, c, rx, cz, rz = cf
    head = bpy.data.objects["head"]
    me = head.data.copy()
    cap = new_obj("hair_cap", me)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    ry = max(abs(v.co.y) for v in bm.verts if v.co.y < 0)
    kill = [v for v in bm.verts if (v.co.z < cz + rz * hp.get("face_cut", 0.42) and v.co.y < -ry * 0.3)
            or v.co.z < cz - rz * hp["cap_low"]]
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    for v in bm.verts:
        v.co += v.normal * 0.0025
    bm.to_mesh(me)
    bm.free()
    me.materials.clear()
    me.materials.append(mat_cap)
    if me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    shade_smooth(cap)
    return cap


def ribbon(pts, ups, sides, widths, lift, m, ridge=0.32, thick=0.18):
    """Прядь-лента как у игровых аниме-моделей: плоская, с гребнем посередине, острый кончик.
    pts — ось, ups — «наружу» (нормаль к голове), sides — поперёк ленты, widths — ширина в точках."""
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    prof = [(-0.5, 0.0), (-0.25, 0.75), (0.0, 1.0 + ridge), (0.25, 0.75), (0.5, 0.0), (0.0, -0.6)]
    rings = []
    n = len(pts)
    for i, (c, up, sd, w) in enumerate(zip(pts, ups, sides, widths)):
        h = max(w, 1e-4) * thick * 0.5
        base = c + up * lift
        rings.append([bm.verts.new(base + sd * (a * w) + up * (b * h)) for a, b in prof])
    for i in range(n - 1):
        va, vb = 1 - i / (n - 1), 1 - (i + 1) / (n - 1)
        for k in range(len(prof)):
            k2 = (k + 1) % len(prof)
            f = bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
            for loop, uvv in zip(f.loops, ((k / 6, va), (k2 / 6, va), (k2 / 6, vb), (k / 6, vb))):
                loop[uv_layer].uv = uvv
    bm.normal_update()
    mid = n // 2
    f0 = next(f for f in bm.faces if all(v in rings[mid] or v in rings[mid + 1] for v in f.verts))
    if f0.normal.dot(f0.calc_center_median() - (pts[mid] + ups[mid] * lift)) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    me = bpy.data.meshes.new("strand")
    bm.to_mesh(me)
    bm.free()
    o = new_obj("strand", me)
    o.data.materials.append(m)
    shade_smooth(o)
    return o


def build_hair_ribbons(cid, head_obj, hd, hp, mat_cap, mat_strand):
    """Причёска по принципу игровых аниме-моделей (изучено на референсах art/references/3d и Lyney):
    1) «шлем» — масса волос вокруг черепа (копия головы, отодвинутая наружу; задаёт объём и форму);
    2) поверх — широкие плоские пряди-ленты: расходятся от вихра на макушке (вперёд — чёлка, вбок, назад),
       лежат по поверхности шлема с S-изгибом, концы завиваются наружу-вверх (крючок/локон)."""
    global CONFORM
    rx, ry, rz, cz = hd
    rnd = random.Random(sum(map(ord, cid)) + 11)
    deps = bpy.context.evaluated_depsgraph_get()
    # 1. Шлем.
    me = head_obj.data.copy()
    helm = new_obj("hair_cap", me)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    hl, nape = hp["hairline"], hp["nape"]
    # Вырезаем только лицо (переднюю часть ниже линии роста) — бока над щеками и ушами остаются: там объём копны.
    face_x = hp.get("face_open_x", 0.7) * rx
    kill = [v for v in bm.verts if (v.co.y < -0.05 * ry and v.co.z < cz + rz * hl and
                                    (abs(v.co.x) < face_x or v.co.y < -0.75 * ry)) or v.co.z < cz - rz * nape]
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    t_top, t_side = hp["thick_top"], hp["thick_side"]
    for v in bm.verts:
        zn = (v.co.z - cz) / rz
        k = min(1.0, max(0.0, (zn + 0.3) / 1.2))
        t = t_side + (t_top - t_side) * k * k * (3 - 2 * k)
        t *= 1 + hp.get("cheek_puff", 0.0) * math.exp(-((zn + 0.45) / 0.35) ** 2)   # пышнее на уровне щёк
        if v.co.y < -0.4 * ry:
            t *= 0.55                                  # у линии роста волос над лбом тоньше
        v.co += v.normal * t
    for _ in range(3):
        bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.to_mesh(me)
    bm.free()
    me.materials.clear()
    me.materials.append(mat_cap)
    if me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    shade_smooth(helm)
    t_helm = BVHTree.FromObject(helm, bpy.context.evaluated_depsgraph_get())
    t_face = BVHTree.FromObject(head_obj, bpy.context.evaluated_depsgraph_get())

    class _Outer:
        """Прижатие к ВНЕШНЕЙ поверхности: из шлема и головы берём ту точку, что дальше от центра
        (иначе пряди проваливаются под шлем на череп)."""
        def find_nearest(self, P):
            a = t_helm.find_nearest(P)
            b = t_face.find_nearest(P)
            if a[0] is None:
                return b
            if b[0] is None:
                return a
            # ближайшая поверхность, с перевесом в пользу шлема (пряди не проваливаются под него на череп);
            # ниже края шлема на лбу ближе лицо — чёлка ложится на лоб, а не застревает на кромке шлема
            return a if a[3] <= b[3] + 0.01 else b
    t_snap = _Outer()
    CONFORM = (t_helm, Vector((0, 0, cz)), rx, cz, rz)          # уши, заколки, хохолок — на шлеме
    bottom = cz - rz * nape
    whorl_dir = Vector((0, hp["whorl"][0], hp["whorl"][1])).normalized()
    hit = t_helm.ray_cast(Vector((0, 0, cz)) + whorl_dir * rx * 4, -whorl_dir)
    whorl = hit[0] if hit[0] else Vector((0, 0, cz + rz))

    def on_helm(theta, phi):
        d = Vector((math.sin(phi) * math.sin(theta), -math.sin(phi) * math.cos(theta), math.cos(phi)))
        h = t_helm.ray_cast(Vector((0, 0, cz)) + d * rx * 4, -d)
        return (h[0], h[1]) if h[0] else (None, None)

    def strand(theta, phi, length, w0, lift, sway, curl_deg, curl_frac, bias, phase, thick=0.18, twist=0.0):
        P, N = on_helm(theta, phi)
        if P is None:
            return None
        step = 0.006
        n = max(6, int(length / step))
        nc = int(n * curl_frac)
        pts, ups, sides = [P.copy()], [N.copy()], []
        d = None
        B = None
        for i in range(n):
            loc, N2, _, dist = t_snap.find_nearest(P)
            N = N2 if N2 is not None else N
            if (P - Vector((0, 0, cz))).dot(N) < 0:
                N = -N
            away = P - whorl
            away -= N * away.dot(N)
            down = Vector((0, 0, -1)) - N * (-N.z)
            # у корня — от вихра, дальше пряди падают вниз по голове (вес «вниз» растёт по длине)
            b = bias + (1 - bias) * min(1.0, i / max(1.0, n * 0.45))
            flow = away.normalized() * (1 - b) + (down.normalized() if down.length > 1e-6 else away.normalized()) * b
            flow -= N * flow.dot(N)
            ang = sway * math.sin(i / n * math.pi * 2 * 0.8 + phase)
            flow = Matrix.Rotation(ang, 3, N) @ flow.normalized()
            if i < n - nc:                             # в завитке «тяга вниз» не действует, иначе он распрямляется
                d = flow if d is None else (d * 0.55 + flow * 0.45).normalized()
            if i >= n - nc:                            # завиток: кончик загибается наружу и вверх
                if B is None:
                    B = d.cross(N).normalized()
                    if twist:                          # ось завитка чуть повёрнута — локон, а не плоский крючок
                        B = (Matrix.Rotation(twist, 3, d) @ B).normalized()
                d = (Matrix.Rotation(math.radians(curl_deg) / max(nc, 1), 3, B) @ d).normalized()
                P = P + d * step
                up = B.cross(d).normalized()
            elif P.z < bottom:                          # ниже шлема — свободно висит
                d = (d * 0.75 + Vector((0, 0, -1)) * 0.25).normalized()
                P = P + d * step
                up = N
            else:
                P = P + d * step
                loc, N2, _, _ = t_snap.find_nearest(P)
                if loc is not None:
                    if (loc - Vector((0, 0, cz))).dot(N2) < 0:
                        N2 = -N2
                    P = loc + N2 * 0.0008
                    N = N2
                up = N
            pts.append(P.copy())
            ups.append(up.copy())
        for i in range(len(pts)):
            T = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            sd = T.cross(ups[i])
            sides.append(sd.normalized() if sd.length > 1e-6 else Vector((1, 0, 0)))
        if os.environ.get("KPC_DBG"):
            prog = sum((pts[i + 1] - pts[i]).length for i in range(len(pts) - 1))
            print(f"DBG strand th={theta:+.2f} ph={phi:.2f} n={n} z {pts[0].z:.3f}->{pts[-1].z:.3f} path={prog:.3f} "
                  f"chord={(pts[-1]-pts[0]).length:.3f} zmin={min(q.z for q in pts):.3f} nc={nc} tail={[round(q.z, 3) for q in pts[-nc-1::max(1, nc // 5)]]}")
        m = len(pts)
        # Ширина держится почти до конца (завиток должен быть виден), сужение — только у самого кончика.
        widths = [w0 * (0.75 + 0.25 * min(1.0, (i / (m - 1)) / 0.2)) * (1 - max(0.0, (i / (m - 1) - 0.72) / 0.28) ** 1.4)
                  for i in range(m)]
        return ribbon(pts, ups, sides, widths, lift, mat_strand, thick=thick)

    objs = []
    for g in hp["groups"]:
        for j in range(g["count"]):
            th0, th1 = g["theta"]
            theta = th0 + (th1 - th0) * (j + rnd.uniform(0.2, 0.8)) / g["count"]
            if g.get("skip_front") and abs(theta) < g["skip_front"]:
                continue                                   # спереди вместо мантии — чёлка
            phi = rnd.uniform(*g["phi"])
            cd = rnd.uniform(*g["curl"]) * (rnd.choice((-1, 1)) if g.get("curl_both") else 1)
            o = strand(theta, phi, rnd.uniform(*g["length"]), rnd.uniform(*g["w"]), g.get("lift", 0.002) + 0.0012 * j % 0.004,
                       g.get("sway", 0.2), cd, g.get("curl_frac", 0.3), g.get("bias", 0.3),
                       rnd.uniform(0, 6.28), thick=g.get("thick", hp.get("thick", 0.18)),
                       twist=rnd.uniform(-0.6, 0.6) if g.get("curl_both") else 0.0)
            if o is not None:
                objs.append(o)
    # Прядь на глаз под повязкой — длинная лента через глаз до щеки.
    if hp.get("eye_lock"):
        el = hp["eye_lock"]
        for k in range(el["count"]):
            o = strand(FP["patch_side"] * (el["theta"] + 0.12 * k), el["phi"] + 0.04 * k, el["length"] * (1 - 0.1 * k),
                       el["w"], 0.004 + 0.002 * k, 0.15, el["curl"], 0.25, 0.65, k * 1.3)
            if o is not None:
                objs.append(o)
    hair_obj = join(objs, "hair_cards")
    paint_gradient(hair_obj, 0, 0, hp["c_root"], hp["c_tip"], by_uv=True, strand_jitter=hp.get("strand_jitter", 0.0))
    paint_gradient(helm, cz + rz * 1.2, cz - rz * 0.4, hp["c_root"], hp["c_tip"])
    # Толщина шлема: изнанка у щёк — настоящая поверхность цвета волос, а не «дыра» с контуром.
    sol = helm.modifiers.new("sol", "SOLIDIFY")
    sol.thickness = 0.004
    sol.offset = -1
    apply_mods(helm)
    parts = [helm]
    if hp.get("ahoge_spiral"):
        st = whorl.copy()
        r0 = rx * 0.17
        pts = [st + Vector((0.0, 0.0, rz * hp.get("ahoge_h", 0.3) * k / 5)) for k in range(6)]
        c0 = pts[-1] + Vector((r0, 0, 0))
        for k in range(1, 26):
            a = math.pi - k / 25 * 2 * math.pi * 1.35
            rr = r0 * (1 - 0.6 * k / 25)
            pts.append(c0 + Vector((math.cos(a) * rr, -0.0006 * k, math.sin(a) * rr)))
        ah = clump(pts, rx * 0.12, rx * 0.05, (rx, ry, rz, cz), mat_strand, flat=0.8, v_tip=0.55)
        paint_gradient(ah, 0, 0, hp["c_root"], hp["c_tip"], by_uv=True)
        hair_obj = join([hair_obj, ah], "hair_cards")
    return [join(parts, "hair_cap"), hair_obj]


def build_hair(cid, hd, hp, mat_cap, mat_cards, hd_head=None):
    """hd — «сфера» причёски (у пышной копны больше головы), hd_head — сама голова: на ней внутренняя шапка,
    чёлка и прядь на глаз (они должны лежать у лица, а не на внешнем объёме)."""
    rnd = random.Random(sum(map(ord, cid)))
    rx, ry, rz, cz = hd
    hh = hd_head or hd
    if CONFORM is not None:
        parts = [head_shell_cap(CONFORM, hp, mat_cap)]
    else:
        parts = [hair_cap(hd, hp.get("face_cut", 0.42), hp["cap_low"], 1.06 if hd_head is None else 1.0, mat_cap)]
    if hd_head is not None:
        parts.append(hair_cap(hd_head, 0.42, hp.get("inner_cap_low", 0.6), 1.06, mat_cap))

    cards = []
    solid = hp.get("solid", False)

    def strand(pts, w0, w1, curve=0.25, on=None, **kw):
        if solid:
            return clump(pts, w0 * 0.55, max(w1 * 0.3, rx * 0.04), on or hd, mat_cards, **kw)
        return card(pts, w0, w1, on or hd, mat_cards, curve=curve)
    # Слои вокруг головы: внутренний — плотнее и короче, внешний — пышнее.
    for layer, (phi0, count, lift) in enumerate(hp["layers"]):
        for i in range(count):
            theta = 2 * math.pi * (i + 0.5 * layer) / count + rnd.uniform(-0.06, 0.06)
            front = math.cos(theta)
            if front > hp["bang_front"]:
                # Чёлка спадает на лоб: без завитка вверх, кончики чуть внутрь.
                phi1 = hp["bang_len"] + rnd.uniform(-0.1, 0.12)
                drop = 0.0
                curl = -0.25 * hp["curl"]
            else:
                side = 1 - max(front, -1) * 0.5
                phi1 = hp["side_len"] * side + rnd.uniform(-0.15, 0.15)
                drop = hp["long"] * (0.55 + 0.45 * (1 - front)) * rnd.uniform(0.85, 1.1)
                curl = hp["curl"]
            lift1 = hp.get("bang_lift_end", lift + 0.1) if front > hp["bang_front"] else lift + 0.1 + 0.03 * layer
            if hd_head is not None and front > hp["bang_front"]:
                # Чёлка — по самой голове, до глаз.
                pts = flow_path(hh, theta, phi0, hp["bang_len_head"] + rnd.uniform(-0.08, 0.1), 1.12, 1.07,
                                curl=hp.get("bang_curl", curl), rnd=rnd)
                cards.append(strand(pts, hh[0] * hp["w_bang"] * rnd.uniform(0.85, 1.15), hh[0] * 0.3, on=hh))
                continue
            # Поверх черепа: корень у кожи, к кончику прядь отходит — объём без «полки» на макушке.
            lift0 = 1.03 + (lift - 1) * 0.35 if CONFORM is not None else lift
            pts = flow_path(hd, theta, phi0, phi1, lift0, lift1, curl=curl, drop=drop, rnd=rnd)
            cards.append(strand(pts, rx * hp["w"] * rnd.uniform(0.85, 1.15), rx * 0.32))
    # Плотный ряд чёлки (без просветов между прядями).
    bx = hp.get("bang_row")
    if bx:
        for i in range(bx["count"]):
            theta = -bx["spread"] + 2 * bx["spread"] * i / (bx["count"] - 1) + rnd.uniform(-0.03, 0.03)
            pts = flow_path(hd, theta, bx["phi0"], hp["bang_len"] + rnd.uniform(-0.08, 0.1), bx["lift"], hp["bang_lift_end"],
                            curl=-0.05, rnd=rnd)
            cards.append(strand(pts, rx * bx["w"] * rnd.uniform(0.85, 1.15), rx * 0.3))
    # Крупная прядь на правый глаз (Кот).
    if hp.get("eye_bang"):
        eb = hp["eye_bang"] if isinstance(hp["eye_bang"], dict) else {}
        for th, ph1, w in ((0.36, 1.68, 0.9), (0.18, 1.5, 0.75), (0.55, 1.62, 0.7)):
            th *= FP["patch_side"]                       # прядь падает на глаз под повязкой
            pts = flow_path(hh, th, 0.18, eb.get("len", 1.62) + (ph1 - 1.62), eb.get("lift0", 1.13), eb.get("lift1", 1.17), curl=-0.2, rnd=rnd)
            cards.append(strand(pts, hh[0] * w, hh[0] * 0.3, on=hh))
    # Хохолок-завиток.
    if hp.get("ahoge"):
        top = on_scalp(hd, 0.3, 0.08, 1.06)
        pts = [top + Vector((0.0, -0.012 * k * k * 0.25, 0.022 * k - 0.0035 * k * k)) * (rx / 0.08) for k in range(8)]
        cards.append(card(pts, rx * 0.22, rx * 0.04, hd, mat_cards, curve=0.0))
    # Хохолок-спираль «@» (Кот, реф. 16): трубка, закрученная в плоскости лица.
    if hp.get("ahoge_spiral"):
        st = conform(on_scalp(hd, 0.2, 0.12, 1.1), 1.1)
        pts = [st + Vector((0.0, 0.0, rz * hp.get("ahoge_h", 0.1) * k / 5)) for k in range(6)]
        r0 = rx * 0.14
        c0 = pts[-1] + Vector((r0, 0, 0))
        for k in range(1, 26):
            a = math.pi - k / 25 * 2 * math.pi * 1.35
            rr = r0 * (1 - 0.6 * k / 25)
            pts.append(c0 + Vector((math.cos(a) * rr, -0.0006 * k, math.sin(a) * rr)))
        if solid:
            cards.append(clump(pts, rx * 0.1, rx * 0.05, hd, mat_cards, flat=0.8, v_tip=0.55))
        else:
            parts.append(curve_tube(pts, rx * 0.045, mat_cap, taper=0.25))
    # Кудри-колечки по бокам и сзади.
    n_r = hp.get("ringlets", 0)
    for k in range(n_r):
        theta = 0.75 + (k + 0.5) / n_r * (2 * math.pi - 1.5) + rnd.uniform(-0.08, 0.08)
        phi = hp.get("ringlet_phi", 1.3) + rnd.uniform(0.0, hp.get("ringlet_spread", 0.3)) + (0.25 if abs(theta - math.pi) < 1.2 else 0.0)
        base = on_scalp(hd, theta, phi, 1.15)
        out = Vector((math.sin(theta), -math.cos(theta), 0))
        tang = Vector((math.cos(theta), math.sin(theta), 0))
        r = rx * rnd.uniform(*hp.get("ringlet_r", (0.07, 0.1)))
        turns = rnd.uniform(1.2, 1.8)
        drop = rz * rnd.uniform(*hp.get("ringlet_drop", (0.32, 0.5)))
        steps = int(14 * turns)
        pts = []
        for i in range(steps + 1):
            a = 2 * math.pi * turns * i / steps
            pts.append(base + out * (r * (1 - math.cos(a)) * 0.8) + tang * (r * math.sin(a)) + Vector((0, 0, -drop * i / steps)))
        cards.append(strand(pts, rx * hp.get("ringlet_w", 0.26), rx * 0.1, curve=0.15, **({"flat": 0.95} if solid else {})))
    # Пучки (Габи): шар-основа + карты вокруг.
    for side in hp.get("buns", []):
        c = on_scalp(hd, side * 1.05, 0.62, 1.2)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=16, radius=rx * 0.4, location=c)
        b = bpy.context.active_object
        shade_smooth(b)
        b.data.materials.append(mat_cap)
        parts.append(b)
        for k in range(10):
            a = 2 * math.pi * k / 10
            ring = [c + Vector((math.cos(a + t * 1.6) * rx * 0.44, math.sin(a + t * 1.6) * rx * 0.44 * 0.9, (t - 0.5) * rx * 0.5)) for t in [i / 6 for i in range(7)]]
            cards.append(card([Vector(p) for p in ring], rx * 0.3, rx * 0.15, (rx, ry, rz, c.z), mat_cards, curve=0.1))
    # Хвост (Сора): пучок карт от затылка вниз.
    if hp.get("ponytail"):
        base = on_scalp(hd, math.pi, 1.75, 1.05)
        for k in range(9):
            a = 2 * math.pi * k / 9
            off = Vector((math.cos(a) * rx * 0.12, math.sin(a) * rx * 0.08, 0))
            pts = [base + off + Vector((0, 0.015 * i + 0.002 * i * i, -0.04 * i)) * (rx / 0.08) for i in range(8)]
            cards.append(card(pts, rx * 0.3, rx * 0.06, hd, mat_cards, curve=0.1))
    cards_obj = join(cards, "hair_cards")
    paint_gradient(cards_obj, 0, 0, hp["c_root"], hp["c_tip"], by_uv=True, strand_jitter=hp.get("strand_jitter", 0.0))
    cap_obj = join(parts, "hair_cap")
    paint_gradient(cap_obj, cz + rz, cz - rz * 0.3, hp["c_root"], hp["c_tip"])
    return [cap_obj, cards_obj]


EAR_DEFAULT = {"theta": 1.1, "phi": 0.62, "lift": 1.02, "tip": (0.36, 0.06, 0.6), "r": 0.27}


def build_ears(hd, color, inner, ear):
    """Кошачьи уши: сплюснутый конус (снаружи — цвет волос) + тёмная внутренняя часть спереди.
    ear: theta/phi/lift — основание на поверхности hd; tip — смещение кончика (в rx, ry, rz); r — радиус основания (в rx)."""
    rx, ry, rz, cz = hd
    objs, tips = [], []
    for side in (-1, 1):
        base = conform(on_scalp(hd, side * ear["theta"], ear["phi"], ear["lift"]), ear["lift"])
        tx, ty, tz = ear["tip"]
        axis = Vector((side * rx * tx, ry * ty, rz * tz))
        tips.append(base + axis)
        rot = Vector((0, 0, 1)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
        for m, r, depth, flat, fwd in ((color, ear["r"], 1.0, 0.42, 0.0), (inner, ear["r"] * 0.75, 0.8, 0.22, -0.06)):
            bpy.ops.mesh.primitive_cone_add(vertices=20, radius1=rx * r, radius2=0, depth=axis.length * depth,
                                            location=(0, 0, axis.length * depth / 2))
            o = bpy.context.active_object
            o.data.transform(Matrix.Diagonal((1, flat, 1, 1)))
            o.data.transform(Matrix.Translation(base + Vector((0, fwd * ry * r * 3, 0))) @ rot)
            if m is color:
                o.modifiers.new("sub", "SUBSURF").levels = 1
                apply_mods(o)
            shade_smooth(o)
            o.data.materials.append(m)
            objs.append(o)
    return objs, tips


# ------------------------------------------------------------------ одежда

# Одежда и бельё — «оболочки», снятые с самого тела: участки по ближайшей кости, сдвиг наружу по нормали.
# Так ткань всегда облегает фигуру и тело не проступает сквозь неё (раньше одежда строилась отдельно и
# на стыках кожа просвечивала).
_BODY = None
_BONE_SEGS = []


def set_body(body, J):
    global _BODY, _BONE_SEGS
    _BODY = body
    _BONE_SEGS = [(n, J[a], J[b]) for n, a, b, _ in BONES if b in J]


def _nearest_bone(co):
    best = None
    for name, a, b in _BONE_SEGS:
        ab = b - a
        t = max(0.0, min(1.0, (co - a).dot(ab) / max(ab.length_squared, 1e-9)))
        d = (a + ab * t - co).length
        if best is None or d < best[0]:
            best = (d, name, t)
    return best[1], best[2]


def shell(name, m, spec, smooth=0, uv=(3, 5)):
    """spec(bone, t, co) → смещение наружу (м) или None (участок не входит в вещь)."""
    me = _BODY.data.copy()
    o = new_obj(name, me)
    o.data.materials.clear()
    o.data.materials.append(m)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    kill, moves = [], []
    for v in bm.verts:
        bone, t = _nearest_bone(v.co)
        off = spec(bone, t, v.co)
        if off is None:
            kill.append(v)
        else:
            moves.append((v, v.normal.copy(), off))
    for v, n, off in moves:
        v.co += n * off
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    # Кромка вещи: удаление по вершинам даёт «пилу» — выравниваем край (сглаживание вдоль граничной петли).
    for _ in range(6):
        upd = []
        for v in bm.verts:
            if not v.is_boundary:
                continue
            nb = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
            if len(nb) == 2:
                upd.append((v, (nb[0].co + nb[1].co) / 2))
        for v, c in upd:
            v.co = v.co * 0.4 + c * 0.6
    if smooth:
        for _ in range(smooth):
            bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.to_mesh(me)
    bm.free()
    o.modifiers.new("sol", "SOLIDIFY").thickness = 0.0015
    apply_mods(o)
    shade_smooth(o)
    cylinder_uv(o, *uv)
    return o


def top(J, p, name, m, sleeve="long", neck=False, loose=0.0, cover_hand=False, hem_drop=0.035):
    s = p["s"]
    hem_z = J["pelvis"].z - hem_drop * s
    collar_z = J["neck"].z + 0.05 * s
    base = 0.006 * s + loose * s

    def spec(b, t, co):
        if b in ("spine", "chest", "upper_chest"):
            return base
        if b == "hips" or b.startswith("thigh"):
            return base + 0.004 * s if co.z >= hem_z else None
        if b == "neck":
            if neck:
                return base * 0.8 + 0.006 * s if co.z <= collar_z else None
            return base if co.z <= J["neck"].z - 0.012 * s else None
        if b.startswith("upper_arm"):
            if sleeve == "none":
                # Безрукавка: проймы держим у плеча, чтобы под мышкой не было дыр.
                return base if abs(co.x) < abs(J["sh_l"].x) * 0.92 else None
            if sleeve == "short":
                return base + 0.006 * s if t < 0.55 else None
            return base + 0.004 * s
        if b.startswith("forearm"):
            return base + (0.004 + 0.012 * t) * s if sleeve == "long" else None
        if b.startswith("hand"):
            return base + 0.02 * s if (cover_hand and sleeve == "long" and t < 0.45) else None
        return None
    return shell(name, m, spec, smooth=2 if loose > 0.01 else 1)


def legs(J, p, name, m, kind):
    s = p["s"]
    waist_z = J["pelvis"].lerp(J["spine"], 0.6).z

    if kind == "trousers":
        hem_z = J["an_l"].z + 0.012 * s
        arm_x = abs(J["sh_l"].x) * 0.95

        def spec(b, t, co):
            if b.startswith(("upper_arm", "forearm", "hand")):
                return None
            if not hem_z <= co.z <= waist_z:
                return None
            k = max(0.0, min(1.0, (J["kn_l"].z - co.z) / (J["kn_l"].z - hem_z)))
            return (0.01 + 0.01 * k) * s
        return shell(name, m, spec, smooth=1)
    if kind == "socks":
        def spec(b, t, co):
            if b.startswith("shin"):
                return 0.003 * s if t >= 0.4 else None
            if b.startswith("foot"):
                return 0.003 * s
            return None
        return shell(name, m, spec, uv=(4, 8))
    if kind == "shoes":
        def spec(b, t, co):
            if b.startswith("foot"):
                return 0.011 * s
            if b.startswith("shin"):
                return 0.011 * s if t > 0.9 else None
            return None
        return shell(name, m, spec, smooth=1, uv=(2, 6))
    if kind == "gloves":
        def spec(b, t, co):
            if b.startswith("hand"):
                return 0.004 * s
            if b.startswith("forearm"):
                return 0.005 * s if t > 0.75 else None
            return None
        return shell(name, m, spec)


def underwear(J, p, kind, m):
    """Бельё — базовый слой, который нельзя снять. Мужчинам — боксеры, женщинам — бюстгальтер и трусики."""
    s = p["s"]
    out = []
    wb_z = J["pelvis"].lerp(J["spine"], 0.3 if kind == "male" else 0.18).z
    leg = 0.3 if kind == "male" else 0.16

    leg_z = J["hip_l"].z - leg * (J["hip_l"].z - J["kn_l"].z)
    arm_x = abs(J["sh_l"].x) * 0.95

    def low(b, t, co):
        # Геометрически: от линии пояса до среза на бедре; руки (кисти у бёдер) не захватываем.
        if b.startswith(("upper_arm", "forearm", "hand")) or abs(co.x) > arm_x:
            return None
        return 0.0035 * s if leg_z <= co.z <= wb_z else None
    out.append(shell("underwear__briefs" if kind == "male" else "underwear__panties", m, low))
    if kind == "female":
        # уровень груди — где тело сильнее всего выступает вперёд (по самой сетке, а не по доле роста)
        z0, z1 = J["pelvis"].z + 0.45 * (J["neck"].z - J["pelvis"].z), J["pelvis"].z + 0.9 * (J["neck"].z - J["pelvis"].z)
        cand = [v.co for v in _BODY.data.vertices if 0.02 * s < abs(v.co.x) < 0.09 * s and z0 < v.co.z < z1]
        cz = min(cand, key=lambda c: c.y).z if cand else J["chest"].z

        def bra(b, t, co):
            if not b.startswith(("upper_arm", "forearm", "hand")) and -0.06 * s < co.z - cz < 0.045 * s:
                return 0.0035 * s
            return None
        out.append(shell("underwear__bra", m, bra))
    return out


def add_bust(body, J, p):
    """Мягкие формы груди у женских моделей (смещение вершин тела вперёд)."""
    s = p["s"]
    cz = J["chest"].z + 0.005 * s
    for v in body.data.vertices:
        co = v.co
        if co.y < 0 and abs(co.z - cz) < 0.08 * s:
            for sx in (-1, 1):
                d = ((co.x - sx * 0.045 * s) / (0.035 * s)) ** 2 + ((co.z - cz) / (0.032 * s)) ** 2
                co.y -= 0.018 * s * math.exp(-d)


def skirt(J, p, name, m, top_z, bottom_z, r_top, r_bottom, pleats=14, depth=0.012):
    s = p["s"]
    bm = bmesh.new()
    seg = pleats * 4
    rings = []
    for k, (z, r) in enumerate([(top_z, r_top), ((top_z + bottom_z) / 2, (r_top + r_bottom) / 2), (bottom_z, r_bottom)]):
        rings.append([bm.verts.new((math.cos(2 * math.pi * i / seg) * (r + depth * k * math.sin(2 * math.pi * i / seg * pleats)) * s,
                                    math.sin(2 * math.pi * i / seg) * (r + depth * k * math.sin(2 * math.pi * i / seg * pleats)) * s * 0.85,
                                    z * s)) for i in range(seg)])
    for a, b in zip(rings, rings[1:]):
        for i in range(seg):
            bm.faces.new((a[i], a[(i + 1) % seg], b[(i + 1) % seg], b[i]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = new_obj(name, me)
    o.modifiers.new("sol", "SOLIDIFY").thickness = 0.006 * s
    o.modifiers.new("sub", "SUBSURF").levels = 1
    apply_mods(o)
    shade_smooth(o)
    o.data.materials.append(m)
    cylinder_uv(o, 4, 6)
    return o


def surface_points(target, count, seed, x_range, z_range):
    deps = bpy.context.evaluated_depsgraph_get()
    tree = BVHTree.FromObject(target, deps)
    rnd = random.Random(seed)
    out = []
    for _ in range(count * 3):
        if len(out) >= count:
            break
        x, z = rnd.uniform(*x_range), rnd.uniform(*z_range)
        hit = tree.ray_cast(Vector((x, -1, z)), Vector((0, 1, 0)))
        if hit[0] is not None:
            out.append((hit[0], hit[1]))
    return out


def flower(loc, nrm, r, m_petal, m_core):
    bm = bmesh.new()
    up = nrm.cross(Vector((0, 0, 1))).normalized()
    side = nrm.cross(up).normalized()
    center = bm.verts.new(loc + nrm * 0.0025)
    ring = []
    for k in range(20):
        a = 2 * math.pi * k / 20
        rr = r * (0.55 + 0.45 * abs(math.cos(a * 2.5)))       # 5 лепестков
        ring.append(bm.verts.new(loc + nrm * 0.0025 + (up * math.cos(a) + side * math.sin(a)) * rr))
    for k in range(20):
        bm.faces.new((center, ring[k], ring[(k + 1) % 20]))
    me = bpy.data.meshes.new("flower")
    bm.to_mesh(me)
    bm.free()
    o = new_obj("flower", me)
    o.data.materials.append(m_petal)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=r * 0.22, location=loc + nrm * 0.004)
    c = bpy.context.active_object
    c.data.materials.append(m_core)
    return [o, c]


# ------------------------------------------------------------------ Кот по развороту (реф. 16)
# Образ из art/references/characters/16_kot_turnaround.jpg: серый свитер-«резинка» с высоким воротом,
# рукавами-фонариками и манжетами, ветка белых цветов с листьями на правой стороне груди; чёрные широкие
# брюки-карго (карманы, ремешки с пряжками, ремень с серебряной пряжкой, брелок-цепочка с цветами
# и круглый значок); массивные чёрные ботинки на платформе; заколки — две рыбки и облачко.

def basis_at(loc, nrm, angle=0.0):
    """Локальный базис на поверхности: X — вдоль (горизонтально), Y — «вверх», Z — наружу по нормали."""
    n = nrm.normalized()
    x = Vector((0, 0, 1)).cross(n)
    x = x.normalized() if x.length > 1e-4 else Vector((1, 0, 0))
    y = n.cross(x)
    ca, sa = math.cos(angle), math.sin(angle)
    x, y = x * ca + y * sa, y * ca - x * sa
    M = Matrix((x, y, n)).transposed().to_4x4()
    M.translation = loc
    return M


def ellipsoid(c, r, M, m, seg=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=max(6, seg // 2), radius=1)
    o = bpy.context.active_object
    o.data.transform(Matrix.Diagonal((r[0], r[1], r[2], 1)))
    o.data.transform(Matrix.Translation(Vector(c)))
    o.data.transform(M)
    shade_smooth(o)
    o.data.materials.append(m)
    return o


def flat_poly(pts2d, M, m, z=0.0, thick=0.0012):
    bm = bmesh.new()
    bm.faces.new([bm.verts.new((x, y, z)) for x, y in pts2d])
    me = bpy.data.meshes.new("poly")
    bm.to_mesh(me)
    bm.free()
    o = new_obj("poly", me)
    o.modifiers.new("sol", "SOLIDIFY").thickness = thick
    apply_mods(o)
    o.data.transform(M)
    o.data.materials.append(m)
    return o


def box(center, size, m, bevel=0.0, rot=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    o = bpy.context.active_object
    o.scale = size
    if rot:
        o.rotation_euler = rot
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bevel:
        b = o.modifiers.new("bev", "BEVEL")
        b.width = bevel
        b.segments = 2
        apply_mods(o)
    o.data.materials.append(m)
    return o


def lathe(name, prof, m, center=(0.0, 0.0), sy=1.0, seg=48, thick=0.004, wobble=None, uv=(3, 5)):
    """Тело вращения вокруг вертикали: prof — [(z, r)], wobble(a, k) — складки (доля радиуса)."""
    bm = bmesh.new()
    rings = []
    for k, (z, r) in enumerate(prof):
        ring = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            rr = r * (1 + (wobble(a, k) if wobble else 0.0))
            ring.append(bm.verts.new((center[0] + math.cos(a) * rr, center[1] + math.sin(a) * rr * sy, z)))
        rings.append(ring)
    for a_, b_ in zip(rings, rings[1:]):
        for i in range(seg):
            bm.faces.new((a_[i], a_[(i + 1) % seg], b_[(i + 1) % seg], b_[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = new_obj(name, me)
    if thick:
        o.modifiers.new("sol", "SOLIDIFY").thickness = thick
    o.modifiers.new("sub", "SUBSURF").levels = 1
    apply_mods(o)
    shade_smooth(o)
    o.data.materials.append(m)
    cylinder_uv(o, *uv)
    return o


def tube_along(name, axis_pts, radii, m, seg=40, sy=0.95, wobble=None, uv=(2, 5)):
    """Труба вдоль ломаной (штанина): кольца перпендикулярно вертикали, центр и радиус по точкам."""
    bm = bmesh.new()
    rings = []
    for k, (c, r) in enumerate(zip(axis_pts, radii)):
        ring = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            rr = r * (1 + (wobble(a, k / (len(axis_pts) - 1)) if wobble else 0.0))
            ring.append(bm.verts.new((c.x + math.cos(a) * rr, c.y + math.sin(a) * rr * sy, c.z)))
        rings.append(ring)
    for a_, b_ in zip(rings, rings[1:]):
        for i in range(seg):
            bm.faces.new((a_[i], a_[(i + 1) % seg], b_[(i + 1) % seg], b_[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = new_obj(name, me)
    o.modifiers.new("sol", "SOLIDIFY").thickness = 0.004
    o.modifiers.new("sub", "SUBSURF").levels = 1
    apply_mods(o)
    shade_smooth(o)
    o.data.materials.append(m)
    cylinder_uv(o, *uv)
    return o


def section(obj, z, band=0.012, xmax=0.165):
    """Габариты сечения торса на высоте z: (max|x|, min y, max y); руки (|x| > xmax) не учитываются."""
    xs, ys = [], []
    for v in obj.data.vertices:
        if abs(v.co.z - z) < band and abs(v.co.x) < xmax:
            xs.append(abs(v.co.x))
            ys.append(v.co.y)
    return max(xs), min(ys), max(ys)


def tree_of(objs):
    """BVH по нескольким мешам сразу (координаты вершин — мировые, объекты без трансформаций)."""
    verts, polys = [], []
    for o in objs:
        off = len(verts)
        verts += [v.co.copy() for v in o.data.vertices]
        polys += [[off + i for i in p.vertices] for p in o.data.polygons]
    return BVHTree.FromPolygons(verts, polys)


def front_hit(tree, x, z):
    hit = tree.ray_cast(Vector((x, -2, z)), Vector((0, 1, 0)))
    return (hit[0], hit[1]) if hit[0] is not None else (None, None)


def surface_strip(tree, pts, width, m, lift=0.003):
    """Лента по поверхности (стебель вышивки, ремешок): точки проецируются на ближайшую поверхность."""
    proj = []
    for q in pts:
        loc, nrm, _, _ = tree.find_nearest(q)
        proj.append((loc + nrm * lift, nrm))
    bm = bmesh.new()
    rows = []
    for i, (pt, nrm) in enumerate(proj):
        tan = (proj[min(i + 1, len(proj) - 1)][0] - proj[max(i - 1, 0)][0]).normalized()
        side = nrm.cross(tan).normalized() * (width / 2)
        rows.append((bm.verts.new(pt + side), bm.verts.new(pt - side)))
    for (a1, a2), (b1, b2) in zip(rows, rows[1:]):
        bm.faces.new((a1, a2, b2, b1))
    me = bpy.data.meshes.new("strip")
    bm.to_mesh(me)
    bm.free()
    o = new_obj("strip", me)
    o.modifiers.new("sol", "SOLIDIFY").thickness = 0.0015
    apply_mods(o)
    shade_smooth(o)
    o.data.materials.append(m)
    return o


def leaf(loc, nrm, angle, length, m):
    M = basis_at(loc + nrm * 0.002, nrm, angle)
    pts = [(length * (i / 10), length * 0.32 * math.sin(math.pi * i / 10)) for i in range(11)]
    pts += [(length * (i / 10), -length * 0.32 * math.sin(math.pi * i / 10)) for i in range(9, 0, -1)]
    return flat_poly(pts, M, m)


def blossom(loc, nrm, r, mats, spin=0.0):
    """Цветок вышивки/брелока: 5 округлых лепестков, розоватая середина, жёлтые тычинки."""
    m_petal, m_mid, m_core = mats
    M = basis_at(loc, nrm, spin)
    objs = []
    for k in range(5):
        objs.append(_petal(M, 2 * math.pi * k / 5, r, m_petal))
    objs.append(ellipsoid((0, 0, 0.002), (r * 0.32, r * 0.32, r * 0.1), M, m_mid, seg=10))
    objs.append(ellipsoid((0, 0, 0.0035), (r * 0.13, r * 0.13, r * 0.08), M, m_core, seg=8))
    return objs


def _petal(M, a, r, m):
    R = M @ Matrix.Rotation(a, 4, "Z")
    return ellipsoid((r * 0.55, 0, 0.0012), (r * 0.52, r * 0.4, r * 0.1), R, m, seg=12)


def kot_sweater(J, p, m, flower_mats, leaf_m, stem_m, hem_z):
    s = p["s"]
    base = 0.03 * s          # оверсайз: толстая вязка (реф. 16)

    def spec(b, t, co):
        if b in ("spine", "chest", "upper_chest"):
            return base + 0.012 * s * gauss((co.z - hem_z - 0.04 * s) / (0.05 * s))   # блузит над ремнём
        if b == "hips" or b.startswith("thigh"):
            return base + 0.01 * s if co.z >= hem_z else None
        if b == "neck":
            return base * 0.5 if co.z <= J["neck"].z - 0.03 * s else None
        if b.startswith("upper_arm"):
            return base * 0.8 + 0.014 * s * t        # спущенное плечо, рукав сразу свободный
        if b.startswith("forearm"):
            if t < 0.85:   # рукав-фонарик: расширяется к запястью (реф. 16), над манжетой — пышнее всего
                return 0.03 * s + 0.036 * s * (t / 0.85) ** 1.5
            return 0.009 * s   # манжета-резинка
        if b.startswith("hand"):
            return 0.009 * s if t < 0.1 else None
        return None
    body = shell("tmp", m, spec, smooth=3, uv=(3, 5))
    # Ровный низ-резинка поверх рваного края оболочки.
    hx, hy0, hy1 = section(_BODY, hem_z + 0.02 * s, band=0.02 * s, xmax=0.165 * s)
    hcy = (hy0 + hy1) / 2
    hr = hx + 0.034 * s
    hsy = ((hy1 - hy0) / 2 + 0.034 * s) / hr
    hem = lathe("hem", [(hem_z - 0.004 * s, hr * 0.97), (hem_z + 0.008 * s, hr), (hem_z + 0.03 * s, hr), (hem_z + 0.045 * s, hr * 0.97)],
                m, center=(0, hcy), sy=hsy, uv=(5, 7))
    # Высокий ворот-«труба» (Meshy-лист, IMG_4680/4685): плотно облегает шею (на ~1.5 см шире её),
    # с подвёрнутым толстым валиком; верх — под подбородком; низ расширяется и ложится на плечи свитера.
    nz = J["neck"].z
    nr = 0.5 * (section(_BODY, nz, band=0.01 * s, xmax=0.09 * s)[0] * 2) / 2 * 2      # полуширина шеи
    ny0, ny1 = section(_BODY, nz, band=0.01 * s, xmax=0.09 * s)[1:]
    ncy = (ny0 + ny1) / 2
    nsy = ((ny1 - ny0) / 2) / max(nr, 1e-4)
    r0 = nr + 0.016 * s
    prof = [(nz - 0.11 * s, r0 + 0.035 * s), (nz - 0.085 * s, r0 + 0.035 * s), (nz - 0.06 * s, r0 + 0.026 * s),
            (nz - 0.035 * s, r0 + 0.014 * s),
            (nz - 0.015 * s, r0 + 0.004 * s), (nz + 0.005 * s, r0 + 0.002 * s),
            # валик: подвёрнутый край, толще трубы
            (nz + 0.018 * s, r0 + 0.012 * s), (nz + 0.032 * s, r0 + 0.017 * s), (nz + 0.046 * s, r0 + 0.012 * s),
            (nz + 0.056 * s, r0 + 0.004 * s), (nz + 0.062 * s, r0 - 0.004 * s)]
    collar = lathe("collar", prof, m, center=(0, ncy), sy=min(1.15, max(0.85, nsy)), uv=(9, 9), seg=64,
                   wobble=lambda a, k: 0.035 * max(0.0, math.cos(a * 22)) ** 2)   # вертикальные рубчики вязки
    MARKS["collar"] = Vector((0, ncy - (r0 + 0.017 * s) * min(1.15, max(0.85, nsy)), nz + 0.062 * s))
    # Вышивка (реф. 16, вид спереди): крупная ветка на левой стороне груди (для зрителя справа, +X)
    # и маленькая веточка внизу справа у персонажа (для зрителя слева, −X).
    tree = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
    parts = []
    sprigs = [
        {"path": [(0.112, 1.285), (0.1, 1.255), (0.085, 1.225), (0.07, 1.195), (0.055, 1.165), (0.045, 1.135), (0.04, 1.1)],
         "blooms": [(0.105, 1.268, 0.019, 0.2), (0.078, 1.236, 0.021, 1.0), (0.11, 1.215, 0.015, 2.1), (0.06, 1.2, 0.018, 0.6),
                    (0.083, 1.172, 0.016, 1.7), (0.042, 1.158, 0.015, 2.6), (0.06, 1.128, 0.013, 0.3), (0.035, 1.105, 0.011, 1.2)],
         "leaves": [(0.094, 1.25, 0.5), (0.066, 1.214, 3.5), (0.098, 1.19, -0.5), (0.05, 1.18, 3.3), (0.068, 1.145, -0.3), (0.05, 1.12, 0.3)]},
        {"path": [(-0.06, 1.145), (-0.072, 1.115), (-0.085, 1.085), (-0.098, 1.055), (-0.105, 1.035)],
         "blooms": [(-0.065, 1.13, 0.016, 0.4), (-0.088, 1.098, 0.018, 1.3), (-0.1, 1.06, 0.014, 2.2), (-0.075, 1.07, 0.012, 0.9)],
         "leaves": [(-0.078, 1.118, 2.8), (-0.094, 1.08, 3.6), (-0.06, 1.1, -0.4)]},
    ]
    for sp in sprigs:
        stem_pts = [front_hit(tree, x * s, z * s)[0] for x, z in sp["path"]]
        parts.append(surface_strip(tree, [q for q in stem_pts if q], 0.003 * s, stem_m))
        for x, z, r, spin in sp["blooms"]:
            loc, nrm = front_hit(tree, x * s, z * s)
            if loc:
                parts += blossom(loc + nrm * 0.002, nrm, r * s, flower_mats, spin)
        for x, z, ang in sp["leaves"]:
            loc, nrm = front_hit(tree, x * s, z * s)
            if loc:
                parts.append(leaf(loc, nrm, ang, 0.024 * s, leaf_m))
    return join([body, hem, collar] + parts, "garment__upper_body__turtleneck_flowers")


def kot_cargo(J, p, m, metal, leather, chain_m, flower_mats, leaf_m, badge_mats, belt_z):
    """Широкие брюки-карго: облегающий пояс-оболочка + две широкие штанины, складки у щиколотки."""
    s = p["s"]
    waist_top = belt_z + 0.13 * s     # пояс глубоко уходит под свитер — без голой полоски

    leg_z = J["hip_l"].z - 0.55 * (J["hip_l"].z - J["kn_l"].z)
    arm_x = abs(J["sh_l"].x) * 0.95

    def spec(b, t, co):
        if b.startswith(("upper_arm", "forearm", "hand")) or abs(co.x) > arm_x:
            return None
        return 0.028 * s if leg_z <= co.z <= waist_top else None     # мешковатый пояс
    parts = [shell("tmp", m, spec, smooth=1)]
    legs_by_side = {}
    for sx in (1, -1):
        hip = J["hip_l"] if sx > 0 else J["hip_r"]
        # Очень широкие штанины (реф. 16, по наложению): у пола полуширина брюк ≈ 3U, между штанинами ~5 см.
        # центр штанины — по реальному сечению бедра тела (у базовой модели бедро впереди сустава)
        zz = hip.z - 0.06 * s
        th = [v.co for v in _BODY.data.vertices if abs(v.co.z - zz) < 0.01 * s and v.co.x * sx > 0.01 * s
              and abs(v.co.x) < abs(J["sh_l"].x) * 0.9]
        # перед штанины — на 1.5 см впереди бедра (по центру сечения мешают ягодицы: штанина уезжала назад
        # и спереди сквозь неё проступала кожа)
        thf = [v.co for v in _BODY.data.vertices if J["kn_l"].z < v.co.z < hip.z and v.co.x * sx > 0.01 * s
               and abs(v.co.x) < abs(J["sh_l"].x) * 0.9]
        fy = min(q.y for q in thf) if thf else hip.y - 0.08 * s
        cy = fy + 0.095 * s * 0.95 - 0.015 * s
        cx = (min(abs(q.x) for q in th) + max(abs(q.x) for q in th)) / 2 if th else 0.085 * s
        top_c = Vector((sx * cx, cy, hip.z + 0.02 * s))
        bot_c = Vector((sx * 0.152 * s, 0.006 * s, 0.085 * s))     # низ над ботинками (реф. 16)
        n = 16
        axis = [top_c.lerp(bot_c, k / (n - 1)) for k in range(n)]
        key = [(0.0, 0.095), (0.12, 0.098), (0.4, 0.1), (0.6, 0.106), (1.0, 0.124)]

        def rad(t):
            for (t0, r0), (t1, r1) in zip(key, key[1:]):
                if t <= t1:
                    return (r0 + (r1 - r0) * (t - t0) / (t1 - t0)) * s
            return key[-1][1] * s
        radii = [rad(k / (n - 1)) for k in range(n)]
        ph = 0.7 if sx > 0 else 2.1
        leg = tube_along("leg", axis, radii, m, wobble=lambda a, t, ph=ph: 0.05 * t ** 2 * math.sin(5 * a + ph)
                         + 0.03 * math.sin(3 * a + ph * 2) * t + 0.06 * gauss((t - 0.82) / 0.07))
        parts.append(leg)
        legs_by_side[sx] = leg
        # Карман-карго сбоку бедра с клапаном.
        t = 0.44
        c = top_c.lerp(bot_c, t)
        out_x = c.x + sx * (rad(t) + 0.004 * s)
        parts.append(box((out_x, c.y + 0.004 * s, c.z), (0.016 * s, 0.075 * s, 0.1 * s), m, bevel=0.004 * s))
        parts.append(box((out_x + sx * 0.005 * s, c.y + 0.004 * s, c.z + 0.043 * s), (0.012 * s, 0.08 * s, 0.03 * s), m, bevel=0.003 * s))
        # Ремешок спереди-сбоку от пояса до колена и квадратная пряжка.
        a0 = math.radians(-62 if sx > 0 else -118)
        strap_pts = []
        for k in range(12):
            tt = 0.05 + 0.5 * k / 11
            cc = top_c.lerp(bot_c, tt)
            rr = rad(tt) + 0.003 * s
            strap_pts.append(Vector((cc.x + math.cos(a0) * rr, cc.y + math.sin(a0) * rr * 0.95, cc.z)))
        tree = BVHTree.FromObject(leg, bpy.context.evaluated_depsgraph_get())
        parts.append(surface_strip(tree, strap_pts, 0.014 * s, m, lift=0.004 * s))
        bpt = strap_pts[-1]
        loc, nrm, _, _ = tree.find_nearest(bpt)
        M = basis_at(loc + nrm * 0.006 * s, nrm)
        for x0, y0, w, h in ((0, 0.011, 0.026, 0.004), (0, -0.011, 0.026, 0.004), (0.011, 0, 0.004, 0.026), (-0.011, 0, 0.004, 0.026)):
            fr = box((0, 0, 0), (w * s, h * s, 0.004 * s), metal)
            fr.data.transform(Matrix.Translation((x0 * s, y0 * s, 0)))
            fr.data.transform(M)
            parts.append(fr)
    # Ремень по сечению тела + серебряная пряжка-рамка.
    body_x, y0, y1 = section(_BODY, belt_z, xmax=0.165 * s)
    cy = (y0 + y1) / 2
    rx_b = body_x + 0.042 * s
    ry_b = (y1 - y0) / 2 + 0.036 * s
    parts.append(lathe("belt", [(belt_z - 0.014 * s, rx_b), (belt_z + 0.014 * s, rx_b)], leather, center=(0, cy),
                       sy=ry_b / rx_b, thick=0.003))
    fy = cy - ry_b - 0.004 * s
    for x0, z0, w, h in ((0, 0.016, 0.044, 0.006), (0, -0.016, 0.044, 0.006), (0.019, 0, 0.006, 0.032), (-0.019, 0, 0.006, 0.032)):
        parts.append(box((x0 * s, fy, belt_z + z0 * s), (w * s, 0.006 * s, h * s), metal, bevel=0.0015 * s))
    parts.append(box((0, fy + 0.002 * s, belt_z), (0.004 * s, 0.004 * s, 0.03 * s), metal))
    # Брелок-цепочка с цветами (слева у персонажа = +X) от ремня до середины бедра.
    tree_l = tree_r = tree_of([parts[0], legs_by_side[1], legs_by_side[-1]])
    chain = []
    for k in range(22):
        t = k / 21
        x = (0.07 + 0.02 * t + 0.008 * math.sin(t * 9)) * s
        z = belt_z - 0.012 * s - t * 0.27 * s
        loc, nrm = front_hit(tree_l, x, z)
        if loc is None:
            continue
        q = loc + nrm * (0.012 + 0.006 * t) * s
        bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=0.0035 * s, location=q)
        chain.append(bpy.context.active_object)
        chain[-1].data.materials.append(chain_m)
        if k in (4, 8, 11, 15, 19):
            parts += blossom(q + Vector((0.008 * s * (1 if k % 2 else -1), -0.004 * s, 0)), Vector((0, -1, 0.15)).normalized(),
                             0.012 * s, flower_mats, k * 0.7)
        if k in (6, 13, 17):
            parts.append(leaf(q, Vector((0, -1, 0)), 3.6 if k % 2 else -0.5, 0.016 * s, leaf_m))
    parts += chain
    # Круглый значок-«пластинка» на кольце (справа у персонажа = −X).
    loc, nrm = front_hit(tree_r, -0.1 * s, belt_z - 0.08 * s)
    if loc is None:
        loc, nrm = Vector((-0.095 * s, -0.11 * s, belt_z - 0.075 * s)), Vector((0, -1, 0))
    M = basis_at(loc + nrm * 0.01 * s, nrm)
    for k, (r, z) in enumerate(((0.03, 0.0), (0.022, 0.002), (0.0125, 0.0035), (0.006, 0.0048))):
        bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=r * s, depth=0.003 * s, location=(0, 0, z * s))
        d = bpy.context.active_object
        d.data.transform(Matrix.Translation((0, 0, z * s)))
        d.data.transform(M)
        bpy.ops.object.transform_apply(location=True)
        d.data.materials.append(badge_mats[k])
        parts.append(d)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.008 * s, minor_radius=0.0018 * s, location=(0, 0, 0))
    ring = bpy.context.active_object
    ring.data.transform(Matrix.Rotation(math.pi / 2, 4, "Y"))
    ring.data.transform(Matrix.Translation((0, 0.036 * s, 0.004 * s)))
    ring.data.transform(M)
    bpy.ops.object.transform_apply(location=True)
    ring.data.materials.append(metal)
    parts.append(ring)
    return join(parts, "garment__lower_body__cargo")


def kot_boots(J, p, m, sole_m):
    """Массивные ботинки на платформе: верх — оболочка стопы, подошва-«трактор» — скошенный брусок."""
    s = p["s"]

    def spec(b, t, co):
        if b.startswith("foot"):
            return 0.022 * s
        if b.startswith("shin"):
            return 0.022 * s if t > 0.72 else None
        return None
    parts = [shell("tmp", m, spec, smooth=2, uv=(2, 6))]
    for side in ("l", "r"):
        an, to = J["an_" + side], J["to_" + side]
        heel_y, toe_y = an.y + 0.05 * s, to.y - 0.04 * s
        x = (an.x + to.x) / 2
        bm = bmesh.new()
        vs = []
        for yy, ztop, hw in ((heel_y, 0.075, 0.046), (toe_y, 0.04, 0.054)):
            for xx in (-hw, hw):
                vs.append(bm.verts.new((x + xx * s, yy, -0.028 * s)))
                vs.append(bm.verts.new((x + xx * s, yy, ztop * s)))
        bmesh.ops.convex_hull(bm, input=vs)
        me = bpy.data.meshes.new("sole")
        bm.to_mesh(me)
        bm.free()
        so = new_obj("sole", me)
        bev = so.modifiers.new("bev", "BEVEL")
        bev.width = 0.012 * s
        bev.segments = 3
        so.modifiers.new("sub", "SUBSURF").levels = 1
        apply_mods(so)
        shade_smooth(so)
        so.data.materials.append(sole_m)
        parts.append(so)
        # Рифление подошвы: тёмные поперечные выступы по бокам.
        for k in range(6):
            yy = heel_y + (toe_y - heel_y) * (k + 0.5) / 6
            parts.append(box((x, yy, -0.027 * s), (0.088 * s, 0.01 * s, 0.008 * s), sole_m, bevel=0.002 * s))
    return join(parts, "garment__footwear__boots")


def fish_clip(loc, nrm, angle, rx, m_body, m_belly, m_eye):
    M = basis_at(loc, nrm, angle)
    u = rx
    objs = [ellipsoid((0, 0, 0.05 * u), (0.2 * u, 0.1 * u, 0.06 * u), M, m_body),
            ellipsoid((0.03 * u, -0.035 * u, 0.075 * u), (0.12 * u, 0.045 * u, 0.035 * u), M, m_belly),
            ellipsoid((0.12 * u, 0.025 * u, 0.09 * u), (0.022 * u, 0.022 * u, 0.015 * u), M, m_eye, seg=10)]
    objs.append(flat_poly([(-0.17 * u, 0), (-0.33 * u, 0.1 * u), (-0.28 * u, 0), (-0.33 * u, -0.1 * u)], M, m_body, z=0.05 * u, thick=0.012 * u))
    objs.append(flat_poly([(-0.08 * u, 0.07 * u), (0.05 * u, 0.09 * u), (-0.12 * u, 0.16 * u)], M, m_body, z=0.05 * u, thick=0.01 * u))
    return objs


def cloud_clip(loc, nrm, angle, rx, m_white, m_edge):
    M = basis_at(loc, nrm, angle)
    u = rx
    puffs = [(-0.13, -0.01, 0.075), (-0.05, 0.04, 0.09), (0.06, 0.05, 0.085), (0.14, -0.005, 0.07), (0.0, -0.03, 0.08)]
    objs = []
    for x, y, r in puffs:
        objs.append(ellipsoid((x * u, y * u, 0.05 * u), (r * u, r * u * 0.85, 0.035 * u), M, m_white, seg=14))
        objs.append(ellipsoid((x * u, y * u, 0.035 * u), (r * u * 1.18, r * u * 1.03, 0.03 * u), M, m_edge, seg=14))
    return objs


# ------------------------------------------------------------------ скелет и анимация

BONES = [
    ("hips", "pelvis", "spine", None), ("spine", "spine", "chest", "hips"), ("chest", "chest", "upchest", "spine"),
    ("upper_chest", "upchest", "neck", "chest"),
    ("neck", "neck", "head", "upper_chest"), ("head", "head", "head_top", "neck"),
    ("upper_arm.L", "sh_l", "el_l", "upper_chest"), ("forearm.L", "el_l", "wr_l", "upper_arm.L"), ("hand.L", "wr_l", "palm_l", "forearm.L"),
    ("upper_arm.R", "sh_r", "el_r", "upper_chest"), ("forearm.R", "el_r", "wr_r", "upper_arm.R"), ("hand.R", "wr_r", "palm_r", "forearm.R"),
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
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def _seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


def bind(rig, objs, rigid_bone=None):
    """Веса: две ближайшие кости (обратный квадрат расстояния); голова и всё на ней — жёстко к кости head."""
    bones = [(b.name, b.head_local.copy(), b.tail_local.copy()) for b in rig.data.bones if b.name != "head"]
    for o in objs:
        o.parent = rig
        o.modifiers.new("rig", "ARMATURE").object = rig
        if rigid_bone:
            o.vertex_groups.new(name=rigid_bone).add(range(len(o.data.vertices)), 1.0, "REPLACE")
            continue
        groups = {name: o.vertex_groups.new(name=name) for name, _, _ in bones}
        mw = o.matrix_world
        for v in o.data.vertices:
            p = mw @ v.co
            d = sorted((_seg_dist(p, h, t), name) for name, h, t in bones)[:2]
            w0, w1 = 1.0 / max(d[0][0], 1e-4) ** 2, 1.0 / max(d[1][0], 1e-4) ** 2
            if d[1][0] > d[0][0] * 1.8:
                w1 = 0.0
            tot = w0 + w1
            groups[d[0][1]].add([v.index], w0 / tot, "REPLACE")
            if w1 > 0:
                groups[d[1][1]].add([v.index], w1 / tot, "ADD")


def idle_animation(rig, frames=96):
    rig.animation_data_create()
    rig.animation_data.action = bpy.data.actions.new("idle")
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    pb = rig.pose.bones
    for b in pb:
        b.rotation_mode = "XYZ"
    for f in range(0, frames + 1, 12):
        t = f / frames * 2 * math.pi
        pb["chest"].rotation_euler = (math.sin(t) * 0.02, 0, 0)
        pb["chest"].scale = (1 + math.sin(t) * 0.006,) * 3
        pb["head"].rotation_euler = (math.sin(t + 0.6) * 0.025, math.sin(t * 0.5) * 0.035, 0)
        pb["upper_arm.L"].rotation_euler = (0, 0, math.sin(t) * 0.015)
        pb["upper_arm.R"].rotation_euler = (0, 0, -math.sin(t) * 0.015)
        for n in ("chest", "head", "upper_arm.L", "upper_arm.R"):
            pb[n].keyframe_insert("rotation_euler", frame=f)
        pb["chest"].keyframe_insert("scale", frame=f)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = frames


# ------------------------------------------------------------------ персонажи

CHARACTERS = {
    # Кот (реф. 04, разворот — реф. 16): 163 см, стройный юноша. Кудрявые бирюзовые волосы → синие кончики, чёлка на правый глаз,
    # кошачьи уши, хохолок. Свитер с высоким воротом и цветами — оверсайз, рукава до костяшек.
    "kot": {
        "sex": "male",
        "body": {"s": 1.0, "shoulder": 0.137, "hip": 0.078, "head": 1.05, "neck": 0.04, "arm_out": (0.032, 0.1),
                 # тело — открытая базовая модель MakeHuman (CC0), подросток, худощавый (Meshy-лист, реф. 16)
                 "mh": {"teen": 0.5, "thin": 0.8, "neck_z": 1.36, "pelvis_z": 0.9, "slim": 0.89}, "waist": 0.078, "chest": 0.094, "hip_r": 0.098},
        # Пышная кудрявая копна (реф. 16): шире головы в ~1.5 раза, до линии подбородка; чёлка до глаз.
        # Причёска «поверх» вылепленной головы (объём даёт сам череп): крупные острые пряди, без кудряшек;
        # чёлка до глаз, прядь на глаз под повязкой, хохолок-спираль.
        # Причёска по принципу игровых аниме-моделей (см. docs/MODEL_STUDY.md): шлем массы волос + пряди-ленты
        # от вихра на макушке; концы завиваются (реф. 16 — пышные завитки по бокам, чёлка до глаз).
        "hair": {"ribbons": True, "solid": True, "hairline": 0.12, "nape": 0.62, "thick_top": 0.06, "thick_side": 0.055,
                 "cheek_puff": 0.35, "face_open_x": 0.82, "thick": 0.6,
                 "whorl": (0.12, 1.0),
                 # Пряди-локоны как на Meshy-модели: толстые, круглые в сечении, концы закручены в завиток.
                 "groups": [
                     # мантия от макушки: длины сильно разные — концы-завитки на разной высоте (не «юбка»)
                     {"count": 47, "theta": (-2.4, 2.4), "phi": (0.22, 0.5), "length": (0.2, 0.37), "w": (0.026, 0.038),
                      "sway": 0.3, "curl": (220, 340), "curl_frac": 0.35, "bias": 0.35, "lift": 0.004, "skip_front": 0.95,
                      "curl_both": True},
                     {"count": 28, "theta": (2.2, 4.08), "phi": (0.3, 0.8), "length": (0.22, 0.36), "w": (0.026, 0.038),
                      "sway": 0.3, "curl": (220, 340), "curl_frac": 0.35, "bias": 0.5, "lift": 0.004, "curl_both": True},
                     # чёлка: локоны до глаз и ниже, концы — завитки вбок
                     {"count": 24, "theta": (-1.15, 1.15), "phi": (0.25, 0.45), "length": (0.2, 0.26), "w": (0.026, 0.036),
                      "sway": 0.3, "curl": (25, 70), "curl_frac": 0.22, "bias": 0.55, "lift": 0.007, "curl_both": True},
                     # средний слой по бокам и сзади
                     {"count": 61, "theta": (-3.14, 3.14), "phi": (0.6, 1.25), "length": (0.12, 0.26), "w": (0.022, 0.032),
                      "sway": 0.3, "curl": (250, 360), "curl_frac": 0.45, "bias": 0.75, "lift": 0.007, "skip_front": 0.85,
                      "curl_both": True},
                     # нижний слой: свисающие локоны закрывают затылок и шею до ворота
                     {"count": 56, "theta": (-3.14, 3.14), "phi": (1.2, 1.75), "length": (0.08, 0.16), "w": (0.021, 0.028),
                      "sway": 0.2, "curl": (260, 380), "curl_frac": 0.6, "bias": 0.9, "lift": 0.006, "skip_front": 0.75,
                      "curl_both": True},
                     # мелкие завитки по поверхности (фактура кудрей)
                     {"count": 70, "theta": (-3.14, 3.14), "phi": (0.25, 1.3), "length": (0.05, 0.08), "w": (0.017, 0.022),
                      "sway": 0.1, "curl": (260, 360), "curl_frac": 0.8, "bias": 0.5, "lift": 0.011, "skip_front": 0.6,
                      "curl_both": True},
                 ],
                 "eye_lock": {"count": 3, "theta": 0.3, "phi": 0.3, "length": 0.2, "w": 0.045, "curl": 60},
                 "ahoge_spiral": True, "ahoge_h": 0.45, "strand_jitter": 0.06,
                 "c_root": (0.6, 0.76, 0.66), "c_tip": (0.42, 0.52, 0.72)},
        # Уши на черепе (реф. 16): крупные, с тёмной серединой.
        "ear": {"theta": 1.3, "phi": 0.8, "lift": 1.1, "tip": (0.42, 0.02, 1.35), "r": 0.56},
        # Заколки (theta, phi, отступ от кожи, поворот, масштаб): большая рыбка слева, малая справа, облачко.
        "clips": {"fish": [(-1.3, 1.45, 1.5, 1.5, 2.0), (1.3, 1.2, 1.5, 0.0, 1.5)], "cloud": (0.62, 0.95, 1.45, 0.1, 1.4)},
        "geo_lashes": {"lash": (0.1, 0.08, 0.12), "brow": (0.16, 0.3, 0.32)},
        "ears": (0.56, 0.72, 0.64), "ear_inner": (0.3, 0.25, 0.25),
        "garments": ["kot_sweater", "kot_cargo", "kot_boots", "top_long", "top_tshirt", "outer_jacket", "legs_trousers", "legs_skirt", "dress",
                     "socks", "shoes", "gloves", "head_clips", "face_eyepatch", "neck_necklace"],
    },
    # Габи (реф. 05–07): рост не задан — близко к Коту. Два пучка вместе с распущенными волосами (ответ пользователя).
    "gabi": {
        "sex": "female",
        "body": {"s": 0.98, "shoulder": 0.135, "hip": 0.084, "head": 1.0,
                 # тело — та же открытая база (CC0), женская форма; пропорции Silver Palace — только как замеры
                 "mh": {"teen": 0.35, "thin": 0.6, "bust": 0.65, "neck_z": 1.335, "pelvis_z": 0.9, "slim": 0.95}, "waist": 0.07, "chest": 0.092, "chest_d": 0.08, "hip_r": 0.108},
        "hair": {"layers": [(0.15, 20, 1.06), (0.45, 28, 1.1), (0.8, 30, 1.14)], "bang_front": 0.6, "bang_len": 1.2,
                 "side_len": 2.0, "long": 0.22, "curl": 0.1, "w": 0.95, "cap_low": 0.75, "buns": [-1, 1],
                 "c_root": (0.8, 0.28, 0.42), "c_tip": (0.99, 0.62, 0.3)},
        "ears": None,
        "garments": ["top_long", "top_tshirt", "outer_jacket", "legs_trousers", "legs_skirt", "dress", "socks", "shoes",
                     "gloves", "face_eyepatch", "neck_necklace", "head_clips"],
    },
    # Сора (реф. 12): 206 см, шире в плечах; растрёпанные бирюзовые волосы с хвостом, уши, хохолок.
    "sora": {
        "sex": "male",
        "body": {"s": 206 / 163, "shoulder": 0.16, "hip": 0.082, "head": 0.95,
                 "mh": {"teen": 0.0, "thin": 0.5, "neck_z": 1.335, "pelvis_z": 0.9, "slim": 1.0}, "waist": 0.084, "chest": 0.104, "hip_r": 0.1},
        "hair": {"layers": [(0.12, 18, 1.07), (0.4, 26, 1.12), (0.75, 28, 1.17)], "bang_front": 0.55, "bang_len": 1.3,
                 "side_len": 1.85, "long": 0.04, "curl": 0.3, "w": 0.95, "cap_low": 0.6, "ahoge": True, "ponytail": True,
                 "c_root": (0.2, 0.6, 0.6), "c_tip": (0.16, 0.44, 0.54)},
        "ears": (0.2, 0.58, 0.58), "ear_inner": (0.92, 0.7, 0.74),
        "garments": ["top_long", "top_tshirt", "outer_vest", "outer_jacket", "legs_trousers", "socks", "shoes",
                     "neck_tie", "face_eyepatch", "neck_necklace", "head_clips"],
    },
}


def build(cid):
    reset()
    set_face(cid)
    c = CHARACTERS[cid]
    p = c["body"]
    s = p["s"]
    skin = mat("skin", SKIN, rough=0.6)
    if p.get("mh"):
        body, J = build_mh_body(p, c["sex"], skin)
    else:
        J = body_joints(p)
    knit = mat("garment_knit", (1, 1, 1, 1), tex=os.path.join(TEX, "knit.png"))
    cloth = mat("garment_cloth", (1, 1, 1, 1), tex=os.path.join(TEX, "cloth.png"))
    plain = mat("garment_plain", (1, 1, 1, 1))
    rib = mat("garment_rib", (1, 1, 1, 1), tex=os.path.join(TEX, "rib.png"))
    metal = mat("metal", (0.78, 0.78, 0.8, 1), rough=0.2)
    leather = mat("leather", (0.1, 0.09, 0.1, 1), rough=0.4)
    flower_mats = (mat("flower", (0.99, 0.94, 0.94, 1)), mat("flower_mid", (0.95, 0.66, 0.7, 1)), mat("flower_core", (0.97, 0.78, 0.4, 1)))
    leaf_m = mat("leaf", (0.36, 0.56, 0.36, 1))
    stem_m = mat("stem", (0.42, 0.3, 0.26, 1))
    belt_z = J["pelvis"].lerp(J["spine"], 0.38).z
    # Без текстуры: при экспорте с текстурой цвет материала теряется (становится белым, сливается с кожей).
    under = mat("underwear", (0.92, 0.6, 0.7, 1) if c["sex"] == "female" else (0.2, 0.25, 0.4, 1), rough=0.6)

    if not p.get("mh"):
        R = body_radii(p)
        body = build_part("body", J, list(J.keys()), body_edges(), lambda j: _rs(R[j], s), skin)
        if c["sex"] == "female":
            add_bust(body, J, p)
    set_body(body, J)
    head, hd = build_head(cid, J, p)
    eyes = build_eyes(cid, head, hd)
    if c.get("geo_lashes"):
        eyes += build_lashes(head, hd, c["geo_lashes"])
    hair_mat = (mat("hair_solid", (1, 1, 1, 1), vcol=True, rough=0.5) if c["hair"].get("solid") else
                mat("hair", (1, 1, 1, 1), tex=os.path.join(TEX, "hair_strands.png"), vcol=True, clip=True, double=True))
    # Объём причёски: волосы строятся на увеличенной «сфере» hd_h (у Кота по реф. 16 — пышная копна шире головы).
    global CONFORM
    hv = c["hair"].get("volume")
    hd_h = (hd[0] * hv[0], hd[1] * hv[1], hd[2] * hv[2], hd[3] + hd[2] * hv[3]) if hv else hd
    if c["hair"].get("conform"):
        # Волосы «рисуются поверх» вылепленной головы: направления — по сфере черепа, расстояние — от кожи.
        sx, sy, sz = FP.get("cranium", (1.0, 1.0, 1.0))
        hd_h = (hd[0] * sx, hd[1] * sy, hd[2] * sz, hd[3])
        CONFORM = (BVHTree.FromObject(head, bpy.context.evaluated_depsgraph_get()), Vector((0, 0, hd[3])), hd[0], hd[3], hd[2])
    if c["hair"].get("ribbons"):
        hair = build_hair_ribbons(cid, head, hd, c["hair"], mat("hair_cap", (1, 1, 1, 1), vcol=True, rough=0.5), hair_mat)
        hd_h = (hd[0] * 1.15, hd[1] * 1.15, hd[2] * 1.1, hd[3])
    else:
        hair = build_hair(cid, hd_h, c["hair"], mat("hair_cap", (1, 1, 1, 1), vcol=True, rough=0.5), hair_mat,
                          hd_head=hd if hv else None)
    head_parts = [head] + eyes + hair
    marks = landmarks_head(head, hd, hair)
    if c.get("ears"):
        ear = dict(EAR_DEFAULT)
        ear.update(c.get("ear", {}))
        ear_objs, tips = build_ears(hd_h, mat("ear", c["ears"] + (1,)), mat("ear_inner", c["ear_inner"] + (1,)), ear)
        head_parts += ear_objs
        marks["ear_tip_vl"], marks["ear_tip_vr"] = tips
    body_layers = underwear(J, p, c["sex"], under)

    garments = []
    for g in c["garments"]:
        o = None
        if g == "kot_sweater":
            o = kot_sweater(J, p, rib, flower_mats, leaf_m, stem_m, belt_z + 0.008 * s)
        elif g == "kot_cargo":
            o = kot_cargo(J, p, cloth, metal, leather, mat("chain", (0.32, 0.3, 0.33, 1), rough=0.3), flower_mats, leaf_m,
                          [mat("badge_rim", (0.1, 0.1, 0.12, 1), rough=0.3), mat("badge_ring", (0.86, 0.86, 0.88, 1)),
                           mat("badge_red", (0.82, 0.2, 0.24, 1)), mat("badge_dot", (0.25, 0.55, 0.3, 1))], belt_z)
        elif g == "kot_boots":
            o = kot_boots(J, p, plain, mat("sole", (0.07, 0.07, 0.08, 1), rough=0.5))
        elif g == "top_long":
            o = top(J, p, "garment__upper_body__long", cloth, "long")
        elif g == "top_tshirt":
            o = top(J, p, "garment__upper_body__tshirt", cloth, "short")
        elif g == "outer_jacket":
            o = top(J, p, "garment__outerwear__jacket", cloth, "long", loose=0.024)
        elif g == "outer_vest":
            o = top(J, p, "garment__outerwear__vest", cloth, "none", loose=0.012)
        elif g == "legs_trousers":
            o = legs(J, p, "tmp", cloth, "trousers")
            # Ремень.
            bz = J["pelvis"].lerp(J["spine"], 0.55).z
            bpy.ops.mesh.primitive_torus_add(major_radius=1, minor_radius=0.1, location=(0, 0, bz))
            belt = bpy.context.active_object
            belt.scale = ((p["waist"] + 0.016) * s, (0.074) * s, 0.06 * s * 0.18)
            bpy.ops.object.transform_apply(scale=True)
            belt.data.materials.append(leather)
            bpy.ops.mesh.primitive_cube_add(size=0.018 * s, location=(0, -0.07 * s, bz))
            buckle = bpy.context.active_object
            buckle.scale = (1, 0.4, 0.8)
            bpy.ops.object.transform_apply(scale=True)
            buckle.data.materials.append(metal)
            o = join([o, belt, buckle], "garment__lower_body__trousers")
        elif g == "legs_skirt":
            o = skirt(J, p, "garment__lower_body__skirt", cloth, 0.98, 0.66, p["waist"] + 0.02, 0.19)
        elif g == "dress":
            t_ = top(J, p, "tmp", cloth, "none", loose=0.004)
            sk = skirt(J, p, "tmp2", cloth, 0.97, 0.16, p["waist"] + 0.022, 0.28, pleats=10)
            o = join([t_, sk], "garment__full_body__dress")
        elif g == "socks":
            o = legs(J, p, "garment__socks__knee", knit, "socks")
        elif g == "shoes":
            o = legs(J, p, "garment__footwear__shoes", plain, "shoes")
        elif g == "gloves":
            o = legs(J, p, "garment__gloves__gloves", plain, "gloves")
        elif g == "head_clips":
            # Две красные рыбки и облачко (реф. 16): рыбки — основной цвет вещи, облачко — своё.
            rx, ry, rz, cz = hd
            red_belly = mat("clip_belly", (0.98, 0.66, 0.66, 1))
            eye_m = mat("clip_eye", (0.08, 0.06, 0.08, 1), rough=0.2)
            objs = []
            cl = c.get("clips", {"fish": [(-0.98, 0.78, 1.3, 2.6, 1.0), (1.32, 1.0, 1.3, 0.5, 1.0)], "cloud": (0.66, 0.8, 1.3, 0.15, 1.0)})
            hcz = hd_h[3]
            for th, ph, lf, ang, sc in cl["fish"]:
                q = conform(on_scalp(hd_h, th, ph, lf), lf)
                fn = ((q - Vector((0, 0, hcz))).normalized() * 0.45 + Vector((0, -1, 0)) * 0.55).normalized()   # к зрителю
                objs += fish_clip(q, fn, ang, rx * sc, plain, red_belly, eye_m)
            th, ph, lf, ang, sc = cl["cloud"]
            q = conform(on_scalp(hd_h, th, ph, lf), lf)
            objs += cloud_clip(q, ((q - Vector((0, 0, hcz))).normalized() * 0.5 + Vector((0, -1, 0)) * 0.5).normalized(), ang, rx * sc,
                               mat("cloud", (0.99, 0.95, 0.95, 1)), mat("cloud_edge", (0.95, 0.56, 0.62, 1)))
            o = join(objs, "garment__headwear__clips")
        elif g == "face_eyepatch":
            rx, ry, rz, cz = hd
            ps = FP["patch_side"]
            ex, ez = ps * FP["eye_u"] * 2 * rx, cz - (FP["eye_v"] - 0.5) * 2 * rz
            tree = BVHTree.FromObject(head, bpy.context.evaluated_depsgraph_get())
            # Повязка (реф. 16) — скруглённый прямоугольник, повторяет изгиб лица: кусок оболочки головы.
            ex = ps * (FP["eye_u"] * 2 + FP.get("patch_dx", 0.0)) * rx
            pa, pb, pcz = (FP["eye_w"] * 2 + 0.04) * rx, rz * 0.22, ez + rz * FP.get("patch_dz", 0.06)
            pm = head.data.copy()
            patch = new_obj("patch", pm)
            bm = bmesh.new()
            bm.from_mesh(pm)
            bm.normal_update()
            kill = [v for v in bm.verts if v.co.y > -ry * 0.55 or
                    (abs(v.co.x - ex) / pa) ** 3 + (abs(v.co.z - pcz) / pb) ** 3 > 1.0]
            bmesh.ops.delete(bm, geom=kill, context="VERTS")
            for v in bm.verts:   # край — ровно по контуру скруглённого прямоугольника (без «лесенки» сетки)
                if v.is_boundary:
                    dx, dz = v.co.x - ex, v.co.z - pcz
                    f = ((abs(dx) / pa) ** 3 + (abs(dz) / pb) ** 3) ** (1 / 3)
                    if f > 1e-6:
                        q = tree.find_nearest(Vector((ex + dx / f, v.co.y, pcz + dz / f)))[0]
                        if q is not None:
                            v.co = q
            bm.normal_update()
            for v in bm.verts:   # купол: в центре повязка отстоит от лица (под ней ресницы), к краям прилегает
                rr = min(1.0, (abs(v.co.x - ex) / pa) ** 3 + (abs(v.co.z - pcz) / pb) ** 3)
                v.co += v.normal * (0.0015 + 0.009 * (1 - rr ** 1.5))
            bm.to_mesh(pm)
            bm.free()
            pm.materials.clear()
            pm.materials.append(plain)
            patch.modifiers.new("sol", "SOLIDIFY").thickness = 0.003
            apply_mods(patch)
            shade_smooth(patch)
            ring = []
            for k in range(65):
                a = 2 * math.pi * k / 64
                xn, yn = math.sin(a), -math.cos(a)
                # Шнурок в наклонной плоскости (реф. 16): от повязки через переносицу вниз под другой глаз,
                # ниже уха, вокруг затылка и над правым ухом обратно к повязке.
                ezn = 1 - 2 * FP["eye_v"]
                ring.append(Vector((xn * rx * 1.07, yn * ry * 1.07, cz + rz * (0.35 * ps * xn + 0.195 * yn + ezn + 0.155))))
            proj = []
            for q in ring:   # проекция по радиусу к оси головы — шнурок ложится ровно, без изломов на носу
                d = (Vector((0, 0, q.z)) - q).normalized()
                hit = tree.ray_cast(q, d)
                proj.append(hit[0] + hit[1] * 0.0025 if hit[0] else q)
            ring = proj
            strap = curve_tube(ring, 0.0007, mat("strap", (0.08, 0.07, 0.08, 1), rough=0.4), taper=1.0)   # тонкий шнурок
            o = join([patch, strap], "garment__face_accessory__eyepatch")
        elif g == "neck_necklace":
            beads = []
            nz = J["neck"].z - 0.03 * s
            for k in range(20):
                a = math.pi * (0.12 + 0.76 * k / 19)
                loc = Vector((math.cos(a) * 0.058 * s, -math.sin(a) * 0.06 * s - 0.012 * s, nz - math.sin(a) * 0.035 * s))
                bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=0.0065 * s, location=loc)
                beads.append(bpy.context.active_object)
                beads[-1].data.materials.append(plain)
            o = join(beads, "garment__neck_accessory__necklace")
        elif g == "neck_tie":
            nz = J["neck"].z - 0.025 * s
            bm = bmesh.new()
            pts = [(0, nz), (0.012, nz - 0.03 * s), (0.02, nz - 0.2 * s), (0, nz - 0.24 * s), (-0.02, nz - 0.2 * s), (-0.012, nz - 0.03 * s)]
            vs = [bm.verts.new((x * s, -(p["chest"] - 0.004) * s - 0.03, z)) for x, z in pts]
            bm.faces.new(vs)
            me = bpy.data.meshes.new("tie")
            bm.to_mesh(me)
            bm.free()
            o = new_obj("garment__neck_accessory__tie", me)
            o.modifiers.new("sol", "SOLIDIFY").thickness = 0.006
            apply_mods(o)
            o.data.materials.append(plain)
        if o is not None:
            garments.append(o)

    CONFORM = None
    landmarks_body(body, garments)
    export_landmarks()
    rig = build_armature(J, Vector((0, 0, hd[3] + hd[2])))
    on_head = ("garment__headwear", "garment__face")
    bind(rig, [body] + body_layers + [g for g in garments if not g.name.startswith(on_head)])
    bind(rig, head_parts + [g for g in garments if g.name.startswith(on_head)], rigid_bone="head")
    idle_animation(rig)

    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{cid}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_animations=True, export_skins=True, export_yup=True)
    print("exported", path, "garments:", [g.name for g in garments], "underwear:", [u.name for u in body_layers])


if __name__ == "__main__":
    ids = [a for a in sys.argv[1:] if a in CHARACTERS] or list(CHARACTERS)
    for cid in ids:
        build(cid)
