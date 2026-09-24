"""Reference-directed v002 polish. Run with the v001 source open in Blender MCP."""
import bpy, json, math, os, shutil
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), *(['..'] * 9)))
BASE=ROOT+'/assets/art/environments/tower_zones/expedition/source/room_types/l_corridor'
V1=BASE+'/v001'; OUT=BASE+'/v002'
assert os.path.realpath(bpy.data.filepath)==os.path.realpath(V1+'/L型走廊种类_数据连廊_45x35m_v001.blend'), bpy.data.filepath
os.makedirs(OUT,exist_ok=True)
for name in ('reference.png','top.png'):
    shutil.copy2(V1+'/renders/'+name,OUT+'/renders/'+name)
shutil.copytree(V1+'/component_packages',OUT+'/component_packages',dirs_exist_ok=True)
with open(V1+'/component_packages/catalog.json') as f: catalog=json.load(f)
with open(V1+'/room_type_manifest.json') as f: room=json.load(f)
M=[bpy.data.materials[n] for n in ('01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光')]
facility=bpy.data.collections['03_区域固定设施']; support=bpy.data.collections['04_环境支持']; display=bpy.data.collections['90_展示与验收_灯光相机']
packages={}

def uv_mesh(ob,col,row):
    me=ob.data
    for old in list(me.uv_layers):me.uv_layers.remove(old)
    uv=me.uv_layers.new(name='PaletteUV'); me.uv_layers.active=uv; uv.active_render=True
    u=(col+.5)/10; v=1-(row+.5)/10
    corners=[(-.024,-.024),(.024,-.024),(.024,.024),(-.024,.024)]
    for poly in me.polygons:
        for j,i in enumerate(poly.loop_indices):
            a,b=corners[j%4]; uv.data[i].uv=(u+a,v+b)

def put(ob,col,mat,color):
    for c in list(ob.users_collection):c.objects.unlink(ob)
    col.objects.link(ob); ob.data.materials.clear(); ob.data.materials.append(M[mat]); uv_mesh(ob,*color)
    return ob

