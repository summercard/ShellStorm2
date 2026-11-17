from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "scripts"))
import workspace_paths as wp

BLEND_PATH = SOURCE_DIR / "prp_extraction_safe_beacon_v001.blend"
MANIFEST_PATH = SOURCE_DIR / "asset_manifest.json"
PALETTE = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
GLB_PATH = ROOT / "assets/art/props/dungeon_3d/components/prp_extraction_safe_beacon/prp_extraction_safe_beacon_visual_top3d.glb"

ASSET_ID = "PRP-EXTRACTION-SAFE-BEACON-3D"
VERSION = "v001"

MAT_ROLES = {
    "01_精工金属_紫色骨架": (2, 3, (0.12, 0.035, 0.24, 1.0), 0.88, 0.27, 0.18),
    "02_细腻哑光_青绿大面": (1, 5, (0.015, 0.30, 0.25, 1.0), 0.02, 0.70, 0.0),
    "03_清漆反光_紫粉点缀": (6, 2, (0.58, 0.05, 0.38, 1.0), 0.16, 0.14, 0.68),
    "04_柔和自发光_UI灯光": (1, 9, (0.02, 0.85, 0.70, 1.0), 0.0, 0.36, 0.0),
}


def ensure_collection(name: str, parent=None):
    collection = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if parent is None:
        if collection.name not in bpy.context.scene.collection.children:
            bpy.context.scene.collection.children.link(collection)
    elif collection.name not in parent.children:
        parent.children.link(collection)
    return collection


def move_to_collection(obj, collection):
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)


def make_palette_material(name, cell, color, metallic, roughness, coat, emission=False):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = color
    mat.metallic = metallic
    mat.roughness = roughness
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = "PaletteUV"
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(PALETTE), check_existing=True)
    tex.interpolation = "Closest"
    tex.extension = "REPEAT"
    links.new(uv.outputs["UV"], tex.inputs["Vector"])
    links.new(tex.outputs["Color"], shader.inputs["Base Color"])
    if "Metallic" in shader.inputs:
        shader.inputs["Metallic"].default_value = metallic
    if "Roughness" in shader.inputs:
        shader.inputs["Roughness"].default_value = roughness
    if "Coat Weight" in shader.inputs:
        shader.inputs["Coat Weight"].default_value = coat
    elif "Clearcoat" in shader.inputs:
        shader.inputs["Clearcoat"].default_value = coat
    if emission:
        if "Emission Color" in shader.inputs:
            links.new(tex.outputs["Color"], shader.inputs["Emission Color"])
            shader.inputs["Emission Strength"].default_value = 1.35
        else:
            links.new(tex.outputs["Color"], shader.inputs["Emission"])
            shader.inputs["Emission Strength"].default_value = 1.35
    links.new(shader.outputs["BSDF"], out.inputs["Surface"])
    mat["palette_cell"] = [cell[0], cell[1]]
    mat["material_role"] = name
    mat["palette_source"] = "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
    mat["palette_interpolation"] = "Closest"
    return mat


def add_bevel(obj, width=0.03):
    modifier = obj.modifiers.new("边缘微倒角", "BEVEL")
    modifier.width = width
    modifier.segments = 2
    modifier.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def assign_material(obj, material):
    obj.data.materials.append(material)
    for poly in obj.data.polygons:
        poly.material_index = 0


def add_cube(name, location, dimensions, material, rotation=(0.0, 0.0, 0.0), bevel=0.025):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign_material(obj, material)
    if bevel:
        add_bevel(obj, bevel)
    return obj


def add_cylinder(name, location, radius, depth, material, vertices=32, bevel=0.018):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location)
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, material)
    if bevel:
        add_bevel(obj, bevel)
    return obj


def add_cone(name, location, radius1, radius2, depth, material, vertices=6):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius1, radius2=radius2, depth=depth, location=location)
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, material)
    add_bevel(obj, 0.015)
    return obj


def add_torus(name, location, major_radius, minor_radius, material):
    bpy.ops.mesh.primitive_torus_add(major_radius=major_radius, minor_radius=minor_radius, major_segments=32, minor_segments=8, location=location)
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, material)
    return obj


def duplicate_for_output(objects, collection):
    result = []
    for source in objects:
        copy = source.copy()
        copy.data = source.data.copy()
        collection.objects.link(copy)
        copy.hide_set(False)
        copy.hide_viewport = False
        copy.hide_render = False
        result.append(copy)
    return result


