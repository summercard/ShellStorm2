# -*- coding: utf-8 -*-
"""构建「EXIT 霓虹灯标牌」制作源 v001（Blender 4.5 / Z-up / factory-startup）。

坐标契约
  正面（发光面） = Blender 本地 +Y  ->  Godot -Z
  底面 = z=0；X/Y 居中（底面中心原点）；单位 = 米
  角色：框=精工金属（正面 +Y 侧凸出）/ 背板=细腻哑光 / 字样=柔和自发光（红）
  颜色只由 PaletteUV 指向公共色盘单个色格决定，GLB 不内嵌贴图。

用法：
  blender --background --factory-startup --python build_exit_neon_sign.py -- <out.blend> <out.glb> [report.json]
"""

import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector, Matrix

PROJECT = r"I:/工作项目/shellstrom2/ShellStorm2"
PALETTE = os.path.join(
    PROJECT, "assets", "art", "shared", "palette", "设施低亮多巴胺色盘_10x10_512.png"
)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_BLEND = argv[0]
OUT_GLB = argv[1]
OUT_REPORT = argv[2] if len(argv) > 2 else None

# --------------------------------------------------------------------------
# 材质角色 / 色格（col = 从左第 n-1 列；row = 从上第 n-1 行）
# --------------------------------------------------------------------------
MAT_METAL = "01_精工金属_紫色骨架"
MAT_MATTE = "02_细腻哑光_青绿大面"
MAT_EMIT = "04_柔和自发光_UI灯光"

CELL_METAL = (9, 4)   # #4D5E72 深蓝灰（第 10 列冷调灰阶）
CELL_MATTE = (0, 0)   # #090813 近黑底板
CELL_EMIT = (4, 1)    # #650D20 红

ROLE = {
    MAT_METAL: dict(metallic=0.86, roughness=0.28, coat=0.20, emissive=False, strength=0.0),
    MAT_MATTE: dict(metallic=0.03, roughness=0.68, coat=0.0, emissive=False, strength=0.0),
    MAT_EMIT: dict(metallic=0.0, roughness=0.38, coat=0.0, emissive=True, strength=1.5),
}

# --------------------------------------------------------------------------
# 尺寸（米）
# --------------------------------------------------------------------------
HALF_W = 0.92            # 外框半宽 -> 总宽 1.84
FRAME_BAR = 0.06         # 边框条宽
BODY_Z0, BODY_Z1 = 0.0, 0.66
Y_BACK, Y_FRONT = -0.045, 0.030      # 边框厚度区间（总包络 -0.045..+0.045，Y 居中）
TEXT_TARGET_W = 1.20
TEXT_MIN_H, TEXT_MAX_H = 0.22, 0.40
TEXT_THICK = 0.05
TEXT_CTR_Z = 0.33
TEXT_CTR_Y = 0.020                   # 字厚区间 -0.005..+0.045，凸出边框 0.015
EAR_W, EAR_H, EAR_X = 0.08, 0.10, 0.50


def cell_uv(col, row):
    """色格中心 -> Blender UV（v 自图片底部起算）。"""
    return (col + 0.5) / 10.0, 1.0 - (row + 0.5) / 10.0


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0


def build_collections():
    root = bpy.data.collections.new("EXIT霓虹灯标牌_中文资产管理")
    bpy.context.scene.collection.children.link(root)
    edit = bpy.data.collections.new("01_制作组件_已统一材质")
    out = bpy.data.collections.new("02_游戏输出_整合模型")
    root.children.link(edit)
    root.children.link(out)
    return root, edit, out


def get_palette_image():
    name = os.path.basename(PALETTE)
    img = bpy.data.images.get(name)
    if img is None:
        img = bpy.data.images.load(PALETTE)
    img.filepath = PALETTE
    img.reload()
    return img


