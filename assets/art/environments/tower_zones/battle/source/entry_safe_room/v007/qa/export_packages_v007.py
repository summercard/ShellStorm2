"""导出入口安全房 v007 的 17 个房间自有资产包为 Godot 用 GLB（视觉，不含碰撞）。

范围
  - 只导出 catalog.json 列出的 17 个包（14 设施 + 3 支持件）。
  墙面 / 地面 / 门洞的美术不再属于房间：v004 通用组件已把它们并进组件本身，
  房间只保留引用槽位与承重底板 floor_base。
  - **不导出**任何墙 / 门扇 / 地砖槽位：那 23 个槽位引用通用组件库 v003，几何由
    components/common_components/ 提供（见 common_components/v003/qa/export_*.py）。
  - 不导出白模来源环（AP_*）、制作组件集合、相机与灯光。

坐标契约（与通用组件 v003 全库一致）
  - Blender 正面 = 本地 +Y  → Godot -Z
  - export_yup：Blender (x, y, z) → Godot (x, z, -y)
  - 每包原点取「底面中心」：并集包围盒的 x/y 中心，z 取并集最低点。
    这样每个 GLB 是可独立摆放的资产，而不是把整屋坐标背在身上；
    房间内摆位由 summary 的 godot_placement 提供。

背景模式的 matrix_world 陷阱
  blender --background 打开 .blend 后，未触碰 UI 的对象 matrix_world 可能未求值，
  而 export_scene.gltf 内部正是靠 matrix_world 定位。这里先 view_layer.update()，
  再用与 qa/verify_entry_safe_room_v007.py 相同的 W() 重建式交叉验证；不一致就直接失败，
  不让一个静默的错误坐标进入 GLB。

运行：
  "D:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" \
      --background --factory-startup --python export_packages_v007.py
"""

from __future__ import annotations

import json
from pathlib import Path

import bpy
import mathutils

HERE = Path(__file__).resolve().parent            # .../v007/qa
V007 = HERE.parent                                # .../v007
SOURCE_DIR = V007.parent.parent                   # .../source
BATTLE = SOURCE_DIR.parent                        # .../battle
ROOT = BATTLE.parents[4]                          # .../ShellStorm2
assert (ROOT / "assets" / "art").is_dir(), f"ROOT 解析失败: {ROOT}"

BLEND = V007 / "局内关卡01_入口安全房_15x15m_正式美术_v007.blend"
CATALOG = V007 / "component_packages_v007" / "catalog.json"
PALETTE = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
COMPONENTS_DIR = BATTLE / "components" / "entry_safe_room" / "v007"
VERSION = "v007"

if not BLEND.is_file():
    raise SystemExit(f"缺少源 blend: {BLEND}")
if not CATALOG.is_file():
    raise SystemExit(f"缺少 catalog: {CATALOG}")

bpy.ops.wm.open_mainfile(filepath=str(BLEND))
bpy.context.view_layer.update()

# 源 blend 的外链色盘记录的是作者机绝对路径，本机需重新绑定（GLB 不内嵌图片，
# 但要保证导出时材质索引与颜色一致）。
image = bpy.data.images.get("设施低亮多巴胺色盘_10x10_512.png")
if image is None:
    print("WARN: 未找到色盘 image 数据块")
elif not PALETTE.is_file():
    print(f"WARN: 本机缺少色盘文件 {PALETTE}")
else:
    image.filepath = str(PALETTE)
    image.reload()
    print(f"palette rebound -> {image.filepath}")


def W(o):
    """背景模式安全的世界矩阵（与 qa/verify_entry_safe_room_v007.py 一致）。"""
    m = o.matrix_parent_inverse @ o.matrix_basis
    p = o.parent
    while p is not None:
        m = (p.matrix_parent_inverse @ p.matrix_basis) @ m
        p = p.parent
    return m


