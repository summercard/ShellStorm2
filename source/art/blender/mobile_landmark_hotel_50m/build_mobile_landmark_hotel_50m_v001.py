import bpy, math, os, json
from mathutils import Vector

ROOT = r'I:/工作项目/shellstrom2/ShellStorm2'
OUT = ROOT + r'/assets/art/environments/mobile_landmark_3d'
SRC = OUT + r'/source/env_mobile_landmark_hotel_50m/env_mobile_landmark_hotel_50m_source_v001.blend'
GLB = OUT + r'/components/env_mobile_landmark_hotel_50m/env_mobile_landmark_hotel_50m_visual_top3d.glb'
PREVIEW = ROOT + r'/outputs/mobile_landmark_hotel_50m_v001/mobile_landmark_hotel_50m_preview.png'
PALETTE = ROOT + r'/assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
ASSET_ID = 'ENV-MOBILE-LANDMARK-HOTEL-50M'
LOGIC_ID = 'mobile_landmark_hotel_50m'

# Clear scene
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
    pass

# materials: four standard roles

def mat(name, color, metallic=0.0, rough=0.5, emission=None):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1)
    m.use_nodes=True; bs=m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Metallic'].default_value=metallic; bs.inputs['Roughness'].default_value=rough
    if emission:
        bs.inputs['Emission Color'].default_value=(*emission,1); bs.inputs['Emission Strength'].default_value=1.25
    return m
metal=mat('01_精工金属_紫色骨架',(0.16,0.12,0.28),0.86,0.27)
matte=mat('02_细腻哑光_青绿大面',(0.18,0.42,0.43),0.03,0.68)
varnish=mat('03_清漆反光_紫粉点缀',(0.55,0.16,0.42),0.18,0.14)
emit=mat('04_柔和自发光_UI灯光',(0.05,0.65,0.82),0,0.36,(0.05,0.65,0.82))
MATS=[metal,matte,varnish,emit]

# palette image datablock for contract
if os.path.exists(PALETTE):
    img=bpy.data.images.load(PALETTE, check_existing=True); img.name='设施低亮多巴胺色盘_10x10_512.png'
else: img=None

root=bpy.data.collections.new('mobile_landmark_hotel_50m_中文资产管理'); bpy.context.scene.collection.children.link(root)
make=bpy.data.collections.new('01_制作组件_已统一材质'); root.children.link(make); make.hide_viewport=True; make.hide_render=True
out=bpy.data.collections.new('02_游戏输出_独立资产包_v001'); root.children.link(out)
structure=bpy.data.collections.new('01_建筑结构'); out.children.link(structure)
facade=bpy.data.collections.new('02_立面细节'); out.children.link(facade)
roof=bpy.data.collections.new('03_屋顶设施'); out.children.link(roof)
lightcol=bpy.data.collections.new('04_UI灯光'); out.children.link(lightcol)
show=bpy.data.collections.new('90_展示与验收_灯光相机'); root.children.link(show)

def link_obj(obj, col):
    for c in list(obj.users_collection): c.objects.unlink(obj)
    col.objects.link(obj)

def box(name, loc, scale, material, col, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o=bpy.context.object; o.name=name; o.dimensions=scale; bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(material); link_obj(o,col)
    if bevel:
        mod=o.modifiers.new('微倒角','BEVEL'); mod.width=bevel; mod.segments=1
    return o

def cyl(name, loc, radius, depth, material, col, verts=8):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc)
    o=bpy.context.object; o.name=name; o.data.materials.append(material); link_obj(o,col); return o

