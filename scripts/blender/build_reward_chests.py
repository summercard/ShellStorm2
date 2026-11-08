import bpy
import hashlib
import json
import math
import shutil
from pathlib import Path
from mathutils import Vector

PROJECT = Path(__file__).resolve().parents[2]
VERSION = "v001"
PALETTE = PROJECT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
BASE_SOURCE = PROJECT / "art_source/items_weapons/props/reward_chests/source"
EXPORT_ROOT = BASE_SOURCE / "export" / VERSION
RUNTIME_ROOT = PROJECT / "assets/art/items_weapons/props/reward_chests"
COMPONENT_ROOT = RUNTIME_ROOT / "components"
RUNTIME_SCENE_ROOT = RUNTIME_ROOT / "runtime"
WORK_ROOT = PROJECT.parent / "ShellStorm2-work" / "reward_chests"

ROLE_NAMES = [
    "01_精工金属_紫色骨架",
    "02_细腻哑光_青绿大面",
    "03_清漆反光_紫粉点缀",
    "04_柔和自发光_UI灯光",
]
ROLE_PARAMS = [(0.86, 0.27, 0.18), (0.03, 0.70, 0.0), (0.16, 0.14, 0.68), (0.0, 0.36, 0.0)]
TARGET_COLORS = {
    "metal": (0.20, 0.04, 0.40),
    "matte_pink": (0.86, 0.18, 0.50),
    "matte_orange": (0.95, 0.32, 0.08),
    "clear_purple": (0.55, 0.08, 0.92),
    "emissive_orange": (1.0, 0.55, 0.08),
}

VARIANTS = {
    "normal": {
        "asset_id": "PRP-3D-REWARD-CHEST-NORMAL",
        "slug": "prp_reward_chest_normal",
        "display_name": "普通科技宝箱",
        "scale": 1.0,
        "source_name": "prp_reward_chest_normal_source_v001.blend",
        "optimized_name": "prp_reward_chest_normal_optimized_v001.blend",
        "glb_name": "prp_reward_chest_normal_visual_top3d.glb",
        "scene_name": "prp_reward_chest_normal_root_top3d.tscn",
    },
    "advanced": {
        "asset_id": "PRP-3D-REWARD-CHEST-ADVANCED",
        "slug": "prp_reward_chest_advanced",
        "display_name": "高级科技宝箱",
        "scale": 1.2,
        "source_name": "prp_reward_chest_advanced_source_v001.blend",
        "optimized_name": "prp_reward_chest_advanced_optimized_v001.blend",
        "glb_name": "prp_reward_chest_advanced_visual_top3d.glb",
        "scene_name": "prp_reward_chest_advanced_root_top3d.tscn",
    },
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tri_count(obj) -> int:
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons) if obj.type == "MESH" else 0


def mesh_triangles(objects) -> int:
    return sum(tri_count(obj) for obj in objects if obj.type == "MESH")


def cell_center(cell):
    return ((cell[0] + 0.5) / 10.0, (cell[1] + 0.5) / 10.0)


def choose_cells(_image):
    # 设施公共色盘是固定 10x10 格；坐标按图像从左上角开始，脚本后续会转换为
    # Blender UV 的底部原点。这里使用人眼验收过的明确格位，避免后台图像像素缓存
    # 在 Blender 5.2 中返回空切片导致所有材质退化到 (0,0)。
    return {
        "metal": (2, 3),
        "matte_pink": (4, 2),
        "matte_orange": (4, 7),
        "clear_purple": (3, 3),
        "emissive_orange": (5, 7),
    }


def material_role(name, palette, emission=False):
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    metallic, roughness, coat = ROLE_PARAMS[ROLE_NAMES.index(name)]
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = coat
    uv_node = nodes.new("ShaderNodeUVMap")
    uv_node.uv_map = "PaletteUV"
    image_node = nodes.new("ShaderNodeTexImage")
    image_node.image = palette
    image_node.interpolation = "Closest"
    links.new(uv_node.outputs["UV"], image_node.inputs["Vector"])
    links.new(image_node.outputs["Color"], bsdf.inputs["Base Color"])
    if emission:
        if "Emission Color" in bsdf.inputs:
            links.new(image_node.outputs["Color"], bsdf.inputs["Emission Color"])
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = 1.35
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


