"""导出远征 Boss 房种类源的 6 件壳体/标志物组件为 Godot 用 GLB。

背景（口径见 docs/v0.1/design/远征关卡01设计.md 与 00-battle-room-layout-assembler）：
  Boss 房种类源 214 包里，**结构墙 / 门墙 / 门扇 / 地砖** 四类与战局通用库
  （assets/art/environments/tower_zones/battle/components/common_components）逐项同尺寸
  （墙 5.0x11.9x0.3、门净跨 2.2 净高 2.5、地砖 4.94x4.94），直接复用通用件，不再重复导出。
  本脚本只导出**无法用通用件表达**的 6 件专属件：

    ENV-EXPEDITION-BOSSROOM-BASE-FLOOR-BASE     地板底盘 50x40x0.26
    ENV-EXPEDITION-BOSSROOM-MAIN-FAULT-SCREEN   主屏（独立资产）21.52x1.575x7.09
    ENV-EXPEDITION-BOSSROOM-HEAVY-CONDUITS      粗重电线管与桥架 47.31x32.30x3.67
    ENV-EXPEDITION-BOSSROOM-NORTH-WALL-TYPOGRAPHY 数据库墙面标识 35.90x0.042x2.32
    ENV-EXPEDITION-BOSSROOM-SOUTH-FLOOR-MARKING 入口地砖_标识附件 3.70x2.73x0.012
    ENV-EXPEDITION-BOSSROOM-DEBRIS-00          固定碎屑（10 件归并后的代表件）

坐标契约（与战局通用库一致）：
  - Blender 正面 = 本地 -Y  -> Godot +Z（catalog 的 godot_front_axis）
  - XY 居中、底面 Z = 0     -> Godot 底面 Y = 0（origin_contract = bottom-center）
  - export_yup：Blender (X, Y, Z) -> Godot (X, -Z, Y)

导出前把每个 mesh 的世界变换折算成「相对其 ROOT_*_组件」的变换，
使 GLB 内几何坐标 = 该组件自身的局部坐标（剔除源房间里的绝对摆放）。

运行：
  "D:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" \
      --background --factory-startup --python export_boss_shell_components.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy
import mathutils

HERE = Path(__file__).resolve().parent          # .../common_components/v001/qa
V001 = HERE.parent                              # .../common_components/v001
EXPEDITION = V001.parents[2]                    # .../tower_zones/expedition
ROOT = EXPEDITION.parents[4]                    # .../ShellStorm2
assert (ROOT / "assets" / "art").is_dir(), f"ROOT 解析失败: {ROOT}"

sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))
import godot_runtime_naming as grn  # noqa: E402

CATALOG = V001 / "component_catalog.json"
PALETTE = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
COMPONENTS_DIR = EXPEDITION / "components" / "common_components"

# 本次要导出的 6 件（component_id 为唯一键，其余字段一律从 catalog 取，不在此重复声明）
TARGET_IDS = [
    "ENV-EXPEDITION-BOSSROOM-BASE-FLOOR-BASE",
    "ENV-EXPEDITION-BOSSROOM-MAIN-FAULT-SCREEN",
    "ENV-EXPEDITION-BOSSROOM-HEAVY-CONDUITS",
    "ENV-EXPEDITION-BOSSROOM-NORTH-WALL-TYPOGRAPHY",
    "ENV-EXPEDITION-BOSSROOM-SOUTH-FLOOR-MARKING",
    "ENV-EXPEDITION-BOSSROOM-DEBRIS-00",
]


def aabb_world(objects):
    points = []
    for obj in objects:
        mw = obj.matrix_world
        points.extend(mw @ mathutils.Vector(corner) for corner in obj.bound_box)
    mn = [min(p[i] for p in points) for i in range(3)]
    mx = [max(p[i] for p in points) for i in range(3)]
    return mn, mx


def rebind_palette() -> None:
    """源 blend 的外链色盘记录的是作者机绝对路径，本机需重新绑定。"""
    if not PALETTE.is_file():
        print(f"WARN: 本机缺少色盘文件 {PALETTE}")
        return
    rebound = 0
    for image in bpy.data.images:
        if image.name.endswith("色盘_10x10_512.png") or "多巴胺色盘" in image.name:
            image.filepath = str(PALETTE)
            image.reload()
            rebound += 1
    print(f"palette rebound images={rebound}")


print(f"ROOT     = {ROOT}")
print(f"CATALOG  = {CATALOG}")
print(f"COMPONENTS_DIR = {COMPONENTS_DIR}")

if not CATALOG.is_file():
    raise SystemExit(f"缺少 catalog: {CATALOG}")

catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
by_id = {pkg["component_id"]: pkg for pkg in catalog["packages"]}

missing = [cid for cid in TARGET_IDS if cid not in by_id]
if missing:
    raise SystemExit(f"catalog 里找不到这些 component_id: {missing}")

summary = {}
for component_id in TARGET_IDS:
    pkg = by_id[component_id]
    slug = pkg["source_package_id"]
    blend = ROOT / pkg["component_blend"]
    collection_name = pkg["collection"]
    root_name = pkg["root_object"]
    if not blend.is_file():
        raise SystemExit(f"缺少源 blend: {blend}")

    bpy.ops.wm.open_mainfile(filepath=str(blend))
    rebind_palette()
    if bpy.context.object is not None:
        bpy.ops.object.mode_set(mode="OBJECT")

    collection = bpy.data.collections.get(collection_name)
    if collection is None:
        raise SystemExit(f"{slug}: 缺少 collection {collection_name}")
    root = bpy.data.objects.get(root_name)
    if root is None:
        raise SystemExit(f"{slug}: 缺少 ROOT 对象 {root_name}")

    meshes = [o for o in collection.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit(f"{slug}: collection 下无 MESH")
    meshes.sort(key=lambda o: o.name)

    out_dir = COMPONENTS_DIR / slug
    out_dir.mkdir(parents=True, exist_ok=True)

    root_inverse = root.matrix_world.inverted()
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        relative = root_inverse @ obj.matrix_world
        obj.parent = None
        obj.matrix_parent_inverse = mathutils.Matrix.Identity(4)
        obj.matrix_world = relative
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.context.view_layer.update()

    mn, mx = aabb_world(meshes)
    size = [round(mx[i] - mn[i], 4) for i in range(3)]
    per_mesh = {}
    for obj in meshes:
        pts = [obj.matrix_world @ mathutils.Vector(c) for c in obj.bound_box]
        per_mesh[obj.name] = {
            "min": [round(min(p[i] for p in pts), 4) for i in range(3)],
            "max": [round(max(p[i] for p in pts), 4) for i in range(3)],
        }
    print(f"[{slug}] AABB min={[round(v, 4) for v in mn]} max={[round(v, 4) for v in mx]} size={size}")

    # 源 catalog 已把包络归一（XY 居中、底面 Z=0）；这里做一次硬断言，防止源被改动后静默漂移。
    declared = [round(v, 4) for v in pkg["bounds_size_m"]]
    if max(abs(size[i] - declared[i]) for i in range(3)) > 0.002:
        raise SystemExit(f"{slug}: 导出包络 {size} 与 catalog 声明 {declared} 不一致，停止导出")

    out = out_dir / grn.visual_glb_name(slug)
    bpy.ops.export_scene.gltf(
        filepath=str(out),
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
    print(f"EXPORTED {slug} -> {out}")

    summary[slug] = {
        "component_id": component_id,
        "category": pkg["category"],
        "name_zh": pkg["name_zh"],
        "glb": str(out.relative_to(ROOT)).replace("\\", "/"),
        "meshes": [o.name for o in meshes],
        "mesh_count": len(meshes),
        "blender_aabb_min": [round(v, 4) for v in mn],
        "blender_aabb_max": [round(v, 4) for v in mx],
        "blender_size_xyz": size,
        "godot_size_xyz": [size[0], size[2], size[1]],
        "godot_aabb_min": [round(mn[0], 4), round(mn[2], 4), round(-mx[1], 4)],
        "godot_aabb_max": [round(mx[0], 4), round(mx[2], 4), round(-mn[1], 4)],
        "source_blend": pkg["component_blend"],
        "source_version": pkg["version"],
        "material_roles": pkg["material_roles"],
        "emissive_objects": pkg["emissive_objects"],
        "origin_contract": "bottom_center",
        "godot_front_axis": pkg["godot_front_axis"],
        "per_mesh": per_mesh,
    }

summary_path = HERE / "export_boss_shell_components_summary.json"
summary_path.write_text(
    json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
print(f"SUMMARY_WRITTEN {summary_path}")
print(f"EXPORT_OK count={len(TARGET_IDS)}")