# Base 50x50, low podium and terraces
box('建筑基座_50x50', (0,0,1.0), (50,50,2), metal, structure, .25)
box('裙房底座_42x38', (0,0,4.0), (42,38,4), matte, structure, .2)
# lower podium wings
box('南侧裙房', (0,-10,9), (42,16,10), matte, structure, .18)
box('东侧裙房', (13,3,8), (14,24,8), matte, structure, .18)
box('西侧裙房', (-13,3,8), (14,24,8), matte, structure, .18)
# tower stepped mass
box('塔楼主筒_32x26', (0,2,38), (32,26,50), matte, structure, .22)
box('塔楼上段_26x22', (0,2,65), (26,22,20), matte, structure, .18)
box('塔楼顶部机房_18x16', (0,2,78), (18,16,8), matte, structure, .15)
# vertical corner metal piers
for x in (-15.8,15.8):
  for y in (-10.8,14.8): box('塔楼角部骨架', (x,y,40), (1.2,1.2,54), metal, structure, .08)
# floor bands
for z in [13,18,23,28,33,38,43,48,53,58,63,68,73,78]:
    box('楼层压边带', (0,2,z), (33,27,.45), metal, facade, .04)
# windows on front/back, 12 floors x 5 bays each
for side_y in (-11.35,15.35):
  for floor in range(10):
    z=17+floor*4.8
    for i,x in enumerate([-11,-5.5,0,5.5,11]):
      box('立面窗_纵向模块', (x,side_y,z), (3.1,.28,2.8), varnish, facade, .04)
      box('立面窗_灯芯', (x,side_y-.18 if side_y<0 else side_y+.18,z), (1.65,.08,.14), emit, lightcol)
# side windows
for side_x in (-16.35,16.35):
  for floor in range(10):
    z=17+floor*4.8
    for y in [-7,-1,5,11]: box('侧立面窗', (side_x,y,z), (.28,3.0,2.7), varnish, facade, .04)
# podium windows and entrance
for x in [-16,-10,-4,4,10,16]:
  box('裙房窗', (x,-18.15,9), (3.0,.3,3.8), varnish, facade, .05)
box('主入口门廊顶', (0,-21,8), (15,7,1.0), metal, structure, .12)
for x in [-6,-3,0,3,6]: box('主入口玻璃门', (x,-21.15,5.2), (2.0,.25,5.0), varnish, facade, .03)
for x in [-6,-3,0,3,6]: box('门廊灯带', (x,-21.35,7.6), (1.3,.1,.16), emit, lightcol)
# vertical fins on facade
for x in [-14,-8,-2,4,10,14]: box('立面竖向装饰肋', (x,-12.9,42), (.38,.45,48), metal, facade, .03)
# rooftop parapets and tanks
box('屋顶女儿墙南', (0,-7.8,83), (19,.6,2), metal, roof)
box('屋顶女儿墙北', (0,11.8,83), (19,.6,2), metal, roof)
box('屋顶女儿墙东', (9.2,2,83), (.6,20,2), metal, roof)
box('屋顶女儿墙西', (-9.2,2,83), (.6,20,2), metal, roof)
for x,y in [(-5,0),(0,0),(5,0),(-4,6),(4,6)]:
  box('屋顶设备箱', (x,y,85), (3.0,2.6,2.4), metal, roof, .12)
  box('设备指示灯', (x,y-1.35,85), (1.0,.08,.12), emit, lightcol)
# rooftop antenna and helipad-like scenic crown
cyl('屋顶通讯杆',(0,2,91),.35,12,metal,roof,10)
for z in [88,91,94]: cyl('通讯杆环灯',(0,2,z),.6,.12,emit,lightcol,12)
# corner light strips and facade accent lines
for x in [-16.8,16.8]:
  box('塔楼边缘灯带',(x,-11.7,42),(.12,.12,44),emit,lightcol)
# add controlled decorative mullions to approach target face count
for y in [-11.55,15.55]:
  for x in range(-14,15,2): box('窗间细分线',(x,y,41),(.08,.06,42),metal,facade)

# Apply a controlled bevel to output geometry: preserve the low-poly silhouette while
# raising architectural edge density toward the requested ~8000-face budget.
for obj in [o for o in out.all_objects if o.type == 'MESH']:
    if not any(m.type == 'BEVEL' for m in obj.modifiers):
        mod = obj.modifiers.new('建筑边缘细节','BEVEL'); mod.width = min(0.055, min(obj.dimensions) * 0.08); mod.segments = 1
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    for mod in list(obj.modifiers):
        if mod.type == 'BEVEL':
            try: bpy.ops.object.modifier_apply(modifier=mod.name)
            except RuntimeError: pass
    obj.select_set(False)
