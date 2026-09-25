# -*- coding: utf-8 -*-
"""标准房间种类（四墙平房 25x25m）布局源 v001 —— 用 office_room/v001 + bridge_room/v002 的
已验收组件「拼」，不新造几何、不改尺寸、不缩放。

用法：
    blender --background --factory-startup --python build_std25_room_v001.py -- [--no-render]

—— 本文件只拥有「摆位」——
* 组件几何 / 材质 / 组件根原点一律来自两批已验收源，本文件 **只做 Library Link + 实例**，
  不 Append、不复制网格、不新建 Mesh（skill 03 约束 1/2/6）。
* 布局方案的真源是 `std_25x25_v001.layout.json`（由 `_scratch/std25_layout/plan_std25_layout.py`
  算出，纯计算 + 九组断言）。本脚本**只消费**它，不另立一套坐标。

—— 坐标契约（Blender Z-up）——
* 房间局部：房中心为原点；X=东、Y=北、Z=上；Z=0 为房界地面（地砖顶面 0.087、砖底 −0.32）。
* Godot 换算：(bx, by, bz) --export_yup--> (bx, bz, −by)；房间局部 = 世界 − 房中心。
* 两批源的组件都是**按各自房间的最终世界坐标**做的（不是原点归零的库件）⇒ 组件集合实例的
  空物体必须做 `L = desired − R·origin_src`，绕**组件自身原点**旋转；直接设 location=desired
  会把整块几何平移错位。

—— 为什么组件必须按 (来源, slug) 取值 ——
office 与 bridge 两批有 **27 个同名 slug**（四墙 wall_*_k 全部重名），且 bridge 的墙件
**没有 wall_piece_contract**、墙件尺寸也是 30×60 的那一套。故一切查找一律带来源。
"""
import bpy
import json
import math
import sys
from pathlib import Path
from mathutils import Vector, Matrix

# ---------------------------------------------------------------- 路径
HERE = Path(__file__).resolve()
OUT = HERE.parent
ROOT = HERE.parents[9]         # ShellStorm2/
ROOM_TYPES = ROOT / "assets/art/environments/tower_zones/expedition/source/room_types"
LAYOUT = OUT / "std_25x25_v001.layout.json"
BLEND_NAME = "标准房间种类_四墙平房_25x25m_v001.blend"
RENDER = OUT / "renders"

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
NO_RENDER = "--no-render" in argv

SOURCES = {
    "office_room/v001": ROOM_TYPES / "office_room/v001/办公室房间种类_开放办公_30x40m_v001.blend",
    "bridge_room/v002": ROOM_TYPES / "bridge_room/v002/通道桥房间种类_工字型_30x60m_v002.blend",
}

# ---------------------------------------------------------------- 布局方案
plan = json.loads(LAYOUT.read_text(encoding="utf-8"))
instances = plan["instances"]
HALF = plan["dimensions_m"][0] / 2.0
WALL_H = plan["wall_height_m"]
print("[布局] 房型 %s  %.1f×%.1f m  实例 %d"
      % (plan["room_type_id"], plan["dimensions_m"][0], plan["dimensions_m"][1], len(instances)))

# ---------------------------------------------------------------- 场景骨架
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1

root = bpy.data.collections.new("标准房间_四墙平房_v001")
scene.collection.children.link(root)
inst_coll = bpy.data.collections.new("ROOM_LAYOUT_INSTANCES")
root.children.link(inst_coll)
helpers = bpy.data.collections.new("90_展示与验收_灯光相机")
root.children.link(helpers)

# ---------------------------------------------------------------- Library Link
# 只 link 用到的资产包 Collection。⚠️ 不要把被链接的集合本体挂进 scene.collection.children
# （否则房间里会同时出现「布局实例」与「组件库散件」两套，见 skill 03 约束 8）。
needed = sorted({(it["source_room_type"], it["collection"]) for it in instances})
print("[Link] 需要链接的资产包 Collection：%d 个" % len(needed))
loaded = {}          # (src, collection) -> library datablock
for src, coll_name in needed:
    lib_path = SOURCES[src]
    before = set(bpy.data.collections.keys())
    with bpy.data.libraries.load(str(lib_path), link=True) as (data_from, data_to):
        if coll_name not in data_from.collections:
            raise RuntimeError("源 blend 里找不到资产包 Collection：%s @ %s" % (coll_name, lib_path.name))
        data_to.collections = [coll_name]
    got = bpy.data.collections.get(coll_name)
    if got is None:
        raise RuntimeError("链接后取不到 Collection：%s" % coll_name)
    if got.library is None:
        raise RuntimeError("Collection 未被链接（疑似本地重名覆盖）：%s" % coll_name)
    loaded[(src, coll_name)] = got

# 断言：每个被链接包的 instance_offset 必须是 0（skill 03 约束 14）
bad_offset = [(n, tuple(c.instance_offset)) for n, c in
              [((s, n), c) for (s, n), c in loaded.items()] if any(abs(v) > 1e-9 for v in c.instance_offset)]
