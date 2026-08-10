"""Normalize the approved Blender library and export independent Godot GLBs.

Run with Blender 4.5+ in background mode.  Facility assets are ground-centred and
face Godot local -Z.  Weapon assets use their grip as local origin and their
muzzle points down Godot local -Z.
"""

from __future__ import annotations

import math
import json
import struct
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


PROJECT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
LIBRARY = Path(r"C:\Users\zhuangmenghong\Documents\图片制作\新建文件夹\中文游戏资产成品\风格统一重制V3")

PROP_ROOT = PROJECT / "assets/art/props/base_world_3d"
WEAPON_ROOT = PROJECT / "assets/art/weapons/weapon_3d"

MATERIAL_NAMES = (
    "mat_metal_brushed_purple",
    "mat_matte_teal",
    "mat_clearcoat_magenta",
    "mat_emissive_soft",
)

# User-approved in-game presentation multipliers.  Keep the authored baseline
# sizes below intact so future revisions can clearly distinguish art scale from
# the final gameplay presentation scale.
FACILITY_SCALE_MULTIPLIER = 1.60
WEAPON_SCALE_MULTIPLIER = 1.30

FACILITIES = (
    {
        "source": "01_赛博储物站_风格统一源文件.blend",
        "slug": "locker_station",
        "cn": "赛博储物站",
        "target_height": 2.20,
    },
    {
        "source": "02_赛博维修工作台_风格统一源文件.blend",
        "slug": "weapon_workshop",
        "cn": "赛博维修工作台",
        "target_height": 2.05,
    },
    {
        "source": "03_复古游戏电视站_风格统一源文件.blend",
        "slug": "retro_tv_station",
        "cn": "复古游戏电视站",
        "target_height": 2.15,
    },
    {
        "source": "04_战术指挥桌_风格统一源文件.blend",
        "slug": "mission_operations",
        "cn": "战术情报指挥桌",
        "target_height": 2.15,
    },
    {
        "source": "05_科幻自动贩卖机_风格统一源文件.blend",
        "slug": "vending_machine",
        "cn": "科幻自动贩卖机",
        "target_height": 2.25,
    },
)

# Integrated V3 meshes are centre-grounded.  Grip values below are expressed in
# the pre-integration authoring coordinates; min_z converts them to V3 mesh space.
# target_length is the complete in-game length in metres.
WEAPONS = (
    (1, "water_tank_blaster", "水箱爆能枪", (0.65, 0.0, -0.72), -1.45, 1.40),
    (2, "megaphone_cannon", "扩音器加农炮", (-0.05, 0.0, -0.86), -0.825, 1.25),
    (3, "guitar_blaster", "吉他爆能枪", (0.35, 0.0, -0.82), -0.90, 1.35),
    (4, "spatula_rifle", "锅铲步枪", (0.45, 0.0, -0.84), -1.275, 1.35),
    (5, "frying_pan_cannon", "平底锅加农炮", (0.78, 0.0, -0.82), -0.775, 1.25),
    (6, "toaster_launcher", "烤面包机发射器", (0.55, 0.0, -0.72), -0.85, 1.35),
    (7, "scope_cannon", "瞄准镜加农炮", (0.25, 0.0, -0.88), -1.85, 1.45),
    (8, "popcorn_blaster", "爆米花爆能枪", (-0.25, 0.0, -1.00), -0.875, 1.15),
    (9, "gumball_cannon", "口香糖机加农炮", (0.25, 0.0, -0.75), -0.95, 1.35),
    (10, "double_barrel_cannon", "双管炮", (0.65, 0.0, -0.85), -1.05, 1.35),
    (11, "soda_straw_blaster", "饮料管爆能枪", (0.35, 0.0, -0.90), -1.275, 1.35),
    (12, "crocodile_cannon", "鳄鱼加农炮", (0.60, 0.0, -0.85), -0.625, 1.35),
    (13, "candy_sniper", "糖果狙击枪", (0.55, 0.0, -0.72), -1.65, 1.55),
    (14, "camera_blaster", "相机爆能枪", (0.20, 0.0, -0.78), -0.75, 0.95),
    (15, "tissue_box_cannon", "纸巾盒加农炮", (0.55, 0.0, -0.60), -0.725, 1.25),
    (16, "broom_rifle", "扫帚步枪", (0.75, 0.0, -0.70), -1.425, 1.35),
    (17, "fan_blaster", "风扇爆能枪", (0.55, 0.0, -0.70), -0.625, 1.15),
    (18, "hair_dryer", "吹风机", (0.20, 0.0, -0.85), -1.25, 0.95),
)

