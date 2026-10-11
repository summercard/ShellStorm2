import bpy, math, os, json
from mathutils import Vector

OUT = r'I:/工作项目/shellstrom2/ShellStorm2/art_source/environments/tower_zones/battle/source/room_types/master_office/v001'
BLEND = os.path.join(OUT, 'master_office_source_v001.blend')
os.makedirs(OUT, exist_ok=True)
# safety copy of current session
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'session_backup_before_build.blend'), copy=True)
# clear
bpy.ops.object.mode_set(mode='OBJECT') if bpy.context.object and bpy.context.object.mode != 'OBJECT' else None
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):
    if c.name not in {'Collection'}:
        bpy.data.collections.remove(c)
root = bpy.context.scene.collection
for c in list(root.children):
    root.children.unlink(c)
for name in ['01_制作组件','02_游戏输出','展示_相机灯光','参考图']:
    col = bpy.data.collections.new(name); root.children.link(col)

def col(name): return bpy.data.collections[name]
def mat(name, color, metallic=0.0, rough=0.5, emission=None):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color=(*color,1)
    m.use_nodes=True
    bs=next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if bs is None:
        bs=m.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
    bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Metallic'].default_value=metallic
    bs.inputs['Roughness'].default_value=rough
    if emission:
        bs.inputs['Emission Color'].default_value=(*emission,1); bs.inputs['Emission Strength'].default_value=4.0
    return m
m_floor=mat('palette_floor',(0.12,0.16,0.20),0.25,0.38)
m_floor2=mat('palette_floor_worn',(0.20,0.24,0.28),0.15,0.55)
m_wall=mat('palette_wall',(0.08,0.10,0.14),0.35,0.48)
m_metal=mat('palette_metal',(0.22,0.27,0.34),0.8,0.28)
m_sofa=mat('palette_sofa',(0.34,0.39,0.48),0.0,0.82)
m_blue=mat('palette_blue_glow',(0.05,0.22,0.42),0.3,0.3,(0.03,0.28,0.8))
m_plant=mat('palette_plant',(0.12,0.26,0.16),0.0,0.9)
m_debris=mat('palette_debris',(0.25,0.22,0.19),0.0,0.9)

def cube(name, loc, scale, material, collection='01_制作组件', bevel=0.0, rot=(0,0,0)):
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=rot)
    o=bpy.context.object; o.name=name; o.scale=(scale[0]/2,scale[1]/2,scale[2]/2)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if material: o.data.materials.append(material)
    for c in list(o.users_collection): c.objects.unlink(o)
    col(collection).objects.link(o)
    if bevel:
        mod=o.modifiers.new('edge_softness','BEVEL'); mod.width=bevel; mod.segments=2
    return o

def cyl(name, loc, r, depth, material, collection='01_制作组件'):
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=r, depth=depth, location=loc)
    o=bpy.context.object; o.name=name; o.data.materials.append(material)
    for c in list(o.users_collection): c.objects.unlink(o)
    col(collection).objects.link(o); return o
# Room frame: 15 x 20 x 11.9, local XY, floor Z=0
# floor panels, 5m grid
for ix,x in enumerate([-5,0,5]):
  for iy,y in enumerate([-7.5,-2.5,2.5,7.5]):
    cube(f'floor_panel_{ix}_{iy}',(x,y,0.08),(4.92,4.92,0.16),m_floor if (ix+iy)%2 else m_floor2,bevel=0.05)
# walls: west, north, south, east door wall; damaged back wall fractured panels
cube('wall_solid_west',(-7.35,0,5.95),(0.30,20,11.9),m_wall)
cube('wall_solid_south',(0,-9.85,5.95),(15,0.30,11.9),m_wall)
cube('wall_solid_north',(0,9.85,5.95),(15,0.30,11.9),m_wall)
# east door wall split around 2.5 lane
cube('door_wall_east_a',(7.35,-5.0,5.95),(0.30,9.7,11.9),m_wall)
cube('door_wall_east_b',(7.35,7.5,5.95),(0.30,5.0,11.9),m_wall)
cube('door_lintel',(7.35,2.5,10.4),(0.30,4.0,3.0),m_wall)
# damaged rear/back wall panels, offset and angled
for i,(x,y,z,sx,sy,sz,a) in enumerate([(-4.5,9.68,7.8,4.5,.35,7.0,-.08),(-.5,9.58,6.5,3.5,.35,5.5,.16),(3.0,9.65,8.0,3.2,.35,7.5,-.12),(5.8,9.55,5.0,2.0,.35,4.0,.20)]):
    cube(f'wall_damaged_{i}',(x,y,z),(sx,sy,sz),m_metal,rot=(0,a,0),bevel=.08)
# ceiling beams
for x in [-5,0,5]: cube(f'ceiling_beam_{x}',(x,0,11.65),(.28,19.0,.35),m_metal,bevel=.06)
# rug
cube('rug',(0,-1.0,.20),(7.2,8.0,.08),m_blue,bevel=.12)
# sofa along west/center
cube('sofa_base',(-2.9,-3.5,1.05),(2.3,9.2,1.0),m_sofa,bevel=.38)
for i,y in enumerate([-7.3,-5.3,-3.3,-1.3,.7,2.7]): cube(f'sofa_cushion_{i}',(-2.9,y,1.85),(2.4,1.65,1.15),m_sofa,bevel=.42)
for i,y in enumerate([-7.2,2.8]): cube(f'sofa_arm_{i}',(-2.9,y,2.5),(2.5,.5,2.0),m_sofa,bevel=.25)
cube('throw_blanket',(-1.75,1.0,2.15),(.12,1.8,1.5),m_blue,bevel=.06)
# display pods / vertical glass columns
for i,x in enumerate([-5.8,5.6]):
    cyl(f'display_column_{i}',(x,7.4,2.2),.55,4.2,m_metal)
    cyl(f'display_pod_glow_{i}',(x,7.4,2.3),.38,3.4,m_blue)