# —— 陷阱守卫：matrix_world 在 background 模式下可能陈旧 ------------------------
# 这不是可以忽略的噪声：偏离可达数米。W() 重建式是权威（matrix_basis 才是作者写下的
# 事实），而 export_scene.gltf 内部靠 matrix_world。因此本脚本对每个待导出的对象
# **显式写入** matrix_world = shift @ W(obj)，再用折算后的包围盒断言复验最终状态
# （底面归零、x/y 居中）。这里只统计并报告陈旧规模，不阻断。
vl0 = bpy.context.scene.view_layers[0]
stale = []
for o in bpy.data.objects:
    if o.type != "MESH":
        continue
    delta = max(abs(a - b) for row_a, row_b in zip(W(o), o.matrix_world) for a, b in zip(row_a, row_b))
    if delta > 1e-5:
        stale.append(round(delta, 4))
print(f"guard: {len(stale)} mesh objects carry a stale matrix_world "
      f"(max delta {max(stale) if stale else 0.0} m); the export writes it explicitly from W()")

packages = json.loads(CATALOG.read_text(encoding="utf8"))
print(f"catalog packages: {len(packages)}")

summary = {}
for pkg in packages:
    slug = pkg["slug"]
    names = pkg["objects"]

    missing = [n for n in names if bpy.data.objects.get(n) is None]
    if missing:
        raise SystemExit(f"{slug}: catalog 里这些对象在 blend 中不存在: {missing}")
    meshes = [bpy.data.objects[n] for n in names]
    bad = [o.name for o in meshes if o.type != "MESH"]
    if bad:
        raise SystemExit(f"{slug}: 非 MESH 对象: {bad}")

    # 并集包围盒（用重建矩阵，不用可能过期的 matrix_world）
    pts = [W(o) @ mathutils.Vector(c) for o in meshes for c in o.bound_box]
    mn = [min(p[i] for p in pts) for i in range(3)]
    mx = [max(p[i] for p in pts) for i in range(3)]
    origin = [(mn[0] + mx[0]) * 0.5, (mn[1] + mx[1]) * 0.5, mn[2]]
    shift = mathutils.Matrix.Translation(mathutils.Vector((-origin[0], -origin[1], -origin[2])))

    out_dir = COMPONENTS_DIR / slug
    out_dir.mkdir(parents=True, exist_ok=True)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.parent = None
        obj.matrix_parent_inverse = mathutils.Matrix.Identity(4)
        obj.matrix_world = shift @ W(obj)
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.context.view_layer.update()

    # 折算出包后应当落在的状态，自检
    pts2 = [obj.matrix_world @ mathutils.Vector(c) for obj in meshes for c in obj.bound_box]
    mn2 = [min(p[i] for p in pts2) for i in range(3)]
    mx2 = [max(p[i] for p in pts2) for i in range(3)]
    assert abs(mn2[2]) < 1e-4, f"{slug}: 底面未归零 z={mn2[2]}"
    assert abs(mn2[0] + mx2[0]) < 1e-4 and abs(mn2[1] + mx2[1]) < 1e-4, \
        f"{slug}: x/y 未居中 mn={mn2} mx={mx2}"

    size = [round(mx2[i] - mn2[i], 4) for i in range(3)]
    out = out_dir / f"{slug}_visual_top3d_{VERSION}.glb"
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
    print(f"EXPORTED {slug:24s} -> {out.name}  size={size}  origin(blender)={[round(v, 4) for v in origin]}")

    summary[slug] = {
        "package_id": pkg.get("package_id"),
        "category": pkg.get("category"),
        "display_name_zh": pkg.get("name"),
        "glb": str(out.relative_to(ROOT)).replace("\\", "/"),
        "meshes": names,
        "origin_blender_m": [round(v, 4) for v in origin],
        "godot_placement_position": [round(origin[0], 4), round(origin[2], 4), round(-origin[1], 4)],
        "godot_placement_note": "底面中心原点，实例化时 position 用本值、rotation 保持 identity。",
        "blender_size_xyz": size,
        "godot_size_xyz": [size[0], size[2], size[1]],
        "room_bounds_blender": [[round(v, 4) for v in mn], [round(v, 4) for v in mx]],
    }

out_summary = HERE / "export_packages_v007_summary.json"
out_summary.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"SUMMARY_WRITTEN {out_summary}")
print(f"EXPORT_OK count={len(summary)}")
