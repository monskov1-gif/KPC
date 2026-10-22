"""Силуэт тела модели для сверки с референсом (запускается Blender'ом из body_overlay.sh).

Ортокамера спереди и сбоку, только тело и голова (без белья, волос, ушей, одежды), белое на чёрном.
Пишет <out>_front.png, <out>_side.png (и *_hair.png — с причёской и ушами) и <out>.json (масштаб: пикселей на метр, высота пола и подбородка).
Аргументы: -- <model.glb> <out_prefix>
"""
import json
import sys

import bpy
from mathutils import Vector

src, out = sys.argv[sys.argv.index("--") + 1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
sc.render.engine = "CYCLES"              # Workbench без GPU не запускается; эмиссия даёт тот же силуэт
sc.cycles.device = "CPU"
sc.cycles.samples = 1
sc.render.film_transparent = False
white = bpy.data.materials.new("sil")
white.use_nodes = True
nt = white.node_tree
nt.nodes.clear()
em = nt.nodes.new("ShaderNodeEmission")
em.inputs["Color"].default_value = (1, 1, 1, 1)
nt.links.new(em.outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs[0])
sc.view_layers[0].material_override = white
sc.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("W")
sc.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[1].default_value = 0.0
keep = ("body", "head")                # бельё не берём: у рефа свободные шорты, сравниваем само тело
hair = ("hair_cap", "hair_cards", "ear")  # второй проход — с причёской и ушами (силуэт копны)
for o in bpy.data.objects:
    if o.type == "MESH":
        o.hide_render = not o.name.startswith(keep)
dg = bpy.context.evaluated_depsgraph_get()
pts = []
for o in bpy.data.objects:
    if o.type == "MESH" and o.name.startswith(keep + hair):     # кадр — с запасом под копну и уши
        oe = o.evaluated_get(dg)
        me = oe.to_mesh()
        pts += [oe.matrix_world @ v.co for v in me.vertices]
        oe.to_mesh_clear()
floor = min(p.z for p in pts)
top = max(p.z for p in pts)
chin = next((o.matrix_world.translation.z for o in bpy.data.objects if o.name == "lm_chin"), None)
H = top - floor
res_y = 1400
ppm = res_y / (H * 1.04)
cam_d = bpy.data.cameras.new("cam")
cam_d.type = "ORTHO"
cam = bpy.data.objects.new("cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam
sc.render.resolution_y = res_y
sc.render.resolution_x = int(res_y * 0.75)
cam_d.ortho_scale = H * 1.04                 # по большей стороне кадра (высоте)
cz = (floor + top) / 2
for suffix, names in (("", keep), ("_hair", keep + hair)):
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.hide_render = not o.name.startswith(names)
    for view, loc, rot in (("front", (0, -5, cz), (1.5708, 0, 0)), ("side", (5, 0, cz), (1.5708, 0, 1.5708))):
        cam.location = loc
        cam.rotation_euler = rot
        sc.render.filepath = f"{out}_{view}{suffix}.png"
        bpy.ops.render.render(write_still=True)
json.dump({"floor_px": res_y / 2 + (cz - floor) * ppm, "chin_px": res_y / 2 + (cz - chin) * ppm if chin else None,
           "ppm": ppm}, open(out + ".json", "w"))
print("DONE")
