import bpy, os, json, math
from mathutils import Vector
OUT=r'I:/工作项目/shellstrom2/ShellStorm2/art_source/environments/tower_zones/battle/source/room_types/master_office/v003'
BLEND=os.path.join(OUT,'master_office_source_v003.blend'); os.makedirs(OUT,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'session_backup_before_v003.blend'),copy=True)
# clear all scene data
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):
    if c.name!='Collection': bpy.data.collections.remove(c)
root=bpy.context.scene.collection
for c in list(root.children): root.children.unlink(c)
for n in ['01_制作组件_按设施拆分','02_游戏输出_独立资产包_v003','90_展示与验收_灯光相机','参考_白模与效果图']:
    root.children.link(bpy.data.collections.new(n))
C={n:bpy.data.collections[n] for n in ['01_制作组件_按设施拆分','02_游戏输出_独立资产包_v003','90_展示与验收_灯光相机','参考_白模与效果图']}
# shared palette materials, external palette image
pal=r'I:/工作项目/shellstrom2/ShellStorm2/assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
def make_mat(name,color,role,emit=0):
 m=bpy.data.materials.new(name); m.use_nodes=True; nt=m.node_tree; nt.nodes.clear(); out=nt.nodes.new('ShaderNodeOutputMaterial'); bs=nt.nodes.new('ShaderNodeBsdfPrincipled'); bs.inputs['Metallic'].default_value=.85 if role=='metal' else .05; bs.inputs['Roughness'].default_value=.28 if role=='metal' else (.72 if role=='matte' else .16); bs.inputs['Base Color'].default_value=(*color,1)
 if emit: bs.inputs['Emission Color'].default_value=(*color,1); bs.inputs['Emission Strength'].default_value=emit
 nt.links.new(bs.outputs['BSDF'],out.inputs['Surface']);
 # external palette and PaletteUV layer for compliance traceability
 try:
  img=bpy.data.images.load(pal,check_existing=True); tex=nt.nodes.new('ShaderNodeTexImage'); tex.name='公共色盘_外链_Closest'; tex.image=img; tex.interpolation='Closest'; tex.label='PaletteUV / shared palette'
 except: pass
 m['material_role']=role; m['palette_path']=pal; m['palette_uv_layer']='PaletteUV'; return m
M={'metal':make_mat('01_精工金属_紫色骨架',(.28,.30,.36),'metal'), 'matte':make_mat('02_细腻哑光_青绿大面',(.38,.43,.44),'matte'), 'varnish':make_mat('03_清漆反光_紫粉点缀',(.42,.24,.46),'varnish'), 'emit':make_mat('04_柔和自发光_UI灯光',(.16,.55,.9),'emit',1.35)}
def cube(n,loc,dim,mat,collection,rot=(0,0,0),bev=0.0):
 bpy.ops.mesh.primitive_cube_add(location=loc,rotation=rot); o=bpy.context.object; o.name=n; o.dimensions=dim; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True); o.data.materials.append(mat)
 for cc in list(o.users_collection): cc.objects.unlink(o)
 collection.objects.link(o)
 if 'PaletteUV' not in o.data.uv_layers: o.data.uv_layers.new(name='PaletteUV')
 o.data.uv_layers.active=o.data.uv_layers['PaletteUV']; o['component_master']=True; o['origin_contract']='bbox_xy_center_z_bottom'
 if bev: mod=o.modifiers.new('edge_bevel','BEVEL'); mod.width=bev; mod.segments=3
 return o
def cyl(n,loc,r,d,mat,collection):
 bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=r,depth=d,location=loc); o=bpy.context.object; o.name=n; o.data.materials.append(mat)
 for cc in list(o.users_collection): cc.objects.unlink(o)
 collection.objects.link(o); o.data.uv_layers.new(name='PaletteUV'); o['component_master']=True; return o
# masters collection and output collection
master=C['01_制作组件_按设施拆分']; out=C['02_游戏输出_独立资产包_v003']
# room frame metadata only
frame=bpy.data.objects.new('ROOM_FRAME_master_office_15x20',None); master.objects.link(frame); frame['dimensions_m']=[15,20,11.9]; frame['walk_plane_z_m']=0; frame.hide_render=True
# floor master and linked mesh instances
fm=cube('MASTER_floor_panel_5m',(0,0,.08),(4.94,4.94,.16),M['matte'],master,bev=.04)
for ix,x in enumerate([-5,0,5]):
 for iy,y in enumerate([-7.5,-2.5,2.5,7.5]):
  o=fm.copy(); o.data=fm.data; o.name=f'floor_panel_instance_{ix}_{iy}'; o.location=(x,y,.08); out.objects.link(o)