def make_material(name, img):
    cfg = ROLE[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (600, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (300, 0)
    uvmap = nt.nodes.new("ShaderNodeUVMap")
    uvmap.location = (-320, 120)
    uvmap.uv_map = "PaletteUV"
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.location = (-60, 120)
    tex.image = img
    tex.interpolation = "Closest"
    tex.extension = "CLIP"
    nt.links.new(uvmap.outputs["UV"], tex.inputs["Vector"])
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Metallic"].default_value = cfg["metallic"]
    bsdf.inputs["Roughness"].default_value = cfg["roughness"]
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = cfg["coat"]
    if cfg["emissive"]:
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = cfg["strength"]
    else:
        bsdf.inputs["Emission Strength"].default_value = 0.0
    return mat


def add_box(bm, center, size, mat_index):
    res = bmesh.ops.create_cube(bm, size=1.0)
    verts = res["verts"]
    m = Matrix.Translation(Vector(center)) @ Matrix.Diagonal(
        Vector((size[0], size[1], size[2], 1.0))
    )
    bmesh.ops.transform(bm, matrix=m, verts=verts)
    for f in {f for v in verts for f in v.link_faces}:
        f.material_index = mat_index


def span(x0, x1, y0, y1, z0, z1):
    return ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0)


def build_body():
    """背板（哑光, 槽0）+ 外框与吊耳（金属, 槽1）。"""
    me = bpy.data.meshes.new("EXIT霓虹灯_整合主体")
    bm = bmesh.new()
    c, s = span(-HALF_W + FRAME_BAR, HALF_W - FRAME_BAR, Y_BACK, -0.005,
                BODY_Z0 + FRAME_BAR, BODY_Z1 - FRAME_BAR)
    add_box(bm, c, s, 0)
    for box in (
        (-HALF_W, HALF_W, Y_BACK, Y_FRONT, BODY_Z0, BODY_Z0 + FRAME_BAR),
        (-HALF_W, HALF_W, Y_BACK, Y_FRONT, BODY_Z1 - FRAME_BAR, BODY_Z1),
        (-HALF_W, -HALF_W + FRAME_BAR, Y_BACK, Y_FRONT, BODY_Z0 + FRAME_BAR, BODY_Z1 - FRAME_BAR),
        (HALF_W - FRAME_BAR, HALF_W, Y_BACK, Y_FRONT, BODY_Z0 + FRAME_BAR, BODY_Z1 - FRAME_BAR),
    ):
        c, s = span(*box)
        add_box(bm, c, s, 1)
    for sx in (-EAR_X, EAR_X):
        c, s = span(sx - EAR_W / 2, sx + EAR_W / 2, Y_BACK + 0.02, Y_BACK + 0.035, BODY_Z1, BODY_Z1 + EAR_H)
        add_box(bm, c, s, 1)
    bm.to_mesh(me)
    bm.free()
    return me


def build_text_mesh():
    bpy.ops.object.text_add(location=(0.0, 0.0, 0.0))
    txt = bpy.context.object
    txt.data.body = "EXIT"
    txt.data.align_x = "CENTER"
    txt.data.align_y = "CENTER"
    txt.data.size = 1.0
    txt.data.extrude = 0.05
    txt.data.resolution_u = 5
    txt.data.name = "EXIT_字体"

    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(txt.evaluated_get(deps))
    me.name = "EXIT霓虹灯_UI灯光_柔和自发光"
    bpy.data.objects.remove(txt, do_unlink=True)
    for layer in list(me.uv_layers):
        me.uv_layers.remove(layer)

    vs = [v.co.copy() for v in me.vertices]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    size = mx - mn
    scale = TEXT_TARGET_W / size.x
    if size.y * scale > TEXT_MAX_H:
        scale = TEXT_MAX_H / size.y
    if size.y * scale < TEXT_MIN_H:
        scale = TEXT_MIN_H / size.y

    bm = bmesh.new()
    bm.from_mesh(me)
    ctr = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, (mn.z + mx.z) / 2))
    thick_now = max(size.z * scale, 1e-9)
    for v in bm.verts:
        p = (v.co - ctr) * scale
        p.z = p.z / thick_now * TEXT_THICK
        v.co = p
    # 立起姿态（必须是 det=+1 的旋转，否则字会镜像）：
    #   正面 +Z → +Y（发光面朝外，符合契约「正面 = Blender +Y」）
    #   字上 +Y → +Z（字正立）
    #   字右 +X → -X（面向 -Z 侧观察者时，右手边就是 -X）
    # 该旋转 = 绕轴 (0,1,1) 转 180°，R = 2nnᵀ - I = [[-1,0,0],[0,0,1],[0,1,0]]。
    # ⚠️ 曾误用 Rx(+90°)：正面会落到 -Y，导出后在 Godot 里正面朝 +Z，
    #    平铺时玩家从上方看到的是背面的镜像字（真实渲染截图实测为「TIX3」）。
    rot = Matrix.Rotation(math.radians(180.0), 4, Vector((0.0, 1.0, 1.0)))
    for v in bm.verts:
        p = rot @ v.co
        p.y += TEXT_CTR_Y
        p.z += TEXT_CTR_Z
        v.co = p
    bm.to_mesh(me)
    bm.free()
    return me


