import bpy
import json
import math
import shutil
from pathlib import Path
from mathutils import Vector
from mathutils import Matrix

PROJECT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
SOURCE_DIR = PROJECT / "assets/art/props/base_world_3d/source/base99_radio"
COMP_DIR = PROJECT / "assets/art/props/base_world_3d/components/base99_radio"
OUT_DIR = PROJECT / "outputs/base99_radio_v002"
ROLLBACK_DIR = PROJECT / "outputs/base99_radio_v001/rollback"
PALETTE_PATH = PROJECT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
SOURCE_BLEND = SOURCE_DIR / "prp_base99_radio_source_v002.blend"
GLB_PATH = COMP_DIR / "prp_base99_radio_visual_top3d.glb"
ASSET_ID = "PRP-BASE99-RADIO-3D"
VERSION = "v002"
ROLE_METAL = "01_精工金属_紫色骨架"
ROLE_MATTE = "02_细腻哑光_青绿大面"
ROLE_GLOSS = "03_清漆反光_紫粉点缀"
ROLE_EMIT = "04_柔和自发光_UI灯光"
PALETTE_CELLS = {ROLE_METAL: (2, 7), ROLE_MATTE: (1, 4), ROLE_GLOSS: (3, 7), ROLE_EMIT: (5, 4)}


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for c in list(bpy.data.collections):
        if c.name != "Collection":
            bpy.data.collections.remove(c)
    if bpy.data.collections.get("Collection"):
        bpy.data.collections.remove(bpy.data.collections["Collection"])


def collection(name, parent=None, hide_viewport=False, hide_render=False):
    c = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(c)
    c.hide_viewport = hide_viewport
    c.hide_render = hide_render
    return c


