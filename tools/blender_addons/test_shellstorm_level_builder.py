"""ShellStorm Level Builder 后台自测（Blender 4.5）。

运行：blender --background --factory-startup --python test_shellstorm_level_builder.py
"""

import json
import sys
import tempfile
from pathlib import Path

import bpy
from mathutils import Vector


addon_parent = Path(__file__).resolve().parent
sys.path.insert(0, str(addon_parent))
import shellstorm_level_builder as addon


def local_bounds(obj):
    points = [vertex.co for vertex in obj.data.vertices]
    low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return low, high


def world_bounds(obj):
    return addon.operators.snapping.world_bounds([obj])


def assert_close(actual, expected, tol=1e-5, label=""):
    assert abs(actual - expected) < tol, f"{label}: {actual} != {expected}"


def expect_cancelled(call, label):
    """带 report(ERROR) 的取消在 bpy.ops 里表现为 RuntimeError。"""
    try:
        result = call()
    except RuntimeError:
        return
    assert result == {"CANCELLED"}, f"{label} 应当被拒绝"


addon.register()
scene = bpy.context.scene
output = Path(tempfile.mkdtemp(prefix="shellstorm_level_builder_"))
scene.sslb.project_root = str(output)
scene.sslb.package_root = "packages"
scene.sslb.render_root = "renders"
scene.sslb.scene_slug = "addon_test"
scene.sslb.block_id = "stairs"

assert bpy.ops.sslb.setup_scene() == {"FINISHED"}
root_collection = next(
    collection for collection in bpy.data.collections if collection.get("shellstorm_level_root")
)
assert "01_白盒布局_可编辑" in root_collection.children
assert "90_展示与验收_灯光相机" in root_collection.children

operator = bpy.ops.sslb.add_component
assert operator(component_type="WALL") == {"FINISHED"}
wall = bpy.context.active_object
assert wall.type == "MESH" and wall.children == tuple()
assert wall.get("shellstorm_component") and wall.get("component_type") == "WALL"
low, high = local_bounds(wall)
assert_close(low.z, 0.0, label="底面中心锚点底面")
assert_close(low.x, -2.5, label="X 居中")
assert_close(high.x, 2.5, label="X 居中")
assert_close(high.y - low.y, 0.3, label="墙厚")
assert_close(high.z, 11.9, label="墙高")
assert_close(wall.location.z, 0.0, label="底面贴合地面")

wall.sslb.height = 8.9
assert bpy.ops.sslb.rebuild_component() == {"FINISHED"}
wall = bpy.context.view_layer.objects.active
assert_close(local_bounds(wall)[1].z, 8.9, label="重建墙高")
assert len([mesh for mesh in bpy.data.meshes if mesh.name.startswith("墙壁")]) == 1

scene.sslb.origin_mode = "GAME_ASSET"
assert operator(component_type="FLOOR") == {"FINISHED"}
floor_tile = bpy.context.active_object
low, high = local_bounds(floor_tile)
assert_close(low.z, -0.15, label="地砖厚度居中锚点")
assert_close(high.z, 0.15, label="地砖厚度居中锚点")
scene.sslb.origin_mode = "BOTTOM_CENTER"

assert operator(component_type="WALL") == {"FINISHED"}
second = bpy.context.active_object
second.location = (7.3, 1.4, 0.2)
assert bpy.ops.sslb.snap_to_grid() == {"FINISHED"}
assert_close(second.location.x, 5.0, label="网格吸附 X")
assert_close(second.location.y, 0.0, label="网格吸附 Y")
assert_close(second.location.z, 0.3, label="标高吸附 Z")

wall.location = (0.0, 0.0, 0.0)
second.location = (9.0, 0.0, 0.0)
bpy.ops.object.select_all(action="DESELECT")
second.select_set(True)
wall.select_set(True)
bpy.context.view_layer.objects.active = wall
assert bpy.ops.sslb.snap_adjacent(side="X_PLUS") == {"FINISHED"}
assert_close(world_bounds(second)[0].x, world_bounds(wall)[1].x, label="右侧贴齐")
assert_close(world_bounds(second)[0].y, world_bounds(wall)[0].y, label="贴齐后 Y 居中")
assert_close(world_bounds(second)[0].z, 0.0, label="贴齐后底面标高")