def join_objects(objects, name, collection):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = name
    move_to_collection(joined, collection)
    return joined


def make_palette_uv(obj):
    mesh = obj.data
    for layer in list(mesh.uv_layers):
        mesh.uv_layers.remove(layer)
    uv_layer = mesh.uv_layers.new(name="PaletteUV")
    uv_layer.active = True
    uv_layer.active_render = True
    for poly in mesh.polygons:
        material = mesh.materials[poly.material_index]
        cell = MAT_ROLES[material.name][0:2]
        u0 = cell[0] / 10.0
        v0 = cell[1] / 10.0
        center = Vector((u0 + 0.05, v0 + 0.05))
        radius = 0.028
        count = len(poly.loop_indices)
        for local_index, loop_index in enumerate(poly.loop_indices):
            angle = 2.0 * math.pi * local_index / max(3, count)
            uv_layer.data[loop_index].uv = center + Vector((math.cos(angle) * radius, math.sin(angle) * radius))
    mesh.update()


def join_by_material(objects, material_name):
    return [obj for obj in objects if obj.data.materials and obj.data.materials[0].name == material_name]


def triangulated_count(obj):
    mesh = obj.data
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def bounds(objects):
    points = []
    for obj in objects:
        points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    mn = [min(p[i] for p in points) for i in range(3)]
    mx = [max(p[i] for p in points) for i in range(3)]
    return mn, mx, [mx[i] - mn[i] for i in range(3)]