if bad_offset:
    raise RuntimeError("被链接 Collection 的 instance_offset 非零：%s" % bad_offset)

# 🔴 组件根原点只能读 `matrix_basis`（= loc/rot/scale），**不能读 `matrix_world`**：
#    被 link 进来、又没挂进场景树的集合，其对象的 matrix_world 在本次会话里恒为单位阵
#    （实测 `view_layer.update()` 也救不回来 —— 不在场景里的对象不参与依赖图求值）。
#    读 matrix_world 会把每件原点读成 (0,0,0)，于是每件都错位一个原点，且断言静默通过。
PIVOT = {}
for key, coll in loaded.items():
    locs = set()
    for ob in coll.objects:
        if ob.parent is not None:
            raise RuntimeError("组件包内对象有父级，matrix_basis 不再等于世界变换：%s / %s"
                               % (key[1], ob.name))
        mb = ob.matrix_basis
        locs.add(tuple(round(v, 6) for v in mb.translation))
        rot = mb.to_euler()
        if max(abs(v) for v in rot) > 1e-6 or any(abs(s - 1.0) > 1e-6 for s in mb.to_scale()):
            raise RuntimeError("组件包内对象带旋转/缩放，根原点不唯一：%s / %s" % (key[1], ob.name))
    if len(locs) != 1:
        raise RuntimeError("组件包内对象原点不一致：%s -> %s" % (key[1], sorted(locs)))
    PIVOT[key] = Vector(next(iter(locs)))

# 与两批源的 component_inventory.json 交叉核对根原点（真源对账，不信单一来源）
COLL2SLUG = {(it["source_room_type"], it["collection"]): it["slug"] for it in instances}
if len(COLL2SLUG) != len(needed):
    raise RuntimeError("同一资产包 Collection 对应了多个 slug，无法对账")
for src, rel_inv in (("office_room/v001", "office_room/v001/component_inventory.json"),
                     ("bridge_room/v002", "bridge_room/v002/component_inventory.json")):
    inv = json.loads((ROOM_TYPES / rel_inv).read_text(encoding="utf-8"))
    by_slug = {r["slug"]: r for r in inv}
    checked = 0
    for (s, coll_name) in [k for k in PIVOT if k[0] == src]:
        slug = COLL2SLUG[(s, coll_name)]
        rec = by_slug.get(slug)
        if rec is None:
            raise RuntimeError("清单里查不到组件：%s @ %s" % (slug, src))
        o = Vector(rec["world_origin_m"])
        if (PIVOT[(s, coll_name)] - o).length > 1e-6:
            raise RuntimeError("根原点与清单不符：%s @ %s  blend=%s json=%s"
                               % (slug, src, tuple(PIVOT[(s, coll_name)]), tuple(o)))
        checked += 1
    print("[对账] %s：%d 个包的原点与 component_inventory.json 逐值一致 ✓" % (src, checked))
print("[Link] 全部资产包 instance_offset=0，组件根原点唯一且与清单一致 ✓")

# ---------------------------------------------------------------- 摆实例
placed = []
for seq, it in enumerate(instances):
    key = (it["source_room_type"], it["collection"])
    coll = loaded[key]
    pivot = PIVOT[key]
    rz = math.radians(it["rotation_z_deg"])
    R = Matrix.Rotation(rz, 4, "Z")
    desired = Vector(it["position_m"])
    empty = bpy.data.objects.new("INST_%03d_%s" % (seq, it["instance_id"]), None)
    empty.empty_display_type = "PLAIN_AXES"
    empty.empty_display_size = 0.6
    empty.instance_type = "COLLECTION"
    empty.instance_collection = coll
    empty.location = desired - (R @ pivot)
    empty.rotation_euler = (0.0, 0.0, rz)
    empty.scale = (1.0, 1.0, 1.0)
    empty["instance_id"] = it["instance_id"]
    empty["component_slug"] = it["slug"]
    empty["component_id"] = it["component_id"]
    empty["component_collection"] = it["collection"]
    empty["source_room_type"] = it["source_room_type"]
    empty["slot_role"] = it["slot_role"]
    empty["layout_note"] = it["note"]
    inst_coll.objects.link(empty)
    placed.append(dict(instance_id=it["instance_id"], slug=it["slug"], role=it["slot_role"],
                       source=it["source_room_type"], collection=it["collection"],
                       position_m=[round(v, 4) for v in desired],
                       rotation_z_deg=it["rotation_z_deg"],
                       empty_location=[round(v, 4) for v in empty.location]))

print("[摆位] %d 个集合实例已建" % len(placed))

# 落点复核：用**渲染实际采用的变换**（empty.matrix_world @ ob.matrix_world）反算，
# 断言组件根原点确实落在 desired（不是只信 location 自洽）。
bpy.context.view_layer.update()
bad = []
for seq, it in enumerate(instances):
    e = bpy.data.objects["INST_%03d_%s" % (seq, it["instance_id"])]
    key = (it["source_room_type"], it["collection"])
    rendered = e.matrix_world @ Matrix.Translation(PIVOT[key])
    d = (rendered.translation - Vector(it["position_m"])).length
    if d > 5e-4:
        bad.append((it["instance_id"], round(d, 4),
                    [round(v, 4) for v in e.location],
                    [round(v, 4) for v in e.matrix_world.translation],
                    [round(v, 4) for v in Vector(it["position_m"])]))
