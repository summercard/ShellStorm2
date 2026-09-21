"""Build the 100F rooftop decorated layout from linked v002 component collections.

This file owns placement only. It must not create or copy component meshes.
Run with Blender 4.5 background mode.
"""
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector

PROJECT = Path(__file__).resolve().parents[6]
ROOFTOP = PROJECT / "assets/art/environments/tower_zones/rooftop"
LIBRARY = ROOFTOP / "source/reference_components/v002/天台区块_参考组件库_v002.blend"
OUT_DIR = ROOFTOP / "source/layouts/100f_decorated_v001"
OUT_BLEND = OUT_DIR / "rooftop_100f_decorated_layout_v001.blend"
OUT_MANIFEST = OUT_DIR / "rooftop_100f_decorated_layout_v001.json"

OUT_DIR.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.name = "100F天台_组件装饰布局_v001"
scene.unit_settings.system = "METRIC"
scene.unit_settings.length_unit = "METERS"

# Collections are linked from the frozen component source. No mesh is appended.
component_names = {
    "floor_full": "完整地砖_资产包",
    "parapet": "女儿墙直段_资产包",
    "parapet_outer": "女儿墙外角_资产包",
    "room_wall": "房间标准墙_资产包",
    "room_window": "房间窗墙_资产包",
    "room_doorwall": "房间门洞墙_资产包",
    "roof_full": "房顶完整板_资产包",
    "roof_edge": "房顶边缘板_资产包",
    "roof_corner": "房顶角板_资产包",
    "hvac_small": "小型空调机组_资产包",
    "hvac_large": "大型空调机组_资产包",
    "hvac_vent": "小通风口_资产包",
    "flowerbox": "长条花箱_资产包",
    "plant_large": "大盆栽_资产包",
    "plant_small": "小盆栽_资产包",
    "ivy": "墙面攀爬藤蔓_资产包",
    "pipe_straight": "直管段_资产包",
    "pipe_elbow": "转角弯管_资产包",
    "pipe_tee": "三通管_资产包",
    "pipe_riser": "立管下水管_资产包",
    "pipe_bracket": "管道支架_资产包",
}
with bpy.data.libraries.load(str(LIBRARY), link=True) as (data_from, data_to):
    data_to.collections = list(component_names.values())

missing = [name for name in component_names.values() if bpy.data.collections.get(name) is None]
if missing:
    raise RuntimeError("Missing linked component collections: " + ", ".join(missing))

root = bpy.data.collections.new("100F天台_装饰布局_v001")
scene.collection.children.link(root)
instances = bpy.data.collections.new("ROOFTOP_LAYOUT_INSTANCES")
root.children.link(instances)
helpers = bpy.data.collections.new("90_展示与验收_相机灯光")
root.children.link(helpers)

placements = []
instance_seq = 0

def add(slug, x, y, z=0.3, angle=0.0, group="decor", note="", connection=None):
    global instance_seq
    collection_name = component_names[slug]
    empty = bpy.data.objects.new(f"INST_{instance_seq:03}_{slug}", None)
    empty.instance_type = "COLLECTION"
    empty.instance_collection = bpy.data.collections[collection_name]
    empty.location = (x, y, z)
    empty.rotation_euler = (0.0, 0.0, angle)
    empty.scale = (1.0, 1.0, 1.0)
    empty["component_slug"] = slug
    empty["component_collection"] = collection_name
    empty["layout_group"] = group
    empty["collision_policy"] = "visual_only"
    empty["source_blend"] = str(LIBRARY.relative_to(PROJECT)).replace("\\", "/")
    if note:
        empty["design_note"] = note
    if connection:
        empty["connection_id"] = connection
    instances.objects.link(empty)
    record = {
        "instance_id": empty.name,
        "component_slug": slug,
        "component_collection": collection_name,
        "group": group,
        "position_m": [round(float(x), 4), round(float(y), 4), round(float(z), 4)],
        "rotation_y_deg": round(math.degrees(angle), 4),
        "scale": [1.0, 1.0, 1.0],
        "enabled": True,
        "collision_policy": "visual_only",
    }
    if note:
        record["design_note"] = note
    if connection:
        record["connection_id"] = connection
    placements.append(record)
    instance_seq += 1
    return empty