fm.hide_render=True; fm.hide_viewport=True
# wall masters and instances
wm=cube('MASTER_wall_solid_5m',(0,0,5.95),(5,.3,11.9),M['metal'],master,bev=.035); wm.hide_render=True; wm.hide_viewport=True
def inst(base,n,loc,rot=0):
 o=base.copy(); o.data=base.data; o.name=n; o.location=loc; o.rotation_euler[2]=rot; out.objects.link(o); return o
for n,loc,rot in [('wall_south', (0,-9.85,5.95),0),('wall_north',(0,9.85,5.95),0),('wall_west',(-7.35,0,5.95),math.pi/2)]: inst(wm,'wall_solid_'+n,loc,rot)
# door wall with opening east y=2.5
for n,loc,dim in [('door_wall_low',(7.35,-5.0,5.95),(.3,9.7,11.9)),('door_wall_high',(7.35,7.5,5.95),(.3,5,11.9)),('door_lintel',(7.35,2.5,10.55),(.3,4,2.7))]: cube(n,loc,dim,M['metal'],out,bev=.035)
# damaged rear wall: broken slab field
for i,(x,z,sx,sz,a) in enumerate([(-5.5,8,3.3,7,.18),(-2.4,7,3.0,6,-.15),(0.5,8.5,3.5,6.7,.12),(3.8,6.8,3.0,5.8,-.22),(6.0,8.3,2.0,6.5,.15)]): cube(f'wall_damage_panel_{i}',(x,9.55,z),(sx,.42,sz),M['matte'],out,(0,a,0),.12)
# fractured rubble field under the collapsed rear wall
for i,(x,y,z,sx,sy,sz,a) in enumerate([(-5.5,8.6,.45,2.2,.8,.35,.25),(-3.8,8.1,.8,1.5,.7,.5,-.18),(-1.8,8.7,.35,1.0,.6,.3,.4),(0.2,8.2,.65,1.8,.7,.4,-.3),(2.4,8.6,.3,1.2,.55,.25,.15),(4.8,8.0,.7,1.6,.65,.45,-.2)]):
 cube(f'wall_rubble_{i}',(x,y,z),(sx,sy,sz),M['metal'],out,rot=(a*.3,a,a),bev=.08)
for i,(x,z,a) in enumerate([(-4.4,4.5,.18),(-1.2,6.2,-.22),(2.0,5.4,.26),(4.6,6.0,-.16)]):
 cube(f'collapsed_beam_{i}',(x,8.9,z),(5.0,.28,.28),M['metal'],out,rot=(0,a,a),bev=.04)
# sofa continuous L-ish against left wall, seat and back components
sofa=cube('MASTER_sofa_segment',(0,0,0),(1,1,1),M['matte'],master,bev=.2); sofa.hide_render=True; sofa.hide_viewport=True
# sofa along west side x=-4.3, y -4..5
cube('sofa_base',(-4.0,0,1.0),(3.7,10.8,1.0),M['matte'],out,bev=.32)
for i,y in enumerate([-4.1,-2.7,-1.3,.1,1.5,2.9,4.3,5.7]): cube(f'sofa_cushion_{i}',(-4.0,y,1.75),(3.9,1.4,1.25),M['matte'],out,bev=.42)
cube('sofa_back',(-5.45,.8,2.8),(1.0,9.8,2.5),M['matte'],out,bev=.35)
cube('throw_blanket',(-2.15,2.6,2.1),(.12,2.0,1.7),M['varnish'],out,rot=(0,.1,.1),bev=.04)
# rug and floor insets
cube('rug_panel',(0,-.5,.21),(7.2,9,.08),M['varnish'],out,bev=.1)
for x,y in [(-6,-7.4),(-6,6.9),(5.8,-7.2),(5.8,6.6)]:
 cyl('plant_pot',(x,y,.55),.42,1.1,M['metal'],out)
 for j in range(5): cube('plant_leaf',(x+(j-2)*.12,y,.95+j*.25),(.12,.55,1.15),M['matte'],out,rot=(0,(j-2)*.16,0),bev=.04)
# display tubes rear corners
for i,x in enumerate([-5.8,5.5]):
 cyl(f'display_tube_{i}',(x,7.2,2.7),.72,5.0,M['varnish'],out); cyl(f'display_tube_glow_{i}',(x,7.2,2.7),.52,4.5,M['emit'],out)
# debris trays foreground
for i,x in enumerate([-4.8,3.8]):
 cube(f'debris_tray_{i}',(x,-8.35,.55),(3.5,2.2,1.0),M['metal'],out,bev=.08)
 for j in range(5): cube(f'tray_rail_{i}_{j}',(x-1.4+j*.7,-8.35,1.12),(.12,2.3,.12),M['varnish'],out)
