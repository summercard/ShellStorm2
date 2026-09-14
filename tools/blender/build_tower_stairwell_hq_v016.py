import bpy, bmesh, json, math, os, shutil
from mathutils import Vector
from pathlib import Path

ROOT = Path(r'I:\工作项目\shellstrom2\ShellStorm2')
SRC = Path(r'I:\工作项目\shellstrom2\ShellStorm2\tools\3Dgame-design\save\blocks\stairs\whitebox_tower_stairs_v015\whitebox_tower_stairs_v015.blend')
OUT = ROOT/'assets/art/environments/tower_descent_3d/source/stairwell_hq_v016'
OUT.mkdir(parents=True, exist_ok=True)
BLEND = OUT/'env_tower_stairwell_hq_v016.blend'
PALETTE = ROOT/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'

def coll(name, parent=None, hide=False):
    c=bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if parent is None:
        if c.name not in bpy.context.scene.collection.children: bpy.context.scene.collection.children.link(c)
    elif c.name not in parent.children: parent.children.link(c)
    c.hide_viewport=hide; c.hide_render=hide
    return c

def mat(name, base, metallic=0, rough=.5, emission=None):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name); m.use_nodes=True
    n=m.node_tree.nodes; n.clear(); out=n.new('ShaderNodeOutputMaterial'); bs=n.new('ShaderNodeBsdfPrincipled'); bs.inputs['Base Color'].default_value=(*base,1); bs.inputs['Metallic'].default_value=metallic; bs.inputs['Roughness'].default_value=rough
    if emission:
        bs.inputs['Emission Color'].default_value=(*emission[0],1); bs.inputs['Emission Strength'].default_value=emission[1]
    m.node_tree.links.new(bs.outputs['BSDF'],out.inputs['Surface'])
    if PALETTE.exists():
        img=bpy.data.images.get(PALETTE.name) or bpy.data.images.load(str(PALETTE), check_existing=True); img.filepath=str(PALETTE)
        tex=n.new('ShaderNodeTexImage'); tex.image=img; tex.interpolation='Closest'; uv=n.new('ShaderNodeUVMap'); uv.uv_map='PaletteUV'
    return m

MET=mat('01_精工金属_紫色骨架',(0.07,.09,.16),.88,.26)
MAT=mat('02_细腻哑光_青绿大面',(.08,.22,.28),.03,.7)
GLS=mat('03_清漆反光_紫粉点缀',(.22,.06,.25),.18,.14)
EM=mat('04_柔和自发光_UI灯光',(0.04,.35,.55),0,.38,((.04,.5,1.0),1.35))