def create_preview_scene(output_root, body, glow):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    if scene.world is None:
        scene.world = bpy.data.worlds.new("QA_World")
    scene.world.color = (0.006, 0.010, 0.024)
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass
    for obj in [body, glow]:
        obj.hide_render = False
    bpy.ops.object.light_add(type="AREA", location=(3.8, -4.5, 5.2))
    key = bpy.context.object
    key.name = "QA_Key_Light"
    key.data.energy = 850
    key.data.shape = "DISK"
    key.data.size = 4.0
    key.rotation_euler = (math.radians(26), 0.0, math.radians(38))
    bpy.ops.object.light_add(type="AREA", location=(-3.5, 1.8, 3.0))
    fill = bpy.context.object
    fill.name = "QA_Fill_Light"
    fill.data.energy = 500
    fill.data.size = 3.0
    fill.rotation_euler = (math.radians(58), 0.0, math.radians(-112))
    bpy.ops.mesh.primitive_plane_add(size=8, location=(0.0, 0.0, -0.025))
    ground = bpy.context.object
    ground.name = "QA_Display_Ground"
    ground.data.materials.append(make_palette_material("QA_ground_material", (8, 1), (0.03, 0.04, 0.06, 1), 0.0, 0.92, 0.0))
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0.0, 0.0, 1.05))
    target = bpy.context.object
    target.name = "QA_Camera_Target"
    bpy.ops.object.camera_add(location=(3.8, -4.6, 2.8))
    camera = bpy.context.object
    camera.data.lens = 56
    camera.data.sensor_width = 36
    constraint = camera.constraints.new("TRACK_TO")
    constraint.target = target
    constraint.track_axis = "TRACK_NEGATIVE_Z"
    constraint.up_axis = "UP_Y"
    scene.camera = camera
    preview_dir = Path(output_root)
    preview_dir.mkdir(parents=True, exist_ok=True)
    views = {
        "close_3q": (3.8, -4.6, 2.8),
        "top_down": (0.1, -0.1, 5.0),
        "front": (0.0, -5.3, 1.35),
        "side": (5.3, 0.0, 1.35),
    }
    for name, location in views.items():
        camera.location = location
        bpy.context.view_layer.update()
        scene.render.filepath = str(preview_dir / f"{name}.png")
        bpy.ops.render.render(write_still=True)
    for obj in [key, fill, ground, target, camera]:
        bpy.data.objects.remove(obj, do_unlink=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if not PALETTE.is_file():
        raise RuntimeError(f"缺少公共色盘: {PALETTE}")
    source_collection = ensure_collection("01_制作组件_已统一材质")
    output_collection = ensure_collection("02_游戏输出_独立资产包")
    source_collection.hide_viewport = True
    source_collection.hide_render = True
    source_collection["asset_id"] = ASSET_ID
    source_collection["asset_version"] = VERSION
    output_collection["asset_id"] = ASSET_ID
    output_collection["asset_version"] = VERSION

    materials = {}
    for name, (column, row, color, metallic, roughness, coat) in MAT_ROLES.items():
        materials[name] = make_palette_material(name, (column, row), color, metallic, roughness, coat, name.startswith("04_"))

    metal = materials["01_精工金属_紫色骨架"]
    matte = materials["02_细腻哑光_青绿大面"]
    clear = materials["03_清漆反光_紫粉点缀"]
    glow = materials["04_柔和自发光_UI灯光"]

    body_parts = []
    emissive_parts = []
    def source_add(obj, is_emissive=False):
        move_to_collection(obj, source_collection)
        (emissive_parts if is_emissive else body_parts).append(obj)
        return obj

    source_add(add_cylinder("安全信标_三角底座", (0, 0, 0.10), 0.58, 0.20, metal, vertices=32, bevel=0.025))
    for index, angle in enumerate((0.0, 2.0 * math.pi / 3.0, 4.0 * math.pi / 3.0)):
        x, y = math.cos(angle) * 0.48, math.sin(angle) * 0.48
        source_add(add_cube(f"安全信标_三足支脚_{index+1}", (x, y, 0.18), (0.60, 0.19, 0.20), metal, rotation=(0.0, 0.0, angle), bevel=0.035))
        source_add(add_cylinder(f"安全信标_支脚灯_{index+1}", (math.cos(angle) * 0.63, math.sin(angle) * 0.63, 0.29), 0.045, 0.035, glow, vertices=12, bevel=0.0), True)
    source_add(add_cylinder("安全信标_通讯柱", (0, 0, 0.82), 0.17, 1.28, metal, vertices=24, bevel=0.018))
    source_add(add_cylinder("安全信标_青绿护套", (0, 0, 1.00), 0.205, 0.74, matte, vertices=24, bevel=0.018))
    source_add(add_cylinder("安全信标_上部枢纽", (0, 0, 1.42), 0.30, 0.18, metal, vertices=32, bevel=0.02))
    source_add(add_torus("安全信标_收拢环", (0, 0, 1.78), 0.43, 0.048, metal))
    source_add(add_cone("安全信标_上行箭头", (0, 0, 2.00), 0.145, 0.0, 0.27, clear, vertices=4))
    for side in (-1, 1):
        x = side * 0.36
        wing_rotation = (0.0, math.radians(side * 24.0), 0.0)
        source_add(add_cube(f"安全信标_开放双翼_{'左' if side < 0 else '右'}", (x, 0, 1.48), (0.16, 0.30, 0.72), matte, rotation=wing_rotation, bevel=0.035))
        source_add(add_cube(f"安全信标_双翼边灯_{'左' if side < 0 else '右'}", (side * 0.42, -0.16, 1.48), (0.045, 0.035, 0.48), glow, rotation=wing_rotation, bevel=0.006), True)
        source_add(add_cube(f"安全信标_双翼紫粉标识_{'左' if side < 0 else '右'}", (side * 0.39, 0.165, 1.48), (0.05, 0.035, 0.32), clear, rotation=wing_rotation, bevel=0.008))
    source_add(add_cube("安全信标_上行灯条", (0, -0.19, 1.93), (0.12, 0.035, 0.18), glow, bevel=0.008), True)
    source_add(add_torus("安全信标_环形灯带", (0, 0, 1.78), 0.365, 0.018, glow), True)

    output_body = duplicate_for_output(body_parts, output_collection)
    output_glow = duplicate_for_output(emissive_parts, output_collection)
    body = join_objects(output_body, "prp_extraction_safe_beacon_主体_金属哑光反光", output_collection)
    emission = join_objects(output_glow, "prp_extraction_safe_beacon_UI灯光_柔和自发光", output_collection)
    make_palette_uv(body)
    make_palette_uv(emission)

    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 0))
    root = bpy.context.object
    root.name = "ROOT_prp_extraction_safe_beacon_输出根"
    move_to_collection(root, output_collection)
    root["asset_id"] = ASSET_ID
    root["asset_version"] = VERSION
    root["asset_kind"] = "fixed_facility"
    root["pickup_allowed"] = False
    root["local_origin"] = "bottom_center"
    root["dimensions_m"] = [1.6, 1.6, 2.2]
    root["source_blend"] = "art_source/props/extraction_safe_beacon/prp_extraction_safe_beacon_v001.blend"
    root["palette_source"] = "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
    body.parent = root
    emission.parent = root
    output_collection.hide_viewport = False
    output_collection.hide_render = False
    body.hide_set(False)
    emission.hide_set(False)

    # 统一输出包络到设计契约，保持底面在 Z=0、XY 原点居中。
    bpy.context.view_layer.update()
    _, _, authored_size = bounds([body, emission])
    normalize_scale = (1.6 / authored_size[0], 1.6 / authored_size[1], 2.2 / authored_size[2])
    for mesh_object in (body, emission):
        mesh_object.scale = normalize_scale

    bpy.context.view_layer.update()
    mn, mx, size = bounds([body, emission])
    if max(abs(size[0] - 1.6), abs(size[1] - 1.6), abs(size[2] - 2.2)) > 0.18:
        raise RuntimeError(f"尺寸偏离目标过大: {size}")
    # 以求值后的并集包络校正底面中心，根节点本身保持局部原点不动。
    offset = Vector((-(mn[0] + mx[0]) * 0.5, -(mn[1] + mx[1]) * 0.5, -mn[2]))
    body.location += offset
    emission.location += offset
    bpy.context.view_layer.update()
    mn, mx, size = bounds([body, emission])
    if abs(mn[2]) > 1e-4 or abs((mn[0] + mx[0]) * 0.5) > 1e-4 or abs((mn[1] + mx[1]) * 0.5) > 1e-4:
        raise RuntimeError(f"输出根未满足底面/XY居中: {mn} {mx}")

    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    body.select_set(True)
    emission.select_set(True)
    bpy.context.view_layer.objects.active = root
    GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH), export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True, export_texcoords=True,
        export_normals=True, export_materials="EXPORT", export_image_format="NONE",
        export_extras=True, export_cameras=False, export_lights=False,
        export_animations=False,
    )
    tri = triangulated_count(body) + triangulated_count(emission)
    materials_used = sorted({mat.name for obj in (body, emission) for mat in obj.data.materials if mat})
    manifest = {
        "asset_id": ASSET_ID,
        "asset_version": VERSION,
        "name_zh": "安全撤离信标_三足开放双翼固定设施",
        "category": "场景道具",
        "package": {
            "source_blend": "art_source/props/extraction_safe_beacon/prp_extraction_safe_beacon_v001.blend",
            "authoring_script": "art_source/props/extraction_safe_beacon/author_extraction_safe_beacon_v001.py",
            "stable_glb": "assets/art/props/dungeon_3d/components/prp_extraction_safe_beacon/prp_extraction_safe_beacon_visual_top3d.glb",
            "runtime_wrapper": "assets/art/props/dungeon_3d/prp_extraction_safe_beacon_root_top3d.tscn",
        },
        "source": {
            "palette": "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png",
            "palette_uv": "PaletteUV",
            "palette_interpolation": "Closest",
            "embedded_palette": False,
            "editable_collection": "01_制作组件_已统一材质",
            "output_collection": "02_游戏输出_独立资产包",
        },
        "geometry": {
            "aabb_min": [round(v, 6) for v in mn],
            "aabb_max": [round(v, 6) for v in mx],
            "dimensions_m": [round(v, 6) for v in size],
            "triangles": tri,
            "output_meshes": [body.name, emission.name],
        },
        "materials": {
            "count": len(materials_used),
            "roles": materials_used,
            "emissive_mesh": emission.name,
            "body_mesh": body.name,
        },
        "fixed_facility": True,
        "pickup_allowed": False,
        "front_direction": "+Y",
        "notes": "低矮三足落地通讯柱，开放双翼、上行箭头与收拢环；非发光主体与发光独立。",
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    preview_dir = wp.work_path("sessions/2026-11-18_extraction_safe_beacon/previews")
    create_preview_scene(preview_dir, body, emission)
    print(json.dumps({"blend": str(BLEND_PATH), "glb": str(GLB_PATH), "manifest": str(MANIFEST_PATH), "triangles": tri, "aabb": size}, ensure_ascii=False))


if __name__ == "__main__":
    main()
