import bpy
import math
import os
import random
from mathutils import Vector, Matrix


ROOT = "/Users/summercards/ShellStorm2"
ASSET_DIR = os.path.join(ROOT, "assets/art/environments/rooftop_shelter_3d")
PALETTE_PATH = os.path.join(ROOT, "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png")
BLEND_PATH = os.path.join(ASSET_DIR, "source/env_rooftop_shelter_50m_top3d_v011.blend")
PREVIEW_PATH = os.path.join(ASSET_DIR, "previews/env_rooftop_shelter_50m_complete_v011.png")
CLOSE_PREVIEW_PATH = os.path.join(ASSET_DIR, "previews/env_rooftop_shelter_50m_close_v011.png")
GLB_PATH = os.path.join(ASSET_DIR, "runtime/env_rooftop_shelter_50m_game_v011.glb")
random.seed(240830)


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


def build_floor(col, mats):
    variants = ["完整水泥", "裂缝", "积水", "青苔", "排水口", "管线接口", "种植区", "棚屋基础", "设备安装", "边缘护栏", "屋顶入口", "严重破损"]
    for i in range(10):
        for j in range(10):
            x, y = -22.5+i*5, -22.5+j*5
            edge = i in (0,9) or j in (0,9)
            if edge: v = 9
            elif (i,j) in [(1,6),(2,6),(2,7),(1,7),(3,6)]: v = 6
            elif (i,j) in [(4,4),(5,4),(4,5),(5,5)]: v = 7
            elif (i,j) in [(7,6),(8,6),(7,7),(8,7)]: v = 8
            elif (i,j) in [(4,0),(5,0)]: v = 10
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
    return variants