second.location = (2.0, 6.0, 4.0)
assert bpy.ops.sslb.align_to_active(axes="Z") == {"FINISHED"}
assert_close(world_bounds(second)[0].z, world_bounds(wall)[0].z, label="Z 轴对齐")

assert bpy.ops.sslb.move_to_cursor() == {"FINISHED"}
assert_close(world_bounds(second)[0].z, scene.cursor.location.z, label="移到游标")

assert bpy.ops.sslb.measure_layout() == {"FINISHED"}
assert "件" in scene.sslb.layout_summary
assert bpy.data.texts["ShellStorm_布局统计"].as_string().startswith("SHELLSTORM LEVEL BUILDER LAYOUT")

assert bpy.ops.sslb.build_annotations() == {"FINISHED"}
annotations = [
    obj for obj in bpy.data.objects if obj.get("shellstorm_annotation")
]
assert annotations, "应当生成标注"
bodies = [obj.data.body for obj in annotations if obj.type == "FONT"]
assert any("\n" in body for body in bodies), "组件标注应为两行（名称 + 尺寸）"
assert any("墙壁" in body for body in bodies), "标注应使用中文组件名"
scene.sslb.show_annotations = False
assert all(obj.hide_viewport for obj in annotations), "关闭标注开关应隐藏标注"
scene.sslb.show_annotations = True
assert all(not obj.hide_viewport for obj in annotations), "开启标注开关应恢复显示"

scene.sslb.use_palette = False
assert not [
    slot.material
    for slot in wall.material_slots
    if slot.material and slot.material.name.startswith("SSLB_白盒")
], "关闭配色应移除插件占位材质"
scene.sslb.use_palette = True
assert [
    slot.material
    for slot in wall.material_slots
    if slot.material and slot.material.name.startswith("SSLB_白盒")
], "开启配色应重新套用占位材质"

after_annotations = len(addon.operators.whitebox_objects(scene))
assert bpy.ops.sslb.clear_annotations() == {"FINISHED"}
assert not scene.sslb.show_annotations, "清除标注后显示开关应同步关闭"
assert len(addon.operators.whitebox_objects(scene)) == after_annotations

assert bpy.ops.wm.save_as_mainfile(filepath=str(output / "level_builder_source.blend")) == {"FINISHED"}
expect_cancelled(bpy.ops.sslb.sync_manifests, "空场景同步")

scene.sslb.package_name = "测试墙体"
scene.sslb.package_slug = "test_wall"
scene.sslb.package_category = "architecture"
bpy.ops.object.select_all(action="DESELECT")
wall.select_set(True)
bpy.context.view_layer.objects.active = wall
assert bpy.ops.sslb.create_package() == {"FINISHED"}
assert bpy.ops.sslb.validate_structure() == {"FINISHED"}
assert bpy.ops.sslb.sync_manifests() == {"FINISHED"}

manifest_path = output / "packages" / "architecture" / "test_wall" / "asset_manifest.json"
catalog_path = output / "packages" / "catalog.json"
tree_path = output / "packages" / "tree.txt"
assert manifest_path.exists() and catalog_path.exists() and tree_path.exists()
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
assert manifest["package_id"] == "test_wall"
assert manifest["block_id"] == "stairs"
assert manifest["object_names"] == [wall.name]
assert manifest["collection"] == manifest["blender_collection"]
assert "底面中心" in manifest["local_origin"]
assert_close(manifest["bounding_size_m"][2], 8.9, label="清单高度")

catalog_text = catalog_path.read_text(encoding="utf-8")
package = next(
    collection for collection in bpy.data.collections if collection.get("shellstorm_asset_package")
)
del package["shellstorm_asset_package"]
expect_cancelled(bpy.ops.sslb.sync_manifests, "无资产包同步")
assert catalog_path.read_text(encoding="utf-8") == catalog_text
package["shellstorm_asset_package"] = True