# Final face-budget trim: preserve silhouette and bevel language while targeting ~8k faces.
for obj in [o for o in out.all_objects if o.type == 'MESH']:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    dec = obj.modifiers.new('面数预算优化','DECIMATE'); dec.ratio = 0.82
    try: bpy.ops.object.modifier_apply(modifier=dec.name)
    except RuntimeError: pass
    obj.select_set(False)

# root custom props
root['asset_id']=ASSET_ID; root['logic_id']=LOGIC_ID; root['unit']='meter'; root['blender_forward']='-Y'; root['godot_forward']='-Z'; root['module_local_origin']='xy_center_bottom_z0'; root['target_footprint_m']='50x50'; root['target_faces']='8000'; root['reference_image']='Clipboard_Screenshot.png'

# palette UV layer for all output meshes
for obj in [o for o in out.all_objects if o.type=='MESH']:
    if 'PaletteUV' not in obj.data.uv_layers: obj.data.uv_layers.new(name='PaletteUV')
    obj.data.uv_layers.active_index=len(obj.data.uv_layers)-1
    obj.data.uv_layers.active.name='PaletteUV'
    obj['asset_id']=ASSET_ID; obj['logic_id']=LOGIC_ID; obj['export_root']='02_游戏输出_独立资产包_v001'

# camera + lights
bpy.ops.object.camera_add(location=(105,-125,100)); cam=bpy.context.object; cam.name='参考摄像机_主视角'; link_obj(cam,show); bpy.context.scene.camera=cam

def track(obj, target): obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()
track(cam,(0,0,40)); cam.data.lens=58
for loc,energy,size in [((70,-80,110),1800,50),((-70,-30,80),1200,45),((0,60,120),1600,40)]:
 bpy.ops.object.light_add(type='AREA',location=loc); l=bpy.context.object; l.data.energy=energy; l.data.shape='DISK'; l.data.size=size; track(l,(0,0,35)); link_obj(l,show)
scene=bpy.context.scene; scene.render.engine='BLENDER_EEVEE'; scene.render.resolution_x=700; scene.render.resolution_y=700; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.render.filepath=PREVIEW
scene.world.color=(0.025,0.04,0.08)
# save and render
bpy.ops.wm.save_as_mainfile(filepath=SRC)
bpy.ops.render.render(write_still=True)
# export visual GLB
bpy.ops.object.select_all(action='DESELECT')
for o in out.all_objects:
  if o.type=='MESH': o.select_set(True)
bpy.context.view_layer.objects.active=next(o for o in out.all_objects if o.type=='MESH')
bpy.ops.export_scene.gltf(filepath=GLB, export_format='GLB', export_image_format='NONE', use_selection=True)
# report
faces=sum(len(o.data.polygons) for o in out.all_objects if o.type=='MESH'); verts=sum(len(o.data.vertices) for o in out.all_objects if o.type=='MESH')
mins=[1e9,1e9,1e9]; maxs=[-1e9,-1e9,-1e9]
for o in out.all_objects:
 if o.type!='MESH': continue
 for c in o.bound_box:
  w=o.matrix_world @ Vector(c)
  for i in range(3): mins[i]=min(mins[i],w[i]); maxs[i]=max(maxs[i],w[i])
report={'asset_id':ASSET_ID,'logic_id':LOGIC_ID,'source':SRC,'glb':GLB,'preview':PREVIEW,'faces':faces,'vertices':verts,'bounds_min':mins,'bounds_max':maxs,'materials':[m.name for m in MATS],'collections':['01_制作组件_已统一材质','02_游戏输出_独立资产包_v001','90_展示与验收_灯光相机']}
with open(OUT+'/source/env_mobile_landmark_hotel_50m/asset_manifest.json','w',encoding='utf-8') as f: json.dump(report,f,ensure_ascii=False,indent=2)
print(json.dumps(report,ensure_ascii=False))
