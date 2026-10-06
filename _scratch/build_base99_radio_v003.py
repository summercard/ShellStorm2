import bpy
import json
import math
import shutil
from pathlib import Path
from mathutils import Vector, Matrix

PROJECT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
SOURCE_DIR = PROJECT / "assets/art/props/base_world_3d/source/base99_radio"
COMP_DIR = PROJECT / "assets/art/props/base_world_3d/components/base99_radio"
OUT_DIR = PROJECT / "outputs/base99_radio_v003"
SOURCE_V002 = SOURCE_DIR / "prp_base99_radio_source_v002.blend"
SOURCE_V003 = SOURCE_DIR / "prp_base99_radio_source_v003.blend"
GLB_PATH = COMP_DIR / "prp_base99_radio_visual_top3d.glb"
PALETTE_PATH = PROJECT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
ASSET_ID = "PRP-BASE99-RADIO-3D"
VERSION = "v003"

ROLE_METAL = "01_精工金属_紫色骨架"
ROLE_MATTE = "02_细腻哑光_青绿大面"
ROLE_GLOSS = "03_清漆反光_紫粉点缀"
ROLE_EMIT = "04_柔和自发光_UI灯光"
ROLE_CELLS = {
    ROLE_METAL: (1, 2),
    ROLE_MATTE: (1, 4),
    ROLE_GLOSS: (2, 2),
    ROLE_EMIT: (5, 5),
}


def world_bounds(objects):
    points = []
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in objects:
        if obj.type != "MESH":
            continue
        ev = obj.evaluated_get(depsgraph)
        points.extend(ev.matrix_world @ Vector(corner) for corner in ev.bound_box)
    if not points:
        return Vector((0, 0, 0)), Vector((0, 0, 0))
    return (
        Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points))),
        Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points))),
    )


def apply_scale(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)