# plants
for i,(x,y) in enumerate([(-6.1,-7.6),(-6.0,6.8),(5.8,-7.2),(5.8,6.5)]):
    cyl(f'plant_pot_{i}',(x,y,.55),.42,1.1,m_metal)
    for j in range(4): cube(f'plant_leaf_{i}_{j}',(x+(j-1.5)*.12,y,.95+j*.28),(.12,.6,1.2),m_plant,rot=(0,(j-1.5)*.18,0),bevel=.05)
# front debris crates
for i,x in enumerate([-4.8,3.8]):
    cube(f'debris_crate_{i}',(x,-8.4,.55),(3.5,2.0,1.1),m_metal,bevel=.08)
    for j in range(4): cube(f'crate_slats_{i}_{j}',(x-1.3+j*.85,-8.4,1.15),(.12,2.05,.15),m_debris)
# side table and terminal
cyl('side_table',(-1.0,-7.8,.55),.55,1.0,m_metal)
cube('fallen_terminal',(4.3,3.2,.65),(2.0,1.2,.35),m_metal,bevel=.08,rot=(.15,.1,.25))
cube('terminal_screen_glow',(4.3,3.2,.88),(1.5,.08,.18),m_blue,bevel=.03,rot=(.15,.1,.25))
# light strips
for i,(x,y,rot) in enumerate([(-7.15,-5,0),(-7.15,5,0),(0,9.65,math.pi/2),(0,-9.65,math.pi/2)]):
    cube(f'light_strip_emissive_{i}',(x,y,6.8),(.08,7.5,.12),m_blue,collection='02_游戏输出',bevel=.03,rot=(0,0,rot))
# cables/debris
for i,(x,y,z,rx) in enumerate([(-1,-6,.16,.2),(2,-5,.16,-.4),(4,-6,.17,.3),(-4,5,.17,-.2)]):
    cyl(f'cable_bundle_{i}',(x,y,z),.06,2.2,m_debris); bpy.context.object.rotation_euler[1]=rx
for i,(x,y,s,a) in enumerate([(-5,-5,.35,.2),(-4,-2,.25,-.3),(1,-6,.3,.5),(2,5,.22,-.5),(5,-3,.28,.2),(0,7,.2,.1)]):
    cube(f'debris_piece_{i}',(x,y,.28),(s*2,s,.08),m_debris,bevel=.02,rot=(0,0,a))
# Camera and lighting in display collection
bpy.ops.object.camera_add(location=(22,-25,22))
cam=bpy.context.object; cam.name='CAMERA_45_DEGREE'; bpy.context.scene.camera=cam
for c in list(cam.users_collection): c.objects.unlink(cam)
col('展示_相机灯光').objects.link(cam)
def track(obj, point): obj.rotation_euler=(Vector(point)-obj.location).to_track_quat('-Z','Y').to_euler()
track(cam,(0,0,2.5)); cam.data.lens=48
bpy.ops.object.light_add(type='AREA', location=(0,-1,10)); key=bpy.context.object; key.name='KEY_SOFT'; key.data.energy=1400; key.data.shape='RECTANGLE'; key.data.size=12; track(key,(0,0,0));
for c in list(key.users_collection): c.objects.unlink(key)
col('展示_相机灯光').objects.link(key)
bpy.ops.object.light_add(type='AREA', location=(-8,-2,5)); fill=bpy.context.object; fill.name='FILL_BLUE'; fill.data.energy=650; fill.data.color=(.15,.35,1); fill.data.size=8; track(fill,(0,0,2));
for c in list(fill.users_collection): c.objects.unlink(fill)
col('展示_相机灯光').objects.link(fill)
# metadata
bpy.context.scene['room_type']='MASTER_OFFICE'; bpy.context.scene['block_id']='battle'; bpy.context.scene['dimensions_m']=[15.0,20.0,11.9]; bpy.context.scene['walk_plane_z_m']=0.0; bpy.context.scene['design_scope']='scene_art'; bpy.context.scene['component_plan']='component_plan.json'; bpy.context.scene['reference_image']=r'C:/Users/zhuangmenghong/.workbuddy/clipboard-images/clipboard-2026-10-08T16-56-51-718Z-8ee4db79.jpg'
# render settings
scene=bpy.context.scene; scene.render.engine='BLENDER_EEVEE_NEXT'; scene.render.resolution_x=900; scene.render.resolution_y=900; scene.render.resolution_percentage=100
scene.render.filepath=os.path.join(OUT,'master_office_preview.png')
scene.world.color=(0.015,0.018,0.028)
bpy.ops.wm.save_as_mainfile(filepath=BLEND)
bpy.ops.render.render(write_still=True)
# manifest
manifest={'schema':'shellstorm2.battle.room_type_source','schema_version':1,'room_type':'MASTER_OFFICE','display_name_zh':'父亲的办公室','block_id':'battle','dimensions_m':[15.0,20.0,11.9],'whitebox_source':'existing 98F authored layout master_office 15x20m','reference_image':bpy.context.scene['reference_image'],'component_plan':'component_plan.json','source_blend':BLEND,'room_owned_geometry':False,'status':'blender_source_built','runtime_layout_owner':'Godot TSCN'}
with open(os.path.join(OUT,'asset_manifest.json'),'w',encoding='utf-8') as f: json.dump(manifest,f,ensure_ascii=False,indent=2)
print(json.dumps({'blend':BLEND,'render':scene.render.filepath,'objects':len(bpy.data.objects),'status':'ok'},ensure_ascii=False))