# 90m x 80m runtime footprint: center (-5, 5), 18 x 16 five-metre tiles.
for row in range(16):
    y = -32.5 + row * 5.0
    for col in range(18):
        x = -47.5 + col * 5.0
        in_base_atrium = -15.0 <= x < 15.0 and -10.0 <= y < 20.0
        in_west_stair = -45.0 <= x < -30.0 and 0.0 <= y < 30.0
        if in_base_atrium or in_west_stair:
            continue
        add("floor_full", x, y, z=0.0, group="rooftop_base", note="100F 18x16地砖；已扣36格中庭与18格西侧楼梯口")

# 68-piece 0.80m parapet perimeter. The west side keeps the stairs/entry clearance.
for col in range(17):
    x = -45.0 + col * 5.0
    add("parapet", x, -34.75, z=0.0, angle=0.0, group="rooftop_edge", note="南侧女儿墙，贴运行时边界")
    add("parapet", x, 44.75, z=0.0, angle=math.pi, group="rooftop_edge", note="北侧女儿墙，贴运行时边界")
for row in range(15):
    y = -30.0 + row * 5.0
    add("parapet", 39.75, y, z=0.0, angle=math.pi / 2, group="rooftop_edge", note="东侧女儿墙，贴运行时边界")
    add("parapet", -49.75, y, z=0.0, angle=-math.pi / 2, group="rooftop_edge", note="西侧女儿墙，贴运行时边界")
# Four 2.5m outer corner modules complete the 68-module perimeter.
for x, y, angle in [(-48.75, 43.75, 0.0), (38.75, 43.75, math.pi / 2), (38.75, -33.75, math.pi), (-48.75, -33.75, -math.pi / 2)]:
    add("parapet_outer", x, y, z=0.0, angle=angle, group="rooftop_edge", note="天台外围转角")

# Existing 20m x 20m rooftop house, assembled only from shared room/roof components.
for col in range(4):
    x = -7.5 + col * 5.0
    add("room_doorwall" if col == 3 else ("room_window" if col == 1 else "room_wall"), x, -8.0, group="house_shell", note="房屋南立面")
    add("room_window" if col in (1, 2) else "room_wall", -x, 12.0, angle=math.pi, group="house_shell", note="房屋北立面")
    for side in (-1, 1):
        add("room_window" if col == 2 else "room_wall", side * 10.0, -5.5 + col * 5.0, angle=side * math.pi / 2, group="house_shell", note="房屋侧立面")
for row in range(4):
    for col in range(4):
        x = -7.5 + col * 5.0
        y = -5.5 + row * 5.0
        if row in (0, 3) and col in (0, 3):
            slug = "roof_corner"
            angle = {(0, 0): 0.0, (0, 3): math.pi / 2, (3, 3): math.pi, (3, 0): -math.pi / 2}[(row, col)]
        elif row in (0, 3) or col in (0, 3):
            slug = "roof_edge"
            angle = 0.0 if row == 0 else math.pi if row == 3 else math.pi / 2 if col == 3 else -math.pi / 2
        else:
            slug = "roof_full"
            angle = 0.0
        add(slug, x, y, z=12.0, angle=angle, group="house_roof", note="房屋24m封顶")

# Wall-mounted HVAC: four small units, outside the wall face, leaving the door bay clear.
add("hvac_small", -5.0, -9.25, z=5.2, group="hvac_wall", note="南墙挂式空调，避开门洞")
add("hvac_small", 0.5, -9.25, z=5.2, group="hvac_wall", note="南墙挂式空调，避开门洞")
add("hvac_small", 10.55, -2.0, z=4.9, angle=math.pi / 2, group="hvac_wall", note="东墙挂式空调")
add("hvac_small", -10.55, 4.0, z=4.9, angle=-math.pi / 2, group="hvac_wall", note="西墙挂式空调")
add("hvac_vent", -7.4, -9.22, z=8.0, group="hvac_wall", note="南墙辅助通风口")
add("hvac_vent", 10.52, 6.0, z=7.8, angle=math.pi / 2, group="hvac_wall", note="东墙辅助通风口")