def assign(o, m):
    o.data.materials.clear(); o.data.materials.append(m)
    if hasattr(o.data,'uv_layers'):
        uv=o.data.uv_layers.get('PaletteUV') or o.data.uv_layers.new(name='PaletteUV'); o.data.uv_layers.active=uv; uv.active_render=True
        for p in o.data.polygons:
            cx=.05+(p.index%10)*.095; cy=.05+((p.index//10)%10)*.095
            for li in p.loop_indices: uv.data[li].uv=(cx,cy)

def cube(name, loc, scale, m, c):
    bpy.ops.mesh.primitive_cube_add(location=loc); o=bpy.context.object; o.name=name; o.scale=(scale[0]/2,scale[1]/2,scale[2]/2); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True); assign(o,m); c.objects.link(o); bpy.context.collection.objects.unlink(o); return o
def cyl(name, loc, radius, depth, m, c, rot=(0,0,0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=16,radius=radius,depth=depth,location=loc,rotation=rot); o=bpy.context.object; o.name=name; assign(o,m); c.objects.link(o); bpy.context.collection.objects.unlink(o); return o
def beam_between(name,a,b,r,m,c):
    a,b=Vector(a),Vector(b); d=b-a; mid=(a+b)/2
    o=cyl(name,mid,r,d.length,m,c); o.rotation_mode='QUATERNION'; o.rotation_quaternion=d.to_track_quat('Z','Y'); return o

scene=bpy.context.scene; scene['asset_version']='v016'; scene['asset_id']='ENV-TOWER-STAIRWELL-HQ-V016'; scene['reference']='codex-clipboard-8c57cc75-bdcb-4e12-a0c4-15d852c593f9.png'; scene['locked_source']=str(SRC)
src=coll('01_制作组件_白模锁区',hide=True); out=coll('02_游戏输出_独立资产包_v016'); arch=coll('01_建筑结构_楼梯间_资产包',out); support=coll('04_环境支持_管线灯光_资产包',out); qa=coll('90_展示与验收_灯光相机')
for o in list(bpy.data.objects):
    if o.type=='MESH' and o.name not in {'QA_Camera'}:
        for c in list(o.users_collection): c.objects.unlink(o)
        src.objects.link(o)
        cp=o.copy(); cp.data=o.data.copy(); cp.name='OUT_'+o.name; arch.objects.link(cp); assign(cp, MAT if ('墙' in o.name or '地板' in o.name) else MET)

# deep-space wall panels and floor trims
for z,y in [(0,-2.2),(0,27.2),(-9,-2.2),(-9,27.2)]:
    cube(f'WallPanel_{z}_{y}',(7.5,y,z+4.45),(14.4,.12,8.7),MAT,arch)
for z in (-.2,-9.2):
    cube(f'FloorEdge_{z}',(7.5,12.5,z),(14.6,29.8,.18),MAT,arch)

# two stair runs, accent nosings, and layered rails
for run,(x,y,z,sign) in {'UP':(11.5,3.12,0,1),'DOWN':(3.5,18.12,-6,-1)}.items():
    for i in range(20):
        zz=z + sign*i*.30; yy=y + i*.72*sign
        cube(f'{run}_Step_Nosing_{i:02d}',(x,yy,zz+.055),(4.35,.06,.10),GLS,arch)
        for sx in (x-2.3,x+2.3):
            cube(f'{run}_Step_Light_{i:02d}_{sx}',(sx,yy,zz+.10),(.10,.34,.045),EM,support)
    for sx in (x-2.45,x+2.45):
        beam_between(f'{run}_Rail_Post_Base',(sx,y,z+.25),(sx,y+sign*14.4,z+sign*6.0),.07,MET,arch)
        beam_between(f'{run}_Rail_Handrail',(sx,y,z+1.25),(sx,y+sign*14.4,z+sign*6.0+1.25),.10,MET,arch)
        for i in range(0,8): beam_between(f'{run}_Rail_Baluster_{sx}_{i}',(sx,y+sign*i*2.0,z+sign*i*.84+.3),(sx,y+sign*i*2.0,z+sign*i*.84+1.2),.035,MET,arch)

# cross-platform rails and industrial pipe runs
for z in (-.1,-9.1):
    for x in (0.5,14.5):
        beam_between(f'Platform_Rail_{z}_{x}',(x,3,z+1.15),(x,18,z+1.15),.09,MET,arch)
        for y in range(4,18,3): cyl(f'Platform_Post_{z}_{x}_{y}',(x,y,z+.55),.06,1.1,MET,arch)
    for yy in (-1.9,27.1):
        for h in (1.1,1.35): beam_between(f'Pipe_{z}_{yy}_{h}',(1,yy,z+h),(14,yy,z+h),.045,MET,support)
for x in (0.35,14.65):
    for z in (-8.1,-7.7,-.9,-.5): beam_between(f'VerticalPipe_{x}_{z}',(x,1,z),(x,26,z),.05,MET,support)

# wall control panels, warning beacons, and cool-white strips
for z,yy in [(-.3,10),(-9.3,16)]:
    cube(f'ControlPanel_{z}',(7.5,yy,z+2.7),(2.2,.18,1.35),GLS,arch); cube(f'PanelScreen_{z}',(7.5,yy-.11,z+2.8),(1.25,.025,.55),EM,support)
    for xx in (6.7,8.3): cyl(f'PanelBolt_{z}_{xx}',(xx,yy-.15,z+2.35),.06,.04,MET,arch,rot=(math.pi/2,0,0))
for x,y,z in [(1,-1.95,-.5),(14,-1.95,-.5),(1,27,-8.5),(14,27,-8.5)]:
    cube(f'WarningBeacon_{x}_{y}_{z}',(x,y,z+3.0),(.36,.16,.42),EM,support)
for x in (1.0,14.0): cube(f'WallLight_{x}',(x,12.5,4.8),(.12,15,.06),EM,support)

# collision sloped proxies separate from visible detail
col=coll('03_碰撞_简化斜坡与栏杆',out)
for run,(x,y,z,sign) in {'UP':(11.5,3.12,0,1),'DOWN':(3.5,18.12,-6,-1)}.items():
    o=cube(f'COLLISION_{run}_Slope',(x,y+sign*7.2,z+sign*3.0),(4.8,14.6,.35),MET,col); o.rotation_euler[0]=math.atan2(sign*6.0,14.4); o.hide_render=True; o.display_type='WIRE'; o['collision_role']='continuous_walkable_slope'; o['camera_clearance']=True

# metadata and preview camera/lights
camd=bpy.data.cameras.new('Stairwell_Reference_Camera'); cam=bpy.data.objects.new('Stairwell_Reference_Camera',camd); qa.objects.link(cam); cam.location=(31,-34,23); target=Vector((7.5,12,-4)); cam.rotation_euler=(target-Vector(cam.location)).to_track_quat('-Z','Y').to_euler(); camd.lens=48; scene.camera=cam
for name,loc,energy,color,size in [('Key',(10,-10,18),1500,(.18,.45,1),8),('Rim',(16,22,5),1200,(.1,.35,1),7),('Warm',(4,10,-4),700,(1,.16,.04),5)]:
    ld=bpy.data.lights.new(name,'AREA'); ld.energy=energy; ld.color=color; ld.shape='DISK'; ld.size=size; lo=bpy.data.objects.new(name,ld); qa.objects.link(lo); lo.location=loc; lo.rotation_euler=(target-Vector(loc)).to_track_quat('-Z','Y').to_euler()
scene.render.engine='BLENDER_EEVEE_NEXT'; scene.render.resolution_x=900; scene.render.resolution_y=900; scene.render.resolution_percentage=100; scene.render.image_settings.file_format='PNG'; scene.render.film_transparent=False; scene.world.color=(.004,.008,.018); scene.render.filepath=str(OUT/'stairwell_reference.png'); bpy.ops.render.render(write_still=True)

objects=[o for o in out.all_objects if o.type=='MESH']; manifest={'asset_id':scene['asset_id'],'version':'v016','source_blend':str(SRC),'palette':str(PALETTE),'collections':{},'objects':[],'locked_source_collections':[c.name for c in [src]]}
for c in (arch,support,col): manifest['collections'][c.name]=[o.name for o in c.objects]
for o in objects: manifest['objects'].append({'name':o.name,'collection':[c.name for c in o.users_collection],'location':list(o.location),'dimensions':list(o.dimensions),'materials':[m.name for m in o.data.materials]})
(OUT/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND)); print('TOWER_STAIRWELL_V016_OK',BLEND)
