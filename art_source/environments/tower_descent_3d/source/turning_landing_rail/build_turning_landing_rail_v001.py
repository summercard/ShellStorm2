"""楼梯间折返平台护栏 —— 组件母版 v001

背景（2026-10-19 业主实机反馈）
--------------------------------
「99-100 / 99-98 的楼梯间，这两边都没有栏杆，角色会走过去。」
两座楼梯间共用同一套美术（v021 双装配根，A=100→99、B=99→98），
折返平台（三层里的中间层，Blender 局部 z = −6.00）是**唯一没有任何护栏**的楼板：

  · 折返平台楼板：x[0.36, 14.53] × y[18.01, 24.01]（Blender 装配根局部，米）
  · 外侧长边 y = 24.01 → 到围护远墙（y≈27.4）之间是 6m 深、3.4m 宽的采光井；
  · 内侧长边 y = 18.01 → 两跑之间有一段 3.55m 宽的井（两跑内扶手各自封边，
    但井口在平台一侧完全敞开），两侧另有 0.92m / 0.80m 的角部窄槽。
  · 现存的「二楼楼板边缘栏杆」只装在**上层平台**（y=3.22~3.38），
    两跑各有左右扶手；折返平台一条都没有 ⇒ 角色直接从平台走进 6m 深的井。

本组件只补**折返平台**这条缺口，不改楼梯本体（踏步、坡度、跑长、扶手全部保持 v021）。

构件口径 —— 逐项抄楼梯现有扶手，不另立风格
------------------------------------------
  立柱    0.13 × 0.13，z 相对楼面 −0.02 … +1.08（高 1.10）
  上扶手  0.15 × 0.15，z 相对楼面 +1.005 … +1.155
  中横杆  0.09 厚，    z 相对楼面 +0.515 … +0.605
  立柱间距 ≤ 2.85m（楼梯现有 2.947m 一档，这里取 2.85 让两端正好落在墙角/跑边）

坐标契约
--------
几何直接写在**楼梯间装配根局部坐标系**里（与 stairwell_art_v021 的
`楼梯A_100至99层_装配根` / `楼梯B_99至98层_装配根` 同一套局部帧）。
⇒ 运行时把它挂成楼梯间可视根的子节点、恒等变换即可，**代码里不出现任何偏移常量**。
Blender Z-up → glTF Y-up：Godot 局部 = (x, z, −y)，与楼梯 GLB 完全同帧。

色盘
----
单一材质 `01_精工金属_紫色骨架`（metallic 0.88 / roughness 0.27），
全部面 UV 落在色盘第 7 列第 4 行（u≈0.735, v≈0.445 = RGB 46,104,112），
与楼梯现有护栏同色；不新增材质、不内嵌贴图。

跑法：
  blender --background --python build_turning_landing_rail_v001.py
"""

import json
import hashlib
import struct
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[5]
SRC_DIR = Path(__file__).resolve().parent
BLEND = SRC_DIR / "env_tower_stairwell_turn_rail_source_v001.blend"
EXPORT_DIR = SRC_DIR / "export" / "v001"
GLB = ROOT / "assets/art/environments/tower_descent_3d/components/env_tower_stairwell_turn_rail_top3d.glb"
PALETTE = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"

ASSET_ID = "ENV-TOWER-STAIRWELL-TURN-RAIL"
ASSET_VERSION = "v001"
MESH_NAME = "ENV_TOWER_STAIRWELL_TURN_RAIL"

# —— 折返平台实测（来自 stairwell_art_v021 装配根局部 depsgraph 包络）——
LANDING_X0, LANDING_X1 = 0.36, 14.53
LANDING_Y0, LANDING_Y1 = 18.01, 24.01
LANDING_Z = -6.00
# 两跑边线：下跑 x[1.28,5.73]、上跑 x[9.28,13.73]
LOWER_FLIGHT_X0, LOWER_FLIGHT_X1 = 1.28, 5.73
UPPER_FLIGHT_X0, UPPER_FLIGHT_X1 = 9.28, 13.73

POST = 0.13
POST_TOP = 1.08
POST_BOTTOM = -0.02
RAIL_TOP_Z0, RAIL_TOP_Z1 = 1.005, 1.155
RAIL_MID_Z0, RAIL_MID_Z1 = 0.515, 0.605
RAIL_TOP_W = 0.15
RAIL_MID_W = 0.09
# 扶手中心线离楼板边 0.08m，与上层平台栏杆（边 3.38 / 中心 3.30）同口径
EDGE_INSET = 0.08

PALETTE_UV = (0.735, 0.445)


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = 30