def set_palette_uv(obj, cell):
    mesh = obj.data
    for layer in list(mesh.uv_layers):
        mesh.uv_layers.remove(layer)
    uv = mesh.uv_layers.new(name="PaletteUV")
    uv.active = True
    uv.active_render = True
    cx, cy = cell_center(cell)
    half = 0.022
    for poly in mesh.polygons:
        count = len(poly.loop_indices)
        for local_index, loop_index in enumerate(poly.loop_indices):
            angle = math.tau * local_index / max(3, count)
            uv.data[loop_index].uv = (cx + math.cos(angle) * half, cy + math.sin(angle) * half)


def assign_role(obj, material, cell):
    obj.data.materials.clear()
    obj.data.materials.append(material)
    set_palette_uv(obj, cell)
    obj["palette_uv"] = "PaletteUV"
    obj["palette_cell"] = [cell[0], cell[1]]
    obj["material_role"] = material.name


def apply_bevel(obj, width=0.04, segments=2):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    modifier = obj.modifiers.new("圆角低模", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def add_cube(name, size, location, material, cell, parent, bevel=0.04):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        apply_bevel(obj, min(bevel, min(size) * 0.28), 2)
    assign_role(obj, material, cell)
    if isinstance(parent, bpy.types.Collection):
        for collection in list(obj.users_collection):
            collection.objects.unlink(obj)
        parent.objects.link(obj)
    else:
        obj.parent = parent
    return obj


def add_uv_sphere(name, radius, location, material, cell, parent):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius, location=location)
    obj = bpy.context.object
    obj.name = name
    assign_role(obj, material, cell)
    if isinstance(parent, bpy.types.Collection):
        for collection in list(obj.users_collection):
            collection.objects.unlink(obj)
        parent.objects.link(obj)
    else:
        obj.parent = parent
    return obj


def add_cylinder(name, radius, depth, location, rotation, material, cell, parent):
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    apply_bevel(obj, min(0.025, depth * 0.25), 2)
    assign_role(obj, material, cell)
    if isinstance(parent, bpy.types.Collection):
        for collection in list(obj.users_collection):
            collection.objects.unlink(obj)
        parent.objects.link(obj)
    else:
        obj.parent = parent
    return obj