def apply_palette_uv(me, cell_by_slot, uv_name="PaletteUV"):
    """每个面一个带面积的小 UV 岛，完整落在所属材质槽的单一色格安全内区。"""
    for layer in list(me.uv_layers):
        if layer.name != uv_name:
            me.uv_layers.remove(layer)
    layer = me.uv_layers.get(uv_name) or me.uv_layers.new(name=uv_name)
    r = 0.008
    corners = ((-1, -1), (1, -1), (1, 1), (-1, 1))
    for poly in me.polygons:
        col, row = cell_by_slot.get(poly.material_index, (0, 0))
        cu, cv = cell_uv(col, row)
        for k, li in enumerate(poly.loop_indices):
            du, dv = corners[k % 4]
            layer.data[li].uv = (cu + du * r, cv + dv * r)
    for other in me.uv_layers:
        other.active_render = False
    me.uv_layers.active = layer
    layer.active_render = True


def main():
    reset_scene()
    root, edit_coll, out_coll = build_collections()
    img = get_palette_image()

    mat_matte = make_material(MAT_MATTE, img)
    mat_metal = make_material(MAT_METAL, img)
    mat_emit = make_material(MAT_EMIT, img)

    body_me = build_body()
    body_me.materials.append(mat_matte)   # 槽 0
    body_me.materials.append(mat_metal)   # 槽 1
    body = bpy.data.objects.new("EXIT霓虹灯_整合主体", body_me)

    text_me = build_text_mesh()
    text_me.materials.append(mat_emit)    # 槽 0
    text = bpy.data.objects.new("EXIT霓虹灯_UI灯光_柔和自发光", text_me)

    apply_palette_uv(body_me, {0: CELL_MATTE, 1: CELL_METAL})
    apply_palette_uv(text_me, {0: CELL_EMIT})

    for obj in (body, text):
        out_coll.objects.link(obj)

    for obj in (body, text):
        dup = obj.copy()
        dup.data = obj.data.copy()
        dup.name = obj.name + "_制作组件"
        edit_coll.objects.link(dup)
        dup.hide_set(True)
        dup.hide_viewport = True

    for obj in out_coll.objects:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False

    pts = []
    for obj in out_coll.objects:
        pts += [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    mn = [round(min(p[i] for p in pts), 4) for i in range(3)]
    mx = [round(max(p[i] for p in pts), 4) for i in range(3)]
    assert abs(mn[2]) < 1e-4, f"底面未归零 z={mn[2]}"
    assert abs(mn[0] + mx[0]) < 1e-4, f"X 未居中 {mn} {mx}"
    assert abs(mn[1] + mx[1]) < 1e-4, f"Y 未居中 {mn} {mx}"

    os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in out_coll.objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = body
    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_extras=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )

    report = {
        "bounds_blender_m": [mn, mx],
        "size_blender_m": [round(mx[i] - mn[i], 4) for i in range(3)],
        "objects": [o.name for o in out_coll.objects],
        "materials": [m.name for m in (mat_matte, mat_metal, mat_emit)],
        "text_verts": len(text_me.vertices),
        "text_polys": len(text_me.polygons),
        "body_verts": len(body_me.vertices),
        "body_polys": len(body_me.polygons),
    }
    if OUT_REPORT:
        with open(OUT_REPORT, "w", encoding="utf-8") as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
    print("EXIT_NEON_SIGN_BUILD_OK " + json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