def cube(name,loc,dim,col,mat=0,color=(9,3),bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    ob=bpy.context.object; ob.name=name; ob.dimensions=dim
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    put(ob,col,mat,color)
    if bevel:
        b=ob.modifiers.new('圆润金属棱','BEVEL'); b.width=bevel; b.segments=2
        ob.modifiers.new('加权法线','WEIGHTED_NORMAL')
    return ob

def cyl(name,loc,r,depth,col,mat=0,color=(9,3),vertices=12,rotation=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=depth,location=loc)
    ob=bpy.context.object; ob.name=name
    if rotation: ob.rotation_euler=rotation
    return put(ob,col,mat,color)

def rod(name,a,b,r,col,mat=0,color=(9,3),vertices=12):
    aa=Vector(a);bb=Vector(b);d=bb-aa
    ob=cyl(name,(aa+bb)/2,r,d.length,col,mat,color,vertices)
    ob.rotation_euler=d.to_track_quat('Z','Y').to_euler()
    return ob

def newpack(slug,title,category,parent):
    col=bpy.data.collections.new(title+'_资产包');parent.children.link(col)
    packages[slug]={'slug':slug,'title':title,'category':category,'collection':col}
    return col

def oldpack(slug):
    rec=next(x for x in catalog if x['path'].endswith('/'+slug))
    with open(OUT+'/component_packages/'+rec['path'].split('/',1)[1]+'/asset_manifest.json') as f: d=json.load(f)
    return bpy.data.collections[d['collection']]

def remove_old(slug):
    rec=next(x for x in catalog if x['path'].endswith('/'+slug))
    col=oldpack(slug)
    for ob in list(col.objects):bpy.data.objects.remove(ob,do_unlink=True)
    bpy.data.collections.remove(col,do_unlink=True)
    shutil.rmtree(OUT+'/component_packages/'+rec['path'].split('/',1)[1])
    catalog.remove(rec)

# The two reference crops both show open, wheeled maintenance trolleys.
for slug in ('crate_02','crate_03'):
    remove_old(slug)

def trolley(slug,x,y,rot=0):
    col=newpack(slug,'双层带轮数据维修推车','facility',facility)
    # Local axes are kept explicit so that both carts retain identical reusable geometry.
    def pos(dx,dy,z):
        return (x+math.cos(rot)*dx-math.sin(rot)*dy,
                y+math.sin(rot)*dx+math.cos(rot)*dy,z)
    def cb(name,dx,dy,z,dim,mat=0,color=(9,3),bevel=0):
        ob=cube(name,pos(dx,dy,z),dim,col,mat,color,bevel);ob.rotation_euler.z=rot;return ob
    for z in (.22,.81,1.37):
        cb('三层冲压金属托板',0,0,z,(1.48,1.10,.075),0,(9,2),.04)
        cb('托板防滑内衬',0,0,z+.048,(1.30,.92,.022),1,(9,0))
        for sy in (-.54,.54):cb('托盘侧向护栏',0,sy,z+.15,(1.50,.035,.22),0,(4,2))
        for sx in (-.73,.73):cb('托盘端部护栏',sx,0,z+.15,(.035,1.12,.22),0,(4,2))
    for sx in (-.68,.68):
        for sy in (-.48,.48):
            cb('琥珀色承重立柱',sx,sy,.83,(.055,.055,1.30),0,(4,0))
            wheel=cyl('脚轮橡胶胎',pos(sx,sy,.105),.105,.095,col,1,(9,0),16,(math.pi/2,0,rot))
            cyl('脚轮金属轮毂',pos(sx,sy-.055,.105),.042,.014,col,0,(9,6),12,(math.pi/2,0,rot))
            cb('轮架刹车拨片',sx,sy-.10,.17,(.16,.085,.024),0,(4,2))
    # Distinct heavy equipment cases and tray dividers, not a solid black cube.
    cb('底层加固电池箱',-.30,.08,.43,(.57,.65,.38),0,(9,1),.035)
    cb('电池箱金属带箍',-.30,.08,.44,(.61,.10,.39),0,(9,5))
    cb('中层数据盒',.19,-.08,1.03,(.76,.69,.36),1,(9,1),.035)
    cb('中层数据盒盖',.19,-.08,1.23,(.80,.71,.075),0,(9,3),.02)
    for i in range(3):
        cb('侧面橙色识别灯',.42,-.45,.94+i*.095,(.11,.016,.03),3,(4,3))
    cb('顶层独立工具箱',-.17,.12,1.50,(.98,.69,.15),0,(9,1),.035)
    cb('顶部收边盖板',-.17,.12,1.59,(1.02,.73,.045),0,(9,4),.02)
    cb('工具箱把手',-.17,.12,1.66,(.37,.07,.06),0,(4,2))
    for dx in (-.50,.16):
        cb('顶盖紧固栓',dx,-.21,1.63,(.07,.07,.03),0,(9,7))
    # Looping service lead drapes over the side rail.
    pts=[pos(.36,.30,1.62),pos(.58,.42,1.52),pos(.70,.49,1.39),pos(.73,.49,1.16)]
    for a,b in zip(pts,pts[1:]):rod('推车柔性维修电缆',a,b,.025,col,0,(9,0),10)
    cb('车架小型黄色警示贴',.75,-.26,.87,(.018,.18,.08),3,(4,3))

trolley('service_cart_gallery',32.0,8.30)
trolley('service_cart_south',42.60,-10.20,math.pi/2)

# Rework the two kiosk silhouettes in the crops: angled illuminated screen,
# lower vents, card reader, side housing, rear hinge and visible keys.
for slug,x,y,turn in (('console_01',27.0,8.65,0),('console_02',38.6,-14.8,-math.pi/2)):
    col=oldpack(slug)
    for ob in list(col.objects):bpy.data.objects.remove(ob,do_unlink=True)
    def cp(dx,dy,z):return (x+math.cos(turn)*dx-math.sin(turn)*dy,y+math.sin(turn)*dx+math.cos(turn)*dy,z)
    def cc(name,dx,dy,z,dim,mat,color,bevel=0):
        ob=cube(name,cp(dx,dy,z),dim,col,mat,color,bevel);ob.rotation_euler.z=turn;return ob
    cc('终端宽底座',0,0,.12,(.80,.80,.24),0,(9,2),.035)
    cc('终端高柜体',0,.05,.93,(.70,.70,1.54),0,(9,1),.05)
    cc('侧置服务箱',.48,.18,.56,(.38,.56,.87),0,(9,2),.025)
    cc('服务箱橙色扣',.48,-.12,.60,(.18,.025,.11),3,(4,3))
    for zz in (.42,.55,.68,.81):
        cc('柜体前格栅',0,-.32,zz,(.43,.027,.037),1,(9,0))
    cc('倾斜屏幕加厚背框',0,-.26,1.82,(.86,.23,.88),0,(9,4),.055)
    cc('显示屏黑玻璃',0,-.395,1.86,(.68,.020,.62),2,(3,6),.018)
    cc('主UI亮蓝区域',-.13,-.412,1.93,(.34,.009,.40),3,(3,5))
    cc('副UI数据块',.23,-.414,1.99,(.19,.009,.27),3,(9,8))
    for i in range(3):cc('细数据条',.22,-.42,1.76+i*.07,(.20,.009,.018),3,(3,5))
    cc('前沿操作键盘',0,-.48,1.50,(.64,.19,.07),0,(9,5))
    for i in range(5):cc('机械按键',-.24+i*.12,-.59,1.54,(.065,.045,.014),3,(3,5))
    cc('卡片读取槽',.35,-.35,1.12,(.12,.025,.20),0,(9,6))
    cc('读取状态灯',.35,-.38,1.19,(.055,.012,.035),3,(4,3))
    for sx in (-.32,.32):
        cc('可见固定铆钉',sx,-.42,2.24,(.05,.025,.05),0,(9,7))

# Three linked, thick pipes at about 7 m: modular 5 m spans with structural clamps.
for i in range(9):
    col=newpack(f'high_pipe_rear_{i:02d}',f'七米高后墙管道跨段_{i:02d}','support',support)
    x=i*5
    for n,(z,r) in enumerate(((6.78,.075),(7.07,.105),(7.35,.060))):
        rod('高处横向主干管',(x+.12,9.63,z),(x+4.88,9.63,z),r,col,0,(9,2),12)
    for xx in (x+.35,x+4.65):
        cube('墙体厚管支架',(xx,9.73,7.07),(.13,.34,.90),col,0,(9,4))
        cube('琥珀色管卡',(xx,9.52,7.07),(.16,.07,.32),col,0,(4,2))
    if i in (1,3,5,7):
        cube('检修节点警示灯',(x+2.5,9.49,7.09),(.13,.06,.13),col,3,(4,3))
for i in range(7):
    col=newpack(f'high_pipe_east_{i:02d}',f'七米高东墙管道跨段_{i:02d}','support',support)
    y=-25+i*5
    for z,r in ((6.78,.075),(7.07,.105),(7.35,.060)):
        rod('高处转角支臂主管',(44.61,y+.12,z),(44.61,y+4.88,z),r,col,0,(9,2),12)
    for yy in (y+.35,y+4.65):
        cube('墙体厚管支架',(44.73,yy,7.07),(.34,.13,.90),col,0,(9,4))
        cube('琥珀色管卡',(44.52,yy,7.07),(.07,.16,.32),col,0,(4,2))

# Suspended heavy cable with a visible sag/return rather than a straight hairline.
def cable(slug,points):
    col=newpack(slug,'高处下垂粗电缆','support',support)
    for a,b in zip(points,points[1:]):rod('黑色包胶粗电线',a,b,.095,col,1,(9,0),14)
    for index in (0,len(points)-1):
        p=points[index];cyl('电缆接头压环',p,.14,.13,col,0,(4,2),12)
    for a,b in zip(points[1:-1:2],points[2::2]):
        mid=(Vector(a)+Vector(b))*.5;cyl('扎带标识',mid,.107,.07,col,0,(9,5),12)
cable('hanging_cable_gallery_a',[(29.2,9.58,7.12),(29.25,9.30,6.55),(29.52,9.00,5.90),(29.75,9.04,5.30),(29.70,9.30,4.35),(29.70,9.47,3.50)])
cable('hanging_cable_gallery_b',[(33.6,9.58,7.12),(33.5,9.30,6.25),(33.25,9.08,5.45),(33.05,9.12,4.70),(33.12,9.38,4.10)])
cable('hanging_cable_turn',[(43.8,9.6,7.1),(44.25,9.48,6.85),(44.56,9.1,6.5),(44.62,8.5,5.95),(44.62,8.3,4.85)])
cable('hanging_cable_south_a',[(44.61,-9.2,7.1),(44.33,-9.2,6.45),(44.10,-9.05,5.8),(44.08,-8.82,5.15),(44.25,-8.72,4.0),(44.45,-8.75,3.05)])
cable('hanging_cable_south_b',[(44.61,-17.6,7.1),(44.36,-17.5,6.4),(44.10,-17.3,5.65),(44.05,-17.0,4.9),(44.38,-16.95,3.9)])

# Small wall labels at the two requested stations remain fixed visual details.
for slug,x,y in (('wall_label_gallery',31.0,9.46),('wall_label_south',44.4,-12.0)):
    col=newpack(slug,'三角墙面警示标识','support',support)
    cube('发光警告标识底板',(x,y,2.55),(.63,.04,.51),col,0,(9,1))
    cube('小型白色警告条',(x,y-.04,2.63),(.37,.015,.055),col,3,(9,8))
    cube('小型黄色警告条',(x,y-.04,2.47),(.28,.015,.035),col,3,(4,3))

# Two fixed verification cameras isolate the two referenced image crops.
def add_camera(name,loc,target,scale):
    d=bpy.data.cameras.new(name);ob=bpy.data.objects.new(name,d);display.objects.link(ob)
    ob.location=loc;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler();d.type='ORTHO';d.ortho_scale=scale
add_camera('参考相机_补图区块A',(23,-8,12),(30,8,2),13)
add_camera('参考相机_补图区块B',(29,-17,10),(40.5,-12.6,1.5),13)

# Preserve the v001 layout and pass its manifests forward with an explicit version bump.
for entry in catalog:
    entry['path']=entry['path'].replace('component_packages','component_packages')
    path=OUT+'/'+entry['path']+'/asset_manifest.json'
    with open(path) as f:rec=json.load(f)
    col=bpy.data.collections[rec['collection']]
    rec['version']='v002';rec['source_blend']='L型走廊种类_数据连廊_45x35m_v002.blend'
    rec['objects']=[{'name':o.name,'location_m':[round(v,4) for v in o.location],'dimensions_m':[round(v,4) for v in o.dimensions]} for o in col.objects if o.type=='MESH']
    entry['object_count']=len(rec['objects'])
    with open(path,'w') as f:json.dump(rec,f,ensure_ascii=False,indent=2)
for slug,info in packages.items():
    d=OUT+'/component_packages/'+info['category']+'/'+slug
    os.makedirs(d,exist_ok=True);obs=[o for o in info['collection'].objects if o.type=='MESH']
    rec={'package_id':'ENV-EXPEDITION-L-CORRIDOR-'+slug.upper(),'slug':slug,'name_zh':info['title'],'category':info['category'],'version':'v002','source_blend':'L型走廊种类_数据连廊_45x35m_v002.blend','collection':info['collection'].name,'objects':[{'name':o.name,'location_m':[round(v,4) for v in o.location],'dimensions_m':[round(v,4) for v in o.dimensions]} for o in obs],'material_roles':[m.name for m in M],'exported':False,'collision':'pending Godot assembly'}
    with open(d+'/asset_manifest.json','w') as f:json.dump(rec,f,ensure_ascii=False,indent=2)
    catalog.append({'package_id':rec['package_id'],'path':os.path.relpath(d,OUT),'object_count':len(obs)})
with open(OUT+'/component_packages/catalog.json','w') as f:json.dump(catalog,f,ensure_ascii=False,indent=2)
with open(OUT+'/component_packages/tree.txt','w') as f:f.write('\n'.join(e['path'] for e in catalog)+'\n')
room['package_count']=len(catalog);room['reference_image']='reference.png'
room['version']='v002';room['source_blend']='L型走廊种类_数据连廊_45x35m_v002.blend'
room['art_revision']='two reference-crop maintenance stations, 7 m pipe bridge, five thick suspended cable assemblies'
room['reference_crops']=['reference_crop_a.png','reference_crop_b.png']
room['new_detail_cameras']=['参考相机_补图区块A','参考相机_补图区块B']
room['high_pipe_centerline_m']=7.07
room['high_pipe_z_m']=[6.78,7.07,7.35]
room['hanging_cable_count']=5
room['required_components'] += ['wheeled two-tier maintenance cart','7 m overhead pipe span','suspended heavy cable']
with open(OUT+'/room_type_manifest.json','w') as f:json.dump(room,f,ensure_ascii=False,indent=2)

scene=bpy.context.scene
scene.camera=bpy.data.objects['参考相机_全景']
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/L型走廊种类_数据连廊_45x35m_v002.blend')
print(json.dumps({'blend':bpy.data.filepath,'packages':len(catalog),'new_packages':len(packages),'objects':len(bpy.data.objects)},ensure_ascii=False))
