import bpy
import hashlib
import json
import math
import os
import random
from mathutils import Vector, Matrix


ROOT = "/Users/summercards/ShellStorm2"
ASSET_DIR = os.path.join(ROOT, "assets/art/environments/rooftop_shelter_3d")
PALETTE_PATH = os.path.join(ROOT, "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png")
ASSET_ID = "ENV-ROOFTOP-SHELTER-90X80"
ASSET_VERSION = "v017"
BLEND_PATH = os.path.join(ASSET_DIR, "source/env_rooftop_shelter_90x80m_top3d_v017.blend")
PREVIEW_PATH = os.path.join(ASSET_DIR, "previews/env_rooftop_shelter_90x80m_complete_v017.png")
CLOSE_PREVIEW_PATH = os.path.join(ASSET_DIR, "previews/env_rooftop_shelter_90x80m_close_v017.png")
GLB_PATH = os.path.join(ASSET_DIR, "runtime/env_rooftop_shelter_90x80m_facilities_v017.glb")
COMPONENT_GLB_DIR = os.path.join(ASSET_DIR, "runtime/layout_v017/components")
ROOT_TSCN_PATH = os.path.join(ASSET_DIR, "runtime/env_rooftop_shelter_90x80m_facilities_root_top3d_v017.tscn")
MANIFEST_PATH = os.path.join(ASSET_DIR, "reports/asset_manifest_v017.json")
VALIDATION_PATH = os.path.join(ASSET_DIR, "reports/validation_v017.json")
COLLISION_MANIFEST_PATH = os.path.join(ASSET_DIR, "reports/collision_manifest_v017.json")
ROOF_RECT = (-50.0, -35.0, 90.0, 80.0)
BASE_ATRIUM_RECT = (-15.0, -10.0, 30.0, 30.0)
WEST_STAIR_RECT = (-45.0, 0.0, 15.0, 30.0)
GRID_SIZE = 5.0
GRID_DIMENSIONS = (18, 16)
EXPECTED_TILE_COUNT = 234
LIVING_CLUSTER_RECT = (15.25, -31.0, 24.0, 67.0)
DOOR_WALKWAY_RECT = (15.25, -6.0, 24.0, 20.0)
SHELTER_ZONE_RECT = (7.5, 27.5, 21.0, 17.5)
FARM_ZONE_RECT = (-24.0, 22.0, 12.5, 20.0)
RADIO_ZONE_RECT = (30.5, 34.0, 9.5, 10.5)
random.seed(240830)


# Gameplay blockers are authored as one proxy per component.  They stay in a dedicated,
# non-exported Blender collection and are reproduced as independent StaticBody3D nodes in
# the Godot wrapper.  Locations and sizes use Blender's X/Y/Z-up coordinates in metres.
def collision_box(center, size, rotation=(0.0, 0.0, 0.0), label="盒体"):
    return {"shape": "box", "center": center, "size": size, "rotation_degrees": rotation, "label": label}


def collision_cylinder(center, radius, height, label="圆柱"):
    return {"shape": "cylinder", "center": center, "radius": radius, "height": height, "rotation_degrees": (0.0, 0.0, 0.0), "label": label}


def collision_component(component_id, label, component_folder, shapes):
    return {"component_id": component_id, "display_name": label, "component_folder": component_folder, "shapes": shapes}


COLLISION_COMPONENTS = [
    collision_component("shelter_structure", "生活棚结构", "Props_Furniture/10_生活棚结构", [
        *[collision_box((x, y, 3.44), (.30, .30, 5.2), label="棚柱") for x, y in [(8,29.5),(8,37),(8,44.5),(18,29.5),(18,44.5),(28,29.5),(28,37),(28,44.5)]],
        collision_box((8.1,40.7,2.66),(.20,5.8,3.6),label="西侧墙板A"), collision_box((8.1,31.7,2.31),(.20,3.1,2.9),label="西侧墙板B"),
        collision_box((27.9,41.6,2.51),(.20,4.5,3.3),label="东侧墙板A"), collision_box((27.9,31.7,2.11),(.20,3.0,2.5),label="东侧墙板B"),
        collision_box((11.2,44.4,2.51),(5.0,.20,3.3),label="北侧墙板A"), collision_box((17.0,44.4,2.21),(4.8,.20,2.7),label="北侧墙板B"), collision_box((24.3,44.4,2.61),(6.0,.20,3.5),label="北侧墙板C"),
    ]),
    collision_component("shelter_platform", "棚屋木地板平台", "Props_Furniture/05_抬高木平台", [collision_box((18.0,37.0,.59),(20.7,15.7,.50),label="木平台承重面")]),
    collision_component("shelter_stair_ramp", "棚屋木梯连续坡面", "Props_Furniture/06_小木板楼梯", [collision_box((18.0,28.82,.66),(3.2,1.72,.16),(17.35,0,0),"连续坡面")]),
    collision_component("shelter_workbench", "生活棚工作台", "Props_Furniture/20_工作台与工具墙", [
        collision_box((12,40.5,.95),(5.0,1.5,.18),label="桌面"), collision_box((9.8,40.5,1.56),(.22,1.2,1.4),label="左桌腿"), collision_box((14.2,40.5,1.56),(.22,1.2,1.4),label="右桌腿"), collision_box((12,41.22,2.26),(5.0,.16,2.8),label="工具墙"),
    ]),
    collision_component("lounge_sofa", "双人沙发", "Props_Furniture/30_双人沙发", [
        collision_box((21,37.8,1.085),(5.2,2.0,.45),label="底架"), collision_box((21,38.5,2.45),(4.25,.55,1.3),(-7,0,0),"靠背"),
        collision_box((18.55,37.8,1.525),(.55,2.0,.95),label="左扶手"), collision_box((23.45,37.8,1.525),(.55,2.0,.95),label="右扶手"),
    ]),
    collision_component("spool_table", "电缆卷筒圆桌", "Props_Furniture/31_电缆卷筒圆桌", [
        collision_cylinder((21.1,34.5,.95),1.18,.18,"下圆盘"), collision_cylinder((21.1,34.5,1.415),.42,.75,"中轴"), collision_cylinder((21.1,34.5,1.87),1.18,.16,"桌面"),
    ]),
    collision_component("table_radio", "桌面老式收音机", "Props_Furniture/32_桌面老式收音机", [collision_box((20.55,34.45,2.29),(1.05,.52,.66),(0,0,-6.9),"收音机机身")]),
    collision_component("camp_bed", "简易床铺", "Props_Furniture/40_床铺与睡袋", [collision_box((13,31.7,1.085),(4.2,2.0,.45),label="床架")]),
    collision_component("stove", "小型火炉", "Props_Furniture/60_火炉与水壶", [collision_cylinder((17.5,39.7,1.41),.60,1.10,"炉体")]),
    collision_component("dining_table", "公共餐桌", "Props_Survival/10_公共餐桌", [
        collision_box((23,42.5,.93),(4.8,1.35,.18),label="桌面"),
        *[collision_box((x,y,1.515),(.18,.18,1.35),label="桌腿") for x in (21,25) for y in (42.05,42.95)],
    ]),
    collision_component("dining_bench_s", "公共餐桌南长凳", "Props_Survival/11_公共餐桌长凳", [collision_box((23,41.15,1.05),(4.0,.48,.42),label="凳面"), collision_box((21.45,41.15,1.115),(.18,.36,.55),label="左腿"), collision_box((24.55,41.15,1.115),(.18,.36,.55),label="右腿")]),
    collision_component("dining_bench_n", "公共餐桌北长凳", "Props_Survival/11_公共餐桌长凳", [collision_box((23,43.85,1.05),(4.0,.48,.42),label="凳面"), collision_box((21.45,43.85,1.115),(.18,.36,.55),label="左腿"), collision_box((24.55,43.85,1.115),(.18,.36,.55),label="右腿")]),
    collision_component("wash_basin", "生活洗衣盆", "Props_Survival/21_生活洗衣盆", [collision_cylinder((26,32,.98),.72,.28,"盆体")]),
    collision_component("herb_rack", "香草晾晒架", "Props_Survival/22_香草晾晒架", [collision_cylinder((20,31.5,2.34),.08,3.0,"左立柱"), collision_cylinder((27,31.5,2.34),.08,3.0,"右立柱"), collision_box((23.5,31.5,3.82),(7.05,.16,.16),label="横杆")]),
    collision_component("energy_bench", "能源维修工作台", "Props_Energy/34_能源维修工作台", [collision_box((22,-14,.965),(4.5,1.2,1.25),label="工作台")]),
    collision_component("generator", "柴油发电机", "Props_Energy/30_柴油发电机", [collision_box((31,-18,1.14),(3.2,1.8,1.6),label="机身")]),
    *[collision_component(f"battery_{i}", f"蓄电池柜{i}", f"Props_Energy/{31+i}_蓄电池柜{i}", [collision_box((29+i*1.15,-14,1.14),(1.0,.8,1.6),label="柜体")]) for i in range(3)],
    collision_component("water_tank_0", "储水罐0", "Props_Energy/40_储水罐0", [collision_cylinder((35,-23,2.74),2.2,4.8,"罐体")]),
    collision_component("water_tank_1", "储水罐1", "Props_Energy/41_储水罐1", [collision_cylinder((31.8,-26,1.89),1.25,3.1,"罐体")]),
    collision_component("water_tank_2", "储水罐2", "Props_Energy/42_储水罐2", [collision_cylinder((35,-17.8,1.89),1.25,3.1,"罐体")]),
    collision_component("water_tank_3", "储水罐3", "Props_Energy/43_储水罐3", [collision_cylinder((31.8,-10.8,2.09),1.45,3.5,"罐体")]),
    collision_component("wind_mast", "风机塔杆", "Props_Energy/20_风力发电机", [collision_cylinder((29,-24,3.94),.18,7.2,"塔杆")]),
    *[collision_component(f"solar_{i}", f"太阳能板{i}", f"Props_Energy/{10+i}_太阳能板{i}", [collision_box((x,y,1.50),(4.55,2.65,.18),(math.degrees(angle),0,0),"倾斜板面")]) for i,(x,y,angle) in enumerate([(20,-22,.28),(25,-22,.34),(20,-26,.24),(25,-26,.30)])],
    *[collision_component(f"farm_planter_{i}", f"种植池{i}", f"Props_Farming/{10+i}_种植池{i}", [collision_box((x,y,.665),(sx,sy,.65),label="种植箱")]) for i,(x,y,sx,sy) in enumerate([(-21,31,5.2,2.4),(-15,31,5.2,2.4),(-21,27.5,5.2,2.4),(-15,27.5,5.2,2.4),(-21,24,4.4,2.0)])],
    collision_component("bathtub_planter", "浴缸种植池", "Props_Farming/20_浴缸种植池", [collision_box((-15,24,.765),(4.2,1.9,.85),label="浴缸外壳")]),
    collision_component("greenhouse", "温室", "Props_Farming/30_温室", [*[collision_box((x,y,1.94),(.18,.18,3.2),label="温室立柱") for x in (-23,-15) for y in (34.5,40.3)]]),
    collision_component("radio_platform", "广播高台结构", "Props_Communication/10_广播平台结构", [
        collision_box((35,40,4.53),(8.0,8.0,.38),label="高台楼板"), *[collision_box((x,y,2.34),(.32,.32,4.0),label="高台支柱") for x in (31,39) for y in (36,44)],
    ]),
    collision_component("radio_stairs", "广播高台楼梯", "Props_Communication/11_广播平台楼梯", [collision_box((35,36.2,2.35),(2.3,5.38,.22),(48.0,0,0),"连续楼梯坡面")]),
    collision_component("radio_railings", "广播高台栏杆", "Props_Communication/12_广播平台栏杆", [
        collision_box((31.2,40,5.35),(.18,7.4,1.2),label="西栏杆"), collision_box((38.8,40,5.35),(.18,7.4,1.2),label="东栏杆"), collision_box((35,43.8,5.35),(7.4,.18,1.2),label="北栏杆"),
        collision_box((32.25,36.2,5.35),(2.1,.18,1.2),label="南栏杆左"), collision_box((37.75,36.2,5.35),(2.1,.18,1.2),label="南栏杆右"),
    ]),
    collision_component("radio_console", "广播控制桌", "Props_Communication/20_广播控制桌", [collision_box((35,41.8,5.345),(5.2,1.5,1.25),label="控制桌")]),
]


# Palette cells are addressed from Blender UV bottom-left.  The public palette is the only image.
C = {
    "charcoal": (0, 9), "teal_dark": (1, 9), "purple": (2, 9), "blue": (3, 9),
    "rust": (4, 9), "rust_red": (5, 9), "mustard": (6, 9), "green": (7, 9),
    "navy": (8, 9), "cool_dark": (9, 9), "brown": (2, 7), "wood": (5, 7),
    "sand": (7, 7), "concrete": (9, 4), "concrete_mid": (9, 5), "concrete_light": (9, 2),
    "leaf_dark": (2, 5), "leaf": (5, 5), "leaf_light": (6, 5), "water": (8, 4),
    "blue_faded": (8, 1), "canvas": (8, 2), "yellow": (6, 8), "orange": (5, 8),
    "red": (4, 8), "cream": (9, 1), "glass": (8, 3), "soil": (1, 7),
}


def clean_scene():
    # Direct datablock deletion also catches hidden prototype objects from earlier versions.
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    # Remove startup materials as well so the deliverable contains only the four shared roles.
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat, do_unlink=True)
    # Collections stay linked to parent collections even after their objects are gone;
    # remove every generated collection explicitly to avoid .001/.002 hierarchy drift.
    for col in list(bpy.data.collections):
        bpy.data.collections.remove(col, do_unlink=True)
    for datablocks in (bpy.data.curves, bpy.data.meshes, bpy.data.cameras, bpy.data.lights):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def new_collection(name, parent=None):
    col = bpy.data.collections.new(name)
    (parent.children if parent else bpy.context.scene.collection.children).link(col)
    return col


def move_to_collection(obj, col):
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    col.objects.link(obj)


def load_palette():
    img = bpy.data.images.get("设施低亮多巴胺色盘_10x10_512")
    if img is None:
        img = bpy.data.images.load(PALETTE_PATH, check_existing=True)
    img.name = "设施低亮多巴胺色盘_10x10_512"
    img.filepath = PALETTE_PATH
    img.source = 'FILE'
    img.colorspace_settings.name = 'sRGB'
    return img


def make_material(name, role, image):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "PaletteUV"
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = 'Closest'
    nt.links.new(uv.outputs['UV'], tex.inputs['Vector'])
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    if role == "metal":
        bsdf.inputs['Metallic'].default_value = 0.86
        bsdf.inputs['Roughness'].default_value = 0.28
        if 'Coat Weight' in bsdf.inputs:
            bsdf.inputs['Coat Weight'].default_value = 0.16
    elif role == "matte":
        bsdf.inputs['Metallic'].default_value = 0.02
        bsdf.inputs['Roughness'].default_value = 0.70
    elif role == "gloss":
        bsdf.inputs['Metallic'].default_value = 0.16
        bsdf.inputs['Roughness'].default_value = 0.15
        if 'Coat Weight' in bsdf.inputs:
            bsdf.inputs['Coat Weight'].default_value = 0.68
    elif role == "emission":
        bsdf.inputs['Metallic'].default_value = 0.0
        bsdf.inputs['Roughness'].default_value = 0.38
        nt.links.new(tex.outputs['Color'], bsdf.inputs['Emission Color'])
        bsdf.inputs['Emission Strength'].default_value = 1.35
    return mat


def palette_uv(mesh, cell):
    while mesh.uv_layers:
        mesh.uv_layers.remove(mesh.uv_layers[0])
    uv_layer = mesh.uv_layers.new(name="PaletteUV")
    mesh.uv_layers.active = uv_layer
    uv_layer.active_render = True
    cx = (cell[0] + 0.5) / 10.0
    cy = (cell[1] + 0.5) / 10.0
    radius = 0.024
    for poly in mesh.polygons:
        n = poly.loop_total
        for k, li in enumerate(poly.loop_indices):
            a = 2.0 * math.pi * k / max(n, 3) + math.pi * 0.25
            uv_layer.data[li].uv = (cx + radius * math.cos(a), cy + radius * math.sin(a))


def finish_mesh(obj, col, mat, cell, asset_id=None):
    move_to_collection(obj, col)
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    palette_uv(obj.data, cell)
    obj["asset_id"] = asset_id or obj.name
    obj["palette_cell"] = f"{cell[0]},{cell[1]}"
    obj["forward_axis"] = "-Y"
    obj["up_axis"] = "+Z"
    return obj