# table fallen screen
cyl('side_table',(-1.0,-7.2,.55),.55,1.1,M['metal'],out); cube('fallen_screen',(4.2,3.0,.7),(2.4,1.5,.22),M['varnish'],out,rot=(.2,.1,.25),bev=.05); cube('fallen_screen_glow',(4.2,3.0,.83),(1.8,.05,.12),M['emit'],out,rot=(.2,.1,.25))
# lights and beams
for i,(loc,dim,rot) in enumerate([((-7.14,-5,6.5),(.08,7,.16),0),((-7.14,5,6.5),(.08,5,.16),0),((0,-9.65,7),(7,.08,.16),0),((0,9.65,7),(7,.08,.16),0)]): cube(f'wall_light_strip_{i}',loc,dim,M['emit'],out,rot=(0,0,rot),bev=.03)
for x in [-5,0,5]: cube('ceiling_beam',(x,0,11.65),(.3,19,.35),M['metal'],out,bev=.05)
# debris pieces and cables
for i,(x,y,s,a) in enumerate([(-6,-6,.5,.2),(-5,-2,.35,-.3),(-3,4,.4,.5),(1,-6,.45,.1),(3,-4,.32,-.5),(5,-1,.5,.4),(-1,6,.3,-.2),(2,6,.4,.3)]): cube(f'debris_piece_{i}',(x,y,.3),(s*2,s,.08),M['matte'],out,rot=(0,0,a),bev=.02)
for i,(x,y) in enumerate([(-2,-5),(0,-4),(2,-6),(4,-5),(-2,5)]):
 o=cube(f'cable_pipe_{i}',(x,y,.2),(2.4,.09,.09),M['varnish'],out,rot=(0,0,(i%3-1)*.35),bev=.04)
# camera/render
bpy.ops.object.camera_add(location=(1.5,-11.5,8.5)); cam=bpy.context.object; cam.name='CAMERA_REFERENCE_45_DEG'; cam.rotation_euler=(Vector((0,1.5,3.2))-cam.location).to_track_quat('-Z','Y').to_euler(); cam.data.lens=48; C['90_展示与验收_灯光相机'].objects.link(cam); bpy.context.scene.camera=cam
for o in list(cam.users_collection):
 if o!=C['90_展示与验收_灯光相机']: o.objects.unlink(cam)
for typ,loc,energy,size,color in [('AREA',(0,-2,10),1800,10,(1,.8,.7)),('AREA',(-8,0,6),900,8,(.25,.45,1))]:
 bpy.ops.object.light_add(type=typ,location=loc); l=bpy.context.object; l.name='SHOW_'+typ; l.data.energy=energy; l.data.shape='DISK'; l.data.size=size; l.data.color=color; l.rotation_euler=(Vector((0,0,1))-l.location).to_track_quat('-Z','Y').to_euler(); C['90_展示与验收_灯光相机'].objects.link(l)
scene=bpy.context.scene; scene.render.engine='BLENDER_EEVEE_NEXT'; scene.render.resolution_x=1000; scene.render.resolution_y=800; scene.render.resolution_percentage=100; scene.world.color=(.035,.04,.06); scene.render.filepath=os.path.join(OUT,'master_office_45deg.png'); scene['room_type']='MASTER_OFFICE'; scene['room_dimensions_m']=[15,20,11.9]; scene['whitebox_source']=r'art_source/design/whitebox/tower_zones/battle_level01/v004/data/floors/floor_98.json'; scene['reference_image']=r'C:/Users/zhuangmenghong/.workbuddy/clipboard-images/clipboard-2026-10-08T16-56-51-718Z-8ee4db79.jpg'; scene['component_plan']='component_plan.json'; scene['palette_path']=pal
bpy.ops.wm.save_as_mainfile(filepath=BLEND); bpy.ops.render.render(write_still=True)
# metadata
with open(os.path.join(OUT,'asset_manifest.json'),'w',encoding='utf-8') as f: json.dump({'schema':'shellstorm2.battle.room_type_source','schema_version':1,'asset_id':'ENV-BATTLE-MASTER-OFFICE-ROOM-TYPE','asset_version':'v003','room_type':'MASTER_OFFICE','display_name_zh':'父亲的办公室','block_id':'battle','level_id':'battle_level01','dimensions_m':[15,20,11.9],'whitebox_source':scene['whitebox_source'],'reference_image':scene['reference_image'],'component_plan':'component_plan.json','palette_path':pal,'collections':['01_制作组件_按设施拆分','02_游戏输出_独立资产包_v003','90_展示与验收_灯光相机'],'room_owned_geometry':False},f,ensure_ascii=False,indent=2)
print(json.dumps({'status':'ok','blend':BLEND,'objects':len(bpy.data.objects),'meshes':len([o for o in bpy.data.objects if o.type=='MESH']),'render':scene.render.filepath},ensure_ascii=False))