def make_material() -> bpy.types.Material:
    material = bpy.data.materials.new("01_精工金属_紫色骨架")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Base Color"].default_value = (0.8, 0.8, 0.8, 1.0)
    shader.inputs["Metallic"].default_value = 0.88
    shader.inputs["Roughness"].default_value = 0.27
    material.node_tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    # 色盘外链（不 Pack），Godot 由 scene_facility_shared_palette_post_import.gd 统一绑定
    image = bpy.data.images.get(PALETTE.name)
    if image is None:
        image = bpy.data.images.load(str(PALETTE), check_existing=True)
    image.filepath = str(PALETTE)
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Closest"
    return material


def add_box(name: str, x0, x1, y0, y1, z0, z1, material, collection) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bm.to_mesh(mesh)
    bm.free()
    obj.location = ((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
    obj.scale = (x1 - x0, y1 - y0, z1 - z0)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mesh.materials.clear()
    mesh.materials.append(material)
    uv = mesh.uv_layers.get("PaletteUV") or mesh.uv_layers.new(name="PaletteUV")
    uv.active_render = True
    for loop in uv.data:
        loop.uv = PALETTE_UV
    return obj


def post_positions(span: float, step_max: float = 2.85) -> list[float]:
    """两端各一根 + 中间等分，间距不超过 step_max。"""
    count = max(2, int(-(-span // step_max)) + 1)
    return [span * i / (count - 1) for i in range(count)]


def build() -> tuple[bpy.types.Object, dict]:
    reset_scene()
    material = make_material()
    collection = bpy.data.collections.new("01_楼梯间折返平台护栏_资产包")
    bpy.context.scene.collection.children.link(collection)

    z = LANDING_Z
    parts: list[bpy.types.Object] = []

    # —— 四段护栏：(x0, x1, y 中心线) ——
    runs = [
        # 外侧长边（面朝采光井）
        (LANDING_X0 - 0.06, LANDING_X1 + 0.02, LANDING_Y1 - EDGE_INSET, "外沿"),
        # 内侧长边：墙根窄槽 / 两跑之间的井 / 上跑外侧窄槽
        (LANDING_X0, LOWER_FLIGHT_X0, LANDING_Y0 + EDGE_INSET, "内沿_西槽"),
        (LOWER_FLIGHT_X1, UPPER_FLIGHT_X0, LANDING_Y0 + EDGE_INSET, "内沿_中井"),
        (UPPER_FLIGHT_X1, LANDING_X1, LANDING_Y0 + EDGE_INSET, "内沿_东槽"),
    ]

    report_runs = []
    for index, (x0, x1, y_center, label) in enumerate(runs):
        length = x1 - x0
        half = RAIL_TOP_W * 0.5
        # 上扶手
        parts.append(add_box(
            f"上扶手_{index:02d}_{label}", x0, x1,
            y_center - half, y_center + half,
            z + RAIL_TOP_Z0, z + RAIL_TOP_Z1,
            material, collection,
        ))
        # 中横杆
        parts.append(add_box(
            f"中横杆_{index:02d}_{label}", x0, x1,
            y_center - RAIL_MID_W * 0.5, y_center + RAIL_MID_W * 0.5,
            z + RAIL_MID_Z0, z + RAIL_MID_Z1,
            material, collection,
        ))
        # 立柱
        offsets = post_positions(length)
        for post_index, offset in enumerate(offsets):
            center_x = x0 + offset
            parts.append(add_box(
                f"立柱_{index:02d}_{post_index:02d}_{label}",
                center_x - POST * 0.5, center_x + POST * 0.5,
                y_center - POST * 0.5, y_center + POST * 0.5,
                z + POST_BOTTOM, z + POST_TOP,
                material, collection,
            ))
        report_runs.append({
            "label": label,
            "x": [round(x0, 3), round(x1, 3)],
            "y_center": round(y_center, 3),
            "length_m": round(length, 3),
            "post_count": len(offsets),
            "post_spacing_m": round(length / (len(offsets) - 1), 3) if len(offsets) > 1 else 0.0,
        })

    # 合并成单一可见网格：运行时 Prefab 不再展开子件，碰撞由 Prefab 显式持有
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = MESH_NAME
    joined.data.name = f"{MESH_NAME}_Mesh"

    bpy.ops.object.select_all(action="DESELECT")
    joined.select_set(True)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")  # 光标在 (0,0,0) = 装配根

    mesh = joined.data
    triangles = sum(max(0, len(p.vertices) - 2) for p in mesh.polygons)
    bbox = [Vector(corner) for corner in joined.bound_box]
    lo = [min(v[i] for v in bbox) for i in range(3)]
    hi = [max(v[i] for v in bbox) for i in range(3)]

    scene = bpy.context.scene
    scene["asset_id"] = ASSET_ID
    scene["asset_version"] = ASSET_VERSION
    scene["block_id"] = "stairs"
    scene["floor_range"] = "99F-100F / 98F-99F 折返平台"
    scene["design_scope"] = "楼梯间折返平台（Blender 局部 z=-6.00）四段护栏"
    scene["coordinate_frame"] = "stairwell_assembly_root_local"
    scene["godot_local_mapping"] = "(x, z, -y)"
    scene["palette"] = "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
    scene["asset_ledger"] = "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx#3D-场景通用"
    joined["asset_id"] = ASSET_ID
    joined["asset_version"] = ASSET_VERSION
    joined["origin_contract"] = "stairwell_assembly_root"
    joined["bounds_size_m"] = [round(hi[i] - lo[i], 4) for i in range(3)]

    stats = {
        "triangles": triangles,
        "bbox_min": [round(v, 4) for v in lo],
        "bbox_max": [round(v, 4) for v in hi],
        "bbox_size": [round(hi[i] - lo[i], 4) for i in range(3)],
        "runs": report_runs,
        "part_count": len(parts),
        "material_count": len(mesh.materials),
        "uv_layers": [layer.name for layer in mesh.uv_layers],
    }
    return joined, stats


def export_glb(joined: bpy.types.Object) -> dict:
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), compress=True)
    bpy.ops.object.select_all(action="DESELECT")
    joined.select_set(True)
    bpy.context.view_layer.objects.active = joined
    bpy.ops.export_scene.gltf(
        filepath=str(GLB),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_extras=True,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )
    return parse_glb(GLB)


def parse_glb(path: Path) -> dict:
    data = path.read_bytes()
    offset = 12
    document = None
    while offset < len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk = data[offset:offset + length]
        offset += length
        if kind == 0x4E4F534A:
            document = json.loads(chunk.rstrip(b" \0"))
    if document is None:
        raise RuntimeError("GLB JSON chunk missing")
    return document


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    joined, stats = build()
    document = export_glb(joined)
    if document.get("images") or document.get("textures"):
        raise RuntimeError("导出 GLB 含内嵌贴图，违反共用色盘契约")
    manifest = {
        "asset_id": ASSET_ID,
        "name": "楼梯间折返平台护栏",
        "slug": "turning_landing_rail",
        "version": ASSET_VERSION,
        "block_id": "stairs",
        "floor_range": "99F-100F / 98F-99F 折返平台",
        "design_scope": "两座楼梯间折返平台四段护栏（外沿 + 两跑之间井口 + 两处墙角窄槽）",
        "coordinate_frame": "stairwell_assembly_root_local",
        "godot_local_mapping": "Godot local = (x, z, -y) of the stairwell assembly root",
        "scene_design_docs": [
            "docs/v0.1/05_技术施工_关卡生成与爬楼.md",
            "docs/v0.1/05.1_关卡区块设计.md",
            "docs/v0.1/10.1_3D场景美术生产流程.md",
        ],
        "asset_ledger": "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx#3D-场景通用",
        "source_blend": str(BLEND.relative_to(ROOT)).replace("\\", "/"),
        "source_sha256": sha256(BLEND),
        "glb": str(GLB.relative_to(ROOT)).replace("\\", "/"),
        "glb_sha256": sha256(GLB),
        "glb_node_count": len(document.get("nodes", [])),
        "glb_mesh_count": len(document.get("meshes", [])),
        "glb_material_count": len(document.get("materials", [])),
        "glb_image_count": len(document.get("images", [])),
        "glb_texture_count": len(document.get("textures", [])),
        "triangles": stats["triangles"],
        "bbox_min": stats["bbox_min"],
        "bbox_max": stats["bbox_max"],
        "bbox_size": stats["bbox_size"],
        "runs": stats["runs"],
        "part_count": stats["part_count"],
        "material_roles": ["01_精工金属_紫色骨架"],
        "palette": "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png",
        "palette_uv": list(PALETTE_UV),
        "palette_rgb": [46, 104, 112],
        "collision_owner": "assets/art/environments/tower_descent_3d/runtime/env_tower_stairwell_turn_rail/env_tower_stairwell_turn_rail_root_top3d.tscn",
        "collision_method": "4 x BoxShape3D（逐段，尺寸 = 该段扶手包络）",
        "runtime_attach": "TowerDescent3D._add_stairwell_turn_rail()：挂为楼梯间可视根的子节点，恒等变换",
        "build_script": str(Path(__file__).relative_to(ROOT)).replace("\\", "/"),
    }
    (EXPORT_DIR / "import_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("TURN_RAIL_BUILD_OK")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