def canonical_material(name, roughness, metallic, coat, emission_strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = coat
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "PaletteUV"
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.interpolation = "Closest"
    tex.extension = "CLIP"
    tex.image = bpy.data.images.load(str(PALETTE_PATH), check_existing=True)
    nt.links.new(uv.outputs["UV"], tex.inputs["Vector"])
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if emission_strength:
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    mat["palette_path"] = str(PALETTE_PATH)
    mat["material_role"] = name
    return mat


def set_palette_uv(obj, cell):
    mesh = obj.data
    for layer in list(mesh.uv_layers):
        if layer.name != "PaletteUV":
            mesh.uv_layers.remove(layer)
    layer = mesh.uv_layers.get("PaletteUV") or mesh.uv_layers.new(name="PaletteUV")
    mesh.uv_layers.active = layer
    layer.active_render = True
    col, row = cell
    center = Vector(((col + 0.5) / 10.0, (row + 0.5) / 10.0))
    for poly in mesh.polygons:
        count = len(poly.loop_indices)
        radius = 0.022
        for i, loop_index in enumerate(poly.loop_indices):
            angle = 2.0 * math.pi * i / max(3, count) + 0.20
            layer.data[loop_index].uv = center + Vector((math.cos(angle) * radius, math.sin(angle) * radius))


def link_to(obj, target):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    target.objects.link(obj)


def finish_mesh(obj, role, bevel=0.0):
    if bevel:
        mod = obj.modifiers.new("低模边缘柔化", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.select_set(False)
    obj.data.materials.clear()
    obj.data.materials.append(MATS[role])
    for poly in obj.data.polygons:
        poly.material_index = 0
    set_palette_uv(obj, PALETTE_CELLS[role])
    obj["material_role"] = role
    return obj


def cube(name, loc, dims, role, bevel=0.0, coll=None):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    finish_mesh(obj, role, bevel)
    if coll:
        link_to(obj, coll)
    return obj


def cyl(name, loc, radius, depth, role, rotation=(0, 0, 0), vertices=8, coll=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    finish_mesh(obj, role)
    if coll:
        link_to(obj, coll)
    return obj


def cylinder_between(name, a, b, radius, role, coll=None, vertices=8):
    a, b = Vector(a), Vector(b)
    vec = b - a
    obj = cyl(name, (a + b) * 0.5, radius, vec.length, role, vertices=vertices, coll=coll)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(vec.normalized())
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    obj.select_set(False)
    set_palette_uv(obj, PALETTE_CELLS[role])
    return obj


def sphere(name, loc, scale, role, coll=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=4, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    finish_mesh(obj, role)
    if coll:
        link_to(obj, coll)
    return obj


def duplicate_object(src, target):
    obj = src.copy()
    obj.data = src.data.copy()
    target.objects.link(obj)
    return obj


def join_objects(objects, name, target):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    out = bpy.context.object
    out.name = name
    link_to(out, target)
    out.select_set(False)
    return out


def normalize_material_slots(obj, roles):
    old = list(obj.data.materials)
    indices = [poly.material_index for poly in obj.data.polygons]
    lookup = {role: index for index, role in enumerate(roles)}
    obj.data.materials.clear()
    for role in roles:
        obj.data.materials.append(MATS[role])
    for poly, old_index in zip(obj.data.polygons, indices):
        old_name = old[old_index].name if old_index < len(old) else roles[0]
        poly.material_index = lookup.get(old_name, 0)
    set_palette_uv(obj, PALETTE_CELLS[roles[0]])


def bounds(objects):
    points = []
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in objects:
        ev = obj.evaluated_get(depsgraph)
        points.extend(ev.matrix_world @ Vector(corner) for corner in ev.bound_box)
    mins = [min(p[i] for p in points) for i in range(3)]
    maxs = [max(p[i] for p in points) for i in range(3)]
    return mins, maxs


def center_and_ground(objects):
    mins, maxs = bounds(objects)
    delta = Vector((-0.5 * (mins[0] + maxs[0]), -0.5 * (mins[1] + maxs[1]), -mins[2]))
    for obj in objects:
        obj.location += delta


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def setup_preview(coll, root):
    world = bpy.context.scene.world
    world.color = (0.004, 0.006, 0.015)
    for loc, energy, size, color in [((0.55, -0.60, 0.72), 420, 0.55, (0.55, 0.85, 1.0)), ((-0.45, -0.20, 0.40), 280, 0.40, (1.0, 0.25, 0.75)), ((0.05, 0.35, 0.90), 320, 0.45, (0.20, 1.0, 0.85))]:
        data = bpy.data.lights.new("展示灯", "AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        data.color = color
        light = bpy.data.objects.new("展示灯", data)
        coll.objects.link(light)
        light.location = loc
        look_at(light, (0, 0, 0.20))
    cam_data = bpy.data.cameras.new("收音机近景相机")
    cam = bpy.data.objects.new("收音机近景相机", cam_data)
    coll.objects.link(cam)
    bpy.context.scene.camera = cam
    cam_data.lens = 58
    cam_data.sensor_width = 36
    root["preview_camera"] = cam.name
    return cam


def render_preview(cam, filename, location, target):
    cam.location = location
    look_at(cam, target)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.filepath = str(OUT_DIR / filename)
    bpy.ops.render.render(write_still=True)


def mesh_stats(obj):
    faces = len(obj.data.polygons)
    tris = sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)
    return {"faces": faces, "triangles": tris, "vertices": len(obj.data.vertices)}


def main():
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    COMP_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ROLLBACK_DIR.mkdir(parents=True, exist_ok=True)
    old_glb = ROLLBACK_DIR / "prp_base99_radio_visual_top3d_v001.glb"
    if GLB_PATH.is_file() and not old_glb.exists():
        shutil.copy2(GLB_PATH, old_glb)
    clear_scene()
    scene = bpy.context.scene
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.look = "AgX - Medium High Contrast"
    global MATS
    MATS = {
        ROLE_METAL: canonical_material(ROLE_METAL, 0.28, 0.86, 0.16),
        ROLE_MATTE: canonical_material(ROLE_MATTE, 0.68, 0.03, 0.0),
        ROLE_GLOSS: canonical_material(ROLE_GLOSS, 0.14, 0.18, 0.68),
        ROLE_EMIT: canonical_material(ROLE_EMIT, 0.34, 0.0, 0.0, 1.35),
    }
    root_coll = collection("99F床边收音机_中文资产管理")
    source_coll = collection("01_制作组件_已统一材质", root_coll, hide_viewport=True, hide_render=True)
    output_coll = collection("02_游戏输出_独立资产包_v002", root_coll)
    body_coll = collection("01_主体_非自发光", output_coll)
    light_coll = collection("02_状态灯_自发光", output_coll)
    display_coll = collection("90_展示环境_灯光相机", root_coll)
    parts = []
    parts.append(cube("主体外壳_青绿哑光", (0, 0, 0.135), (0.36, 0.20, 0.22), ROLE_MATTE, 0.012, source_coll))
    parts.append(cube("底座_深紫金属", (0, 0, 0.013), (0.34, 0.19, 0.026), ROLE_METAL, 0.006, source_coll))
    parts.extend([
        cube("正面护框_上", (0, -0.108, 0.236), (0.35, 0.016, 0.020), ROLE_METAL, 0.004, source_coll),
        cube("正面护框_下", (0, -0.108, 0.034), (0.35, 0.016, 0.020), ROLE_METAL, 0.004, source_coll),
        cube("正面护框_左", (-0.165, -0.108, 0.135), (0.020, 0.016, 0.184), ROLE_METAL, 0.004, source_coll),
        cube("正面护框_右", (0.165, -0.108, 0.135), (0.020, 0.016, 0.184), ROLE_METAL, 0.004, source_coll),
    ])
    parts.extend([
        cube("侧面装甲_左", (-0.188, 0, 0.138), (0.016, 0.17, 0.17), ROLE_GLOSS, 0.004, source_coll),
        cube("侧面装甲_右", (0.188, 0, 0.138), (0.016, 0.17, 0.17), ROLE_GLOSS, 0.004, source_coll),
        cube("调频玻璃窗_紫粉反光", (-0.080, -0.116, 0.193), (0.13, 0.010, 0.042), ROLE_GLOSS, 0.004, source_coll),
        cube("调频窗刻度_金属", (-0.080, -0.123, 0.193), (0.10, 0.005, 0.003), ROLE_METAL, 0.0, source_coll),
    ])
    for i in range(5):
        parts.append(cube(f"扬声器栅格_竖_{i+1:02d}", (0.020 + i * 0.025, -0.116, 0.132), (0.008, 0.008, 0.112), ROLE_METAL, 0.001, source_coll))
    for i in range(2):
        parts.append(cube(f"扬声器栅格_横_{i+1:02d}", (0.070, -0.121, 0.102 + i * 0.060), (0.125, 0.006, 0.007), ROLE_METAL, 0.001, source_coll))
    parts.extend([
        cyl("旋钮_调频", (0.128, -0.122, 0.190), 0.024, 0.020, ROLE_GLOSS, rotation=(math.pi / 2, 0, 0), coll=source_coll),
        cyl("旋钮_音量", (0.128, -0.122, 0.092), 0.020, 0.018, ROLE_METAL, rotation=(math.pi / 2, 0, 0), coll=source_coll),
        cube("旋钮指示线_调频", (0.128, -0.136, 0.199), (0.003, 0.003, 0.016), ROLE_MATTE, 0.0, source_coll),
        cube("旋钮指示线_音量", (0.128, -0.136, 0.100), (0.003, 0.003, 0.013), ROLE_MATTE, 0.0, source_coll),
    ])
    for x in (-0.150, 0.150):
        for z in (0.055, 0.215):
            parts.append(cyl("护框螺栓", (x, -0.118, z), 0.005, 0.008, ROLE_METAL, rotation=(math.pi / 2, 0, 0), coll=source_coll))
    parts.extend([
        cylinder_between("提手_左", (-0.115, 0, 0.238), (-0.105, 0, 0.305), 0.010, ROLE_METAL, source_coll),
        cylinder_between("提手_顶", (-0.105, 0, 0.305), (0.105, 0, 0.305), 0.010, ROLE_METAL, source_coll),
        cylinder_between("提手_右", (0.105, 0, 0.305), (0.115, 0, 0.238), 0.010, ROLE_METAL, source_coll),
        cylinder_between("伸缩天线", (0.130, 0.020, 0.238), (0.175, 0.020, 0.405), 0.005, ROLE_METAL, source_coll),
        sphere("天线端帽", (0.175, 0.020, 0.405), (0.008, 0.008, 0.008), ROLE_GLOSS, source_coll),
    ])
    status = sphere("StatusLight_UI灯光_柔和自发光_Source", (0.045, -0.126, 0.193), (0.008, 0.005, 0.008), ROLE_EMIT, source_coll)
    status["runtime_override_node"] = True
    status["runtime_interface_name"] = "StatusLight"
    status["default_state"] = "on"
    parts.append(status)
    center_and_ground([obj for obj in source_coll.objects if obj.type == "MESH"])
    body_src = [obj for obj in source_coll.objects if obj.type == "MESH" and obj != status]
    body_out = join_objects([duplicate_object(obj, body_coll) for obj in body_src], "Visual", body_coll)
    normalize_material_slots(body_out, [ROLE_METAL, ROLE_MATTE, ROLE_GLOSS])
    status_out = duplicate_object(status, light_coll)
    status_out.name = "StatusLight_UI灯光_柔和自发光"
    normalize_material_slots(status_out, [ROLE_EMIT])
    root = bpy.data.objects.new("ItemRoot", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.04
    output_coll.objects.link(root)
    body_out.parent = root
    status_out.parent = root
    current_min, current_max = bounds([body_out, status_out])
    current_size = [current_max[i] - current_min[i] for i in range(3)]
    target_size = (0.414, 0.228, 0.411)
    scale = Vector((target_size[i] / current_size[i] for i in range(3)))
    scale_matrix = Matrix.Diagonal((scale.x, scale.y, scale.z, 1.0))
    for obj in (body_out, status_out):
        obj.matrix_world = scale_matrix @ obj.matrix_world
    root["asset_id"] = ASSET_ID
    root["asset_version"] = VERSION
    root["front_direction_godot"] = "-Z"
    root["base_plane"] = "Z=0"
    root["runtime_prefab"] = "assets/art/props/base_world_3d/runtime/base99_radio/prp_base99_radio_root_top3d.tscn"
    root["status_light_node_path"] = "ItemRoot/StatusLight"
    cam = setup_preview(display_coll, root)
    render_preview(cam, "base99_radio_v002_closeup.png", (0.49, -0.68, 0.38), (0, 0, 0.20))
    render_preview(cam, "base99_radio_v002_threequarter.png", (0.58, -0.76, 0.32), (0, 0, 0.19))
    render_preview(cam, "base99_radio_v002_top.png", (0.34, -0.49, 0.70), (0, 0, 0.18))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (root, body_out, status_out):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    original_status_name = status_out.name
    status_out.name = "StatusLight"
    try:
        bpy.ops.export_scene.gltf(filepath=str(GLB_PATH), export_format="GLB", use_selection=True, export_apply=True, export_image_format="NONE", export_materials="EXPORT", export_cameras=False, export_lights=False, export_animations=False)
    finally:
        status_out.name = original_status_name
    scene["asset_id"] = ASSET_ID
    scene["asset_version"] = VERSION
    scene["asset_type"] = "interactive_scene_prop"
    scene["dimensions_contract_m"] = "0.414W x 0.228D x 0.411H; low-poly retro radio"
    scene["front_direction_godot"] = "-Z"
    scene["palette_path"] = str(PALETTE_PATH)
    scene["glb_export_image_format"] = "NONE"
    for material in list(bpy.data.materials):
        if material.name not in set(MATS):
            bpy.data.materials.remove(material)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_BLEND))
    output_meshes = [body_out, status_out]
    mins, maxs = bounds(output_meshes)
    stats = {obj.name: mesh_stats(obj) for obj in output_meshes}
    total_faces = sum(v["faces"] for v in stats.values())
    total_tris = sum(v["triangles"] for v in stats.values())
    bounds_data = {"min": [round(v, 6) for v in mins], "max": [round(v, 6) for v in maxs], "size": [round(maxs[i] - mins[i], 6) for i in range(3)], "center": [round((mins[i] + maxs[i]) * 0.5, 6) for i in range(3)]}
    manifest = {
        "asset_id": ASSET_ID, "asset_name_zh": "99F阁楼收音机", "slug": "base99_radio", "asset_type": "interactive_scene_prop", "version": VERSION,
        "source_blend": str(SOURCE_BLEND), "component_glb": str(GLB_PATH),
        "preview_png": [str(OUT_DIR / f"base99_radio_v002_{name}.png") for name in ("closeup", "threequarter", "top")],
        "runtime_prefab_target": "assets/art/props/base_world_3d/runtime/base99_radio/prp_base99_radio_root_top3d.tscn", "root_node": "ItemRoot", "status_light_node_path": "ItemRoot/StatusLight", "front_direction_godot": "-Z", "base_plane": "Z=0", "bounds_m": bounds_data,
        "polygon_budget": {"limit_faces": 800, "preferred_faces": 700, "faces_visual_plus_statuslight": total_faces, "triangles_visual_plus_statuslight": total_tris, "per_mesh": stats},
        "output_meshes": ["Visual", "StatusLight"], "source_component_count": len([obj for obj in source_coll.objects if obj.type == "MESH"]), "materials": [ROLE_METAL, ROLE_MATTE, ROLE_GLOSS, ROLE_EMIT],
        "palette": {"path": str(PALETTE_PATH), "external_only": True, "interpolation": "Closest", "uv_layer": "PaletteUV", "glb_export_image_format": "NONE"},
        "rollback": {"v001_source_preserved": True, "v001_component_backup": str(old_glb)},
        "scope": {"included": ["Blender可编辑源组件", "游戏整合模型", "GLB", "预览PNG", "JSON资产清单"], "excluded": ["玩法脚本", "Godot场景摆位", "音乐逻辑"]},
    }
    (OUT_DIR / "asset_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