MANIFEST = {"facilities": {}, "weapons": {}}


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def mesh_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    points = [Vector(corner) for corner in obj.bound_box]
    return (
        Vector(tuple(min(point[i] for point in points) for i in range(3))),
        Vector(tuple(max(point[i] for point in points) for i in range(3))),
    )


def godot_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    points = [Vector((vertex.co.x, vertex.co.z, -vertex.co.y)) for vertex in obj.data.vertices]
    return (
        Vector(tuple(min(point[i] for point in points) for i in range(3))),
        Vector(tuple(max(point[i] for point in points) for i in range(3))),
    )


def normalize_palette_uv(obj: bpy.types.Object) -> None:
    palette = obj.data.uv_layers.get("PaletteUV")
    if palette is None:
        palette = next((layer for layer in obj.data.uv_layers if layer.name.startswith("PaletteUV")), None)
    if palette is None:
        raise RuntimeError(f"{obj.name} has no PaletteUV layer")
    for layer in list(obj.data.uv_layers):
        if layer != palette:
            obj.data.uv_layers.remove(layer)
    palette.name = "UVMap"
    obj.data.uv_layers.active = palette
    palette.active_render = True


def configure_materials(obj: bpy.types.Object, force_emissive: bool = False) -> None:
    normalize_palette_uv(obj)
    for index, slot in enumerate(obj.material_slots):
        if slot.material is None:
            continue
        material = slot.material.copy()
        role = 3 if force_emissive else min(index, 2)
        material.name = MATERIAL_NAMES[role]
        material.use_nodes = True
        bsdf = next((n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is not None:
            for node in material.node_tree.nodes:
                if node.type == "UVMAP":
                    node.uv_map = "UVMap"
                elif node.type == "TEX_IMAGE":
                    node.interpolation = "Closest"
                    node.extension = "EXTEND"
            if role == 0:
                bsdf.inputs["Metallic"].default_value = 0.86
                bsdf.inputs["Roughness"].default_value = 0.28
            elif role == 1:
                bsdf.inputs["Metallic"].default_value = 0.03
                bsdf.inputs["Roughness"].default_value = 0.72
            elif role == 2:
                bsdf.inputs["Metallic"].default_value = 0.18
                bsdf.inputs["Roughness"].default_value = 0.16
                if "Coat Weight" in bsdf.inputs:
                    bsdf.inputs["Coat Weight"].default_value = 0.68
            else:
                bsdf.inputs["Metallic"].default_value = 0.0
                bsdf.inputs["Roughness"].default_value = 0.38
                if "Emission Strength" in bsdf.inputs:
                    bsdf.inputs["Emission Strength"].default_value = 0.55
        obj.data.materials[index] = material


def reset_to(objects: list[bpy.types.Object]) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    keep = set(objects)
    for obj in list(bpy.data.objects):
        if obj not in keep:
            bpy.data.objects.remove(obj, do_unlink=True)
    for collection in list(bpy.data.collections):
        if collection != bpy.context.scene.collection and not collection.objects:
            bpy.data.collections.remove(collection)
    for obj in objects:
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj


def export_glb(path: Path, objects: list[bpy.types.Object]) -> None:
    ensure_dir(path.parent)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
    )
    tune_glb_materials(path)


def tune_glb_materials(path: Path) -> None:
    """Apply stable Godot-facing color energy without changing PaletteUV colors."""
    data = path.read_bytes()
    magic, version, _total = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2:
        raise RuntimeError(f"Invalid GLB: {path}")
    json_length, json_type = struct.unpack_from("<II", data, 12)
    document = json.loads(data[20:20 + json_length].decode("utf-8"))
    bin_offset = 20 + json_length
    bin_length, bin_type = struct.unpack_from("<II", data, bin_offset)
    binary = data[bin_offset + 8:bin_offset + 8 + bin_length]
    color_factors = {
        MATERIAL_NAMES[0]: [0.84, 0.84, 0.84, 1.0],
        MATERIAL_NAMES[1]: [0.90, 0.90, 0.90, 1.0],
        MATERIAL_NAMES[2]: [1.0, 1.0, 1.0, 1.0],
        MATERIAL_NAMES[3]: [0.68, 0.68, 0.68, 1.0],
    }
    for material in document.get("materials", []):
        name = material.get("name", "")
        role_name = next((role for role in MATERIAL_NAMES if name.startswith(role)), name)
        pbr = material.setdefault("pbrMetallicRoughness", {})
        pbr["baseColorFactor"] = color_factors.get(role_name, [0.55, 0.55, 0.55, 1.0])
        if role_name == MATERIAL_NAMES[3]:
            pbr["metallicFactor"] = 0.0
            pbr["roughnessFactor"] = 0.38
            material["name"] = MATERIAL_NAMES[3]
            material["emissiveFactor"] = [1.0, 1.0, 1.0]
            extensions = material.setdefault("extensions", {})
            extensions.pop("KHR_materials_clearcoat", None)
            extensions.setdefault("KHR_materials_emissive_strength", {})["emissiveStrength"] = 0.9
    encoded = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    encoded += b" " * ((4 - len(encoded) % 4) % 4)
    binary += b"\x00" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(encoded) + 8 + len(binary)
    output = bytearray(struct.pack("<4sII", b"glTF", 2, total))
    output.extend(struct.pack("<II", len(encoded), json_type))
    output.extend(encoded)
    output.extend(struct.pack("<II", len(binary), bin_type))
    output.extend(binary)
    path.write_bytes(output)


def duplicate_mesh(source: bpy.types.Object, name: str, force_emissive: bool = False) -> bpy.types.Object:
    obj = source.copy()
    obj.data = source.data.copy()
    obj.name = name
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = None
    obj.matrix_world = Matrix.Identity(4)
    configure_materials(obj, force_emissive)
    return obj


def export_facilities() -> None:
    for data in FACILITIES:
        bpy.ops.wm.open_mainfile(filepath=str(LIBRARY / data["source"]))
        output = bpy.data.collections.get("02_游戏输出_整合模型")
        if output is None:
            raise RuntimeError(f"Missing output collection in {data['source']}")
        sources = [obj for obj in output.objects if obj.type == "MESH"]
        if not sources:
            raise RuntimeError(f"No output meshes in {data['source']}")
        height = max(obj.dimensions.z for obj in sources)
        final_height = data["target_height"] * FACILITY_SCALE_MULTIPLIER
        scale = final_height / height
        transform = Matrix.Scale(scale, 4) @ Matrix.Rotation(math.pi, 4, "Z")
        copies = []
        for source in sources:
            is_emissive = "自发光" in source.name or "UI灯光" in source.name
            copy = duplicate_mesh(source, "Emissive" if is_emissive else "Body", is_emissive)
            copy.data.transform(transform)
            copies.append(copy)
        reset_to(copies)
        asset_dir = PROP_ROOT / "source" / data["slug"]
        component_dir = PROP_ROOT / "components" / data["slug"]
        ensure_dir(asset_dir)
        source_path = asset_dir / f"prp_base_{data['slug']}_source_v001.blend"
        glb_path = component_dir / f"prp_base_{data['slug']}_visual_top3d_v001.glb"
        bpy.context.scene["asset_name_cn"] = data["cn"]
        bpy.context.scene["asset_forward_axis"] = "Godot local -Z"
        bpy.context.scene["asset_target_height_m"] = final_height
        bpy.ops.wm.save_as_mainfile(filepath=str(source_path), compress=True)
        export_glb(glb_path, copies)
        mins, maxs = zip(*(godot_bounds(obj) for obj in copies))
        bound_min = [min(value[i] for value in mins) for i in range(3)]
        bound_max = [max(value[i] for value in maxs) for i in range(3)]
        MANIFEST["facilities"][data["slug"]] = {
            "name_cn": data["cn"],
            "glb": glb_path.relative_to(PROJECT).as_posix(),
            "source": source_path.relative_to(PROJECT).as_posix(),
            "bounds_min": bound_min,
            "bounds_max": bound_max,
            "presentation_scale_multiplier": FACILITY_SCALE_MULTIPLIER,
        }
        print(f"EXPORTED FACILITY {data['slug']} -> {glb_path}")


def export_weapons() -> None:
    library_path = LIBRARY / "06_卡通枪械库_风格统一源文件.blend"
    for number, slug, cn, grip_raw, min_z, target_length in WEAPONS:
        bpy.ops.wm.open_mainfile(filepath=str(library_path))
        collection = next(
            (c for c in bpy.data.collections if c.name.startswith(f"{number:02d}_") and c.name.endswith("_游戏整合")),
            None,
        )
        if collection is None:
            raise RuntimeError(f"Missing integrated collection for weapon {number:02d}")
        source = next((obj for obj in collection.objects if obj.type == "MESH"), None)
        if source is None:
            raise RuntimeError(f"Missing integrated mesh for weapon {number:02d}")
        local_min, local_max = mesh_bounds(source)
        width = local_max.x - local_min.x
        final_length = target_length * WEAPON_SCALE_MULTIPLIER
        scale = final_length / width
        grip = Vector((grip_raw[0], grip_raw[1], grip_raw[2] - min_z))
        transform = (
            Matrix.Scale(scale, 4)
            @ Matrix.Rotation(-math.pi * 0.5, 4, "Z")
            @ Matrix.Translation(-grip)
        )
        copy = duplicate_mesh(source, "Body")
        copy.data.transform(transform)
        reset_to([copy])
        asset_dir = WEAPON_ROOT / "source" / slug
        component_dir = WEAPON_ROOT / "components" / slug
        ensure_dir(asset_dir)
        source_path = asset_dir / f"wpn_{slug}_source_v001.blend"
        glb_path = component_dir / f"wpn_{slug}_visual_top3d_v001.glb"
        bpy.context.scene["asset_name_cn"] = cn
        bpy.context.scene["asset_grip_origin"] = "0,0,0"
        bpy.context.scene["asset_forward_axis"] = "Godot local -Z"
        bpy.context.scene["asset_target_length_m"] = final_length
        bpy.ops.wm.save_as_mainfile(filepath=str(source_path), compress=True)
        export_glb(glb_path, [copy])
        bound_min, bound_max = godot_bounds(copy)
        muzzle_z = bound_min.z
        rear_z = bound_max.z
        top_y = bound_max.y
        MANIFEST["weapons"][slug] = {
            "name_cn": cn,
            "glb": glb_path.relative_to(PROJECT).as_posix(),
            "source": source_path.relative_to(PROJECT).as_posix(),
            "bounds_min": list(bound_min),
            "bounds_max": list(bound_max),
            "presentation_scale_multiplier": WEAPON_SCALE_MULTIPLIER,
            "sockets": {
                "grip": [0.0, 0.0, 0.0],
                "support_hand": [0.0, max(0.02, top_y * 0.18), muzzle_z * 0.52],
                "muzzle": [0.0, max(0.0, top_y * 0.40), muzzle_z],
                "muzzle_attachment": [0.0, max(0.0, top_y * 0.40), muzzle_z],
                "scope": [0.0, top_y, muzzle_z * 0.38],
                "magazine": [0.0, bound_min.y * 0.72, muzzle_z * 0.28],
                "stock": [0.0, max(0.0, top_y * 0.20), rear_z],
                "tactical": [bound_max.x, max(0.0, top_y * 0.25), muzzle_z * 0.48],
                "mutator": [bound_min.x, max(0.0, top_y * 0.25), muzzle_z * 0.34],
            },
        }
        print(f"EXPORTED WEAPON {slug} -> {glb_path}")


if __name__ == "__main__":
    import sys

    facilities_only = "--facilities-only" in sys.argv
    manifest_path = PROJECT / "assets/art/asset_import_manifest_v001.json"
    previous = {}
    if facilities_only and manifest_path.exists():
        previous = json.loads(manifest_path.read_text(encoding="utf-8"))
    export_facilities()
    if facilities_only:
        MANIFEST["weapons"] = previous.get("weapons", {})
    else:
        export_weapons()
    manifest_path.write_text(json.dumps(MANIFEST, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"WROTE MANIFEST {manifest_path}")
