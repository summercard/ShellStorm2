import math
import os
import sys

import bpy


args = sys.argv[sys.argv.index("--") + 1:]
output = os.path.abspath(args[0])
render_output = os.path.abspath(args[1]) if len(args) > 1 else None
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for collection in list(bpy.data.collections):
    bpy.data.collections.remove(collection)


def collection(name, parent):
    value = bpy.data.collections.new(name)
    parent.children.link(value)
    return value


def box(name, size, location, owner, material):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    for current in list(obj.users_collection):
        current.objects.unlink(obj)
    owner.objects.link(obj)
    return obj


mat = bpy.data.materials.new("白模_楼梯间结构")
mat.diffuse_color = (0.48, 0.58, 0.60, 1)
mat.roughness = 0.72

root = bpy.context.scene.collection
library = collection("00_组件库", root)
flight_library = collection("楼梯间直梯_母组件", library)
flight_library["asset_id"] = "ENV-TOWER-STAIR-FLIGHT-ADJUSTABLE"
flight_library["run_length"] = 15.0
flight_library["slope_deg"] = 21.8014
flight_library["rise_height"] = 6.0
flight_library["step_count"] = 20
for index in range(20):
    box(f"直梯_踏步_{index + 1:02d}", (6, .75, .3), (0, (index + .5) * .75, (index + .5) * .3), flight_library, mat)

package = collection("01_楼梯间_组件装配", root)
package["3dgame_component_package"] = True
package["assembly_rule"] = "single_flight_component_reused_second_rotated_180"
floors = collection("01_楼板", package)
walls = collection("02_墙壁", package)
stairs = collection("03_楼梯", package)

box("下层楼板_15x30_top_plus_0.1", (15, 30, .3), (0, 0, -.05), floors, mat)["asset_id"] = "ENV-TOWER-STAIR-FLOOR-LOWER"
box("中层楼板_15x6_z6", (15, 6, .3), (0, 6, 5.85), floors, mat)["asset_id"] = "ENV-TOWER-STAIR-FLOOR-MID"
box("上层楼板_15x6_z12", (15, 6, .3), (0, -9, 11.85), floors, mat)["asset_id"] = "ENV-TOWER-STAIR-FLOOR-UPPER"

box("墙壁_左", (.3, 30, 12.9), (-7.35, 0, 6.45), walls, mat)
box("墙壁_右", (.3, 30, 12.9), (7.35, 0, 6.45), walls, mat)
box("墙壁_前", (15, .3, 12.9), (0, -14.85, 6.45), walls, mat)
box("墙壁_后", (15, .3, 12.9), (0, 14.85, 6.45), walls, mat)

flight_a = bpy.data.objects.new("楼梯跑_A_母组件实例", None)
flight_a.instance_type = "COLLECTION"
flight_a.instance_collection = flight_library
flight_a.location = (-4, -12, 0)
flight_a["asset_id"] = "ENV-TOWER-STAIR-FLIGHT-ADJUSTABLE"
stairs.objects.link(flight_a)

flight_b = bpy.data.objects.new("楼梯跑_B_同组件旋转180", None)
flight_b.instance_type = "COLLECTION"
flight_b.instance_collection = flight_library
flight_b.location = (4, 9, 6)
flight_b.rotation_euler.z = math.pi
flight_b["asset_id"] = "ENV-TOWER-STAIR-FLIGHT-ADJUSTABLE"
stairs.objects.link(flight_b)

library.hide_viewport = True
library.hide_render = True

if render_output:
    def point_at(obj, target):
        direction = mathutils.Vector(target) - obj.location
        obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    import mathutils
    camera_data = bpy.data.cameras.new("验收相机")
    camera = bpy.data.objects.new("验收相机", camera_data)
    root.objects.link(camera)
    camera.location = (24, -31, 22)
    camera_data.lens = 48
    point_at(camera, (0, 0, 5.5))
    bpy.context.scene.camera = camera

    light_data = bpy.data.lights.new("验收主光", "AREA")
    light_data.energy = 1900
    light_data.shape = "DISK"
    light_data.size = 12
    light = bpy.data.objects.new("验收主光", light_data)
    root.objects.link(light)
    light.location = (8, -12, 24)
    point_at(light, (0, 0, 5))

    bpy.context.scene.world.color = (0.08, 0.08, 0.08)
    bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT"
    bpy.context.scene.render.resolution_x = 960
    bpy.context.scene.render.resolution_y = 720
    bpy.context.scene.render.resolution_percentage = 100
    bpy.context.scene.render.image_settings.file_format = "PNG"
    bpy.context.scene.render.filepath = render_output
    bpy.context.scene.render.film_transparent = False
    os.makedirs(os.path.dirname(render_output), exist_ok=True)
    walls.hide_render = True
    bpy.ops.render.render(write_still=True)
    walls.hide_render = False

bpy.context.scene["whitebox_structure"] = "stairwell_component_assembly_v014"
bpy.context.scene["runtime_reimported"] = False
bpy.context.scene.unit_settings.system = "METRIC"
bpy.context.scene.unit_settings.scale_length = 1.0
bpy.ops.wm.save_as_mainfile(filepath=output, check_existing=False)