def box_object(name, center, size):
    half = [value / 2.0 for value in size]
    vertices = [
        (center[0] + sx * half[0], center[1] + sy * half[1], center[2] + sz * half[2])
        for sx, sy, sz in (
            (-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
            (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1),
        )
    ]
    faces = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (4, 0, 3, 7)]
    mesh = bpy.data.meshes.new(f"{name}_网格")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    return obj


offset_box = box_object("偏移盒", (4.0, -2.0, 6.0), (2.0, 2.0, 2.0))
before = world_bounds(offset_box)
assert addon.geometry.reanchor_object(offset_box, addon.geometry.BOTTOM_CENTER)
bpy.context.view_layer.update()
after = world_bounds(offset_box)
for index in range(3):
    assert_close(after[0][index], before[0][index], label="重设锚点保持世界坐标")
    assert_close(after[1][index], before[1][index], label="重设锚点保持世界坐标")
assert_close(local_bounds(offset_box)[0].z, 0.0, label="重设后锚点在底面")
bpy.data.objects.remove(offset_box, do_unlink=True)

library_collection = bpy.data.collections.new("测试库Collection")
library_mesh = bpy.data.meshes.new("测试库网格")
library_mesh.from_pydata([(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)], [], [(0, 1, 2, 3)])
library_mesh.update()
library_object = bpy.data.objects.new("测试库对象", library_mesh)
library_collection.objects.link(library_object)
library_blend = output / "library_asset.blend"
bpy.data.libraries.write(str(library_blend), {library_collection, library_mesh, library_object})

project_style_manifest = output / "library_manifest" / "asset_manifest.json"
project_style_manifest.parent.mkdir(parents=True, exist_ok=True)
project_style_manifest.write_text(
    json.dumps(
        {
            "package_id": "ENV-BASE99-ART-LAYOUT-3D::library_asset",
            "display_name": "测试库资产",
            "asset_slug": "library_asset",
            "category": "architecture",
            "source": "library_asset.blend",
            "blender_collection": "测试库Collection",
            "object_names": ["测试库对象"],
        },
        ensure_ascii=False,
        indent=2,
    ),
    encoding="utf-8",
)

scene.sslb.project_root = str(output)
assert bpy.ops.sslb.scan_library() == {"FINISHED"}
assert "可用" in scene.sslb.library_summary, "扫描后应给出可读的组件库状态"
slugs = {item.asset_slug for item in scene.sslb_library}
assert "library_asset" in slugs, "应识别项目既有清单字段"
assert "test_wall" in slugs, "应识别本插件写出的清单"
library_item = next(item for item in scene.sslb_library if item.asset_slug == "library_asset")
assert bpy.ops.sslb.append_library_asset(manifest_path=library_item.manifest_path) == {"FINISHED"}
assert any(collection.get("shellstorm_library_asset") for collection in bpy.data.collections)

components_before = len(addon.operators.whitebox_objects(scene))
assert bpy.ops.sslb.setup_top_camera() == {"FINISHED"}
camera = bpy.data.objects["SSLB_顶视图相机"]
assert camera.data.type == "ORTHO" and scene.camera is camera
engine_before = scene.render.engine
scene.render.resolution_x = 320
scene.render.resolution_y = 240
assert bpy.ops.sslb.render_top_view() == {"FINISHED"}
top_view = output / "renders" / "whitebox_addon_test_v001_top.png"
assert top_view.exists() and top_view.stat().st_size > 0
assert scene.render.engine == engine_before, "渲染后应恢复原渲染引擎"
assert len(addon.operators.whitebox_objects(scene)) == components_before

print(
    json.dumps(
        {
            "ok": True,
            "manifest": str(manifest_path),
            "top_view": str(top_view),
            "objects": manifest["objects"],
            "library": sorted(slugs),
        },
        ensure_ascii=False,
    )
)

addon.unregister()