# Long flower boxes make a green perimeter around the house without blocking the door or stair gap.
for x in (-7.0, -1.0):
    add("flowerbox", x, -10.15, z=0.3, group="greenery", note="南侧连续花圃")
for x in (-7.0, -1.0):
    add("flowerbox", x, 14.15, z=0.3, angle=math.pi, group="greenery", note="北侧连续花圃")
add("flowerbox", -12.15, -3.0, z=0.3, angle=math.pi / 2, group="greenery", note="西侧花圃")
add("flowerbox", 12.15, 7.0, z=0.3, angle=math.pi / 2, group="greenery", note="东侧花圃")
for x, y in [(-13.5, -10.4), (5.7, -10.3), (-13.5, 14.4), (5.7, 14.4), (-13.0, 7.0), (13.0, -4.0)]:
    add("plant_large", x, y, z=0.3, group="greenery", note="花圃边缘高层植物")
for x, y in [(-10.8, -10.3), (3.4, -10.3), (-10.8, 14.3), (3.4, 14.3), (-13.1, 0.0), (13.1, 2.0)]:
    add("plant_small", x, y, z=0.3, group="greenery", note="花圃边缘低层植物")

# Generic vine patches are foliage-only and do not duplicate wall geometry.
for x in (-8.0, -3.0, 2.0):
    add("ivy", x, -8.22, z=0.35, group="ivy", note="南墙局部藤蔓")
for x in (-7.0, -1.5, 4.0):
    add("ivy", x, 12.22, z=0.35, angle=math.pi, group="ivy", note="北墙局部藤蔓")
for y in (-5.0, 1.0, 7.0):
    add("ivy", 10.22, y, z=0.35, angle=math.pi / 2, group="ivy", note="东墙局部藤蔓")
for y in (-2.5, 4.0):
    add("ivy", -10.22, y, z=0.35, angle=-math.pi / 2, group="ivy", note="西墙局部藤蔓")

# Water pipe loop: each straight run uses 2.5m socket spacing, plus corner elbows.
# The loop sits high on the wall, with four risers and two branch tees.
pipe_z = 10.65
pipe_y_south = -8.42
pipe_y_north = 12.42
pipe_x_west = -10.42
pipe_x_east = 10.42
for i in range(8):
    add("pipe_straight", -8.75 + i * 2.5, pipe_y_south, z=pipe_z, group="pipe_loop", note="南墙连续水管", connection="PIPE_LOOP_SOUTH")
for i in range(8):
    add("pipe_straight", pipe_x_east, -6.75 + i * 2.5, z=pipe_z, angle=math.pi / 2, group="pipe_loop", note="东墙连续水管", connection="PIPE_LOOP_EAST")
for i in range(8):
    add("pipe_straight", 8.75 - i * 2.5, pipe_y_north, z=pipe_z, angle=math.pi, group="pipe_loop", note="北墙连续水管", connection="PIPE_LOOP_NORTH")
for i in range(8):
    add("pipe_straight", pipe_x_west, 10.75 - i * 2.5, z=pipe_z, angle=-math.pi / 2, group="pipe_loop", note="西墙连续水管", connection="PIPE_LOOP_WEST")
for x, y, angle in [(10.15, -8.15, 0.0), (10.15, 12.15, math.pi / 2), (-10.15, 12.15, math.pi), (-10.15, -8.15, -math.pi / 2)]:
    add("pipe_elbow", x, y, z=pipe_z, angle=angle, group="pipe_loop", note="水管四角转接", connection="PIPE_LOOP_CORNER")
for x in (-7.5, 2.5):
    add("pipe_tee", x, pipe_y_south, z=pipe_z, group="pipe_loop", note="南墙花圃灌溉分支", connection="PIPE_LOOP_BRANCH")
for x, y in [(-7.5, -8.42), (2.5, -8.42), (10.42, -2.0), (-10.42, 4.0)]:
    add("pipe_riser", x, y, z=5.8, angle=0.0, group="pipe_risers", note="从地面接入墙上环管，顶端接10.65m环管", connection="PIPE_RISER")
for x, y, angle in [(-7.5, -8.42, 0.0), (2.5, -8.42, 0.0), (10.42, -2.0, math.pi / 2), (-10.42, 4.0, -math.pi / 2)]:
    add("pipe_bracket", x, y, z=7.0, angle=angle, group="pipe_risers", note="立管墙面固定支架", connection="PIPE_RISER")