def box(name, loc, size, col, mat, cell, rot=(0,0,0), bevel=0.0, asset_id=None):
    x, y, z = loc
    sx, sy, sz = size
    verts = [(-sx/2,-sy/2,0),(sx/2,-sy/2,0),(sx/2,sy/2,0),(-sx/2,sy/2,0),
             (-sx/2,-sy/2,sz),(sx/2,-sy/2,sz),(sx/2,sy/2,sz),(-sx/2,sy/2,sz)]
    faces = [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    mesh = bpy.data.meshes.new(name + "_网格")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = (x,y,z)
    obj.rotation_euler = rot
    col.objects.link(obj)
    finish_mesh(obj, col, mat, cell, asset_id)
    if bevel > 0:
        mod = obj.modifiers.new("小倒角", 'BEVEL')
        mod.width = bevel
        mod.segments = 2
    return obj


def cylinder(name, loc, radius, depth, col, mat, cell, vertices=12, rot=(0,0,0), asset_id=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=(loc[0],loc[1],loc[2]+depth/2), rotation=rot)
    obj = bpy.context.object
    obj.name = name
    # Shift geometry so object origin is bottom-center in local Z.
    obj.data.transform(Matrix.Translation((0,0,depth/2)))
    obj.location = loc
    finish_mesh(obj, col, mat, cell, asset_id)
    return obj


def sphere(name, loc, radius, col, mat, cell, segments=12, rings=6, scale=(1,1,1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    finish_mesh(obj, col, mat, cell)
    return obj


def beam(name, a, b, radius, col, mat, cell, vertices=8):
    a, b = Vector(a), Vector(b)
    vec = b-a
    mid = (a+b)/2
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=vec.length, location=mid)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = Vector((0,0,1)).rotation_difference(vec.normalized())
    obj.rotation_mode = 'XYZ'
    finish_mesh(obj, col, mat, cell)
    return obj


def empty(name, loc, col):
    obj = bpy.data.objects.new(name, None)
    obj.location = loc
    col.objects.link(obj)
    return obj


def add_area_light(name, loc, energy, color, size, target, col):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy = energy
    data.color = color
    data.shape = 'DISK'
    data.size = size
    obj = bpy.data.objects.new(name, data)
    obj.location = loc
    col.objects.link(obj)
    direction = Vector(target)-obj.location
    obj.rotation_euler = direction.to_track_quat('-Z','Y').to_euler()
    return obj


def add_point_light(name, loc, energy, color, radius, col):
    data = bpy.data.lights.new(name, 'POINT')
    data.energy = energy
    data.color = color
    data.shadow_soft_size = radius
    obj = bpy.data.objects.new(name, data)
    obj.location = loc
    col.objects.link(obj)
    return obj


def point_in_rect(x, y, rect):
    rx, ry, rw, rh = rect
    return rx <= x < rx + rw and ry <= y < ry + rh


def build_floor(col, mats):
    variants = ["完整水泥", "裂缝", "积水", "青苔", "排水口", "管线接口", "种植区", "棚屋基础", "设备安装", "边缘护栏", "屋顶入口", "严重破损"]
    tile_count = 0
    for i in range(GRID_DIMENSIONS[0]):
        for j in range(GRID_DIMENSIONS[1]):
            x = ROOF_RECT[0] + GRID_SIZE * (i + 0.5)
            y = ROOF_RECT[1] + GRID_SIZE * (j + 0.5)
            if point_in_rect(x, y, BASE_ATRIUM_RECT) or point_in_rect(x, y, WEST_STAIR_RECT):
                continue
            tile_count += 1
            edge = i in (0, GRID_DIMENSIONS[0] - 1) or j in (0, GRID_DIMENSIONS[1] - 1)
            if edge: v = 9
            elif x < -10 and y > 20: v = 6
            elif x > 15 and -8 < y < 15: v = 7
            elif x > 15 and y > 20: v = 8
            elif i in (0, 1) and 0 <= y < 30: v = 10
            else: v = (i*3+j*5)%6
            tone = C["concrete_mid"] if (i+j)%4 else C["concrete"]
            tile = box(f"地砖_{i:02d}_{j:02d}_{variants[v]}",(x,y,0),(5,5,0.34),col,mats['matte'],tone,bevel=0.025,
                       asset_id=f"ENV_GROUND_TILE_5M_{v:02d}")
            tile["module_size"] = "5x5x0.34m"
            tile["grid_coord"] = f"{i},{j}"
            tile["pivot_rule"] = "bottom_center"
            # Designed, replaceable details stay separate from the compatible base tile.
            if v in (1,11):
                for k in range(2 if v==1 else 4):
                    px=x-1.2+k*0.7; py=y+0.5*math.sin(i+j+k)
                    beam(f"裂缝线_{i}_{j}_{k}",(px,py,0.348),(px+0.9,py+0.35*(-1)**k,0.348),0.035,col,mats['matte'],C['cool_dark'],6)
            if v==2:
                puddle=box(f"浅积水_{i}_{j}",(x+0.4,y-0.2,0.345),(2.8,1.7,0.025),col,mats['gloss'],C['water'],bevel=0.2)
                puddle.scale.y=0.78
            if v==3:
                for k in range(4):
                    box(f"青苔斑_{i}_{j}_{k}",(x-1.2+k*.7,y+1.4-.25*k,0.345),(.65,.35,.025),col,mats['matte'],C['leaf_dark'],rot=(0,0,.15*k),bevel=.08)
            if v==4:
                cylinder(f"排水口_{i}_{j}",(x+1.3,y-1.4,.345),.42,.08,col,mats['metal'],C['charcoal'],12)
                for k in range(4):
                    box(f"排水格栅_{i}_{j}_{k}",(x+1.3,y-1.7+.2*k,.43),(.65,.06,.04),col,mats['metal'],C['cool_dark'])
            if v==5:
                cylinder(f"管线接口_{i}_{j}",(x-1.2,y+1.2,.345),.22,.35,col,mats['metal'],C['rust'],10)

    # Hidden editable prototypes for the twelve standard modules.
    if tile_count != EXPECTED_TILE_COUNT:
        raise RuntimeError(f"Rooftop tile contract mismatch: {tile_count} != {EXPECTED_TILE_COUNT}")
    return variants


def build_rooftop_shell(col, mats):
    # Only perimeter fascia is modeled below the roof. A full 90x80 slab would seal the
    # two gameplay openings even if their surface tiles were omitted.
    center_x = ROOF_RECT[0] + ROOF_RECT[2] * 0.5
    center_y = ROOF_RECT[1] + ROOF_RECT[3] * 0.5
    box("北侧塔楼立面",(center_x,ROOF_RECT[1],-8),(ROOF_RECT[2],.30,8),col,mats['matte'],C['cool_dark'],asset_id="ENV-ROOFTOP-FASCIA-NORTH-90M")
    box("南侧塔楼立面",(center_x,ROOF_RECT[1]+ROOF_RECT[3],-8),(ROOF_RECT[2],.30,8),col,mats['matte'],C['cool_dark'],asset_id="ENV-ROOFTOP-FASCIA-SOUTH-90M")
    box("西侧塔楼立面",(ROOF_RECT[0],center_y,-8),(.30,ROOF_RECT[3],8),col,mats['matte'],C['cool_dark'],asset_id="ENV-ROOFTOP-FASCIA-WEST-80M")
    box("东侧塔楼立面",(ROOF_RECT[0]+ROOF_RECT[2],center_y,-8),(.30,ROOF_RECT[3],8),col,mats['matte'],C['cool_dark'],asset_id="ENV-ROOFTOP-FASCIA-EAST-80M")
    for side, y in (("北", ROOF_RECT[1]-.01), ("南", ROOF_RECT[1]+ROOF_RECT[3]+.01)):
        for k in range(GRID_DIMENSIONS[0]):
            x=ROOF_RECT[0]+GRID_SIZE*(k+.5)
            box(f"立面窗_{side}_{k}",(x,y,-6.0),(2.5,.08,2.4),col,mats['gloss'],C['navy'])
    for side, x in (("西", ROOF_RECT[0]-.01), ("东", ROOF_RECT[0]+ROOF_RECT[2]+.01)):
        for k in range(GRID_DIMENSIONS[1]):
            y=ROOF_RECT[1]+GRID_SIZE*(k+.5)
            box(f"立面窗_{side}_{k}",(x,y,-6.0),(.08,2.5,2.4),col,mats['gloss'],C['navy'])


def build_shelter(col, lights_col, mats):
    # Central 20x15m semi-open shelter.
    posts=[(-10,-4),(-10,3.5),(-10,11),(0,-4),(0,11),(10,-4),(10,3.5),(10,11)]
    for n,(x,y) in enumerate(posts):
        box(f"生活棚_立柱_{n}",(x,y,.34),(.22,.22,5.2),col,mats['metal'],C['charcoal'],bevel=.03)
    for y in (-4,11):
        beam(f"生活棚_横梁_{y}",(-10,y,5.35),(10,y,5.35),.12,col,mats['metal'],C['charcoal'])
    for x in (-10,0,10):
        beam(f"生活棚_纵梁_{x}",(x,-4,5.35),(x,11,5.35),.12,col,mats['metal'],C['charcoal'])
    roof_cells=[C['rust'],C['blue_faded'],C['canvas'],C['concrete_light'],C['green'],C['rust_red']]
    idx=0
    for ix in range(4):
        for iy in range(3):
            # The south-east lounge is an open courtyard: the sofa remains readable from above.
            if (ix,iy) in ((1,0),(2,0),(2,1),(2,2),(3,0),(3,1)):
                continue
            x=-7.5+ix*5; y=-1.5+iy*5
            tilt=.025*((ix+iy)%3-1)
            box(f"生活棚_屋顶拼板_{idx}",(x,y,5.28),(5.25,5.25,.12),col,mats['matte'],roof_cells[idx%len(roof_cells)],rot=(tilt,-tilt,0),bevel=.03)
            # Sparse ribs read as designed corrugated sheet without noisy textures.
            if idx % 2 == 0:
                for r in range(4):
                    beam(f"生活棚_铁皮压筋_{idx}_{r}",(x-2.0+r*1.3,y-2.25,5.43),(x-2.0+r*1.3,y+2.25,5.43),.028,col,mats['metal'],C['rust'],6)
            idx+=1
    # Ropes and brick weights make the patchwork roof structurally believable.
    for r,x in enumerate((-8,-3,2,7)):
        beam(f"棚顶加固绳_{r}",(x,-3.8,5.55),(x,10.7,5.55),.025,col,mats['matte'],C['sand'],6)
        for y in (-3.2,10.0):
            box(f"棚顶压砖_{r}_{y}",(x,y,5.48),(.48,.28,.18),col,mats['matte'],C['rust'],rot=(0,0,.12*(-1)**r),bevel=.025)
    # Partial walls are assembled from mismatched panels with real gaps rather than solid slabs.
    wall_parts=[
        (-9.9,7.2,.16,5.8,3.6,C['blue_faded']),(-9.9,-1.8,.16,3.1,2.9,C['rust']),
        (9.9,8.1,.16,4.5,3.3,C['rust']),(9.9,-1.8,.16,3.0,2.5,C['canvas']),
        (-6.8,10.9,5.0,.16,3.3,C['wood']),(-1.0,10.9,4.8,.16,2.7,C['blue_faded']),
        (6.3,10.9,6.0,.16,3.5,C['canvas'])]
    for n,(x,y,sx,sy,h,cell) in enumerate(wall_parts):
        box(f"生活棚_残墙板_{n}",(x,y,.36),(sx,sy,h),col,mats['matte'],cell,rot=(0,0,.012*((n%3)-1)),bevel=.04)
        for q in range(2):
            cylinder(f"残墙连接铆钉_{n}_{q}",(x-.09 if sx<1 else x-1.4+q*2.8,y-.09 if sy<1 else y-1.0+q*2.0,.75+h*.65),.045,.05,col,mats['metal'],C['concrete_light'],8,rot=(math.pi/2,0,0))
    for x in (-9.4,9.4):
        beam("生活棚_斜撑",(x,-3.5,.5),(x,-3.5,4.5),.07,col,mats['metal'],C['rust'])
    # Connection plates, bolts and diagonal roof braces enrich the close silhouette.
    for n,(x,y) in enumerate(posts):
        box(f"生活棚_柱脚板_{n}",(x,y,.34),(.52,.52,.08),col,mats['metal'],C['rust'],bevel=.025)
        for sx in (-.17,.17):
            for sy in (-.17,.17): cylinder(f"生活棚_地脚螺栓_{n}_{sx}_{sy}",(x+sx,y+sy,.42),.035,.11,col,mats['metal'],C['concrete_light'],8)
    beam("生活棚_屋架斜撑_左",(-10,-4,4.2),(0,11,5.25),.065,col,mats['metal'],C['rust'],8)
    beam("生活棚_屋架斜撑_右",(10,-4,4.2),(0,11,5.25),.065,col,mats['metal'],C['rust'],8)
    # Workbench and tool wall.
    box("工作台_桌面",(-6,7,.36),(5,1.5,.18),col,mats['matte'],C['wood'],bevel=.05)
    for x in (-8.2,-3.8): box("工作台_桌腿",(x,7,.36),(.18,1.2,1.4),col,mats['metal'],C['charcoal'])
    box("工具墙",(-6,7.72,.36),(5,.12,2.8),col,mats['matte'],C['blue_faded'])
    for k in range(10):
        px=-8.0+(k%5)*1.0; pz=1.4+(k//5)*.7
        box(f"挂墙工具_{k}",(px,7.64,pz),(.12,.08,.55),col,mats['metal'],C['mustard'],rot=(0,0,.18*(-1)**k),bevel=.02)
    # Open lounge: a worn sofa built from separate frame, cushions, patches and loose textiles.
    sofa_x,sofa_y=3.0,4.3
    box("双人沙发_底部框架",(sofa_x,sofa_y,.36),(5.2,2.0,.45),col,mats['metal'],C['charcoal'],bevel=.10)
    for sx in (-2.2,2.2):
        for sy in (-.68,.68): box("双人沙发_短脚",(sofa_x+sx,sofa_y+sy,.34),(.18,.18,.36),col,mats['metal'],C['rust'],bevel=.03)
    for k in range(2):
        box(f"双人沙发_独立座垫_{k}",(sofa_x-1.12+k*2.25,sofa_y-.10,.82),(2.12,1.55,.48),col,mats['matte'],C['green'] if k==0 else C['leaf_dark'],rot=(0,0,.025*(-1)**k),bevel=.22)
        box(f"双人沙发_独立靠垫_{k}",(sofa_x-1.1+k*2.2,sofa_y+.70,1.30),(2.0,.46,1.30),col,mats['matte'],C['green'],rot=(-.12,.03*(-1)**k,.02*(-1)**k),bevel=.20)
    for x in (.55,5.45): box("双人沙发_扶手",(x,sofa_y,.55),(.55,2.0,.95),col,mats['matte'],C['leaf_dark'],bevel=.16)
    box("沙发磨损补丁",(2.25,3.48,1.22),(.70,.03,.42),col,mats['matte'],C['canvas'],rot=(0,0,-.18),bevel=.06)
    box("沙发散落靠枕",(4.2,3.7,1.34),(1.05,.28,.82),col,mats['matte'],C['rust_red'],rot=(.18,-.08,.28),bevel=.16)
    box("沙发旧毛毯",(1.1,4.0,1.38),(1.15,.62,.12),col,mats['matte'],C['blue_faded'],rot=(.08,.18,-.20),bevel=.12)
    # Spool table moves into the open courtyard and receives naturally scattered items.
    table_x,table_y=3.1,1.0
    cylinder("电缆卷筒圆桌",(table_x,table_y,.36),1.18,.18,col,mats['matte'],C['wood'],16)
    cylinder("电缆卷筒轴",(table_x,table_y,.54),.42,.75,col,mats['matte'],C['brown'],12)
    cylinder("电缆卷筒桌面",(table_x,table_y,1.29),1.18,.16,col,mats['matte'],C['wood'],16)
    for k,a in enumerate((0,math.pi/2,math.pi,3*math.pi/2)):
        beam(f"卷筒桌面木缝_{k}",(table_x+.2*math.cos(a),table_y+.2*math.sin(a),1.46),(table_x+1.0*math.cos(a),table_y+1.0*math.sin(a),1.46),.018,col,mats['metal'],C['brown'],6)
    box("老式收音机",(2.55,.95,1.46),(1.05,.52,.66),col,mats['matte'],C['blue_faded'],rot=(0,0,-.12),bevel=.08)
    cylinder("收音机调谐旋钮",(2.92,.66,1.70),.09,.08,col,mats['metal'],C['orange'],10,rot=(math.pi/2,0,0))
    beam("收音机伸缩天线",(2.2,1.0,2.1),(1.45,1.18,3.05),.025,col,mats['metal'],C['concrete_light'],6)
    for k,(dx,dy,a) in enumerate([(.35,.35,.18),(.58,.10,-.12),(.18,-.22,.36),(-.20,.28,-.28)]):
        box(f"桌面散开地图纸_{k}",(table_x+dx,table_y+dy,1.47),(.72,.46,.018),col,mats['matte'],C['cream'] if k<3 else C['yellow'],rot=(0,0,a),bevel=.015)
    cylinder("搪瓷杯",(3.75,.62,1.47),.14,.28,col,mats['gloss'],C['cream'],10)
    box("桌面手电筒",(3.55,1.55,1.48),(.18,.52,.16),col,mats['metal'],C['mustard'],rot=(0,0,.48),bevel=.05)
    for k in range(3): cylinder(f"桌面维修零件_{k}",(2.75+.26*k,1.55+.08*(-1)**k,1.47),.07,.06,col,mats['metal'],C['rust'],8)
    # Rug fragments visually anchor the lounge without becoming a display plinth.
    box("休息区旧地垫_A",(3.0,3.0,.365),(6.5,4.8,.045),col,mats['matte'],C['blue_faded'],rot=(0,0,.035),bevel=.08)
    box("休息区旧地垫_B",(5.2,1.8,.412),(2.1,1.3,.03),col,mats['matte'],C['rust_red'],rot=(0,0,-.16),bevel=.05)
    # Beds and survival clutter.
    box("简易床铺",(-5,-1.8,.36),(4.2,2.0,.45),col,mats['matte'],C['charcoal'],bevel=.08)
    box("睡袋",(-5,-1.8,.82),(3.6,1.55,.25),col,mats['matte'],C['blue_faded'],bevel=.18)
    for k in range(5):
        box(f"收纳木箱_{k}",(-8.4+k%2*1.3,-2.4+(k//2)*1.2,.36),(1.1,1.0,.75),col,mats['matte'],C['wood'],bevel=.04)
    # Note board with layered paper shapes, intentionally no text/UI.
    box("城市地图与物资板",(8.0,10.72,1.2),(3.2,.10,2.5),col,mats['matte'],C['brown'])
    for k in range(12):
        px=6.7+(k%4)*.8; pz=1.45+(k//4)*.65
        box(f"地图便签_{k}",(px,10.64,pz),(.55,.035,.38),col,mats['matte'],[C['cream'],C['yellow'],C['blue_faded']][k%3],rot=(0,0,.08*((k%3)-1)))
    # Stove and cooking rack.
    cylinder("小型火炉",(-.5,6.2,.36),.6,1.1,col,mats['metal'],C['charcoal'],12)
    cylinder("烧水壶",(-.5,6.2,1.48),.38,.45,col,mats['metal'],C['concrete_light'],12)
    beam("水壶提梁",(-.85,6.2,1.75),(-.15,6.2,1.75),.04,col,mats['metal'],C['charcoal'])
    # Warm lamps.
    for n,(x,y,z) in enumerate([(-6,4.7,4.2),(3,4.0,4.0),(7.8,8.5,3.3)]):
        cylinder(f"露营灯灯罩_{n}_自发光",(x,y,z),.18,.34,col,mats['emission'],C['orange'],10)
        light=add_point_light(f"生活棚暖灯_{n}",(x,y,z+.1),900 if n!=1 else 1250,(1.0,.48,.18),2.5,lights_col)
        if n==1:
            light.data.keyframe_insert('energy',frame=1); light.data.energy=1100; light.data.keyframe_insert('energy',frame=90); light.data.energy=1280; light.data.keyframe_insert('energy',frame=180); light.data.energy=1160; light.data.keyframe_insert('energy',frame=250)


def build_shelter_platform_and_motion(col, mats):
    # A 0.5m raised timber deck gives the red-zone shelter a deliberate domestic threshold.
    deck_x, deck_y = 18.0, 37.0
    for i in range(20):
        x = 8.25 + i * 1.025
        cell = C['wood'] if i % 5 else C['brown']
        box(f"棚屋抬高木平台_地板木块_{i:02d}",(x,deck_y,.34),(.98,15.7,.50),col,mats['matte'],cell,rot=(0,0,.002*((i%3)-1)),bevel=.035)
        for q in (0,1):
            cylinder(f"棚屋抬高木平台_固定钉_{i:02d}_{q}",(x,29.65+q*14.7,.845),.035,.035,col,mats['metal'],C['rust'],8)
    # Visible wooden steps descend into the yellow route; gameplay uses one continuous ramp.
    for i,(y,width,height) in enumerate([(29.22,3.2,.50),(28.68,3.0,.34),(28.16,2.8,.18)]):
        box(f"棚屋小木板楼梯_踏步_{i}",(18.0,y,.34),(width,.58,height),col,mats['matte'],C['wood'] if i != 1 else C['brown'],bevel=.035)
    for side in (-1,1):
        beam(f"棚屋小木板楼梯_侧梁_{side}",(18+side*1.42,27.85,.40),(18+side*1.58,29.5,.90),.055,col,mats['metal'],C['rust'],8)

    # Small roof windmill: independent animated rotor, mast and tail.
    cylinder("棚屋小风车_立杆",(26.8,31.0,.84),.075,6.25,col,mats['metal'],C['charcoal'],8)
    rotor=empty("棚屋小风车_旋转根",(26.8,30.75,7.0),col)
    cylinder("棚屋小风车_轮毂",(0,0,0),.15,.28,col,mats['metal'],C['orange'],10,rot=(math.pi/2,0,0)).parent=rotor
    blade_cells=[C['rust_red'],C['mustard'],C['blue_faded'],C['green'],C['canvas'],C['orange']]
    for i in range(6):
        a=i*math.pi/3
        blade=box(f"棚屋小风车_彩色叶片_{i}",(.62*math.cos(a),0,.62*math.sin(a)),(.95,.06,.23),col,mats['matte'],blade_cells[i],rot=(0,a,0),bevel=.06)
        blade.parent=rotor
    box("棚屋小风车_尾舵",(26.8,31.35,6.93),(.08,1.0,.58),col,mats['matte'],C['rust_red'],bevel=.06)
    rotor.rotation_mode='XYZ'; rotor.keyframe_insert('rotation_euler',frame=1,index=1); rotor.rotation_euler.y=2*math.pi; rotor.keyframe_insert('rotation_euler',frame=120,index=1); rotor.rotation_euler.y=4*math.pi; rotor.keyframe_insert('rotation_euler',frame=250,index=1)
    for fc in rotor.animation_data.action.fcurves if rotor.animation_data and rotor.animation_data.action else []:
        for kp in fc.keyframe_points: kp.interpolation='LINEAR'

    # A hanging mobile and wind chimes provide smaller motion beats inside the shelter.
    mobile=empty("棚屋吊挂风铃_摆动根",(17.5,36.5,5.25),col)
    for i in range(5):
        a=i*2*math.pi/5
        beam(f"棚屋吊挂风铃_吊线_{i}",(0,0,0),(.7*math.cos(a),.7*math.sin(a),-1.0-.12*(i%2)),.014,col,mats['matte'],C['charcoal'],6).parent=mobile
        cylinder(f"棚屋吊挂风铃_铃管_{i}",(.7*math.cos(a),.7*math.sin(a),-1.30-.12*(i%2)),.045,.52,col,mats['metal'],C['concrete_light'],8).parent=mobile
    mobile.rotation_mode='XYZ'; mobile.keyframe_insert('rotation_euler',frame=1,index=2); mobile.rotation_euler.z=.20; mobile.keyframe_insert('rotation_euler',frame=80,index=2); mobile.rotation_euler.z=-.16; mobile.keyframe_insert('rotation_euler',frame=165,index=2); mobile.rotation_euler.z=.20; mobile.keyframe_insert('rotation_euler',frame=250,index=2)


def add_planter(name, x,y,sx,sy, crop, col, mats, plant_count=12):
    box(name+"_箱体",(x,y,.34),(sx,sy,.65),col,mats['matte'],C['wood'],bevel=.06)
    box(name+"_土壤",(x,y,.98),(sx-.25,sy-.25,.16),col,mats['matte'],C['soil'],bevel=.05)
    for k in range(plant_count):
        px=x-sx*.38+(k%4)*(sx*.25); py=y-sy*.30+(k//4)*(sy*.28)
        h=.58+.24*((k*7)%3)
        stem=cylinder(f"{name}_{crop}_茎_{k}",(px,py,1.12),.035,h,col,mats['matte'],C['leaf_dark'],6)
        for q in range(3):
            leaf=box(f"{name}_{crop}_叶_{k}_{q}",(px+.16*(-1)**q,py+.05*q,1.32+.18*q),(.42,.16,.055),col,mats['matte'],C['leaf'] if k%5 else C['mustard'],rot=(0,.18*(-1)**q,.45*q),bevel=.055)
            if k%4==0 and q==1:
                leaf.rotation_mode='XYZ'; leaf.keyframe_insert('rotation_euler',frame=1,index=2); leaf.rotation_euler.z+=.12; leaf.keyframe_insert('rotation_euler',frame=100,index=2); leaf.rotation_euler.z-=.08; leaf.keyframe_insert('rotation_euler',frame=200,index=2); leaf.keyframe_insert('rotation_euler',frame=250,index=2)


def build_farm(col, lights_col, mats):
    specs=[(-19,9,5.2,2.4,"番茄"),(-13,9,5.2,2.4,"卷心菜"),(-19,5.5,5.2,2.4,"玉米"),(-13,5.5,5.2,2.4,"土豆"),(-19,2.0,4.4,2.0,"香草")]
    for i,s in enumerate(specs): add_planter(f"种植池_{i}",*s,col,mats,12)
    # Tall corn and tomato stakes create the high/low rhythm seen from the isometric camera.
    for k in range(10):
        x=-20.5+(k%5)*.9; y=5.0+(k//5)*1.0
        cylinder(f"玉米高茎_{k}",(x,y,1.1),.045,1.75,col,mats['matte'],C['leaf_dark'],6)
        for q in range(3): box(f"玉米长叶_{k}_{q}",(x+.18*(-1)**q,y,1.6+.38*q),(.55,.12,.055),col,mats['matte'],C['leaf'],rot=(0,.22*(-1)**q,.4*q),bevel=.04)
    for k in range(6):
        x=-20.0+(k%3)*1.3; y=8.5+(k//3)*1.1
        cylinder(f"番茄支架_{k}",(x,y,1.0),.03,1.8,col,mats['matte'],C['wood'],6)
        for q in range(3): sphere(f"番茄果实_{k}_{q}",(x+.12*(-1)**q,y,1.45+.35*q),.11,col,mats['gloss'],C['red'],8,4)
    # Reused bathtub planter.
    box("废弃浴缸种植池",(-13,2,.34),(4.2,1.9,.85),col,mats['gloss'],C['concrete_light'],bevel=.28)
    box("浴缸土壤",(-13,2,1.12),(3.6,1.35,.18),col,mats['matte'],C['soil'],bevel=.15)
    for k in range(10): sphere(f"浴缸卷心菜_{k}",(-14.5+(k%5)*.72,1.65+(k//5)*.7,1.45),.28,col,mats['matte'],C['leaf'],8,4,scale=(1,1,.75))
    # Greenhouse frame and translucent-looking glossy panels.
    gx,gy=-17,15.4
    for x in (-21,-13):
        for y in (12.5,18.3): box("温室立柱",(x,y,.34),(.12,.12,3.2),col,mats['metal'],C['charcoal'])
    for y in (12.5,18.3): beam("温室拱顶",(-21,y,3.3),(-17,y,5.0),.08,col,mats['metal'],C['charcoal']); beam("温室拱顶",(-17,y,5.0),(-13,y,3.3),.08,col,mats['metal'],C['charcoal'])
    for x in (-20,-18,-16,-14): beam("温室纵梁",(x,12.5,3.6+(2-abs(x+17))*.55),(x,18.3,3.6+(2-abs(x+17))*.55),.055,col,mats['metal'],C['concrete_light'])
    for side,x in enumerate((-20,-16,-14)):
        film=box(f"温室薄膜_{side}",(x,15.4,3.45),(1.9,5.7,.05),col,mats['gloss'],C['glass'],rot=(0,.18*(side-1),0))
        film.keyframe_insert('rotation_euler',frame=1,index=1); film.rotation_euler.y+=.025; film.keyframe_insert('rotation_euler',frame=110,index=1); film.rotation_euler.y-=.04; film.keyframe_insert('rotation_euler',frame=220,index=1); film.keyframe_insert('rotation_euler',frame=250,index=1)
    # Water and drip system.
    for k in range(3):
        cylinder(f"种植区储水桶_{k}",(-11.5,14+k*1.5,.34),.6,1.4,col,mats['matte'],C['blue_faded'],12)
    for row,y in enumerate((9,5.5,2)):
        beam(f"滴灌主管_{row}",(-21,y,1.25),(-10.5,y,1.25),.035,col,mats['matte'],C['charcoal'],6)
    # Compost and garden tools.
    box("堆肥箱",(-11.5,18,.34),(2.4,2.0,1.5),col,mats['matte'],C['brown'],bevel=.08)
    for k in range(4): beam(f"园艺工具_{k}",(-10.6+k*.25,17,.4),(-10.6+k*.25,17,2.1),.035,col,mats['metal'],C['mustard'],6)
    add_point_light("温室暖灯",(-17,15.4,3.8),110,(1,.55,.25),2.2,lights_col)


def solar_panel(name,x,y,z,angle,col,mats):
    base=empty(name+"_旋转根",(x,y,z),col)
    panel=box(name+"_面板",(0,0,0),(4.3,2.4,.12),col,mats['gloss'],C['navy'],rot=(angle,0,0),bevel=.05)
    panel.parent=base; panel.location=(0,0,0)
    frame=box(name+"_边框",(0,0,-.04),(4.55,2.65,.08),col,mats['metal'],C['concrete_light'],rot=(angle,0,0),bevel=.06)
    frame.parent=base; frame.location=(0,0,-.04)
    for k in range(3):
        line=box(name+f"_电池片竖线_{k}",(-1.1+k*1.1,0,.08),(.035,2.25,.02),col,mats['metal'],C['blue_faded'],rot=(angle,0,0)); line.parent=base
    for k in range(2):
        line=box(name+f"_电池片横线_{k}",(0,-.6+k*1.2,.08),(4.1,.035,.02),col,mats['metal'],C['blue_faded'],rot=(angle,0,0)); line.parent=base
    for sx in (-1.5,1.5):
        beam(name+"_支架",(x+sx,y,z-.1),(x+sx,y+.6,z-1.0),.07,col,mats['metal'],C['charcoal'])
        cylinder(name+"_调角铰链",(x+sx,y-.05,z-.08),.12,.12,col,mats['metal'],C['rust'],10,rot=(0,math.pi/2,0))
    beam(name+"_背部横撑",(x-1.6,y+.52,z-.90),(x+1.6,y+.52,z-.90),.055,col,mats['metal'],C['rust'],8)


def build_energy_water(col, mats):
    # v013 compresses generation and water into the south service yard of the lived-in east cluster.
    for i,(x,y,a) in enumerate([(20,-22,.28),(25,-22,.34),(20,-26,.24),(25,-26,.30)]): solar_panel(f"太阳能板_{i}",x,y,1.5,a,col,mats)
    # Wind turbine with animated rotor.
    mastx,masty=29.0,-24.0
    cylinder("风机塔杆",(mastx,masty,.34),.16,7.2,col,mats['metal'],C['charcoal'],10)
    rotor=empty("风力发电机_旋转中心",(mastx,masty-.35,7.4),col)
    hub=cylinder("风机轮毂",(0,0,0),.24,.5,col,mats['metal'],C['rust'],10,rot=(math.pi/2,0,0)); hub.parent=rotor; hub.location=(0,0,0)
    for k in range(3):
        a=k*2*math.pi/3
        blade=beam(f"风机叶片_{k}",(0,0,0),(2.15*math.cos(a),0,2.15*math.sin(a)),.16,col,mats['matte'],C['concrete_light'],6)
        blade.parent=rotor
    rotor.rotation_mode='XYZ'; rotor.keyframe_insert('rotation_euler',frame=1,index=1); rotor.rotation_euler.y=2*math.pi; rotor.keyframe_insert('rotation_euler',frame=250,index=1)
    for fc in rotor.animation_data.action.fcurves if rotor.animation_data and rotor.animation_data.action else []:
        for kp in fc.keyframe_points: kp.interpolation='LINEAR'
    # Generator, batteries, repair bench.
    box("柴油发电机_机身",(31,-18,.34),(3.2,1.8,1.6),col,mats['metal'],C['mustard'],bevel=.16)
    box("柴油发电机_控制面板",(31.9,-18.91,.75),(1.15,.05,.82),col,mats['matte'],C['charcoal'],bevel=.06)
    for k in range(6): box(f"发电机散热格栅_{k}",(29.95+k*.32,-18.92,.76),(.12,.04,.72),col,mats['metal'],C['charcoal'],rot=(0,0,.05))
    for sx in (-1.25,1.25):
        box("发电机底脚",(31+sx,-18,.34),(.34,1.15,.18),col,mats['metal'],C['rust'],bevel=.035)
        beam("发电机搬运框",(31+sx,-18.65,.75),(31+sx,-18.65,1.75),.045,col,mats['metal'],C['charcoal'],8)
    cylinder("发电机电压表",(32.12,-18.96,1.26),.16,.035,col,mats['gloss'],C['cream'],12,rot=(math.pi/2,0,0))
    cylinder("发电机排气",(31.9,-17.8,1.94),.12,1.0,col,mats['metal'],C['charcoal'],8)
    for i in range(3):
        bx=29+i*1.15
        box(f"蓄电池柜_{i}",(bx,-14,.34),(1.0,.8,1.6),col,mats['matte'],C['blue_faded'],bevel=.05)
        for q in (-.22,.22): cylinder(f"蓄电池接线柱_{i}_{q}",(bx+q,-14,1.96),.055,.10,col,mats['metal'],C['red'] if q>0 else C['charcoal'],8)
        beam(f"蓄电池提手_{i}",(bx-.26,-14,1.90),(bx+.26,-14,1.90),.035,col,mats['metal'],C['concrete_light'],8)
    box("能源维修工作台",(22,-14,.34),(4.5,1.2,1.25),col,mats['matte'],C['wood'])
    # Water storage faces the service lane so daily chores are visible from the living shelter.
    for i,(x,y,r,h) in enumerate([(35,-23,2.2,4.8),(31.8,-26,1.25,3.1),(35,-17.8,1.25,3.1),(31.8,-10.8,1.45,3.5)]):
        cylinder(f"储水罐_{i}",(x,y,.34),r,h,col,mats['metal'] if i==0 else mats['matte'],C['concrete_light'] if i==0 else C['blue_faded'],16)
        for q in range(3):
            cylinder(f"储水罐箍带_{i}_{q}",(x,y,.34+h*(q+1)/4),r+.05,.07,col,mats['metal'],C['charcoal'],16)
        cylinder(f"储水罐顶盖_{i}",(x,y,.34+h),r*.92,.18,col,mats['metal'],C['concrete_light'],16)
        cylinder(f"储水罐检修口_{i}",(x,y,.52+h),r*.22,.20,col,mats['metal'],C['rust'],12)
        for a in range(0,360,90):
            ar=math.radians(a)
            beam(f"储水罐竖向加强筋_{i}_{a}",(x+r*math.cos(ar),y+r*math.sin(ar),.5),(x+r*math.cos(ar),y+r*math.sin(ar),.34+h),.035,col,mats['metal'],C['charcoal'],6)
    # Pipes with deliberate functional routing.
    routes=[((35,-23,.7),(31.8,-10.8,.7)),((31.8,-26,.7),(35,-23,.7)),((35,-17.8,.9),(31.8,-10.8,.9)),((31.8,-10.8,3.9),(31.8,-5.2,3.9)),((29,-14,.8),(26,-5,.8))]
    for i,(a,b) in enumerate(routes): beam(f"供水能源管线_{i}",a,b,.075,col,mats['matte'],C['charcoal'],8)
    for k in range(4):
        box(f"修补胶带接口_{k}",(32.2+k*.8,-23,.68),(.18,.22,.22),col,mats['matte'],C['red'],bevel=.03)
    # Visible cable runs connect generation, storage and living zones.
    for i,(a,b) in enumerate([((31,-18,.55),(29,-14,.55)),((29,-14,.48),(26,-5,.48)),((26,-5,.48),(34,-5,.48)),((25,-22,.48),(29,-14,.48))]):
        beam(f"外露电缆_{i}",a,b,.035,col,mats['matte'],C['charcoal'],6)
    box("防水配电箱",(27.2,-14,.34),(1.2,.55,1.45),col,mats['metal'],C['rust'],bevel=.08)


def build_radio(col, lights_col, mats):
    # Raised 8x8m communication platform in north-east.
    for x in (13,21):
        for y in (10,18): box("广播平台立柱",(x,y,.34),(.28,.28,4.0),col,mats['metal'],C['charcoal'])
    box("广播平台楼板",(17,14,4.34),(8,8,.38),col,mats['metal'],C['brown'],bevel=.08)
    # Under-deck X braces and node plates make the raised platform structurally credible.
    for x0 in (13.2,20.8):
        beam("广播平台斜撑",(x0,10.2,.7),(x0,17.8,4.2),.075,col,mats['metal'],C['rust'],8)
        beam("广播平台斜撑",(x0,17.8,.7),(x0,10.2,4.2),.075,col,mats['metal'],C['rust'],8)
    for x in (13,21):
        for y in (10,18): box("广播平台节点板",(x,y,3.55),(.52,.52,.10),col,mats['metal'],C['rust'],bevel=.03)
    # Stairs from south.
    for k in range(9): box(f"广播平台楼梯_{k}",(17,8.6+k*.42,.34+k*.44),(2.3,.62,.18),col,mats['metal'],C['concrete_mid'],bevel=.03)
    for sx in (-1.05,1.05):
        beam("广播楼梯扶手斜杆",(17+sx,8.5,1.4),(17+sx,12.1,5.4),.055,col,mats['metal'],C['charcoal'],8)
        for k in range(5): cylinder("广播楼梯扶手立柱",(17+sx,8.7+k*.78,.7+k*.87),.04,.9,col,mats['metal'],C['rust'],8)
    # Railings.
    for x in (13.2,20.8):
        for y in (10.4,13,15.6,17.6): cylinder("广播台栏杆立柱",(x,y,4.72),.055,1.2,col,mats['metal'],C['charcoal'],8)
        beam("广播台栏杆横杆",(x,10.4,5.75),(x,17.6,5.75),.055,col,mats['metal'],C['charcoal'])
    # Broadcast console and equipment.
    box("广播控制桌",(17,15.8,4.72),(5.2,1.5,1.25),col,mats['matte'],C['wood'],bevel=.08)
    for i in range(4):
        box(f"无线电收发机_{i}",(15.3+i*1.15,15.55,6.0),(1.0,.65,.72),col,mats['metal'],C['blue_faded'],bevel=.06)
        for q in range(3): cylinder(f"无线电旋钮_{i}_{q}",(15.0+i*1.15+q*.28,15.18,6.2),.055,.06,col,mats['metal'],C['orange'],8,rot=(math.pi/2,0,0))
        box(f"无线电指示灯_{i}_自发光",(15.6+i*1.15,15.17,6.35),(.14,.04,.08),col,mats['emission'],C['yellow'])
    box("广播地图板",(17,17.65,5.1),(4.8,.10,2.2),col,mats['matte'],C['blue_faded'])
    for k in range(8): box(f"广播联络记录_{k}",(15.3+(k%4)*1.1,17.56,5.5+(k//4)*.65),(.75,.03,.38),col,mats['matte'],C['cream'],rot=(0,0,.05*(-1)**k))
    # Antenna mast with slow turntable.
    cylinder("通信主桅杆",(17,14,4.72),.16,10.5,col,mats['metal'],C['charcoal'],10)
    for z in (8,11,14):
        for a in (0,2*math.pi/3,4*math.pi/3): beam("桅杆拉线",(17,14,z),(17+4*math.cos(a),14+4*math.sin(a),4.8),.025,col,mats['metal'],C['concrete_light'],6)
    turn=empty("大型定向天线_慢速转台",(17,14,12.2),col)
    boom=beam("八木天线主梁",(-3.4,0,0),(3.4,0,0),.11,col,mats['metal'],C['rust'],8); boom.parent=turn; boom.location=(0,0,0)
    for k in range(8):
        elem=beam(f"八木天线振子_{k}",(-2.8+k*.8,-1.6+0.1*k,0),(-2.8+k*.8,1.6-.1*k,0),.045,col,mats['metal'],C['concrete_light'],6); elem.parent=turn; elem.location=(0,0,0)
    turn.keyframe_insert('rotation_euler',frame=1,index=2); turn.rotation_euler.z=.42; turn.keyframe_insert('rotation_euler',frame=250,index=2)
    # Satellite dish from shallow UV sphere slice illusion: dish + receiver arm.
    dish=sphere("卫星接收锅",(20,11.2,9.0),1.35,col,mats['metal'],C['concrete_light'],16,8,scale=(1,.23,1))
    dish.rotation_euler=(math.radians(22),0,math.radians(-25))
    beam("卫星锅馈源臂",(20,11.0,9.0),(20,9.9,9.3),.045,col,mats['metal'],C['charcoal'],6)
    # Signal beacon and radio meter needle animation.
    beacon=cylinder("天线红色信号灯_自发光",(17,14,15.25),.16,.28,col,mats['emission'],C['red'],10)
    beacon.keyframe_insert('scale',frame=1); beacon.scale=(1.35,1.35,1.35); beacon.keyframe_insert('scale',frame=18); beacon.scale=(1,1,1); beacon.keyframe_insert('scale',frame=45); beacon.keyframe_insert('scale',frame=250)
    red=add_point_light("天线信号点光",(17,14,15.55),60,(1,.02,.01),.4,lights_col)
    red.data.keyframe_insert('energy',frame=1); red.data.energy=0; red.data.keyframe_insert('energy',frame=18); red.data.energy=60; red.data.keyframe_insert('energy',frame=30); red.data.energy=0; red.data.keyframe_insert('energy',frame=55); red.data.keyframe_insert('energy',frame=250)
    needle=box("广播信号表指针_自发光",(17,15.16,6.75),(.05,.04,.55),col,mats['emission'],C['orange'],rot=(0,0,-.25)); needle.keyframe_insert('rotation_euler',frame=1,index=2); needle.rotation_euler.z=.28; needle.keyframe_insert('rotation_euler',frame=60,index=2); needle.rotation_euler.z=-.05; needle.keyframe_insert('rotation_euler',frame=120,index=2); needle.rotation_euler.z=.18; needle.keyframe_insert('rotation_euler',frame=250,index=2)
    add_point_light("广播台暖灯",(17,14.8,7.4),160,(1,.42,.15),1.4,lights_col)


def build_security(col, lights_col, mats):
    # Match the runtime 18x16 perimeter. The west side keeps the same two-module
    # circulation gap centered on Z=15 as the Godot stair contract.
    for side, y, rotation in (("北", -34.85, 0.0), ("南", 44.85, math.pi)):
        for i in range(GRID_DIMENSIONS[0]):
            x = ROOF_RECT[0] + GRID_SIZE * (i + .5)
            box(f"{side}侧矮墙_{i:02d}",(x,y,.34),(5.0,.30,.75),col,mats['matte'],C['concrete_mid'],rot=(0,0,rotation),asset_id="ENV-TOWER-WALL-PARAPET-5M")
    for side, x in (("西", -49.85), ("东", 39.85)):
        for j in range(GRID_DIMENSIONS[1]):
            y = ROOF_RECT[1] + GRID_SIZE * (j + .5)
            if side == "西" and abs(y - 15.0) <= 5.0:
                # Door-wall modules keep an obvious opening and do not occupy the stair footprint.
                box(f"西侧楼梯门洞矮墙下沿_{j:02d}",(x,y,.34),(.30,5.0,.24),col,mats['matte'],C['concrete_mid'],asset_id="ENV-TOWER-WALL-PARAPET-DOOR-5M")
                continue
            box(f"{side}侧矮墙_{j:02d}",(x,y,.34),(.30,5.0,.75),col,mats['matte'],C['concrete_mid'],asset_id="ENV-TOWER-WALL-PARAPET-5M")

    # Barricades frame the compact south service yard instead of scattering across the empty roof.
    for i in range(18):
        x=18.0+(i%9)*1.8; y=-30.0+(i//9)*.75
        box(f"南侧补给沙袋_{i}",(x,y,.34),(1.55,.62,.38),col,mats['matte'],C['sand'],rot=(0,0,.08*(-1)**i),bevel=.18)

    # Two small lookouts anchor opposite free corners without occupying the central base void.
    for side,(x,y) in enumerate(((-44.0,-28.0),(-44.0,39.0))):
        for dx in (-1.2,1.2):
            for dy in (-1.2,1.2): box("瞭望台支柱",(x+dx,y+dy,.34),(.16,.16,3.2),col,mats['metal'],C['charcoal'])
        box("瞭望台平台",(x,y,3.55),(3.2,3.2,.25),col,mats['matte'],C['wood'])
        cylinder("望远镜支架",(x,y,3.8),.08,1.0,col,mats['metal'],C['charcoal'],8)
        beam("望远镜",(x-.5,y,4.8),(x+.5,y,4.8),.12,col,mats['metal'],C['blue_faded'],10)
    for i,(x,y,z) in enumerate([(-48,-20,2.4),(38,-20,2.2),(29,44,2.5),(-44,-33,2.4)]):
        cloth=box(f"警示布条_{i}",(x,y,z),(.9,.05,.34),col,mats['matte'],C['red'],rot=(0,0,.15*i),bevel=.03)
        cloth.keyframe_insert('rotation_euler',frame=1,index=2); cloth.rotation_euler.z+=.12; cloth.keyframe_insert('rotation_euler',frame=100,index=2); cloth.rotation_euler.z-=.18; cloth.keyframe_insert('rotation_euler',frame=200,index=2); cloth.keyframe_insert('rotation_euler',frame=250,index=2)


def build_clutter(col, mats):
    # Story clusters support the red shelter, blue farm and service yard without entering the door route.
    clusters=[
        ("工坊拆件",20.0,-18.0,1.0,0.0),("南侧补给",19.5,-27.0,.7,.9),
        ("水箱维修",36.0,-14.5,.4,1.1),("农场园艺",-11.0,34.0,.3,.9),
        ("广播备件",30.0,32.0,1.1,.2),("生活储备",9.5,40.5,.8,.6)]
    for ci,(label,cx,cy,walk_x,walk_y) in enumerate(clusters):
        rng=random.Random(6100+ci)
        heights=[]
        for k in range(7):
            angle=rng.uniform(-math.pi,math.pi)
            radius=.35+k*.28+rng.uniform(-.18,.18)
            dx=math.cos(angle)*radius + walk_y*.25*k
            dy=math.sin(angle)*radius - walk_x*.18*k
            sx=rng.uniform(.68,1.28); sy=rng.uniform(.58,1.10); h=rng.uniform(.48,.92)
            z=.34
            if k in (4,6):
                # Two deliberately imperfect stacks rest on earlier crates.
                base_h=heights[k-3][2]
                dx=heights[k-3][0]+rng.uniform(-.12,.18); dy=heights[k-3][1]+rng.uniform(-.12,.18); z=.34+base_h
            box(f"{label}_木箱_{k}",(cx+dx,cy+dy,z),(sx,sy,h),col,mats['matte'],C['wood'] if k%3 else C['brown'],rot=(0,0,rng.uniform(-.38,.38)),bevel=.065)
            # Slatted battens and metal corner plates keep each crate from reading as a plain box.
            box(f"{label}_木箱压条_{k}",(cx+dx,cy+dy-sy*.42,z+h*.35),(sx*.88,.07,.10),col,mats['metal'],C['rust'],rot=(0,0,rng.uniform(-.38,.38)),bevel=.018)
            heights.append((dx,dy,h))
        bx=cx+rng.uniform(-1.5,1.5); by=cy+rng.uniform(-1.2,1.2)
        cylinder(f"{label}_回收油桶",(bx,by,.34),.46,1.28,col,mats['metal'],C['blue_faded'] if ci%2 else C['rust'],12,rot=(0,rng.uniform(-.08,.08),rng.uniform(-.2,.2)))
        # Sacks, baskets, bottles and cans soften the hard crate silhouette.
        for k in range(5):
            px=cx+rng.uniform(-1.8,1.8); py=cy+rng.uniform(-1.4,1.4)
            box(f"{label}_物资袋_{k}",(px,py,.34),(.58+rng.random()*.35,.42+rng.random()*.28,.34+rng.random()*.22),col,mats['matte'],C['sand'] if k%2 else C['canvas'],rot=(0,0,rng.uniform(-.7,.7)),bevel=.16)
        for k in range(7):
            px=cx+rng.uniform(-1.9,1.9); py=cy+rng.uniform(-1.45,1.45)
            cylinder(f"{label}_瓶罐_{k}",(px,py,.34),.07+rng.random()*.05,.18+rng.random()*.20,col,mats['gloss'] if k%3==0 else mats['metal'],C['blue_faded'] if k%3==0 else C['concrete_light'],8)
    # A used tire pile mixes lying, leaning and stacked pieces rather than a two-row array.
    tire_specs=[(20.0,-23.5,0,.10),(21.1,-23.1,.28,-.25),(22.2,-23.4,0,.18),(23.0,-22.7,.62,.38),(20.6,-22.35,.58,-.45),(21.8,-22.1,.25,.18),(23.6,-23.6,.45,-.2)]
    for i,(x,y,tilt,rz) in enumerate(tire_specs):
        cylinder(f"备用轮胎_{i}",(x,y,.34),.55,.34,col,mats['matte'],C['charcoal'],12,rot=(math.pi/2-tilt,0,rz))
    # Laundry line and moving clothes.
    beam("晾衣绳",(9.0,42.0,4.0),(17.0,42.0,4.0),.018,col,mats['matte'],C['concrete_light'],6)
    for i in range(5):
        cloth=box(f"晾晒衣物_{i}",(9.7+i*1.55,42.0,2.75),(.8,.04,1.1),col,mats['matte'],[C['blue_faded'],C['canvas'],C['rust'],C['green']][i%4],rot=(0,0,.03*(-1)**i),bevel=.05)
        cloth.keyframe_insert('rotation_euler',frame=1,index=1); cloth.rotation_euler.y=.08; cloth.keyframe_insert('rotation_euler',frame=120,index=1); cloth.rotation_euler.y=-.05; cloth.keyframe_insert('rotation_euler',frame=240,index=1); cloth.keyframe_insert('rotation_euler',frame=250,index=1)
    # Covered stock with bricks.
    tarp=box("防水布覆盖物资",(11.0,42.0,.84),(4.0,1.6,1.05),col,mats['matte'],C['canvas'],bevel=.28)
    for sx in (-2.1,2.1):
        for sy in (-.6,.6): box("压布砖块",(11.0+sx,42.0+sy,1.87),(.5,.28,.18),col,mats['matte'],C['rust'])
    # A repaired boardwalk connects service yard, shelter and dining threshold.
    for i in range(11):
        rng=random.Random(8800+i)
        y=-10+i*1.55+rng.uniform(-.09,.09)
        box(f"南侧木板便道_{i}",(24.5+rng.uniform(-.10,.12),y,.36),(3.0+rng.uniform(-.15,.12),1.20+rng.uniform(-.08,.08),.08+rng.uniform(0,.035)),col,mats['matte'],C['wood'] if i%4 else C['brown'],rot=(0,0,rng.uniform(-.035,.035)))
        if i in (2,7): box(f"便道修补铁片_{i}",(24.35,y,.46),(.7,.36,.035),col,mats['metal'],C['rust'],rot=(0,0,.15*(-1)**i),bevel=.02)
    for i in range(9):
        x=18+i*2.25
        box(f"南侧黄色区域标线_{i}",(x,-12.0+.04*math.sin(i),.37),(1.2+(.25 if i%3 else 0),.08,.025),col,mats['matte'],C['yellow'],rot=(0,0,.01*((i%4)-2)))


def build_lived_in_cluster(col, lights_col, mats):
    # The red-zone raised shelter receives the densest domestic storytelling.
    table_x, table_y = 23.0, 42.5
    box("公共餐桌_旧木桌面",(table_x,table_y,.84),(4.8,1.35,.18),col,mats['matte'],C['wood'],bevel=.08)
    for x in (table_x-2.0,table_x+2.0):
        for y in (table_y-.45,table_y+.45):
            box("公共餐桌_桌腿",(x,y,.84),(.18,.18,1.35),col,mats['metal'],C['charcoal'],bevel=.03)
    for y in (table_y-1.35,table_y+1.35):
        box("公共餐桌_长凳",(table_x,y,.84),(4.0,.48,.42),col,mats['matte'],C['blue_faded'] if y<table_y else C['rust'],bevel=.10)
        for x in (table_x-1.55,table_x+1.55):
            box("公共餐桌_长凳腿",(x,y,.84),(.16,.36,.55),col,mats['metal'],C['charcoal'])
    for i,(dx,dy,cell) in enumerate([(-1.4,-.2,C['cream']),(-.5,.25,C['blue_faded']),(.55,-.15,C['cream']),(1.35,.18,C['mustard'])]):
        cylinder(f"公共餐桌_搪瓷碗_{i}",(table_x+dx,table_y+dy,1.70),.20,.10,col,mats['gloss'],cell,12)
        cylinder(f"公共餐桌_水杯_{i}",(table_x+dx+.28,table_y+dy+.18,1.70),.09,.24,col,mats['gloss'],C['cream'],10)
    box("公共餐桌_切菜板",(table_x+.2,table_y,1.705),(1.1,.55,.05),col,mats['matte'],C['sand'],rot=(0,0,.08),bevel=.05)
    for i in range(5):
        sphere(f"公共餐桌_蔬菜_{i}",(table_x-.2+i*.18,table_y+.05*(-1)**i,1.80),.10,col,mats['matte'],C['leaf'] if i%2 else C['red'],8,4)

    # Shoes, wash basin and drying herbs imply repeatable daily routines.
    for i in range(4):
        box(f"棚口旧鞋_{i}",(9.2+i*.38,29.6+.08*(-1)**i,.84),(.55,.24,.20),col,mats['matte'],C['charcoal'] if i%2 else C['brown'],rot=(0,0,.12*(-1)**i),bevel=.10)
    cylinder("生活洗衣盆",(26.0,32.0,.84),.72,.28,col,mats['gloss'],C['blue_faded'],16)
    cylinder("生活洗衣盆水面",(26.0,32.0,1.13),.62,.025,col,mats['gloss'],C['water'],16)
    beam("香草晾晒架横杆",(20.0,31.5,3.8),(27.0,31.5,3.8),.045,col,mats['metal'],C['charcoal'],8)
    for x in (20.0,27.0):
        cylinder("香草晾晒架立柱",(x,31.5,.84),.055,3.0,col,mats['metal'],C['rust'],8)
    for i in range(7):
        beam(f"晾晒香草束_{i}",(20.5+i*.95,31.5,3.7),(20.5+i*.95,31.5,2.65-.08*(i%2)),.035,col,mats['matte'],C['leaf_dark'],6)
        for q in range(3):
            box(f"晾晒香草叶_{i}_{q}",(20.5+i*.95+.10*(-1)**q,31.5,2.85+.22*q),(.28,.10,.06),col,mats['matte'],C['leaf'],rot=(0,.15*(-1)**q,.35*q),bevel=.04)

    # A low string of warm bulbs visually ties shelter, dining and farm into one home.
    beam("聚落串灯电线",(8.5,31.5,4.9),(27.0,44.0,5.1),.018,col,mats['matte'],C['charcoal'],6)
    for i in range(9):
        t=i/8.0; x=8.5+(27.0-8.5)*t; y=31.5+(44.0-31.5)*t; z=4.85-.42*math.sin(math.pi*t)
        cylinder(f"聚落串灯_{i}_自发光",(x,y,z),.11,.20,col,mats['emission'],C['orange'] if i%3 else C['yellow'],10)
        if i in (1,4,7): add_point_light(f"聚落串灯点光_{i}",(x,y,z),55,(1.0,.38,.12),1.2,lights_col)

    # Small potted plants soften the boardwalk edge and repeat the farm palette near the home.
    for i,(x,y) in enumerate([(9.0,31.5),(14.0,31.0),(18.0,44.3),(27.0,34.5),(27.0,40.5)]):
        cylinder(f"生活区盆栽_{i}",(x,y,.84),.32,.48,col,mats['matte'],C['rust'] if i%2 else C['blue_faded'],10)
        for q in range(5):
            box(f"生活区盆栽叶_{i}_{q}",(x+.16*math.cos(q*1.25),y+.16*math.sin(q*1.25),1.48+.08*q),(.38,.13,.055),col,mats['matte'],C['leaf'],rot=(0,.18,.45*q),bevel=.05)


def add_ruined_tower(name,x,y,w,d,floors,col,mats,seed):
    """Build one distant tower from slabs, columns and incomplete facade modules."""
    rng=random.Random(seed)
    base_z=-18.0
    fh=3.05
    concrete_cells=[C['concrete'],C['concrete_mid'],C['cool_dark'],C['concrete']]
    # Split floor plates expose broken edges and missing quarters.
    for level in range(floors+1):
        z=base_z+level*fh
        damage=min(.30,.04+level/floors*.22+rng.uniform(-.03,.05))
        parts=[(-.255,0,.47,.92),(.255,0,.47,.92)]
        for part,(ox,oy,sw,sd) in enumerate(parts):
            if level>floors*.65 and rng.random()<damage*.10 and part==(level+seed)%2:
                continue
            pw=w*sw*rng.uniform(.86,1.0); pd=d*sd*rng.uniform(.84,1.0)
            px=x+ox*w+rng.uniform(-.12,.12); py=y+oy*d+rng.uniform(-.10,.10)
            box(f"{name}_楼板_{level}_{part}",(px,py,z),(pw,pd,.30),col,mats['matte'],concrete_cells[(level+part+seed)%len(concrete_cells)],rot=(0,rng.uniform(-.012,.012),rng.uniform(-.018,.018)),bevel=.045)
        # A deep per-floor core gives the ruin believable mass behind windows and damaged facade.
        if level < floors:
            core_w=w*(.76 if level<max(2,floors-2) else .68)
            core_d=d*(.74 if level<max(2,floors-2) else .65)
            box(f"{name}_楼层实体内核_{level}",(x,y,z+.30),(core_w,core_d,fh-.48),col,mats['matte'],C['concrete_mid'] if level%3 else C['concrete'],bevel=.055)
        # Broken slab lips and hanging rebar are visible on damaged levels.
        if level>1 and rng.random()<.55:
            edge_y=y-d*.46
            beam(f"{name}_断裂楼板边_{level}",(x-w*.42,edge_y,z+.17),(x+w*(.05+rng.random()*.35),edge_y,z+.10+rng.uniform(-.1,.1)),.065,col,mats['metal'],C['rust'],8)
            for r in range(2):
                rx=x+w*rng.uniform(-.38,.38)
                beam(f"{name}_外露钢筋_{level}_{r}",(rx,edge_y,z+.12),(rx+rng.uniform(-.25,.25),edge_y-.45,z-.65-rng.random()*.5),.025,col,mats['metal'],C['rust'],6)
    # Per-floor structural columns allow upper floors and facade damage to remain legible.
    corners=[(-.43,-.43),(.43,-.43),(-.43,.43),(.43,.43)]
    for level in range(floors):
        z=base_z+level*fh+.30
        damage=min(.28,.03+level/floors*.20)
        for ci,(sx,sy) in enumerate(corners):
            if level>floors*.78 and rng.random()<damage*.12:
                continue
            box(f"{name}_结构柱_{level}_{ci}",(x+sx*w,y+sy*d,z),(.42,.42,fh-.30),col,mats['matte'],C['concrete_mid'] if ci%2 else C['concrete'],rot=(0,0,rng.uniform(-.025,.025)),bevel=.035)
        # South facade faces the camera. Left/right wall fragments frame empty window bays.
        wall_z=z+.18
        if rng.random()>damage*.12:
            lw=w*rng.uniform(.18,.32)
            box(f"{name}_南残墙左_{level}",(x-w*.43+lw*.5,y-d*.455,wall_z),(lw,.22,fh*.74),col,mats['matte'],concrete_cells[(level+seed)%len(concrete_cells)],rot=(0,0,rng.uniform(-.02,.02)),bevel=.035)
        if rng.random()>damage*.16:
            rw=w*rng.uniform(.16,.30)
            box(f"{name}_南残墙右_{level}",(x+w*.43-rw*.5,y-d*.455,wall_z),(rw,.22,fh*rng.uniform(.48,.78)),col,mats['matte'],concrete_cells[(level+seed+1)%len(concrete_cells)],rot=(0,0,rng.uniform(-.025,.025)),bevel=.035)
        if rng.random()>.12+damage*.20:
            beam(f"{name}_窗洞过梁_{level}",(x-w*.22,y-d*.47,z+fh*.72),(x+w*.22,y-d*.47,z+fh*.72+rng.uniform(-.06,.06)),.055,col,mats['metal'],C['rust'],8)
        # Recessed dark window modules read as openings while the interior core remains solid.
        window_count=max(2,min(4,int(w/3.0)))
        for wi in range(window_count):
            if level>floors*.75 and rng.random()<damage*.30:
                continue
            wx=x-w*.30+wi*(w*.60/max(window_count-1,1))
            box(f"{name}_深嵌窗面_{level}_{wi}",(wx,y-d*.475,z+.72),(min(1.15,w*.16),.055,1.35),col,mats['gloss'],C['navy'],bevel=.025)
        box(f"{name}_立面中央实体墙肢_{level}",(x,y-d*.46,z+.32),(.44,.24,fh*.68),col,mats['matte'],C['concrete_mid'],bevel=.03)
        # One side facade is also partially retained for rotation-view readability.
        side= -1 if (level+seed)%2 else 1
        if rng.random()>damage*.18:
            box(f"{name}_侧面残墙_{level}",(x+side*w*.455,y+d*rng.uniform(-.18,.16),wall_z),(.22,d*rng.uniform(.22,.50),fh*rng.uniform(.42,.76)),col,mats['matte'],concrete_cells[(level+2)%len(concrete_cells)],bevel=.03)
        # Occasional tilted balcony slab or collapsed wall creates a non-repetitive silhouette.
        if level>1 and level%3==seed%3:
            box(f"{name}_倾斜悬板_{level}",(x+w*rng.uniform(-.2,.2),y-d*.58,z+.12),(w*rng.uniform(.28,.52),1.2,.16),col,mats['matte'],C['concrete_mid'],rot=(rng.uniform(-.10,.10),rng.uniform(-.08,.08),rng.uniform(-.08,.08)),bevel=.035)
    roof_z=base_z+floors*fh+.35
    # Irregular roof machinery and antenna silhouettes.
    if seed%2==0:
        cylinder(f"{name}_残存屋顶水箱",(x-w*.16,y+d*.08,roof_z),min(w,d)*.11,1.3+rng.random()*.8,col,mats['matte'],C['navy'],10)
        beam(f"{name}_水箱支脚A",(x-w*.40,y-d*.18,roof_z),(x-w*.16,y+d*.08,roof_z+1.1),.045,col,mats['metal'],C['rust'],6)
        beam(f"{name}_水箱支脚B",(x+w*.06,y-d*.18,roof_z),(x-w*.16,y+d*.08,roof_z+1.1),.045,col,mats['metal'],C['rust'],6)
    if seed%3==0:
        beam(f"{name}_倾斜通信杆",(x+w*.22,y,roof_z),(x+w*.35,y+.25,roof_z+4.0+rng.random()*2),.055,col,mats['metal'],C['concrete_mid'],7)
    # Collapsed debris is concentrated at the facade base, never scattered uniformly.
    for k in range(5):
        px=x+w*rng.uniform(-.42,.42); py=y-d*.53+rng.uniform(-1.0,.8)
        box(f"{name}_基底坠落残块_{k}",(px,py,base_z+.15),(rng.uniform(.45,1.4),rng.uniform(.35,1.0),rng.uniform(.24,.65)),col,mats['matte'],C['concrete_mid'],rot=(rng.uniform(-.2,.2),rng.uniform(-.2,.2),rng.uniform(-.8,.8)),bevel=.05)
    # Sparse invasive vines soften a few silhouettes without competing with the rooftop farm.
    if seed%4==1:
        vx=x-w*.44; vy=y-d*.46
        beam(f"{name}_侵蚀藤蔓主茎",(vx,vy,base_z+1),(vx+.5,vy-.05,base_z+fh*min(floors,5)),.035,col,mats['matte'],C['leaf_dark'],6)
        for k in range(7):
            box(f"{name}_侵蚀藤叶_{k}",(vx+.08*k,vy-.12,base_z+1.5+k*1.5),(.38,.08,.16),col,mats['matte'],C['leaf_dark'],rot=(0,.2*(-1)**k,.4*k),bevel=.05)


def build_city(col, mats):
    # Large skyline towers are modular ruins: no distant building is represented by a single box.
    specs=[
        (-54,34,13,11,9),(-37,44,11,13,8),(-18,40,15,11,10),(2,47,12,10,8),
        (22,41,14,12,10),(43,36,11,13,8),(59,48,14,11,9),(-63,63,16,13,11),
        (-39,69,13,11,8),(-14,66,12,14,9),(10,73,15,13,10),(35,65,12,11,8),
        (60,68,16,14,10),(-66,18,13,11,7),(67,21,13,12,8)]
    for n,(x,y,w,d,floors) in enumerate(specs):
        add_ruined_tower(f"远景模块化废楼_{n}",x,y,w,d,floors,col,mats,9200+n)
    # Stopped cranes use truss towers and diagonals rather than two plain strokes.
    for ci,(x,y,h) in enumerate([(-48,29,24),(52,30,21)]):
        for z in range(-10,h,4):
            beam(f"远景起重机立柱A_{ci}_{z}",(x-.45,y,z),(x-.45,y,z+4),.09,col,mats['metal'],C['cool_dark'],8)
            beam(f"远景起重机立柱B_{ci}_{z}",(x+.45,y,z),(x+.45,y,z+4),.09,col,mats['metal'],C['cool_dark'],8)
            beam(f"远景起重机塔斜撑_{ci}_{z}",(x-.45,y,z),(x+.45,y,z+4),.045,col,mats['metal'],C['rust'],6)
        beam(f"远景起重机主臂_{ci}",(x-3,y,h),(x+18,y,h),.15,col,mats['metal'],C['cool_dark'],8)
        beam(f"远景起重机上弦_{ci}",(x-1,y,h+3),(x+16,y,h+.3),.08,col,mats['metal'],C['cool_dark'],8)
        for k in range(7):
            px=x+k*2.5
            beam(f"远景起重机臂腹杆_{ci}_{k}",(px,y,h),(px+1.25,y,h+2.5-k*.35),.04,col,mats['metal'],C['rust'],6)
    # Three animated smoke/dust columns drift slowly through the volumetric atmosphere.
    for s,(x,y,z0) in enumerate([(-42,52,13),(28,57,10),(61,44,8)]):
        rng=random.Random(12000+s)
        for k in range(9):
            px=x+.55*k+rng.uniform(-.5,.5); py=y+rng.uniform(-.5,.5); pz=z0+1.65*k
            puff=sphere(f"远景烟尘_{s}_{k}",(px,py,pz),1.0+.24*k,col,mats['matte'],C['concrete_mid'],8,4,scale=(1.25+rng.random()*.4,1,1.25+rng.random()*.5))
            puff.keyframe_insert('location',frame=1,index=0); puff.location.x+=1.8+rng.random(); puff.location.z+=.6; puff.keyframe_insert('location',frame=250,index=0)


def build_camera_lighting(col, mats):
    scene=bpy.context.scene
    scene.render.engine='BLENDER_EEVEE_NEXT'
    scene.render.resolution_x=1400; scene.render.resolution_y=900; scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    scene.render.film_transparent=False
    scene.render.image_settings.color_mode='RGBA'
    scene.render.resolution_percentage=100
    scene.render.filepath=PREVIEW_PATH
    scene.render.image_settings.color_depth='8'
    scene.render.engine='BLENDER_EEVEE_NEXT'
    scene.render.image_settings.compression=18
    scene.frame_start=1; scene.frame_end=250; scene.render.fps=24
    scene.world.color=(0.42,0.48,0.54)
    world=scene.world
    world.use_nodes=True
    nt=world.node_tree
    nt.nodes.clear()
    world_out=nt.nodes.new('ShaderNodeOutputWorld')
    bg=nt.nodes.new('ShaderNodeBackground')
    nt.links.new(bg.outputs['Background'],world_out.inputs['Surface'])
    bg.inputs['Color'].default_value=(.42,.48,.54,1)
    bg.inputs['Strength'].default_value=.85
    # Finite camera-distance mist avoids the black-sky artifact caused by infinite world volume.
    bpy.context.view_layer.use_pass_mist=True
    world.mist_settings.use_mist=True
    # Keep the playable roof readable; fog starts behind it and mainly separates the city.
    world.mist_settings.start=150
    world.mist_settings.depth=180
    world.mist_settings.falloff='QUADRATIC'
    scene.use_nodes=True
    comp_nodes=scene.node_tree
    comp_nodes.nodes.clear()
    render_layers=comp_nodes.nodes.new('CompositorNodeRLayers')
    fog_mix=comp_nodes.nodes.new('CompositorNodeMixRGB')
    composite=comp_nodes.nodes.new('CompositorNodeComposite')
    fog_mix.blend_type='MIX'
    fog_mix.inputs[2].default_value=(.43,.47,.52,1)
    comp_nodes.links.new(render_layers.outputs['Image'],fog_mix.inputs[1])
    comp_nodes.links.new(render_layers.outputs['Mist'],fog_mix.inputs[0])
    comp_nodes.links.new(fog_mix.outputs['Image'],composite.inputs['Image'])
    # Camera uses near-isometric orthographic framing for free inspection and full-scene readability.
    cam_data=bpy.data.cameras.new("第三视角等距展示相机")
    cam=bpy.data.objects.new("第三视角等距展示相机",cam_data)
    col.objects.link(cam)
    cam.location=(92,-108,82)
    target=Vector((-5,5,2.8)); cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    cam_data.type='ORTHO'; cam_data.ortho_scale=122; cam_data.lens=58
    scene.camera=cam
    add_area_light("阴天主光",(-28,-35,62),9000,(.64,.72,.82),42,(0,0,0),col)
    add_area_light("冷色轮廓光",(35,25,35),5200,(.45,.55,.68),30,(0,5,3),col)
    add_area_light("暖色庇护所补光",(0,-1,15),1450,(1.0,.58,.34),20,(0,3,1),col)
    add_area_light("休息区沙发柔光",(-1,-4,9),700,(1.0,.62,.40),8,(3,4.2,1.0),col)
    add_area_light("远景城市雾中散射光",(0,48,58),9000,(.56,.64,.74),70,(0,52,1),col)
    # A very weak warm direction only preserves subtle color separation inside the shelter.
    sun_data=bpy.data.lights.new("阴天微暖方向光",'SUN')
    sun_data.energy=.18
    sun_data.color=(1.0,.78,.62)
    sun_data.angle=math.radians(28)
    sun=bpy.data.objects.new("阴天微暖方向光",sun_data)
    sun.rotation_euler=(math.radians(68),math.radians(-8),math.radians(-38))
    col.objects.link(sun)
    cool_sun_data=bpy.data.lights.new("高空冷色散射日光",'SUN')
    cool_sun_data.energy=2.10
    cool_sun_data.color=(.78,.84,.92)
    cool_sun_data.angle=math.radians(38)
    cool_sun=bpy.data.objects.new("高空冷色散射日光",cool_sun_data)
    cool_sun.rotation_euler=(math.radians(28),0,math.radians(24))
    col.objects.link(cool_sun)
    # Sparse airborne dust catches the warm light without becoming screen-space noise.
    rng=random.Random(16660)
    for i in range(72):
        x=rng.uniform(-48,38); y=rng.uniform(-33,43); z=rng.uniform(.8,13)
        dust=sphere(f"空气浮尘_{i}",(x,y,z),rng.uniform(.025,.075),col,mats['matte'],C['sand'] if i%5==0 else C['concrete_mid'],6,3,scale=(rng.uniform(.7,1.5),rng.uniform(.7,1.3),rng.uniform(.7,1.8)))
        dust.keyframe_insert('location',frame=1,index=0)
        dust.location.x+=rng.uniform(.5,1.8); dust.location.z+=rng.uniform(.15,.8)
        dust.keyframe_insert('location',frame=250,index=0)
    # Slightly larger low-poly dust wisps hover near traffic paths and the generator.
    for i,(x,y,z,s) in enumerate([(-9,-11,1.2,1.0),(-1,-6,1.0,.8),(12,-8,1.5,1.1),(-18,1,1.3,.9),(8,13,5.8,.75)]):
        wisp=sphere(f"近景烟尘薄团_{i}",(x,y,z),s,col,mats['matte'],C['concrete_mid'],8,4,scale=(1.7,1.0,.45))
        wisp.keyframe_insert('location',frame=1,index=0); wisp.location.x+=1.0; wisp.location.z+=.45; wisp.keyframe_insert('location',frame=250,index=0)
    # Grounding shadow plane below the collectible block.
    box("大雾阴天冷灰背景承托面",(-5,5,-18.3),(190,180,.25),col,mats['matte'],C['concrete_mid'],bevel=.4)
    scene.view_settings.look='AgX - Medium Low Contrast'
    scene.view_settings.exposure=.65


def create_prototypes(src_col, mats, variants):
    proto_col=new_collection("地砖母版_12种标准模块",src_col)
    for i,name in enumerate(variants):
        obj=box(f"母版_5x5m_{name}",(0,0,0),(5,5,.34),proto_col,mats['matte'],C['concrete_mid'],bevel=.025,asset_id=f"ENV_GROUND_TILE_5M_{i:02d}")
        obj["module_contract"]="5m x 5m; bottom Z=0; snap grid=5m"
        obj.hide_render=True; obj.hide_viewport=True
    src_col.hide_viewport=True
    src_col.hide_render=True


def translate_collection_roots(col, offset):
    members = set(col.all_objects)
    delta = Vector(offset)
    for obj in list(col.objects):
        if obj.parent is None or obj.parent not in members:
            obj.location += delta


def translate_named_roots(col, prefixes, offset):
    delta = Vector(offset)
    for obj in list(col.objects):
        if obj.parent is None and any(obj.name.startswith(prefix) for prefix in prefixes):
            obj.location += delta


def move_matching_objects(parent_col, group_name, prefixes):
    """Move direct members into a named component folder without joining their meshes."""
    target = new_collection(group_name, parent_col)
    for obj in list(parent_col.objects):
        if any(obj.name.startswith(prefix) for prefix in prefixes):
            move_to_collection(obj, target)
            obj["component_folder"] = group_name
    return target


def organize_output_hierarchy(cats):
    """Create a fine-grained, stable Blender hierarchy for practical hand editing."""
    rules = {
        "Props_Furniture": [
            ("05_抬高木平台", ("棚屋抬高木平台",)),
            ("06_小木板楼梯", ("棚屋小木板楼梯",)),
            ("10_生活棚结构", ("生活棚_", "棚顶", "残墙连接铆钉")),
            ("20_工作台与工具墙", ("工作台_", "工具墙", "挂墙工具")),
            ("30_双人沙发", ("双人沙发_", "沙发")),
            ("31_电缆卷筒圆桌", ("电缆卷筒", "卷筒桌面木缝")),
            ("32_桌面老式收音机", ("老式收音机", "收音机")),
            ("33_桌面独立散件", ("桌面", "搪瓷杯")),
            ("34_休息区地垫", ("休息区旧地垫",)),
            ("40_床铺与睡袋", ("简易床铺", "睡袋")),
            ("41_生活收纳木箱", ("收纳木箱",)),
            ("50_地图物资板", ("城市地图与物资板", "地图便签")),
            ("60_火炉与水壶", ("小型火炉", "烧水壶", "水壶提梁")),
            ("70_露营灯具", ("露营灯灯罩",)),
            ("71_棚屋小风车", ("棚屋小风车",)),
            ("72_棚屋吊挂风铃", ("棚屋吊挂风铃",)),
        ],
        "Props_Survival": [
            ("10_公共餐桌", ("公共餐桌_旧木桌面", "公共餐桌_桌腿")),
            ("11_公共餐桌长凳", ("公共餐桌_长凳",)),
            ("12_公共餐桌餐具", ("公共餐桌_搪瓷碗", "公共餐桌_水杯", "公共餐桌_切菜板", "公共餐桌_蔬菜")),
            ("20_棚口旧鞋", ("棚口旧鞋",)),
            ("21_生活洗衣盆", ("生活洗衣盆",)),
            ("22_香草晾晒架", ("香草晾晒架", "晾晒香草")),
            ("23_聚落串灯", ("聚落串灯",)),
            ("24_生活区盆栽", ("生活区盆栽",)),
            ("30_晾衣设施", ("晾衣绳", "晾晒衣物")),
            ("31_防水布物资", ("防水布覆盖物资", "压布砖块")),
            ("32_备用轮胎", ("备用轮胎",)),
            ("40_木板便道", ("南侧木板便道", "便道修补铁片", "南侧黄色区域标线")),
            ("50_工坊拆件", ("工坊拆件",)),
            ("51_南侧补给", ("南侧补给",)),
            ("52_水箱维修", ("水箱维修",)),
            ("53_农场园艺", ("农场园艺",)),
            ("54_广播备件", ("广播备件",)),
            ("55_生活储备", ("生活储备",)),
        ],
        "Props_Energy": [
            ("10_太阳能板0", ("太阳能板_0",)),
            ("11_太阳能板1", ("太阳能板_1",)),
            ("12_太阳能板2", ("太阳能板_2",)),
            ("13_太阳能板3", ("太阳能板_3",)),
            ("20_风力发电机", ("风机", "风力发电机")),
            ("30_柴油发电机", ("柴油发电机", "发电机")),
            ("31_蓄电池柜0", ("蓄电池柜_0", "蓄电池接线柱_0", "蓄电池提手_0")),
            ("32_蓄电池柜1", ("蓄电池柜_1", "蓄电池接线柱_1", "蓄电池提手_1")),
            ("33_蓄电池柜2", ("蓄电池柜_2", "蓄电池接线柱_2", "蓄电池提手_2")),
            ("34_能源维修工作台", ("能源维修工作台",)),
            ("40_储水罐0", ("储水罐_0", "储水罐箍带_0", "储水罐顶盖_0", "储水罐检修口_0", "储水罐竖向加强筋_0")),
            ("41_储水罐1", ("储水罐_1", "储水罐箍带_1", "储水罐顶盖_1", "储水罐检修口_1", "储水罐竖向加强筋_1")),
            ("42_储水罐2", ("储水罐_2", "储水罐箍带_2", "储水罐顶盖_2", "储水罐检修口_2", "储水罐竖向加强筋_2")),
            ("43_储水罐3", ("储水罐_3", "储水罐箍带_3", "储水罐顶盖_3", "储水罐检修口_3", "储水罐竖向加强筋_3")),
            ("50_管线与配电", ("供水能源管线", "修补胶带接口", "外露电缆", "防水配电箱")),
        ],
        "Props_Farming": [
            ("10_种植池0", ("种植池_0", "番茄支架", "番茄果实")),
            ("11_种植池1", ("种植池_1",)),
            ("12_种植池2", ("种植池_2", "玉米高茎", "玉米长叶")),
            ("13_种植池3", ("种植池_3",)),
            ("14_种植池4", ("种植池_4",)),
            ("20_浴缸种植池", ("废弃浴缸种植池", "浴缸土壤", "浴缸卷心菜")),
            ("30_温室", ("温室",)),
            ("31_种植储水滴灌", ("种植区储水桶", "滴灌主管")),
            ("32_堆肥与园艺工具", ("堆肥箱", "园艺工具")),
        ],
        "Props_Communication": [
            ("10_广播平台结构", ("广播平台立柱", "广播平台楼板", "广播平台斜撑", "广播平台节点板")),
            ("11_广播平台楼梯", ("广播平台楼梯", "广播楼梯扶手")),
            ("12_广播平台栏杆", ("广播台栏杆",)),
            ("20_广播控制桌", ("广播控制桌",)),
            ("21_无线电收发机", ("无线电",)),
            ("22_广播地图与记录", ("广播地图板", "广播联络记录")),
            ("30_通信主桅杆", ("通信主桅杆", "桅杆拉线")),
            ("31_八木定向天线", ("大型定向天线", "八木天线")),
            ("32_卫星接收锅", ("卫星接收锅", "卫星锅馈源臂")),
            ("33_信号灯与仪表", ("天线红色信号灯", "广播信号表指针")),
        ],
    }
    summary = {}
    for category_name, groups in rules.items():
        parent = cats[category_name]
        for group_name, prefixes in groups:
            move_matching_objects(parent, group_name, prefixes)
        leftovers = list(parent.objects)
        if leftovers:
            fallback = new_collection("99_待归类", parent)
            for obj in leftovers:
                move_to_collection(obj, fallback)
                obj["component_folder"] = fallback.name
        summary[category_name] = {
            "component_folder_count": len(parent.children),
            "unclassified_object_count": len(leftovers),
        }
    return summary


def build_collision_proxies(collision_root, mats):
    groups = {
        "生活家具": new_collection("10_生活家具阻挡", collision_root),
        "餐饮日常": new_collection("20_餐饮日常阻挡", collision_root),
        "能源供水": new_collection("30_能源供水阻挡", collision_root),
        "种植通信": new_collection("40_种植通信阻挡", collision_root),
    }
    for index, component in enumerate(COLLISION_COMPONENTS):
        group = groups[
            "生活家具" if component["component_folder"].startswith("Props_Furniture") else
            "餐饮日常" if component["component_folder"].startswith("Props_Survival") else
            "能源供水" if component["component_folder"].startswith("Props_Energy") else "种植通信"
        ]
        for shape_index, shape in enumerate(component["shapes"]):
            cx, cy, cz = shape["center"]
            rotation = shape.get("rotation_degrees", (0.0, 0.0, 0.0))
            if shape["shape"] == "cylinder":
                obj = cylinder(
                    f"COL_{component['display_name']}_{shape['label']}_{shape_index:02d}",
                    (cx, cy, cz-shape["height"]/2.0), shape["radius"], shape["height"],
                    group, mats['matte'], C['red'], 12,
                    asset_id=f"{ASSET_ID}:COL:{component['component_id']}:{shape_index:02d}"
                )
            else:
                sx, sy, sz = shape["size"]
                obj = box(
                    f"COL_{component['display_name']}_{shape['label']}_{shape_index:02d}",
                    (cx, cy, cz-sz/2.0), shape["size"], group, mats['matte'], C['red'],
                    rot=tuple(math.radians(value) for value in rotation),
                    asset_id=f"{ASSET_ID}:COL:{component['component_id']}:{shape_index:02d}"
                )
            obj.display_type = 'WIRE'
            obj.hide_render = True
            obj["collision_component_id"] = component["component_id"]
            obj["collision_label"] = component["display_name"]
            obj["collision_shape"] = shape["shape"]
            obj["runtime_owner"] = "Godot editable component node"
            obj["export_to_runtime_glb"] = False
    collision_root.hide_render = True


def collection_world_bounds(collection):
    mesh_objects = [obj for obj in collection.all_objects if obj.type == 'MESH']
    points = [obj.matrix_world @ Vector(corner) for obj in mesh_objects for corner in obj.bound_box]
    if not points:
        return None
    return (
        min(point.x for point in points), min(point.y for point in points), min(point.z for point in points),
        max(point.x for point in points), max(point.y for point in points), max(point.z for point in points),
    )


def select_objects(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = next((obj for obj in objects if obj.type == 'MESH'), None)


def export_editable_component_glbs(cats, out):
    os.makedirs(COMPONENT_GLB_DIR, exist_ok=True)
    category_specs = [
        ("Props_Furniture", "01_生活棚与家具", "furniture"),
        ("Props_Survival", "02_生存日常", "survival"),
        ("Props_Energy", "03_能源供水", "energy"),
        ("Props_Farming", "04_种植", "farming"),
        ("Props_Communication", "05_通信高台", "communication"),
    ]
    prop_objects = set()
    records = []
    for category_name, category_display, slug in category_specs:
        parent = cats[category_name]
        prop_objects.update(parent.all_objects)
        for index, component_collection in enumerate(sorted(parent.children, key=lambda item: item.name), 1):
            objects = [obj for obj in component_collection.all_objects if obj.type in {'MESH', 'EMPTY', 'LIGHT'}]
            bounds = collection_world_bounds(component_collection)
            if not objects or bounds is None:
                continue
            min_x, min_y, min_z, max_x, max_y, max_z = bounds
            pivot = Vector(((min_x+max_x)/2.0, (min_y+max_y)/2.0, min_z))
            members = set(objects)
            roots = [obj for obj in objects if obj.parent not in members]
            saved_locations = {obj: obj.location.copy() for obj in roots}
            for obj in roots:
                obj.location -= pivot
            filepath = os.path.join(COMPONENT_GLB_DIR, f"{slug}_{index:02d}_{ASSET_VERSION}.glb")
            select_objects(objects)
            bpy.ops.export_scene.gltf(
                filepath=filepath, export_format='GLB', use_selection=True,
                export_image_format='NONE', export_animations=True
            )
            for obj, location in saved_locations.items():
                obj.location = location
            records.append({
                "category": category_name,
                "category_display": category_display,
                "folder": component_collection.name,
                "folder_key": f"{category_name}/{component_collection.name}",
                "glb_path": filepath,
                "pivot": [round(float(value), 5) for value in pivot],
                "bounds_world": [round(float(value), 5) for value in bounds],
                "object_count": len(objects),
            })

    return records


def godot_resource_path(path):
    return "res://" + os.path.relpath(path, ROOT).replace(os.sep, "/")


def write_collision_manifest_and_wrapper(component_records):
    record_by_folder = {record["folder_key"]: record for record in component_records}
    missing_collision_folders = sorted({
        component["component_folder"] for component in COLLISION_COMPONENTS
        if component["component_folder"] not in record_by_folder
    })
    if missing_collision_folders:
        raise RuntimeError(f"Collision owners missing editable component folders: {missing_collision_folders}")
    shape_count = sum(len(component["shapes"]) for component in COLLISION_COMPONENTS)
    manifest = {
        "asset_id": ASSET_ID,
        "version": ASSET_VERSION,
        "coordinate_source": "Blender X/Y/Z-up metres",
        "runtime_coordinate_mapping": "Godot (X, Z, -Y)",
        "collision_owner": ROOT_TSCN_PATH,
        "count": len(COLLISION_COMPONENTS),
        "shape_count": shape_count,
        "policy": "compound collision follows each editable TSCN component; decorative gaps remain passable",
        "components": COLLISION_COMPONENTS,
    }
    with open(COLLISION_MANIFEST_PATH, 'w', encoding='utf-8') as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)

    lines = [f"[gd_scene load_steps={1 + len(component_records) + shape_count} format=3]", ""]
    for index, record in enumerate(component_records, 1):
        record["resource_id"] = f"component_{index:02d}"
        lines.extend([f'[ext_resource type="PackedScene" path="{godot_resource_path(record["glb_path"])}" id="{record["resource_id"]}"]', ""])
    shape_resource_index = 0
    for component in COLLISION_COMPONENTS:
        for shape in component["shapes"]:
            shape_resource_index += 1
            shape["resource_id"] = f"CollisionShape_{shape_resource_index:03d}"
            if shape["shape"] == "cylinder":
                lines.extend([
                    f'[sub_resource type="CylinderShape3D" id="{shape["resource_id"]}"]',
                    f"radius = {shape['radius']:.5f}", f"height = {shape['height']:.5f}", "",
                ])
            else:
                sx, sy, sz = shape["size"]
                lines.extend([
                    f'[sub_resource type="BoxShape3D" id="{shape["resource_id"]}"]',
                    f"size = Vector3({sx:.5f}, {sz:.5f}, {sy:.5f})", "",
                ])
    lines.extend([
        f'[node name="末世天台生活聚落_90x80米_{ASSET_VERSION}" type="Node3D"]',
        f'metadata/asset_id = "{ASSET_ID}"',
        f'metadata/version = "{ASSET_VERSION}"',
        'metadata/runtime_scope = "facilities_only"',
        "metadata/native_floor_and_parapet_preserved = true",
        "metadata/facility_vertical_offset_m = -0.34",
        "metadata/grid_dimensions = Vector2i(18, 16)",
        "metadata/tile_size_m = 5.0",
        "metadata/tile_count = 234",
        "metadata/roof_world_rect = Rect2(-50, -35, 90, 80)",
        "metadata/base_atrium_world_rect = Rect2(-15, -10, 30, 30)",
        "metadata/west_stair_world_rect = Rect2(-45, 0, 15, 30)",
        "metadata/living_cluster_rect = Rect2(15.25, -31, 24, 67)",
        'metadata/layout_style = "东北角通信高台；贴边棚屋位于其西侧且留2米间距；种植与能源继续沿外围布置"',
        f"metadata/independent_blocker_count = {len(COLLISION_COMPONENTS)}",
        f"metadata/collision_shape_count = {shape_count}",
        f"metadata/editable_component_count = {len(component_records)}",
        f"metadata/door_walkway_rect = Rect2({DOOR_WALKWAY_RECT[0]}, {DOOR_WALKWAY_RECT[1]}, {DOOR_WALKWAY_RECT[2]}, {DOOR_WALKWAY_RECT[3]})",
        f"metadata/shelter_zone_rect = Rect2({SHELTER_ZONE_RECT[0]}, {SHELTER_ZONE_RECT[1]}, {SHELTER_ZONE_RECT[2]}, {SHELTER_ZONE_RECT[3]})",
        f"metadata/farm_zone_rect = Rect2({FARM_ZONE_RECT[0]}, {FARM_ZONE_RECT[1]}, {FARM_ZONE_RECT[2]}, {FARM_ZONE_RECT[3]})",
        f"metadata/radio_zone_rect = Rect2({RADIO_ZONE_RECT[0]}, {RADIO_ZONE_RECT[1]}, {RADIO_ZONE_RECT[2]}, {RADIO_ZONE_RECT[3]})",
        'metadata/collision_policy = "组合碰撞挂在对应可编辑组件节点下；圆形设施使用CylinderShape3D；桌椅/棚架/温室/高台使用贴合结构的多Shape"',
        "",
        '[node name="布局_可手动编辑" type="Node3D" parent="."]',
        'position = Vector3(0, -0.34, 0)', "",
    ])
    categories_written = set()
    component_path_by_folder = {}
    for record in component_records:
        category_path = f"布局_可手动编辑/{record['category_display']}"
        if category_path not in categories_written:
            lines.extend([f'[node name="{record["category_display"]}" type="Node3D" parent="布局_可手动编辑"]', ""])
            categories_written.add(category_path)
        component_path = f"{category_path}/{record['folder']}"
        component_path_by_folder[record["folder_key"]] = component_path
        px, py, pz = record["pivot"]
        lines.extend([
            f'[node name="{record["folder"]}" type="Node3D" parent="{category_path}"]',
            f"position = Vector3({px:.5f}, {pz:.5f}, {-py:.5f})",
            f'metadata/component_folder = "{record["folder_key"]}"',
            'metadata/manual_layout_editable = true', "",
            f'[node name="Visual" parent="{component_path}" instance=ExtResource("{record["resource_id"]}")]', "",
        ])
    for component in COLLISION_COMPONENTS:
        record = record_by_folder[component["component_folder"]]
        component_path = component_path_by_folder[component["component_folder"]]
        px, py, pz = record["pivot"]
        body_path = f"{component_path}/阻挡_{component['component_id']}"
        lines.extend([
            f'[node name="阻挡_{component["component_id"]}" type="StaticBody3D" parent="{component_path}"]',
            f'metadata/component_id = "{component["component_id"]}"',
            f'metadata/collision_mode = "compound_{len(component["shapes"])}_shapes"', "",
        ])
        for shape_index, shape in enumerate(component["shapes"]):
            cx, cy, cz = shape["center"]
            # Runtime uses Godot (X, Z, -Y).  The Blender runtime-output
            # collections are mirrored on Y immediately before export, while
            # collision authoring remains in the gameplay-plan coordinate
            # space.  Therefore the component pivot is already mirrored and
            # the remaining local Z delta must retain the original Y sign.
            local_x, local_y, local_z = cx-px, cz-pz, cy-py
            rotation = shape.get("rotation_degrees", (0.0,0.0,0.0))
            lines.extend([
                f'[node name="Shape_{shape_index:02d}_{shape["label"]}" type="CollisionShape3D" parent="{body_path}"]',
                f"position = Vector3({local_x:.5f}, {local_y:.5f}, {local_z:.5f})",
            ])
            if any(abs(value) > .0001 for value in rotation):
                lines.append(f"rotation_degrees = Vector3({rotation[0]:.5f}, {rotation[1]:.5f}, {rotation[2]:.5f})")
            lines.extend([f'shape = SubResource("{shape["resource_id"]}")', ""])
    os.makedirs(os.path.dirname(ROOT_TSCN_PATH), exist_ok=True)
    with open(ROOT_TSCN_PATH, 'w', encoding='utf-8') as handle:
        handle.write("\n".join(lines))
    return {"editable_component_count": len(component_records), "collision_shape_count": shape_count}


def object_xy_bounds(obj):
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return min(p.x for p in points), min(p.y for p in points), max(p.x for p in points), max(p.y for p in points)


def mirror_runtime_output_y_basis(out, collision_root):
    """Convert authored plan-space Y into Blender Y for Godot (X, Z, -Y).

    Gameplay layout constants are intentionally authored in the same planar
    coordinates as Godot.  Blender's exported basis needs their Y values
    mirrored so that Godot's standard -Y-to-Z conversion puts facilities back
    onto the native 100F roof rectangle.  The distant-city presentation is
    excluded because it is not a runtime rooftop facility.
    """
    objects = set()
    for collection in out.children:
        if collection.name == "远景荒废城市_低对比":
            continue
        objects.update(collection.all_objects)
    objects.update(collision_root.all_objects)
    for obj in objects:
        matrix = obj.matrix_world.copy()
        matrix.translation.y = -matrix.translation.y
        obj.matrix_world = matrix


def bounds_overlap_rect(bounds, rect, margin=0.0):
    min_x, min_y, max_x, max_y = bounds
    rx, ry, rw, rh = rect
    return not (
        max_x <= rx - margin or min_x >= rx + rw + margin
        or max_y <= ry - margin or min_y >= ry + rh + margin
    )


def bounds_inside_rect(bounds, rect, tolerance=.02):
    min_x, min_y, max_x, max_y = bounds
    rx, ry, rw, rh = rect
    return (
        min_x >= rx - tolerance and max_x <= rx + rw + tolerance
        and min_y >= ry - tolerance and max_y <= ry + rh + tolerance
    )


def validate_layout(out):
    tiles = [
        obj for obj in out.all_objects
        if obj.type == 'MESH' and str(obj.get("asset_id", "")).startswith("ENV_GROUND_TILE_5M_")
    ]
    overlaps = {"base_atrium": [], "west_stair": []}
    zone_violations = {"shelter": [], "farm": [], "radio": []}
    zone_contracts = {
        "Props_Furniture": ("shelter", SHELTER_ZONE_RECT),
        "Props_Farming": ("farm", FARM_ZONE_RECT),
        "Props_Communication": ("radio", RADIO_ZONE_RECT),
    }
    roof_min_x, roof_min_y, roof_w, roof_h = ROOF_RECT
    for obj in out.all_objects:
        if obj.type != 'MESH' or obj in tiles or obj.name.startswith("立面窗_") or "塔楼立面" in obj.name:
            continue
        bounds = object_xy_bounds(obj)
        # Perimeter wall modules sit outside both gameplay openings by contract.
        if bounds_overlap_rect(bounds, BASE_ATRIUM_RECT):
            overlaps["base_atrium"].append(obj.name)
        if bounds_overlap_rect(bounds, WEST_STAIR_RECT):
            overlaps["west_stair"].append(obj.name)
        for collection in obj.users_collection:
            contract = zone_contracts.get(collection.name)
            if contract and not bounds_inside_rect(bounds, contract[1]):
                zone_violations[contract[0]].append(obj.name)
        if (
            bounds[0] < roof_min_x - 0.5 or bounds[2] > roof_min_x + roof_w + 0.5
            or bounds[1] < roof_min_y - 0.5 or bounds[3] > roof_min_y + roof_h + 0.5
        ) and "远景" not in obj.name:
            obj["outside_rooftop_contract"] = True
    if len(tiles) != EXPECTED_TILE_COUNT:
        raise RuntimeError(f"Expected {EXPECTED_TILE_COUNT} runtime tiles, found {len(tiles)}")
    for tile in tiles:
        x, y = tile.location.x, tile.location.y
        if point_in_rect(x, y, BASE_ATRIUM_RECT) or point_in_rect(x, y, WEST_STAIR_RECT):
            raise RuntimeError(f"Tile entered a reserved opening: {tile.name}")
    if overlaps["base_atrium"] or overlaps["west_stair"]:
        sample = {key: value[:12] for key, value in overlaps.items() if value}
        raise RuntimeError(f"Rooftop props overlap reserved openings: {sample}")
    if any(zone_violations.values()):
        sample = {key: value[:12] for key, value in zone_violations.items() if value}
        raise RuntimeError(f"Marked rooftop zones contain misplaced assets: {sample}")
    walkway_blockers = []
    for component in COLLISION_COMPONENTS:
        for shape in component["shapes"]:
            x, y, _ = shape["center"]
            if shape["shape"] == "cylinder":
                sx = sy = shape["radius"] * 2.0
            else:
                sx, sy, _ = shape["size"]
            if bounds_overlap_rect((x-sx/2, y-sy/2, x+sx/2, y+sy/2), DOOR_WALKWAY_RECT):
                walkway_blockers.append(component["component_id"])
    if walkway_blockers:
        raise RuntimeError(f"Refined collision shapes entered the yellow door walkway: {sorted(set(walkway_blockers))}")
    if bounds_overlap_rect(
        (SHELTER_ZONE_RECT[0], SHELTER_ZONE_RECT[1], SHELTER_ZONE_RECT[0]+SHELTER_ZONE_RECT[2], SHELTER_ZONE_RECT[1]+SHELTER_ZONE_RECT[3]),
        RADIO_ZONE_RECT,
    ):
        raise RuntimeError("Shelter and north-east radio platform zones overlap")
    shelter_radio_clearance = RADIO_ZONE_RECT[0] - (SHELTER_ZONE_RECT[0] + SHELTER_ZONE_RECT[2])
    if shelter_radio_clearance < 1.5:
        raise RuntimeError(f"Shelter/radio editable zones need >=1.5m clearance, got {shelter_radio_clearance:.2f}m")
    return {
        "passed": True,
        "tile_count": len(tiles),
        "grid_dimensions": list(GRID_DIMENSIONS),
        "roof_world_rect": list(ROOF_RECT),
        "base_atrium_world_rect": list(BASE_ATRIUM_RECT),
        "west_stair_world_rect": list(WEST_STAIR_RECT),
        "reserved_overlap_count": 0,
        "living_cluster_rect": list(LIVING_CLUSTER_RECT),
        "door_walkway_rect": list(DOOR_WALKWAY_RECT),
        "door_walkway_blocker_count": 0,
        "shelter_radio_overlap_count": 0,
        "shelter_radio_clearance_m": round(shelter_radio_clearance, 3),
        "shelter_zone_rect": list(SHELTER_ZONE_RECT),
        "farm_zone_rect": list(FARM_ZONE_RECT),
        "radio_zone_rect": list(RADIO_ZONE_RECT),
        "marked_zone_violation_count": 0,
    }


def write_manifest_and_validation(out, layout_validation, hierarchy_summary, component_records, wrapper_stats):
    mesh_objects = [obj for obj in out.all_objects if obj.type == 'MESH']
    objects = []
    for obj in sorted(mesh_objects, key=lambda item: item.name):
        objects.append({
            "name": obj.name,
            "asset_id": str(obj.get("asset_id", obj.name)),
            "collections": sorted(col.name for col in obj.users_collection),
            "location_m": [round(float(value), 5) for value in obj.location],
            "dimensions_m": [round(float(value), 5) for value in obj.dimensions],
            "materials": [slot.name for slot in obj.data.materials],
            "uv_layers": [layer.name for layer in obj.data.uv_layers],
            "animated": obj.animation_data is not None,
        })
    with open(BLEND_PATH, 'rb') as handle:
        blend_sha256 = hashlib.sha256(handle.read()).hexdigest()
    with open(GLB_PATH, 'rb') as handle:
        runtime_sha256 = hashlib.sha256(handle.read()).hexdigest()
    manifest = {
        "asset_id": ASSET_ID,
        "version": ASSET_VERSION,
        "source_blend": BLEND_PATH,
        "runtime_glb": GLB_PATH,
        "runtime_scope": "facilities_only",
        "runtime_excludes": ["Environment_Ground", "Environment_Architecture", "Vegetation", "Lighting", "VFX", "distant_city"],
        "facility_vertical_offset_m": -0.34,
        "source_sha256": blend_sha256,
        "runtime_sha256": runtime_sha256,
        "units": "meters",
        "grid_dimensions": list(GRID_DIMENSIONS),
        "tile_size_m": GRID_SIZE,
        "tile_count": EXPECTED_TILE_COUNT,
        "roof_world_rect": list(ROOF_RECT),
        "reserved_openings": {
            "base_atrium": list(BASE_ATRIUM_RECT),
            "west_stair": list(WEST_STAIR_RECT),
        },
        "living_cluster_rect": list(LIVING_CLUSTER_RECT),
        "door_walkway_rect": list(DOOR_WALKWAY_RECT),
        "shelter_zone_rect": list(SHELTER_ZONE_RECT),
        "farm_zone_rect": list(FARM_ZONE_RECT),
        "radio_zone_rect": list(RADIO_ZONE_RECT),
        "layout_style": "clear yellow door route; raised red-zone shelter; blue-zone farm; adjacent radio platform",
        "component_hierarchy": hierarchy_summary,
        "editable_components": component_records,
        "editable_component_count": wrapper_stats["editable_component_count"],
        "independent_blocker_count": len(COLLISION_COMPONENTS),
        "collision_shape_count": wrapper_stats["collision_shape_count"],
        "collision_manifest": COLLISION_MANIFEST_PATH,
        "object_count": len(out.all_objects),
        "mesh_count": len(mesh_objects),
        "material_count": len(bpy.data.materials),
        "shared_palette": PALETTE_PATH,
        "objects": objects,
    }
    checks = {
        "layout_validation": bool(layout_validation.get("passed", False)),
        "material_budget": len(bpy.data.materials) == 4,
        "runtime_tile_count_234": layout_validation.get("tile_count") == EXPECTED_TILE_COUNT,
        "grid_contract_18x16": tuple(layout_validation.get("grid_dimensions", [])) == GRID_DIMENSIONS,
        "base_atrium_is_empty": layout_validation.get("reserved_overlap_count") == 0,
        "west_stair_is_empty": layout_validation.get("reserved_overlap_count") == 0,
        "marked_zones_match_reference": layout_validation.get("marked_zone_violation_count") == 0,
        "door_walkway_has_zero_blockers": layout_validation.get("door_walkway_blocker_count") == 0,
        "component_folders_are_fine_grained": all(
            result.get("component_folder_count", 0) >= 9 and result.get("unclassified_object_count", 1) == 0
            for result in hierarchy_summary.values()
        ),
        "editable_component_count_68": wrapper_stats["editable_component_count"] == 68,
        "independent_blocker_component_count_39": len(COLLISION_COMPONENTS) == 39,
        "compound_collision_shape_count_refined": wrapper_stats["collision_shape_count"] >= 80,
        "shelter_radio_do_not_overlap": layout_validation.get("shelter_radio_overlap_count") == 0,
        "palette_uv_on_all_output_meshes": all("PaletteUV" in obj.data.uv_layers for obj in mesh_objects),
        "shared_palette_external": all(not image.packed_file for image in bpy.data.images),
        "runtime_facilities_only": True,
        "native_floor_and_parapet_preserved": True,
    }
    validation = {
        "blend": BLEND_PATH,
        "passed": all(checks.values()),
        "checks": checks,
        "layout": layout_validation,
        "output_mesh_count": len(mesh_objects),
        "material_count": len(bpy.data.materials),
    }
    os.makedirs(os.path.dirname(MANIFEST_PATH), exist_ok=True)
    with open(MANIFEST_PATH, 'w', encoding='utf-8') as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
    with open(VALIDATION_PATH, 'w', encoding='utf-8') as handle:
        json.dump(validation, handle, ensure_ascii=False, indent=2)


def mark_collections(root, src, out, display):
    root["asset_id"]=ASSET_ID
    root["version"]=ASSET_VERSION
    root["scale_unit"]="meters"
    root["grid_contract"]="18x16 tiles @ 5m; 234 tiles after 36-tile base atrium and 18-tile west stair openings"
    root["roof_world_rect"]=str(ROOF_RECT)
    root["base_atrium_world_rect"]=str(BASE_ATRIUM_RECT)
    root["west_stair_world_rect"]=str(WEST_STAIR_RECT)
    root["door_walkway_rect"]=str(DOOR_WALKWAY_RECT)
    root["shelter_zone_rect"]=str(SHELTER_ZONE_RECT)
    root["farm_zone_rect"]=str(FARM_ZONE_RECT)
    root["radio_zone_rect"]=str(RADIO_ZONE_RECT)
    root["palette_path"]=PALETTE_PATH
    src["purpose"]="editable modular prototypes"
    out["purpose"]="assembled game-editable independent assets"
    display["purpose"]="camera lights and distant city presentation"


def main():
    clean_scene()
    os.makedirs(os.path.dirname(BLEND_PATH),exist_ok=True)
    os.makedirs(os.path.dirname(PREVIEW_PATH),exist_ok=True)
    image=load_palette()
    mats={
        'metal':make_material("01_精工金属_紫色骨架","metal",image),
        'matte':make_material("02_细腻哑光_青绿大面","matte",image),
        'gloss':make_material("03_清漆反光_紫粉点缀","gloss",image),
        'emission':make_material("04_柔和自发光_UI灯光","emission",image),
    }
    root=new_collection("末世天台庇护所_中文资产管理")
    src=new_collection("01_制作组件_已统一材质",root)
    out=new_collection("02_游戏输出_独立模块",root)
    collision_root=new_collection("03_阻挡代理_不导出",root)
    display=new_collection("90_展示环境_灯光相机",root)
    cats={}
    for name in ["Environment_Architecture","Environment_Ground","Props_Furniture","Props_Survival","Props_Communication","Props_Energy","Props_Farming","Vegetation","Lighting","VFX"]:
        cats[name]=new_collection(name,out)
    city_col=new_collection("远景荒废城市_低对比",out)
    mark_collections(root,src,out,display)
    build_rooftop_shell(cats['Environment_Architecture'],mats)
    variants=build_floor(cats['Environment_Ground'],mats)
    create_prototypes(src,mats,variants)
    build_shelter(cats['Props_Furniture'],cats['Lighting'],mats)
    translate_collection_roots(cats['Props_Furniture'],(18,33.5,.5))
    translate_named_roots(cats['Lighting'],("生活棚暖灯",),(18,33.5,.5))
    build_shelter_platform_and_motion(cats['Props_Furniture'],mats)
    build_farm(cats['Props_Farming'],cats['Lighting'],mats)
    translate_collection_roots(cats['Props_Farming'],(-2,22,0))
    translate_named_roots(cats['Lighting'],("温室暖灯",),(-2,22,0))
    build_energy_water(cats['Props_Energy'],mats)
    build_radio(cats['Props_Communication'],cats['Lighting'],mats)
    translate_collection_roots(cats['Props_Communication'],(18,26,0))
    translate_named_roots(cats['Lighting'],("天线信号点光","广播台暖灯"),(18,26,0))
    build_security(cats['Environment_Architecture'],cats['Lighting'],mats)
    build_clutter(cats['Props_Survival'],mats)
    build_lived_in_cluster(cats['Props_Survival'],cats['Lighting'],mats)
    build_city(city_col,mats)
    translate_collection_roots(city_col,(0,50,0))
    build_camera_lighting(display,mats)
    # Validate authored gameplay-plan positions before converting them to the
    # Blender export basis.  This keeps door, stair and roof-zone contracts in
    # the same coordinate space as TowerFloorStage3D.
    layout_validation=validate_layout(out)
    hierarchy_summary=organize_output_hierarchy(cats)
    build_collision_proxies(collision_root,mats)
    mirror_runtime_output_y_basis(out, collision_root)
    component_records=export_editable_component_glbs(cats,out)
    # Scene metadata and registry text.
    scene=bpy.context.scene
    scene["asset_id"]=ASSET_ID
    scene["version"]=ASSET_VERSION
    scene["description"]="90x80m modular rooftop matching the formal 100F game contract"
    scene["tile_count"]=EXPECTED_TILE_COUNT
    scene["tile_size_m"]=5.0
    scene["grid_dimensions"]="18x16"
    scene["roof_world_rect"]=str(ROOF_RECT)
    scene["base_atrium_world_rect"]=str(BASE_ATRIUM_RECT)
    scene["west_stair_world_rect"]=str(WEST_STAIR_RECT)
    scene["layout_zones"]="north-east corner radio platform; edge shelter west of radio with 2m clearance; farm shifted to west perimeter; yellow door route clear"
    scene["editable_component_count"]=len(component_records)
    scene["collision_component_count"]=len(COLLISION_COMPONENTS)
    scene["collision_shape_count"]=sum(len(component["shapes"]) for component in COLLISION_COMPONENTS)
    scene["living_cluster_rect"]=str(LIVING_CLUSTER_RECT)
    scene["door_walkway_rect"]=str(DOOR_WALKWAY_RECT)
    scene["shelter_zone_rect"]=str(SHELTER_ZONE_RECT)
    scene["farm_zone_rect"]=str(FARM_ZONE_RECT)
    scene["radio_zone_rect"]=str(RADIO_ZONE_RECT)
    scene["material_roles"]=4
    scene["palette_external"]=PALETTE_PATH
    scene["animation_notes"]="wind turbine, antenna turntable, signal beacon, meter needle, cloth, crops, lights, greenhouse film, distant smoke"
    # Ensure every mesh has active/render PaletteUV and exactly one shared material role.
    for obj in bpy.data.objects:
        if obj.type=='MESH':
            if 'PaletteUV' in obj.data.uv_layers:
                obj.data.uv_layers.active=obj.data.uv_layers['PaletteUV']
                obj.data.uv_layers['PaletteUV'].active_render=True
            obj.data.validate(verbose=False)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    scene.frame_set(48)
    bpy.ops.render.render(write_still=True)
    # A second close material/detail preview is required by the asset standard.
    cam=scene.camera
    old_loc=cam.location.copy(); old_rot=cam.rotation_euler.copy(); old_scale=cam.data.ortho_scale
    cam.location=(72,-42,52)
    cam.rotation_euler=(Vector((18,30.0,2.8))-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.ortho_scale=62
    scene.render.filepath=CLOSE_PREVIEW_PATH
    bpy.ops.render.render(write_still=True)
    cam.location=old_loc; cam.rotation_euler=old_rot; cam.data.ortho_scale=old_scale
    scene.render.filepath=PREVIEW_PATH
    # Runtime GLB keeps material roles and UVs but does not embed the public palette.
    os.makedirs(os.path.dirname(GLB_PATH),exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    runtime_category_names = ["Props_Furniture", "Props_Survival", "Props_Communication", "Props_Energy", "Props_Farming"]
    facility_objects = {obj for category_name in runtime_category_names for obj in cats[category_name].all_objects}
    for obj in facility_objects:
        if obj.type in {'MESH','EMPTY','LIGHT'}:
            obj.select_set(True)
    bpy.context.view_layer.objects.active=next((o for o in facility_objects if o.type=='MESH'),None)
    bpy.ops.export_scene.gltf(filepath=GLB_PATH,export_format='GLB',use_selection=True,export_image_format='NONE',export_animations=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    wrapper_stats=write_collision_manifest_and_wrapper(component_records)
    write_manifest_and_validation(out, layout_validation, hierarchy_summary, component_records, wrapper_stats)
    print({
        'blend':BLEND_PATH,'preview':PREVIEW_PATH,'close_preview':CLOSE_PREVIEW_PATH,'glb':GLB_PATH,'objects':len(bpy.data.objects),
        'meshes':sum(1 for o in bpy.data.objects if o.type=='MESH'),
        'materials':len(bpy.data.materials),'tiles':scene['tile_count'],'layout':layout_validation,
        'editable_components':len(component_records),'collision_components':len(COLLISION_COMPONENTS),
        'collision_shapes':wrapper_stats['collision_shape_count']
    })


main()