def add_arch(name, location, radius, material, cell, parent):
    curve = bpy.data.curves.new(name + "_曲线", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = 0.065
    curve.bevel_resolution = 1
    spline = curve.splines.new("POLY")
    points = 13
    spline.points.add(points - 1)
    for index in range(points):
        angle = math.pi * (index / (points - 1))
        # A front-facing inverted-U arch in the X/Z plane.
        x = math.cos(angle) * radius
        z = math.sin(angle) * radius
        spline.points[index].co = (x, 0.0, z, 1.0)
    obj = bpy.data.objects.new(name, curve)
    parent.users_collection[0].objects.link(obj)
    obj.location = location
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj.select_set(False)
    assign_role(obj, material, cell)
    obj.parent = parent
    return obj


def add_question_mark(name, location, size, material, cell, parent):
    font_curve = bpy.data.curves.new(name + "_文字", "FONT")
    font_curve.body = "?"
    font_curve.align_x = "CENTER"
    font_curve.align_y = "CENTER"
    font_curve.size = size
    font_curve.extrude = 0.025
    font_curve.bevel_depth = 0.008
    obj = bpy.data.objects.new(name, font_curve)
    parent.users_collection[0].objects.link(obj)
    obj.location = location
    obj.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj.select_set(False)
    assign_role(obj, material, cell)
    obj.parent = parent
    return obj


def _insert_action_keys(obj, action_name, properties):
    action = bpy.data.actions.new(action_name)
    action.use_fake_user = True
    obj.animation_data_create()
    obj.animation_data.action = action
    scene = bpy.context.scene
    for data_path, index, points in properties:
        for frame, value in points:
            scene.frame_set(int(frame))
            current = getattr(obj, data_path.split('.')[0])
            if data_path == "location":
                current[index] = value
            elif data_path == "rotation_euler":
                current[index] = value
            elif data_path == "scale":
                current[index] = value
            obj.keyframe_insert(data_path=data_path, index=index, frame=frame)
    return action


def action_land(root):
    return _insert_action_keys(root, "land", [
        ("location", 2, [(1, 0.24), (6, 0.02), (12, 0.0)]),
        ("scale", 0, [(1, 0.84), (7, 1.05), (12, 1.0)]),
        ("scale", 1, [(1, 0.84), (7, 0.96), (12, 1.0)]),
        ("scale", 2, [(1, 0.84), (7, 1.05), (12, 1.0)]),
    ])


def action_open(root, lid):
    fps = 30.0
    def f(seconds):
        return 1.0 + seconds * fps
    root_action = _insert_action_keys(root, "open", [
        ("rotation_euler", 2, [(f(0.0), 0.0), (f(0.105), math.radians(3.8)), (f(0.21), math.radians(-3.8)), (f(0.315), math.radians(3.8)), (f(0.42), math.radians(-3.8)), (f(0.47), 0.0), (f(1.05), 0.0)]),
        ("scale", 0, [(f(0.0), 1.0), (f(0.47), 1.035), (f(0.59), 1.02), (f(0.83), 1.0), (f(1.05), 1.0)]),
        ("scale", 1, [(f(0.0), 1.0), (f(0.47), 0.94), (f(0.59), 0.975), (f(0.83), 1.0), (f(1.05), 1.0)]),
        ("scale", 2, [(f(0.0), 1.0), (f(0.47), 1.02), (f(0.59), 1.02), (f(0.83), 1.0), (f(1.05), 1.0)]),
        ("location", 2, [(f(0.0), 0.0), (f(0.59), 0.0), (f(0.665), 0.055), (f(0.83), 0.0), (f(1.05), 0.0)]),
    ])
    _insert_action_keys(lid, "open_lid", [
        ("rotation_euler", 0, [(f(0.0), 0.0), (f(0.47), math.radians(3.0)), (f(0.59), math.radians(3.0)), (f(0.73), math.radians(-126.0)), (f(0.97), math.radians(-104.0)), (f(1.05), math.radians(-104.0))]),
    ])
    return root_action


def duplicate_source_collection(output_collection, source_collection):
    for obj in list(output_collection.objects):
        source_obj = obj.copy()
        if obj.data is not None:
            source_obj.data = obj.data.copy()
        source_obj.animation_data_clear()
        source_collection.objects.link(source_obj)
        source_obj.name = "源_" + obj.name
        source_obj.hide_viewport = True
        source_obj.hide_render = True


def make_runtime_scene(info, dimensions, glb_relative):
    runtime = RUNTIME_SCENE_ROOT / info["scene_name"]
    text = """[gd_scene load_steps=3 format=3]\n\n[ext_resource type=\"Script\" path=\"res://src/world3d/RewardChestVisual3D.gd\" id=\"1_script\"]\n[ext_resource type=\"PackedScene\" path=\"res://%s\" id=\"2_glb\"]\n\n[node name=\"RewardChestVisual3D\" type=\"Node3D\"]\nscript = ExtResource(\"1_script\")\nmetadata/asset_id = \"%s\"\nmetadata/asset_version = \"%s\"\nmetadata/dimensions_m = Vector3(%s, %s, %s)\nmetadata/root_scale_contract = Vector3(1, 1, 1)\nmetadata/front_axis = \"+Z\"\nmetadata/model_kind = \"reward_chest_visual\"\n\n[node name=\"ImportedModel\" parent=\".\" instance=ExtResource(\"2_glb\")]\n""" % (glb_relative, info["asset_id"], VERSION, dimensions[0], dimensions[1], dimensions[2])
    runtime.parent.mkdir(parents=True, exist_ok=True)
    runtime.write_text(text, encoding="utf-8")
    return runtime


def build_variant(key, info, _palette, cells):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    palette = bpy.data.images.load(str(PALETTE), check_existing=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene["asset_id"] = info["asset_id"]
    scene["asset_version"] = VERSION
    scene["asset_category"] = "props/道具/可交互容器"
    scene["geometry_baked_scale"] = info["scale"]
    scene["reference_note"] = "依据已记录特征制作：Q版科技宝箱；原参考图无法取回，不宣称高还原。"
    root = bpy.data.collections.new(info["display_name"] + "_中文资产管理")
    scene.collection.children.link(root)
    source_col = bpy.data.collections.new("01_制作组件_源组件")
    source_col.hide_viewport = True
    source_col.hide_render = True
    root.children.link(source_col)
    output_col = bpy.data.collections.new("02_游戏输出_整合模型")
    root.children.link(output_col)
    preview_col = bpy.data.collections.new("90_展示与验收_灯光相机")
    root.children.link(preview_col)
    visual_root = bpy.data.objects.new("ChestVisual", None)
    output_col.objects.link(visual_root)
    visual_root.empty_display_type = "PLAIN_AXES"
    visual_root["asset_id"] = info["asset_id"]
    visual_root["visual_role"] = "游戏输出根"
    metal = material_role(ROLE_NAMES[0], palette)
    matte = material_role(ROLE_NAMES[1], palette)
    clear = material_role(ROLE_NAMES[2], palette)
    emissive = material_role(ROLE_NAMES[3], palette, emission=True)
    scale = info["scale"]
    width, depth, height = (1.45 * scale, 0.98 * scale, 1.12 * scale)
    body = add_cube("ChestBody_主体", (width, depth, height * 0.62), (0, 0, height * 0.31), matte, cells["matte_pink"], output_col, 0.09 * scale)
    body.parent = visual_root
    lower_band = add_cube("ChestLowerBand_橙色腰线", (width + 0.035 * scale, depth + 0.035 * scale, 0.08 * scale), (0, 0, height * 0.59), matte, cells["matte_orange"], output_col, 0.025 * scale)
    lower_band.parent = visual_root
    lid_pivot = bpy.data.objects.new("LidPivot", None)
    output_col.objects.link(lid_pivot)
    lid_pivot.parent = visual_root
    lid_pivot.location = (0, depth * 0.5, height * 0.62)
    lid = add_cube("ChestLid_可动盖", (width, depth, height * 0.30), (0, -depth * 0.5, height * 0.15), matte, cells["matte_pink"], output_col, 0.09 * scale)
    lid.parent = lid_pivot
    for side in (-1, 1):
        belt = add_cube("LidBand_%s_盖面护带" % ("L" if side < 0 else "R"), (0.095 * scale, depth + 0.035 * scale, height * 0.32), (side * (width * 0.34), -depth * 0.5, height * 0.15), metal, cells["metal"], output_col, 0.025 * scale)
        belt.parent = lid_pivot
    lock = add_cube("ChestLock_锁扣", (0.26 * scale, 0.14 * scale, 0.24 * scale), (0, -depth * 0.98, height * 0.10), metal, cells["metal"], output_col, 0.035 * scale)
    lock.parent = lid_pivot
    for side in (-1, 1):
        arch = add_arch("SideArch_%s_粗拱护框" % ("L" if side < 0 else "R"), (side * width * 0.36, -depth * 0.55, height * 0.53), 0.28 * scale, metal, cells["metal"], visual_root)
        gem = add_uv_sphere("SideGem_%s_紫色宝石" % ("L" if side < 0 else "R"), 0.105 * scale, (side * width * 0.51, -depth * 0.61, height * 0.56), clear, cells["clear_purple"], visual_root)
        gem.rotation_euler = (math.radians(18), 0, math.radians(12 * side))
    badge = add_cylinder("QuestionBadge_中央问号徽章", 0.29 * scale, 0.085 * scale, (0, -depth * 0.56, height * 0.53), (math.pi * 0.5, 0, 0), clear, cells["clear_purple"], visual_root)
    question = add_question_mark("QuestionMark_中央大问号", (0, -depth * 0.625, height * 0.53), 0.52 * scale, emissive, cells["emissive_orange"], visual_root)
    glow = add_cube("ChestGlow_开箱内能量", (width * 0.76, depth * 0.67, 0.045 * scale), (0, 0, height * 0.61), emissive, cells["emissive_orange"], output_col, 0.015 * scale)
    glow.parent = visual_root
    glow["emission_role"] = "开箱爆点"
    visual_root["dimensions_m"] = [width, depth + 0.2 * scale, height + 0.28 * scale]
    visual_root["front_axis"] = "+Z"
    visual_root["material_roles"] = ROLE_NAMES
    visual_root["clips"] = ["land", "open"]
    # Blender 5.2 的 glTF 导出器对当前 Action 最稳定；用无几何驱动节点承载
    # land，模型根承载 open，两个片段都会进入 Godot AnimationPlayer。
    land_driver = bpy.data.objects.new("LandAnimationDriver_落地动画驱动", None)
    output_col.objects.link(land_driver)
    action_land(land_driver)
    action_open(visual_root, lid_pivot)
    duplicate_source_collection(output_col, source_col)
    # Apply the final default pose after action authoring; playback sets the initial land/open poses.
    visual_root.location = (0, 0, 0)
    visual_root.scale = (1, 1, 1)
    lid_pivot.rotation_euler = (0, 0, 0)
    output_objects = [obj for obj in output_col.all_objects if obj.type in {"MESH", "EMPTY"}]
    triangles_before = mesh_triangles(output_objects)
    source_path = BASE_SOURCE / info["source_name"]
    optimized_path = EXPORT_ROOT / info["optimized_name"]
    source_path.parent.mkdir(parents=True, exist_ok=True)
    EXPORT_ROOT.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(source_path))
    source_hash_before = sha256(source_path)
    bpy.ops.wm.save_as_mainfile(filepath=str(optimized_path))
    # Reopen the persisted optimized file before exporting, as required by the import gate.
    bpy.ops.wm.open_mainfile(filepath=str(optimized_path), load_ui=False)
    output_objects_persisted = list(bpy.data.collections.get("02_游戏输出_整合模型").all_objects)
    export_objects = [obj for obj in output_objects_persisted if obj.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in output_objects_persisted:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = next(obj for obj in output_objects_persisted if obj.name == "ChestVisual")
    glb = COMPONENT_ROOT / info["glb_name"]
    glb.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(glb), export_format="GLB", use_selection=True, export_yup=True,
        export_apply=False, export_animations=True, export_animation_mode="ACTIONS",
        export_nla_strips=False, export_materials="EXPORT", export_image_format="NONE",
        export_lights=False, export_cameras=False, export_force_sampling=True,
    )
    source_hash_after = sha256(source_path)
    glb_hash = sha256(glb)
    dimensions = [round(width, 4), round(depth + 0.2 * scale, 4), round(height + 0.28 * scale, 4)]
    glb_triangles = mesh_triangles(export_objects)
    make_runtime_scene(info, dimensions, str(glb.relative_to(PROJECT)).replace("\\", "/"))
    return {
        "asset_id": info["asset_id"], "slug": info["slug"], "display_name": info["display_name"],
        "version": VERSION, "category": "props/道具/可交互容器", "source_blend": str(source_path.relative_to(PROJECT)),
        "source_sha256_before": source_hash_before, "source_sha256_after": source_hash_after,
        "source_hash_unchanged": source_hash_before == source_hash_after,
        "optimized_blend": str(optimized_path.relative_to(PROJECT)), "optimized_sha256": sha256(optimized_path),
        "glb": str(glb.relative_to(PROJECT)), "glb_sha256": glb_hash,
        "runtime_scene": str((RUNTIME_SCENE_ROOT / info["scene_name"]).relative_to(PROJECT)),
        "triangles_before": triangles_before, "triangles_after": glb_triangles,
        "reduction_ratio": 0.0 if triangles_before == 0 else (triangles_before - glb_triangles) / triangles_before,
        "dimensions_m": dimensions, "root_scale": [1, 1, 1], "geometry_baked_scale": info["scale"],
        "materials": ROLE_NAMES, "material_role_count": 4, "clips": {"land": 0.4, "open": 1.05},
        "open_burst_delay_seconds": 0.59, "front_axis": "+Z", "palette": str(PALETTE.relative_to(PROJECT)),
        "palette_external_only": True, "glb_export_image_format": "NONE",
        "optimization": {"operations": ["独立另存优化文件", "重开优化文件", "保留轮廓与PaletteUV", "三角化统计"], "removed_triangles": 0, "zero_change_reason": "Q版轮廓与动画结构已是低模，继续减面会损害拱框/问号/宝石轮廓"},
        "status": "exported_pending_godot_validation",
    }


def main():
    if not PALETTE.is_file():
        raise RuntimeError("公共设施色盘不存在: %s" % PALETTE)
    for path in (BASE_SOURCE, EXPORT_ROOT, COMPONENT_ROOT, RUNTIME_SCENE_ROOT, WORK_ROOT):
        path.mkdir(parents=True, exist_ok=True)
    palette = bpy.data.images.load(str(PALETTE), check_existing=True)
    cells = choose_cells(palette)
    records = []
    for key, info in VARIANTS.items():
        records.append(build_variant(key, info, palette, cells))
    manifest = {
        "asset_family": "reward_chests", "version": VERSION, "category": "props/道具/可交互容器",
        "reference_note": "原图无法取回；按已记录的Q版科技宝箱特征制作，不宣称与原图高还原。",
        "palette_cells": cells, "variants": records,
        "source_and_export_manifest": "本清单同时记录源/优化/GLB/运行路径、SHA、三角数、动画和状态。",
        "generated_by": "scripts/blender/build_reward_chests.py",
    }
    manifest_path = BASE_SOURCE.parent / "reward_chests_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    (RUNTIME_ROOT / "asset_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    (WORK_ROOT / "build_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print("REWARD_CHEST_BUILD_OK")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