def scale_group_about_ground(objects, factor):
    mn, mx = world_bounds(objects)
    pivot = Vector(((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mn.z))
    transform = (
        Matrix.Translation(pivot)
        @ Matrix.Diagonal((factor, factor, factor, 1.0))
        @ Matrix.Translation(-pivot)
    )
    for obj in objects:
        local_transform = obj.matrix_world.inverted() @ transform @ obj.matrix_world
        obj.data.transform(local_transform)
    return pivot


def assign_palette_uv(obj):
    if obj.type != "MESH":
        return
    mesh = obj.data
    for layer in list(mesh.uv_layers):
        if layer.name != "PaletteUV":
            mesh.uv_layers.remove(layer)
    uv = mesh.uv_layers.get("PaletteUV") or mesh.uv_layers.new(name="PaletteUV")
    mesh.uv_layers.active = uv
    uv.active_render = True
    for poly in mesh.polygons:
        material = mesh.materials[poly.material_index] if poly.material_index < len(mesh.materials) else None
        role = str(material.get("material_role", material.name if material else ROLE_MATTE)) if material else ROLE_MATTE
        cell = ROLE_CELLS.get(role, ROLE_CELLS[ROLE_MATTE])
        center = Vector(((cell[0] + 0.5) / 10.0, (cell[1] + 0.5) / 10.0))
        radius = 0.018
        count = max(3, len(poly.loop_indices))
        for i, loop_index in enumerate(poly.loop_indices):
            angle = 2.0 * math.pi * i / count + 0.17
            uv.data[loop_index].uv = center + Vector((math.cos(angle) * radius, math.sin(angle) * radius))


def tune_material(material):
    material.use_nodes = True
    material["palette_path"] = str(PALETTE_PATH)
    role = str(material.get("material_role", material.name))
    if role not in ROLE_CELLS:
        return
    principled = next((node for node in material.node_tree.nodes if node.bl_idname == "ShaderNodeBsdfPrincipled"), None)
    if principled is None:
        return
    if role == ROLE_METAL:
        principled.inputs["Metallic"].default_value = 0.28
        principled.inputs["Roughness"].default_value = 0.82
        if "Coat Weight" in principled.inputs:
            principled.inputs["Coat Weight"].default_value = 0.03
    elif role == ROLE_MATTE:
        principled.inputs["Metallic"].default_value = 0.02
        principled.inputs["Roughness"].default_value = 0.88
        if "Coat Weight" in principled.inputs:
            principled.inputs["Coat Weight"].default_value = 0.0
    elif role == ROLE_GLOSS:
        principled.inputs["Metallic"].default_value = 0.16
        principled.inputs["Roughness"].default_value = 0.62
        if "Coat Weight" in principled.inputs:
            principled.inputs["Coat Weight"].default_value = 0.05
    else:
        principled.inputs["Roughness"].default_value = 0.46
        if "Emission Strength" in principled.inputs:
            principled.inputs["Emission Strength"].default_value = 0.8


def mesh_stats(obj):
    return {
        "faces": len(obj.data.polygons),
        "triangles": sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons),
        "vertices": len(obj.data.vertices),
        "scale": [round(v, 6) for v in obj.scale],
        "uv_layers": [uv.name for uv in obj.data.uv_layers],
    }


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    COMP_DIR.mkdir(parents=True, exist_ok=True)
    rollback = OUT_DIR / "rollback"
    rollback.mkdir(parents=True, exist_ok=True)
    if GLB_PATH.is_file():
        shutil.copy2(GLB_PATH, rollback / "prp_base99_radio_visual_top3d_v002.glb")

    bpy.ops.wm.open_mainfile(filepath=str(SOURCE_V002))
    root = bpy.data.objects.get("ItemRoot")
    visual = bpy.data.objects.get("Visual")
    status_out = next((o for o in bpy.data.objects if o.type == "MESH" and o.get("runtime_interface_name") == "StatusLight" and o.parent == root), None)
    source_coll = bpy.data.collections.get("01_制作组件_已统一材质")
    output_coll = bpy.data.collections.get("02_游戏输出_独立资产包_v002")
    if not all((root, visual, status_out, source_coll, output_coll)):
        raise RuntimeError("v002源缺少 ItemRoot / Visual / StatusLight / source/output 集合")

    source_meshes = [o for o in source_coll.objects if o.type == "MESH"]
    output_meshes = [visual, status_out]
    for obj in output_meshes:
        apply_scale(obj)
    scale_group_about_ground(source_meshes, 2.0)
    scale_group_about_ground(output_meshes, 2.0)

    for material in bpy.data.materials:
        tune_material(material)
    for obj in source_meshes + output_meshes:
        assign_palette_uv(obj)

    root["asset_version"] = VERSION
    root["dimensions_contract_m"] = "0.828W x 0.456D x 0.822H Blender; Godot 0.828W x 0.822H x 0.456D"
    root["scale_baked"] = True
    root["material_finish"] = "deep ink green / dark brown copper retro matte; StatusLight only emissive at runtime"
    output_coll.name = "02_游戏输出_独立资产包_v003"
    scene = bpy.context.scene
    scene["asset_version"] = VERSION
    scene["dimensions_contract_m"] = "0.828W x 0.456D x 0.822H Blender; low-poly retro radio"
    scene["scale_baked"] = True
    scene["palette_path"] = str(PALETTE_PATH)
    scene["glb_export_image_format"] = "NONE"

    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    visual.select_set(True)
    status_out.select_set(True)
    bpy.context.view_layer.objects.active = root
    original_name = status_out.name
    status_out.name = "StatusLight"
    try:
        bpy.ops.export_scene.gltf(
            filepath=str(GLB_PATH), export_format="GLB", use_selection=True,
            export_apply=True, export_image_format="NONE", export_materials="EXPORT",
            export_cameras=False, export_lights=False, export_animations=False,
        )
    finally:
        status_out.name = original_name

    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_V003))
    mn, mx = world_bounds(output_meshes)
    stats = {obj.name: mesh_stats(obj) for obj in output_meshes}
    total_faces = sum(item["faces"] for item in stats.values())
    total_tris = sum(item["triangles"] for item in stats.values())
    bounds = {
        "min": [round(v, 6) for v in mn],
        "max": [round(v, 6) for v in mx],
        "size": [round(mx[i] - mn[i], 6) for i in range(3)],
        "center": [round((mn[i] + mx[i]) * 0.5, 6) for i in range(3)],
    }
    manifest = {
        "asset_id": ASSET_ID,
        "asset_name_zh": "99F阁楼收音机",
        "slug": "base99_radio",
        "asset_type": "interactive_scene_prop",
        "version": VERSION,
        "source_blend": str(SOURCE_V003),
        "input_source_preserved": str(SOURCE_V002),
        "component_glb": str(GLB_PATH),
        "runtime_prefab_target": "assets/art/props/base_world_3d/runtime/base99_radio/prp_base99_radio_root_top3d.tscn",
        "root_node": "ItemRoot",
        "status_light_node_path": "ItemRoot/StatusLight",
        "front_direction_godot": "-Z",
        "base_plane": "Z=0 Blender / Y=0 Godot",
        "bounds_m_blender": bounds,
        "bounds_m_godot": {"size": [bounds["size"][0], bounds["size"][2], bounds["size"][1]]},
        "polygon_budget": {
            "limit_faces": 800,
            "faces_visual_plus_statuslight": total_faces,
            "triangles_visual_plus_statuslight": total_tris,
            "per_mesh": stats,
        },
        "output_meshes": ["Visual", "StatusLight"],
        "materials": [ROLE_METAL, ROLE_MATTE, ROLE_GLOSS, ROLE_EMIT],
        "palette": {
            "path": str(PALETTE_PATH),
            "external_only": True,
            "interpolation": "Closest",
            "uv_layer": "PaletteUV",
            "glb_export_image_format": "NONE",
            "body_cell": ROLE_CELLS[ROLE_MATTE],
            "metal_cell": ROLE_CELLS[ROLE_METAL],
        },
        "finish": "deep ink green body / dark brown copper accents / low reflectance; only StatusLight emits during A/B",
        "rollback": {"v002_glb": str(rollback / "prp_base99_radio_visual_top3d_v002.glb")},
        "scope": {"included": ["v003 Blender source", "stable GLB replacement", "manifest"], "excluded": ["Godot placement", "music logic changes"]},
    }
    (OUT_DIR / "asset_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
