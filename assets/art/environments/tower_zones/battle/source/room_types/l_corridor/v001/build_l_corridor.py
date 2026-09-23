"""Build the reference-derived, 5 m modular L corridor in the connected Blender scene."""
import bpy, math, json, os, hashlib
from mathutils import Vector

ROOT = '/Users/summercards/ShellStorm2'
OUT = ROOT + '/assets/art/environments/tower_zones/battle/source/room_types/l_corridor/v001'
PALETTE = ROOT + '/assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
os.makedirs(OUT, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for col in list(bpy.data.collections):
    if col.name != bpy.context.scene.collection.name:
        bpy.data.collections.remove(col, do_unlink=True)

def collection(name, parent=None):
    c = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(c)
    return c

root = collection('L型数据库走廊_中文资产管理')
source = collection('01_制作组件_按设施拆分', root)
game = collection('02_游戏输出_独立资产包_v001', root)
arch = collection('01_建筑结构', game)
floor = collection('02_地面系统', game)
facility = collection('03_区域固定设施', game)
support = collection('04_环境支持', game)
display = collection('90_展示与验收_灯光相机', root)
source.hide_viewport = True
image = bpy.data.images.load(PALETTE, check_existing=True)
image.filepath = PALETTE
image.pack if False else None

MAT_NAMES = ['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
materials = []
for i, name in enumerate(MAT_NAMES):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    n = m.node_tree.nodes
    n.clear()
    uv = n.new('ShaderNodeUVMap'); uv.uv_map = 'PaletteUV'
    tex = n.new('ShaderNodeTexImage'); tex.image = image; tex.interpolation = 'Closest'
    p = n.new('ShaderNodeBsdfPrincipled')
    out = n.new('ShaderNodeOutputMaterial')
    m.node_tree.links.new(uv.outputs['UV'], tex.inputs['Vector'])
    m.node_tree.links.new(tex.outputs['Color'], p.inputs['Base Color'])
    m.node_tree.links.new(p.outputs['BSDF'], out.inputs['Surface'])
    p.inputs['Metallic'].default_value = [0.86,0.02,0.16,0.0][i]
    p.inputs['Roughness'].default_value = [0.27,0.7,0.14,0.36][i]
    if i == 3:
        m.node_tree.links.new(tex.outputs['Color'], p.inputs['Emission Color'])
        p.inputs['Emission Strength'].default_value = 1.5
    materials.append(m)
for old_mat in list(bpy.data.materials):
    if old_mat.name not in MAT_NAMES:
        bpy.data.materials.remove(old_mat, do_unlink=True)

packages = {}
def pkg(slug, title, category, parent):
    c = collection(title + '_资产包', parent)
    packages[slug] = {'slug':slug,'name_zh':title,'category':category,'collection':c,'objects':[]}
    return c

def assign_uv(obj, col, row):
    mesh = obj.data
    for layer in list(mesh.uv_layers): mesh.uv_layers.remove(layer)
    layer = mesh.uv_layers.new(name='PaletteUV')
    mesh.uv_layers.active = layer
    layer.active_render = True
    u = (col+0.5)/10
    v = 1-(row+0.5)/10
    corners = [(-.024,-.024),(.024,-.024),(.024,.024),(-.024,.024)]
    for poly in mesh.polygons:
        for j, li in enumerate(poly.loop_indices):
            a,b = corners[j%4]
            layer.data[li].uv = (u+a,v+b)

def link_obj(obj, pack):
    for old in list(obj.users_collection): old.objects.unlink(obj)
    pack.objects.link(obj)
    for info in packages.values():
        if info['collection'] == pack:
            info['objects'].append(obj.name)
            break

def box(name, loc, dim, pack, mat=1, color=(9,1), bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    ob=bpy.context.object; ob.name=name
    ob.dimensions=dim
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.append(materials[mat])
    assign_uv(ob,*color)
    if bevel:
        mod=ob.modifiers.new('柔化硬边','BEVEL'); mod.width=bevel; mod.segments=2
        ob.modifiers.new('加权法线','WEIGHTED_NORMAL')
    link_obj(ob,pack)
    return ob

def cylinder(name,loc,radius,depth,pack,mat=0,color=(9,3),verts=12,rot=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=radius,depth=depth,location=loc)
    ob=bpy.context.object; ob.name=name
    if rot: ob.rotation_euler=rot
    ob.data.materials.append(materials[mat]); assign_uv(ob,*color)
    link_obj(ob,pack)
    return ob

def text_mesh(label, name, loc, size, rot, pack, color=(9,8)):
    bpy.ops.object.text_add(location=loc,rotation=rot)
    ob=bpy.context.object; ob.name=name; ob.data.body=label; ob.data.size=size; ob.data.extrude=.002
    bpy.ops.object.convert(target='MESH'); ob=bpy.context.object
    ob.data.materials.append(materials[3]); assign_uv(ob,*color)
    link_obj(ob,pack)

# The two connected 10 m lanes are defined on a 5 m grid. The elbow overlaps four tiles.
cells=[(x,y) for x in range(9) for y in range(2)]
cells += [(x,y) for x in (7,8) for y in range(-5,0)]
for x,y in cells:
    guide=bpy.data.objects.new(f'砖块定位_R{y+5:02d}_C{x:02d}',None)
    source.objects.link(guide); guide.location=(x*5+2.5,y*5+2.5,0)
    guide.empty_display_type='CUBE'; guide.empty_display_size=2.5
for x,y in cells:
    cx=x*5+2.5; cy=y*5+2.5
    p=pkg(f'tile_r{y+5:02d}_c{x:02d}',f'地砖_R{y+5:02d}_C{x:02d}','floor',floor)
    box('5米结构地砖',(cx,cy,-.15),(5,5,.3),p,1,(9,0))
    box('深蓝分缝面板',(cx,cy,.027),(4.84,4.84,.055),p,0,(9,1),.035)
    box('中心可维护面板',(cx,cy,.060),(4.30,4.24,.018),p,1,(9,2))
    for dx in (-2.27,2.27):
        box('侧边钢轨',(cx+dx,cy,.072),(.065,4.54,.025),p,0,(9,4))
        box('冷光轨',(cx+dx,cy,.09),(.018,3.98,.012),p,3,(3,5))
    for dy in (-2.25,2.25):
        box('端缝金属压条',(cx,cy+dy,.075),(4.5,.055,.025),p,0,(9,4))
    for dx in (-2.12,2.12):
        for dy in (-2.12,2.12):
            cylinder('角部沉头螺栓',(cx+dx,cy+dy,.091),.035,.012,p,0,(9,7),8)
    if (x+y)%3==0:
        box('嵌入检修井框',(cx,cy,.092),(1.28,1.34,.025),p,0,(9,6))
        box('检修井深色凹面',(cx,cy,.110),(1.04,1.10,.01),p,1,(9,0))
        for j in range(7):
            box('通风格栅',(cx-.46+j*.15,cy,.126),(.055,1.0,.014),p,0,(9,4))
    if (x+y)%2==0:
        for side in (-1,1):
            for j in range(4):
                box('边缘警示斜块',(cx+side*1.72,cy-1.45+j*.78,.088),(.24,.34,.012),p,1,(9,8))
    if (x+2*y)%4==0:
        box('地面识别箭头底',(cx+1.28,cy-.8,.092),(.28,.36,.01),p,3,(9,8))

# Each structural module has its own package and a full-height rear shell.
def wall_x(x0,y,door=False,visible=True):
    p=pkg(f'wall_x_{int(x0):02d}_{"rear" if y>0 else "front"}',f'{"后" if y>0 else "前"}墙_{int(x0):02d}米','architecture',arch)
    h=11.9 if visible else 1.35
    if door:
        for sx in (x0+.58,x0+4.42):
            box('门侧结构墙',(sx,y,h/2),(.95,.30,h),p,1,(9,0))
        box('门楣',(x0+2.5,y,(3.35+h)/2),(2.9,.30,h-3.35),p,1,(9,0))
    else:
        box('标准5米墙体',(x0+2.5,y,h/2),(5,.30,h),p,1,(9,0))
    box('墙脚踢脚板',(x0+2.5,y-.19,.28),(4.9,.10,.55),p,0,(9,1))
    if visible:
        for z in (4.05,7.85):
            box('墙体水平分仓线',(x0+2.5,y-.185,z),(4.86,.025,.035),p,0,(9,2))
        for sx in (x0+.15,x0+4.85):
            box('竖向结构边筋',(sx,y-.21,5.75),(.075,.08,11.3),p,0,(9,3))
        box('上沿管线桥架',(x0+2.5,y-.28,4.14),(4.8,.11,.14),p,0,(9,0))
        box('上沿细蓝光导线',(x0+2.5,y-.355,4.13),(4.7,.012,.025),p,3,(3,5))
        box('冷蓝墙灯',(x0+2.5,y-.27,4.00),(2.0,.13,.10),p,3,(9,8))
    return p
for i in range(9): wall_x(i*5,10,door=i in (1,7))
for i in range(7): wall_x(i*5,0,visible=False)
wall_x(35,-25,door=True,visible=True); wall_x(40,-25,visible=True)

def wall_y(y0,x,visible=True):
    p=pkg(f'wall_y_{int(y0+25):02d}_{int(x):02d}',f'侧墙_{int(y0)}米_{int(x)}米','architecture',arch)
    h=11.9 if visible else 1.35
    box('标准5米墙体',(x,y0+2.5,h/2),(.3,5,h),p,1,(9,0))
    box('墙脚踢脚板',(x-.19,y0+2.5,.28),(.1,4.9,.55),p,0,(9,1))
    if visible:
        box('水平结构线',(x-.20,y0+2.5,4.05),(.04,4.9,.055),p,0,(9,3))
        box('纵向桥架',(x-.31,y0+2.5,4.18),(.10,4.75,.10),p,0,(9,1))
        box('蓝色细光缆',(x-.37,y0+2.5,4.18),(.012,4.65,.028),p,3,(3,5))
        if (y0+25)%10==0:
            box('墙面灯条',(x-.25,y0+2.5,3.7),(.12,2.2,.10),p,3,(9,8))
    return p
for y in range(0,10,5): wall_y(y,0,True)
for y in range(-25,0,5): wall_y(y,35,False); wall_y(y,45,True)
for y in range(0,10,5): wall_y(y,45,True)

# Main secured doors: sill, inset leaves, illuminated lintel, access reader.
def secure_door(slug,cx,cy,along_x=True):
    p=pkg(slug,'数据库安全门','facility',facility)
    if along_x:
        box('加厚门框',(cx,cy-.30,1.75),(3.15,.22,3.50),p,0,(9,3),.06)
        box('门叶',(cx,cy-.46,1.56),(2.62,.13,2.97),p,1,(9,1),.07)
        for dx in (-1.14,1.14):
            box('门叶纵筋',(cx+dx,cy-.55,1.60),(.075,.05,2.8),p,0,(9,4))
        box('上门楣灯带',(cx,cy-.48,3.33),(2.45,.11,.12),p,3,(9,8))
        box('门槛冷光',(cx,cy-.52,.11),(2.72,.05,.035),p,3,(3,5))
        box('读卡器外壳',(cx+1.83,cy-.38,1.45),(.40,.26,.64),p,0,(9,3))
        box('读卡器屏',(cx+1.83,cy-.53,1.56),(.25,.02,.31),p,3,(3,5))
    else:
        box('加厚门框',(cx-.30,cy,1.75),(.22,3.15,3.50),p,0,(9,3),.06)
        box('门叶',(cx-.46,cy,1.56),(.13,2.62,2.97),p,1,(9,1),.07)
        box('上门楣灯带',(cx-.48,cy,3.33),(.11,2.45,.12),p,3,(9,8))
        box('读卡器外壳',(cx-.38,cy+1.83,1.45),(.26,.4,.64),p,0,(9,3))
        box('读卡器屏',(cx-.53,cy+1.83,1.56),(.02,.25,.31),p,3,(3,5))
secure_door('door_west',7.5,10)
secure_door('door_east',37.5,10)
secure_door('door_south',37.5,-25)

def server(slug,x,y,turn=False):
    p=pkg(slug,'蓝光服务器机柜','facility',facility)
    ob=box('深色主柜',(x,y,1.55),(.93,.82,3.1),p,0,(9,0),.07)
    if turn: ob.rotation_euler.z=math.pi/2
    for z in (.65,1.15,1.65,2.15,2.65):
        box('服务器模块',(x,y-.45,z),(.77,.08,.36),p,1,(9,1))
        for j in range(4):
            box('蓝色状态灯',(x-.28+j*.16,y-.50,z),(.055,.018,.055),p,3,(3,5))
    box('柜顶金属帽',(x,y,3.12),(1.02,.92,.13),p,0,(9,4))
    for sx in (-.49,.49):
        box('正面边框',(x+sx,y-.48,1.53),(.055,.09,2.9),p,0,(9,5))
for n,(x,y) in enumerate(((12.8,8.8),(14.0,8.8),(42.8,-22),(42.8,-18),(36.1,-14))):
    server(f'server_{n:02d}',x,y)

# The reference's principal focal point is a ten-metre glazed server gallery.
bay=pkg('server_gallery','双跨玻璃数据库陈列窗','facility',facility)
box('黑色凹入式展示舱',(23.0,9.68,2.30),(9.50,.17,2.55),bay,1,(9,0))
box('玻璃反光面',(23.0,9.56,2.30),(9.12,.025,2.24),bay,2,(3,6))
for xx in (18.35,21.0,23.65,26.3,27.65):
    box('玻璃竖向金属分隔',(xx,9.52,2.30),(.065,.075,2.60),bay,0,(9,5))
for z in (1.00,3.60):
    box('窗框水平压条',(23.0,9.50,z),(9.62,.09,.075),bay,0,(9,5))
for xx in (19.4,22.0,24.6,27.1):
    box('玻璃后机柜立柱',(xx,9.45,2.33),(.37,.045,1.83),bay,0,(9,1))
    for zz in (1.55,1.82,2.09,2.36,2.63,2.90):
        box('机柜蓝色状态阵列',(xx,9.39,zz),(.20,.016,.033),bay,3,(3,5))
for xx in (18.45,23.0,27.55):
    box('陈列舱顶灯',(xx,9.39,3.48),(.72,.05,.055),bay,3,(9,8))

# Cable risers and lock plates give the repeated 5 m wall modules a readable scale.
for n,xx in enumerate((2.5,10.2,16.0,29.7,34.4,42.3)):
    p=pkg(f'pipe_riser_{n:02d}',f'墙面竖向管线_{n:02d}','support',support)
    for dx in (-.085,.085):
        box('竖向粗管',(xx+dx,9.66,2.15),(.065,.08,3.65),p,0,(9,3))
    for z in (.55,2.0,3.68):
        box('管卡',(xx,9.61,z),(.38,.13,.10),p,0,(9,5))
    box('橙色检修标记',(xx+.22,9.55,.55),(.05,.02,.11),p,3,(4,3))

def console(slug,x,y):
    p=pkg(slug,'立式访问终端','facility',facility)
    box('终端底座',(x,y,.12),(.7,.76,.24),p,0,(9,2))
    box('终端立柱',(x,y,1.05),(.53,.52,1.72),p,0,(9,1),.07)
    box('屏幕倾斜框',(x,y-.29,1.65),(.60,.12,.68),p,0,(9,5))
    box('屏幕玻璃',(x,y-.365,1.67),(.48,.014,.52),p,2,(3,6))
    for j in range(3): box('屏幕信息条',(x,y-.38,1.5+j*.13),(.35,.016,.027),p,3,(3,5))
for n,(x,y) in enumerate(((3,8.65),(27,8.65),(40.7,-23.5))):console(f'console_{n:02d}',x,y)

def crate(slug,x,y):
    p=pkg(slug,'固定维修设备箱','facility',facility)
    box('加固箱体',(x,y,.46),(1.15,.85,.92),p,0,(9,1),.05)
    box('箱盖',(x,y,.96),(1.21,.91,.12),p,0,(9,3))
    for z in (.30,.70):
        box('橙色安全扣',(x,y-.45,z),(.13,.045,.12),p,3,(4,3))
for n,(x,y) in enumerate(((1.9,8.7),(20.2,8.75),(32.3,8.7),(42.8,-10),(42.5,-23))): crate(f'crate_{n:02d}',x,y)

def planter(slug,x,y):
    p=pkg(slug,'白色方形固定花槽','facility',facility)
    box('陶瓷白花槽',(x,y,.47),(.9,.9,.94),p,1,(9,8),.06)
    box('深色泥土',(x,y,.95),(.74,.74,.035),p,1,(9,0))
    cylinder('植物主茎',(x,y,1.24),.055,.57,p,0,(7,4),8)
    for j in range(7):
        a=j*math.tau/7
        leaf=box('叶片',(x+math.cos(a)*.28,y+math.sin(a)*.28,1.42+(.15 if j%2 else 0)),(.12,.52,.025),p,1,(7,4))
        leaf.rotation_euler.z=a-math.pi/2; leaf.rotation_euler.x=.34
for n,(x,y) in enumerate(((5.4,8.8),(33.2,8.8),(36.25,-22.8))):planter(f'planter_{n:02d}',x,y)

# Wall height is contractual. Low foreground panels above are a presentation cutaway.
# Full-height invisible-to-render collision reference remains editable in source.
for idx,(x,y,dx,dy) in enumerate(((17.5,-.0,35,.3),(35,-12.5,.3,25))):
    p=pkg(f'cutaway_wall_contract_{idx}',f'镜头侧墙完整高度基准_{idx}','architecture',arch)
    ob=box('11点9米墙体基准',(x,y,5.95),(dx,dy,11.9),p,1,(9,0))
    ob.hide_render=True; ob.hide_set(True)

world=bpy.context.scene.world
world.use_nodes=True
world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.023,.043,.075,1)
world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.6
def area(name,loc,power,color,size):
    d=bpy.data.lights.new(name,'AREA'); d.energy=power; d.color=color; d.shape='DISK'; d.size=size
    ob=bpy.data.objects.new(name,d); display.objects.link(ob); ob.location=loc
    direction=Vector((23,-6,0))-ob.location; ob.rotation_euler=direction.to_track_quat('-Z','Y').to_euler()
area('冷色主光',(12,-4,24),5700,(.34,.60,1),28)
area('冷色转角补光',(40,-16,23),3400,(.28,.54,1),20)
area('暖色小面积反射',(32,11,15),600,(1,.66,.32),16)

def camera(name,loc,target,scale):
    d=bpy.data.cameras.new(name); ob=bpy.data.objects.new(name,d); display.objects.link(ob)
    ob.location=loc; ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
    d.type='ORTHO'; d.ortho_scale=scale; return ob
cam=camera('参考相机_全景',(-38,-76,66),(22,-6,7),66)
top=camera('参考相机_俯视',(22,-8,82),(22,-8,0),58)
close=camera('参考相机_近景',(12,-12,13),(23,9,2),19)
scene=bpy.context.scene
scene.camera=cam
scene.render.engine='CYCLES'
scene.cycles.samples=24
scene.render.resolution_x=1600; scene.render.resolution_y=1100; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='AgX'
scene.view_settings.look='AgX - Medium High Contrast'
scene.view_settings.exposure=1.35
scene.render.filepath=OUT+'/overview.png'
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/l_corridor_room_type_v001.blend')

catalog=[]
for slug, info in packages.items():
    category=info['category']; d=OUT+'/component_packages_v001/'+category+'/'+slug
    os.makedirs(d,exist_ok=True)
    obs=[bpy.data.objects[n] for n in info['objects']]
    entries=[]
    for ob in obs:
        entries.append({'name':ob.name,'location_m':[round(v,4) for v in ob.location], 'dimensions_m':[round(v,4) for v in ob.dimensions]})
    rec={'package_id':'ENV-BATTLE-LCORRIDOR-'+slug.upper(), 'slug':slug,'name_zh':info['name_zh'],'category':category,'version':'v001','source_blend':'l_corridor_room_type_v001.blend','collection':info['collection'].name,'objects':entries,'material_roles':MAT_NAMES,'exported':False,'collision':'pending Godot assembly'}
    with open(d+'/asset_manifest.json','w') as f: json.dump(rec,f,ensure_ascii=False,indent=2)
    catalog.append({'package_id':rec['package_id'],'path':os.path.relpath(d,OUT),'object_count':len(obs)})
with open(OUT+'/component_packages_v001/catalog.json','w') as f:json.dump(catalog,f,ensure_ascii=False,indent=2)
with open(OUT+'/component_packages_v001/tree.txt','w') as f:
    f.write('\n'.join(e['path'] for e in catalog)+'\n')
manifest={'room_type':'L_CORRIDOR','room_asset_id':'ENV-BATTLE-L-CORRIDOR-TYPE','design_scope':'scene_art','block_id':'battle','floor_range':'battle level 01 / unassigned instance','scene_design_docs':['docs/v0.1/05_技术施工_关卡生成与爬楼.md','docs/v0.1/05.1_关卡区块设计.md','docs/v0.1/10.1_3D场景美术生产流程.md'],'asset_ledger':'assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx#3D-场景通用','whitebox_source':None,'reference_image':'reference.png','grid_m':5,'tile_dimensions_m':[5,5,.3],'dimensions_m':{'outer_bounds':[45,35],'horizontal_arm':[45,10],'south_arm_extension':[10,25]},'tile_count':len(cells),'wall_visual_height_m':11.9,'wall_logic_height_m':12,'wall_thickness_m':.3,'door_centers_m':[[7.5,10],[37.5,10],[37.5,-25]],'door_opening_m':[2.9,3.35],'required_components':['5m floor tile','5m solid wall','secure door','server rack','access terminal','cable bridge','planter'],'required_facilities':[],'package_count':len(catalog),'layout_source':'reference-derived dimensions; 10 m corridor width is user specified; no whitebox exists','status':'Blender art source only; gameplay topology and Godot import pending'}
with open(OUT+'/room_type_manifest.json','w') as f:json.dump(manifest,f,ensure_ascii=False,indent=2)
print(json.dumps({'blend':OUT+'/l_corridor_room_type_v001.blend','packages':len(catalog),'tiles':len(cells),'objects':len(bpy.data.objects)},ensure_ascii=False))
