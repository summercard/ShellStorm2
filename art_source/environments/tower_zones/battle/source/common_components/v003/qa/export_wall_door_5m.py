"""导出战局通用组件库 v003 的 08_墙壁组件 与 10_门组件 为 Godot 用 GLB。

覆盖三件：
  wall_standard_5m  5 x 0.3 x 11.9 m 实墙（此前 GLB 丢失，本次重导出）
  wall_door_5m      5 x 0.3 x 11.9 m 带门洞墙（3 mesh：左门垛 / 右门垛 / 门楣）
  door_5m           2.2 x 0.18 x 2.5 m 门扇（底边中心原点，供 RoomDoor3D 作 panel visual）

坐标契约（与 v003 全库一致）：
  - Blender 正面 = 本地 +Y          → Godot -Z
  - XY 居中、底面 Z = 0             → Godot 底面 Y = 0（底面中心原点）
  - export_yup：Blender (X, Y, Z) → Godot (X, -Z, Y)

导出前把每个 mesh 的世界变换折算成「相对其 ROOT_*_通用组件」的变换，
使 GLB 内几何坐标 = 该组件自身的局部坐标（剔除展示阵列的 showcase 偏移）。

运行：
  "D:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" \
      --background --factory-startup --python export_wall_door_5m.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy
import mathutils

HERE = Path(__file__).resolve().parent          # .../v003/qa
V003 = HERE.parent                              # .../v003
SOURCE_DIR = V003.parent.parent                 # .../source
BATTLE = SOURCE_DIR.parent                      # .../battle
ROOT = BATTLE.parents[4]                        # .../ShellStorm2
assert (ROOT / "assets" / "art").is_dir(), f"ROOT 解析失败: {ROOT}"

sys.path.insert(0, str(ROOT / "tools" / "asset_pipeline"))
import godot_runtime_naming as grn  # noqa: E402

BLEND = V003 / "战局区块_通用组件库_v003.blend"
PALETTE = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
COMPONENTS_DIR = BATTLE / "components" / "common_components"

# slug: (blender collection, ROOT object, 输出子目录)
EXPORTS = {
    "wall_standard_5m": ("wall_standard_5m_通用包", "ROOT_wall_standard_5m_通用组件", "wall_standard_5m"),
    "wall_door_5m": ("wall_door_5m_通用包", "ROOT_wall_door_5m_通用组件", "wall_door_5m"),
    "door_5m": ("door_5m_通用包", "ROOT_door_5m_通用组件", "door_5m"),
}

print(f"ROOT     = {ROOT}")
print(f"BLEND    = {BLEND}")
print(f"COMPONENTS_DIR = {COMPONENTS_DIR}")

if not BLEND.is_file():
    raise SystemExit(f"缺少源 blend: {BLEND}")

bpy.ops.wm.open_mainfile(filepath=str(BLEND))

# 源 blend 的外链色盘记录的是作者机（macOS）绝对路径，本机需重新绑定。
image = bpy.data.images.get("设施低亮多巴胺色盘_10x10_512.png")
if image is None:
    print("WARN: 未找到色盘 image 数据块")
elif not PALETTE.is_file():
    print(f"WARN: 本机缺少色盘文件 {PALETTE}")
else:
    image.filepath = str(PALETTE)
    image.reload()
    print(f"palette rebound -> {image.filepath}")

bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object else None


def aabb_world(objects):
    points = []
    for obj in objects:
        mw = obj.matrix_world
        points.extend(mw @ mathutils.Vector(corner) for corner in obj.bound_box)
    mn = [min(p[i] for p in points) for i in range(3)]
    mx = [max(p[i] for p in points) for i in range(3)]
    return mn, mx


summary = {}

for slug, (collection_name, root_name, out_subdir) in EXPORTS.items():
    collection = bpy.data.collections.get(collection_name)
    if collection is None:
        raise SystemExit(f"缺少 collection: {collection_name}")
    root = bpy.data.objects.get(root_name)
    if root is None:
        raise SystemExit(f"缺少 ROOT 对象: {root_name}")

    meshes = [o for o in collection.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit(f"{slug} 无 MESH 对象")
    meshes.sort(key=lambda o: o.name)

    out_dir = COMPONENTS_DIR / out_subdir
    out_dir.mkdir(parents=True, exist_ok=True)

    # 把世界变换折算为「相对 ROOT」的变换；ROOT 原点即组件原点。
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
        mw_points = [obj.matrix_world @ mathutils.Vector(c) for c in obj.bound_box]
        per_mesh[obj.name] = {
            "min": [round(min(p[i] for p in mw_points), 4) for i in range(3)],
            "max": [round(max(p[i] for p in mw_points), 4) for i in range(3)],
        }
    print(f"[{slug}] AABB min={[round(v, 4) for v in mn]} max={[round(v, 4) for v in mx]} size={size}")
    for name, box in per_mesh.items():
        print(f"    {name}: {box['min']} -> {box['max']}")

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
        "glb": str(out),
        "meshes": [o.name for o in meshes],
        "blender_aabb_min": [round(v, 4) for v in mn],
        "blender_aabb_max": [round(v, 4) for v in mx],
        "blender_size_xyz": size,
        "godot_size_xyz": [size[0], size[2], size[1]],
        "godot_aabb_min": [round(mn[0], 4), round(mn[2], 4), round(-mx[1], 4)],
        "godot_aabb_max": [round(mx[0], 4), round(mx[2], 4), round(-mn[1], 4)],
        "per_mesh": per_mesh,
    }

summary_path = HERE / "export_wall_door_5m_summary.json"
summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"SUMMARY_WRITTEN {summary_path}")
print(f"EXPORT_OK count={len(EXPORTS)}")