if bad:
    raise RuntimeError("实例落点复核失败（%d 件）：%s" % (len(bad), bad[:6]))

# ---------------------------------------------------------------- 验收相机 / 灯光
world = bpy.data.worlds.new("冷蓝灰展示环境")
scene.world = world
world.use_nodes = True
world.node_tree.nodes.clear()
bg = world.node_tree.nodes.new("ShaderNodeBackground")
wo = world.node_tree.nodes.new("ShaderNodeOutputWorld")
world.node_tree.links.new(bg.outputs["Background"], wo.inputs["Surface"])
bg.inputs["Color"].default_value = (0.075, 0.115, 0.185, 1)
bg.inputs["Strength"].default_value = 0.38


def lamp(name, loc, energy, kind="AREA", size=14.0):
    d = bpy.data.lights.new(name, kind)
    d.energy = energy
    if kind == "AREA":
        d.size = size
    ob = bpy.data.objects.new(name, d)
    ob.location = loc
    helpers.objects.link(ob)
    return ob


k = lamp("KEY", (14.0, -14.0, 18.0), 9000.0)
k.rotation_euler = (math.radians(38), 0.0, math.radians(45))
f = lamp("FILL", (-16.0, 12.0, 12.0), 3500.0)
f.rotation_euler = (math.radians(52), 0.0, math.radians(-140))
t = lamp("TOP", (0.0, 0.0, 22.0), 2600.0)
t.rotation_euler = (0.0, 0.0, 0.0)

cam_data = bpy.data.cameras.new("验收相机")
cam_data.lens = 24.0
cam = bpy.data.objects.new("验收相机", cam_data)
helpers.objects.link(cam)
scene.camera = cam


def look(frm, at):
    """相机摆位一律用「相机位置 -> 注视点」，不用方位角/俯仰角 ——
    方位角那套极易把相机放到墙外正对墙面（实测机位 03 渲出一张全黑）。"""
    cam.location = Vector(frm)
    d = Vector(at) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


# ---------------------------------------------------------------- 保存
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / BLEND_NAME))
print("[保存]", OUT / BLEND_NAME)

# ---------------------------------------------------------------- 渲染（可选）
if not NO_RENDER:
    RENDER.mkdir(exist_ok=True)
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 40
    scene.cycles.use_denoising = True
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type != "CPU"
        if any(d.use for d in prefs.devices):
            scene.cycles.device = "GPU"
    except Exception as exc:
        print("[渲染] GPU 不可用，退回 CPU：", exc)
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 1200
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = -0.25

    # (tag, 相机位置, 注视点, 焦距, 渲染时临时隐藏的 slot_role 集合)
    VIEWS = [
        ("01_top", (0.6, -0.6, 34.0), (0.0, 0.0, 0.0), 22.0, set()),
        ("02_cutaway_nw", (-26.0, 26.0, 22.0), (0.0, 0.0, 3.0), 24.0, set()),
        ("03_corridor_west_in", (-11.4, 0.0, 2.4), (11.0, 0.0, 1.7), 26.0, set()),
        ("04_south_mech_from_north", (0.0, 10.6, 5.4), (0.0, -7.0, 1.6), 24.0, set()),
        ("05_north_office_from_south", (0.0, -10.6, 5.4), (0.0, 7.0, 1.6), 24.0, set()),
        # 隐藏外壳后的内部剖视：看陈设层次（只改渲染可见性，源文件四墙完好）
        ("06_interior_no_shell", (-22.0, 22.0, 25.0), (0.0, 0.0, 2.0), 26.0,
         {"solid_wall", "door_wall"}),
    ]
    for tag, frm, at, lens, hide_roles in VIEWS:
        for ob in inst_coll.objects:
            ob.hide_render = ob.get("slot_role") in hide_roles
        cam_data.lens = lens
        look(frm, at)
        scene.render.filepath = str(RENDER / ("std25_%s.png" % tag))
        bpy.ops.render.render(write_still=True)
        print("[渲染]", scene.render.filepath)
    for ob in inst_coll.objects:
        ob.hide_render = False

# ---------------------------------------------------------------- 交付记录
(OUT / "layout_build_report.json").write_text(json.dumps(dict(
    schema="shellstorm2.room_type_layout_build_report",
    schema_version=1,
    room_type_id=plan["room_type_id"],
    blend=BLEND_NAME,
    instances=len(placed),
    linked_packages=len(needed),
    components_created=0,
    appended_meshes=0,
    non_unit_scale=0,
    print="Library Link + Collection Instance；无 Append、无新建 Mesh、无缩放",
    placements=placed,
), ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\r\n")
print("[记录] layout_build_report.json")
print("DONE")