# Display setup. These objects are not part of the layout manifest.
def track(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()

world = bpy.data.worlds.new("100F天台_展示世界")
world.use_nodes = True
world_nodes = world.node_tree.nodes
world_nodes.clear()
out_node = world_nodes.new("ShaderNodeOutputWorld")
bg_node = world_nodes.new("ShaderNodeBackground")
bg_node.inputs["Color"].default_value = (0.16, 0.21, 0.28, 1)
bg_node.inputs["Strength"].default_value = 0.55
world.node_tree.links.new(bg_node.outputs["Background"], out_node.inputs["Surface"])
scene.world = world
for name, loc, energy, size, color in [
    ("主柔光", (-35, -45, 75), 50000, 42, (1.0, 0.92, 0.80)),
    ("冷色补光", (45, 20, 45), 28000, 32, (0.72, 0.84, 1.0)),
]:
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    ob = bpy.data.objects.new(name, data)
    helpers.objects.link(ob)
    ob.location = loc
    track(ob, (-5, 5, 4))
cam_data = bpy.data.cameras.new("100F天台_装饰总览相机")
cam = bpy.data.objects.new("100F天台_装饰总览相机", cam_data)
helpers.objects.link(cam)
cam.location = (72, -92, 72)
track(cam, (-5, 5, 3))
cam_data.type = "ORTHO"
cam_data.ortho_scale = 112
scene.camera = cam
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 1800
scene.render.resolution_y = 1400
scene.render.resolution_percentage = 60
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.view_settings.look = "AgX - Medium High Contrast"
scene.view_settings.exposure = 0.65

scene["asset_id"] = "ENV-ROOFTOP-100F-DECORATED-LAYOUT"
scene["layout_version"] = "v001"
scene["component_source_blend"] = str(LIBRARY.relative_to(PROJECT)).replace("\\", "/")
scene["room_owned_geometry"] = False
scene["instance_mode"] = "COLLECTION_INSTANCE"
scene["collision_policy"] = "visual_only"
scene["design_summary"] = "100F天台：墙挂空调、房屋周边花圃、墙面藤蔓、闭环水管"

manifest = {
    "schema": "shellstrom2.rooftop.decorated_layout",
    "schema_version": 1,
    "layout_id": "ENV-ROOFTOP-100F-DECORATED-LAYOUT",
    "layout_version": "v001",
    "floor": "100F",
    "block_id": "rooftop",
    "source_blend": str(OUT_BLEND.relative_to(PROJECT)).replace("\\", "/"),
    "component_library": str(LIBRARY.relative_to(PROJECT)).replace("\\", "/"),
    "dimensions_m": [90.0, 80.0],
    "world_rect_m": [-50.0, -35.0, 90.0, 80.0],
    "coordinate_contract": {"up_axis": "+Z", "horizontal_axes": ["+X", "+Y"], "rotation_axis": "+Z", "units": "meters"},
    "instances": placements,
    "design_intent": {
        "hvac_wall_mounts": 4,
        "hvac_vents": 2,
        "flowerboxes": 6,
        "large_plants": 6,
        "small_plants": 6,
        "ivy_patches": 11,
        "pipe_loop_straights": 32,
        "pipe_loop_elbows": 4,
        "pipe_branch_tees": 2,
        "pipe_risers": 4,
        "pipe_brackets": 4,
        "door_clearance_kept": True,
        "stair_clearance_kept": True,
    },
    "validation": {
        "room_owned_geometry": False,
        "collection_instance_only": True,
        "non_unit_scale_count": 0,
        "missing_components": [],
        "visual_only_collision_count": len(placements),
        "component_library_modified": False,
        "pipe_socket_spacing_m": 2.5,
        "pipe_diameter_m": 0.3,
    },
}

bpy.ops.wm.save_as_mainfile(filepath=str(OUT_BLEND), compress=True)
OUT_MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("ROOFTOP_DECOR_LAYOUT_V001_OK instances=%d blend=%s manifest=%s" % (len(placements), OUT_BLEND, OUT_MANIFEST), flush=True)