def build_rooftop_shell(col, mats):
    box("屋顶建筑基座",(0,0,-8),(50,50,8),col,mats['matte'],C['cool_dark'],bevel=.12,asset_id="ENV_ROOFTOP_BASE_50M")
    # Facade strips and broken windows give the collectible diorama a readable base.
    for side in (-1,1):
        for k in range(10):
            x=-22.5+k*5
            box(f"立面窗_南北_{side}_{k}",(x,side*25.01,-6.0),(2.5,.08,2.4),col,mats['gloss'],C['navy'])
    for side in (-1,1):
        for k in range(10):
            y=-22.5+k*5
            box(f"立面窗_东西_{side}_{k}",(side*25.01,y,-6.0),(.08,2.5,2.4),col,mats['gloss'],C['navy'])


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
    for i,(x,y,a) in enumerate([(-19,-14,.28),(-14,-14,.34),(-19,-18,.24),(-14,-18,.30)]): solar_panel(f"太阳能板_{i}",x,y,1.5,a,col,mats)
    # Wind turbine with animated rotor.
    mastx,masty=-10.5,-16
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
    box("柴油发电机_机身",(-9,-12,.34),(3.2,1.8,1.6),col,mats['metal'],C['mustard'],bevel=.16)
    box("柴油发电机_控制面板",(-8.1,-12.91,.75),(1.15,.05,.82),col,mats['matte'],C['charcoal'],bevel=.06)
    for k in range(6): box(f"发电机散热格栅_{k}",(-10.05+k*.32,-12.92,.76),(.12,.04,.72),col,mats['metal'],C['charcoal'],rot=(0,0,.05))
    for sx in (-1.25,1.25):
        box("发电机底脚",(-9+sx,-12,.34),(.34,1.15,.18),col,mats['metal'],C['rust'],bevel=.035)
        beam("发电机搬运框",(-9+sx,-12.65,.75),(-9+sx,-12.65,1.75),.045,col,mats['metal'],C['charcoal'],8)
    cylinder("发电机电压表",(-7.88,-12.96,1.26),.16,.035,col,mats['gloss'],C['cream'],12,rot=(math.pi/2,0,0))
    cylinder("发电机排气",(-8.1,-11.8,1.94),.12,1.0,col,mats['metal'],C['charcoal'],8)
    for i in range(3):
        bx=-10+i*1.15
        box(f"蓄电池柜_{i}",(bx,-9.5,.34),(1.0,.8,1.6),col,mats['matte'],C['blue_faded'],bevel=.05)
        for q in (-.22,.22): cylinder(f"蓄电池接线柱_{i}_{q}",(bx+q,-9.5,1.96),.055,.10,col,mats['metal'],C['red'] if q>0 else C['charcoal'],8)
        beam(f"蓄电池提手_{i}",(bx-.26,-9.5,1.90),(bx+.26,-9.5,1.90),.035,col,mats['metal'],C['concrete_light'],8)
    box("能源维修工作台",(-17,-10,.34),(4.5,1.2,1.25),col,mats['matte'],C['wood'])
    # Water cluster on east side.
    for i,(x,y,r,h) in enumerate([(18,-16,2.2,4.8),(13.8,-16,1.25,3.1),(13.8,-12.5,1.25,3.1),(18,-10.8,1.45,3.5)]):
        cylinder(f"储水罐_{i}",(x,y,.34),r,h,col,mats['metal'] if i==0 else mats['matte'],C['concrete_light'] if i==0 else C['blue_faded'],16)
        for q in range(3):
            cylinder(f"储水罐箍带_{i}_{q}",(x,y,.34+h*(q+1)/4),r+.05,.07,col,mats['metal'],C['charcoal'],16)
        cylinder(f"储水罐顶盖_{i}",(x,y,.34+h),r*.92,.18,col,mats['metal'],C['concrete_light'],16)
        cylinder(f"储水罐检修口_{i}",(x,y,.52+h),r*.22,.20,col,mats['metal'],C['rust'],12)
        for a in range(0,360,90):
            ar=math.radians(a)
            beam(f"储水罐竖向加强筋_{i}_{a}",(x+r*math.cos(ar),y+r*math.sin(ar),.5),(x+r*math.cos(ar),y+r*math.sin(ar),.34+h),.035,col,mats['metal'],C['charcoal'],6)
    # Pipes with deliberate functional routing.
    routes=[((18,-16,.7),(18,-10.8,.7)),((13.8,-16,.7),(18,-16,.7)),((13.8,-12.5,.9),(18,-10.8,.9)),((18,-10.8,3.9),(22,-10.8,3.9)),((-10,-9.5,.8),(0,-4,.8))]
    for i,(a,b) in enumerate(routes): beam(f"供水能源管线_{i}",a,b,.075,col,mats['matte'],C['charcoal'],8)
    for k in range(4):
        box(f"修补胶带接口_{k}",(14.5+k*1.0,-16,.68),(.18,.22,.22),col,mats['matte'],C['red'],bevel=.03)
    # Visible cable runs connect generation, storage and living zones.
    for i,(a,b) in enumerate([((-9,-12,.55),(-10,-9.5,.55)),((-10,-9.5,.48),(-2,-4,.48)),((-2,-4,.48),(8,-4,.48)),((-14,-14,.48),(-10,-9.5,.48))]):
        beam(f"外露电缆_{i}",a,b,.035,col,mats['matte'],C['charcoal'],6)
    box("防水配电箱",(-11.8,-9.5,.34),(1.2,.55,1.45),col,mats['metal'],C['rust'],bevel=.08)


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
    # Perimeter rail segments leave a controlled entrance gap on south side.
    for side in (-1,1):
        y=side*24.4
        for x in range(-22,23,4):
            if side==-1 and abs(x)<4: continue
            cylinder("边缘护栏立柱",(x,y,.34),.065,1.45,col,mats['metal'],C['charcoal'],8)
        for x0 in range(-24,24,6):
            if side==-1 and x0<=0<=x0+6: continue
            beam("边缘护栏横杆",(x0,y,1.65),(min(x0+6,24),y,1.65),.065,col,mats['metal'],C['rust'])
            beam("边缘护栏中杆",(x0,y,1.10),(min(x0+6,24),y,1.10),.045,col,mats['metal'],C['charcoal'])
    for side in (-1,1):
        x=side*24.4
        for y in range(-22,23,4): cylinder("边缘护栏立柱",(x,y,.34),.065,1.45,col,mats['metal'],C['charcoal'],8)
        for y0 in range(-24,24,6):
            beam("边缘护栏横杆",(x,y0,1.65),(x,min(y0+6,24),1.65),.065,col,mats['metal'],C['rust'])
            beam("边缘护栏中杆",(x,y0,1.10),(x,min(y0+6,24),1.10),.045,col,mats['metal'],C['charcoal'])
    # Sandbags and improvised barricades.
    for i in range(18):
        x=-7.5+(i%9)*1.8; y=-23.0+(i//9)*.75
        bag=box(f"入口沙袋_{i}",(x,y,.34),(1.55,.62,.38),col,mats['matte'],C['sand'],rot=(0,0,.08*(-1)**i),bevel=.18)
    # Stairwell exit with double reinforced door.
    box("楼梯间出口主体",(0,-19,.34),(7,5,4.4),col,mats['matte'],C['cool_dark'],bevel=.12)
    box("楼梯间双层防护门",(0,-21.52,.34),(3.2,.16,3.45),col,mats['metal'],C['rust'],bevel=.06)
    box("防护门加固横闩",(0,-21.65,2.0),(3.7,.18,.18),col,mats['metal'],C['charcoal'])
    cylinder("防护门警报铃_自发光",(2.3,-21.8,3.3),.22,.25,col,mats['emission'],C['red'],12,rot=(math.pi/2,0,0))
    add_point_light("入口暖灯",(0,-22.0,4.1),110,(1,.45,.15),1.0,lights_col)
    # Low lookout towers.
    for side,x in enumerate((-21.5,21.5)):
        y=20.5 if side==0 else 4.0
        for dx in (-1.2,1.2):
            for dy in (-1.2,1.2): box("瞭望台支柱",(x+dx,y+dy,.34),(.16,.16,3.2),col,mats['metal'],C['charcoal'])
        box("瞭望台平台",(x,y,3.55),(3.2,3.2,.25),col,mats['matte'],C['wood'])
        cylinder("望远镜支架",(x,y,3.8),.08,1.0,col,mats['metal'],C['charcoal'],8)
        beam("望远镜",(x-.5,y,4.8),(x+.5,y,4.8),.12,col,mats['metal'],C['blue_faded'],10)
    # Flags and cloth strips with gentle animation.
    for i,(x,y,z) in enumerate([(-23,14,2.4),(23,-3,2.2),(8,24,2.5),(-6,-24,2.4)]):
        cloth=box(f"警示布条_{i}",(x,y,z),(.9,.05,.34),col,mats['matte'],C['red'],rot=(0,0,.15*i),bevel=.03)
        cloth.keyframe_insert('rotation_euler',frame=1,index=2); cloth.rotation_euler.z+=.12; cloth.keyframe_insert('rotation_euler',frame=100,index=2); cloth.rotation_euler.z-=.18; cloth.keyframe_insert('rotation_euler',frame=200,index=2); cloth.keyframe_insert('rotation_euler',frame=250,index=2)


def build_clutter(col, mats):
    # Story clusters are dense but asymmetric: each serves a nearby function and keeps a walkable side.
    clusters=[
        ("工坊拆件",-8.1,12.8,1.0,0.0),("入口补给",-4.8,-13.0,.7,.9),
        ("水箱维修",20.2,-7.4,.4,1.1),("农场园艺",-10.8,11.2,.3,.9),
        ("广播备件",10.6,18.8,1.1,.2),("生活储备",8.0,-7.5,.8,.6)]
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
    tire_specs=[(-1.8,-9.5,0,.10),(-.7,-9.1,.28,-.25),(.4,-9.4,0,.18),(1.2,-8.7,.62,.38),(-1.2,-8.35,.58,-.45),(.0,-8.1,.25,.18),(1.8,-9.6,.45,-.2)]
    for i,(x,y,tilt,rz) in enumerate(tire_specs):
        cylinder(f"备用轮胎_{i}",(x,y,.34),.55,.34,col,mats['matte'],C['charcoal'],12,rot=(math.pi/2-tilt,0,rz))
    # Laundry line and moving clothes.
    beam("晾衣绳",(17,-5,3.2),(23,-5,3.2),.018,col,mats['matte'],C['concrete_light'],6)
    for i in range(5):
        cloth=box(f"晾晒衣物_{i}",(17.7+i*1.15,-5,2.0),(.8,.04,1.1),col,mats['matte'],[C['blue_faded'],C['canvas'],C['rust'],C['green']][i%4],rot=(0,0,.03*(-1)**i),bevel=.05)
        cloth.keyframe_insert('rotation_euler',frame=1,index=1); cloth.rotation_euler.y=.08; cloth.keyframe_insert('rotation_euler',frame=120,index=1); cloth.rotation_euler.y=-.05; cloth.keyframe_insert('rotation_euler',frame=240,index=1); cloth.keyframe_insert('rotation_euler',frame=250,index=1)
    # Covered stock with bricks.
    tarp=box("防水布覆盖物资",(10,-4,.34),(5.0,2.4,1.25),col,mats['matte'],C['canvas'],bevel=.28)
    for sx in (-2.1,2.1):
        for sy in (-.9,.9): box("压布砖块",(10+sx,-4+sy,1.55),(.5,.28,.18),col,mats['matte'],C['rust'])
    # Boardwalk planks carry small offsets and repairs while maintaining the clear circulation route.
    for i in range(11):
        rng=random.Random(8800+i)
        x=-5+i+rng.uniform(-.09,.09)
        box(f"中央木板便道_{i}",(x,rng.uniform(-.10,.12),.36),(.80+rng.uniform(-.08,.08),3.0+rng.uniform(-.15,.12),.08+rng.uniform(0,.035)),col,mats['matte'],C['wood'] if i%4 else C['brown'],rot=(0,0,rng.uniform(-.055,.055)))
        if i in (2,7): box(f"便道修补铁片_{i}",(x,.15,.46),(.36,.7,.035),col,mats['metal'],C['rust'],rot=(0,0,.15*(-1)**i),bevel=.02)
    for i in range(16):
        x=-20+i*2.5
        box(f"黄色区域标线_{i}",(x,-7.2+.04*math.sin(i),.37),(1.2+(.25 if i%3 else 0),.08,.025),col,mats['matte'],C['yellow'],rot=(0,0,.01*((i%4)-2)))


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
    world.mist_settings.start=75
    world.mist_settings.depth=130
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
    cam.location=(62,-72,54)
    target=Vector((0,2,2.8)); cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    cam_data.type='ORTHO'; cam_data.ortho_scale=72; cam_data.lens=58
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
        x=rng.uniform(-28,28); y=rng.uniform(-25,28); z=rng.uniform(.8,13)
        dust=sphere(f"空气浮尘_{i}",(x,y,z),rng.uniform(.025,.075),col,mats['matte'],C['sand'] if i%5==0 else C['concrete_mid'],6,3,scale=(rng.uniform(.7,1.5),rng.uniform(.7,1.3),rng.uniform(.7,1.8)))
        dust.keyframe_insert('location',frame=1,index=0)
        dust.location.x+=rng.uniform(.5,1.8); dust.location.z+=rng.uniform(.15,.8)
        dust.keyframe_insert('location',frame=250,index=0)
    # Slightly larger low-poly dust wisps hover near traffic paths and the generator.
    for i,(x,y,z,s) in enumerate([(-9,-11,1.2,1.0),(-1,-6,1.0,.8),(12,-8,1.5,1.1),(-18,1,1.3,.9),(8,13,5.8,.75)]):
        wisp=sphere(f"近景烟尘薄团_{i}",(x,y,z),s,col,mats['matte'],C['concrete_mid'],8,4,scale=(1.7,1.0,.45))
        wisp.keyframe_insert('location',frame=1,index=0); wisp.location.x+=1.0; wisp.location.z+=.45; wisp.keyframe_insert('location',frame=250,index=0)
    # Grounding shadow plane below the collectible block.
    box("大雾阴天冷灰背景承托面",(0,0,-18.3),(150,150,.25),col,mats['matte'],C['concrete_mid'],bevel=.4)
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


def mark_collections(root, src, out, display):
    root["asset_id"]="ENV_ROOFTOP_SHELTER_50M"
    root["version"]="v011"
    root["scale_unit"]="meters"
    root["grid_contract"]="10x10 tiles @ 5m"
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
    build_farm(cats['Props_Farming'],cats['Lighting'],mats)
    build_energy_water(cats['Props_Energy'],mats)
    build_radio(cats['Props_Communication'],cats['Lighting'],mats)
    build_security(cats['Environment_Architecture'],cats['Lighting'],mats)
    build_clutter(cats['Props_Survival'],mats)
    build_city(city_col,mats)
    build_camera_lighting(display,mats)
    # Scene metadata and registry text.
    scene=bpy.context.scene
    scene["asset_id"]="ENV_ROOFTOP_SHELTER_50M"
    scene["description"]="50x50m modular post-apocalyptic rooftop survivor shelter"
    scene["tile_count"]=100
    scene["tile_size_m"]=5.0
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
    cam.location=(31,-36,25)
    cam.rotation_euler=(Vector((1.8,3.0,2.4))-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.ortho_scale=39
    scene.render.filepath=CLOSE_PREVIEW_PATH
    bpy.ops.render.render(write_still=True)
    cam.location=old_loc; cam.rotation_euler=old_rot; cam.data.ortho_scale=old_scale
    scene.render.filepath=PREVIEW_PATH
    # Runtime GLB keeps material roles and UVs but does not embed the public palette.
    os.makedirs(os.path.dirname(GLB_PATH),exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in out.all_objects:
        if obj.type in {'MESH','EMPTY'}:
            obj.select_set(True)
    bpy.context.view_layer.objects.active=next((o for o in out.all_objects if o.type=='MESH'),None)
    bpy.ops.export_scene.gltf(filepath=GLB_PATH,export_format='GLB',use_selection=True,export_image_format='NONE',export_animations=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print({
        'blend':BLEND_PATH,'preview':PREVIEW_PATH,'close_preview':CLOSE_PREVIEW_PATH,'glb':GLB_PATH,'objects':len(bpy.data.objects),
        'meshes':sum(1 for o in bpy.data.objects if o.type=='MESH'),
        'materials':len(bpy.data.materials),'tiles':scene['tile_count']
    })


main()
