import bpy,math,json,hashlib
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/rig_v006';P.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v005.blend'))
s=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];bpy.context.window.scene=s
rig=bpy.data.objects['Boss002_Rig'];arm=rig.data;ctrl=bpy.data.objects['ExpressionController']
support=[(0,-.08,.18),(0,-.52,.65),(0,-.55,1.32),(0,-.52,2.02)]
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='EDIT')
for i in range(3):
 b=arm.edit_bones['support_%02d'%(i+1)];b.head=support[i];b.tail=support[i+1]
b=arm.edit_bones.new('rear_axle');b.head=support[-1];b.tail=(0,-.52,2.35);b.parent=arm.edit_bones['support_03']
b=arm.edit_bones['monitor_tilt'];b.head=support[-1];b.tail=(0,-.52,2.39);b.parent=arm.edit_bones['rear_axle']
b=arm.edit_bones['monitor_spin'];b.head=support[-1];b.tail=(0,-.12,2.02)
for sign,side in [(1,'L'),(-1,'R')]:
 arm.edit_bones.remove(arm.edit_bones['spring.'+side])
 for i in range(6):
  b=arm.edit_bones.new('arm_%02d.%s'%(i+1,side));b.head=(sign*(.91+1.32*i/6),-.08,2.01);b.tail=(sign*(.91+1.32*(i+1)/6),-.08,2.01);b.parent=arm.edit_bones['rear_axle' if i==0 else 'arm_%02d.%s'%(i,side)];b.use_connect=i>0
 arm.edit_bones['hand_ctrl.'+side].parent=arm.edit_bones['arm_06.'+side]
bpy.ops.object.mode_set(mode='OBJECT')
for b in arm.bones:b.inherit_scale='NONE';b.bbone_x=.028;b.bbone_z=.028
for pb in rig.pose.bones:pb.rotation_mode='XYZ'
for side in ['L','R']:
 rig['stretch_'+side]=1.0;rig.id_properties_ui('stretch_'+side).update(min=.45,max=2.5,description='Arm axial spring length; FK joints control bending')
 for i in range(6):
  pb=rig.pose.bones['arm_%02d.%s'%(i+1,side)];pb.rotation_mode='XYZ';f=pb.driver_add('scale',1);v=f.driver.variables.new();v.name='stretch';v.targets[0].id=rig;v.targets[0].data_path='["stretch_'+side+'"]';f.driver.expression='stretch'
def bind(o,weights):
 o.vertex_groups.clear();groups={}
 for idx,ws in enumerate(weights):
  for name,w in ws.items():
   if w>1e-8:
    if name not in groups:groups[name]=o.vertex_groups.new(name=name)
    groups[name].add([idx],w/sum(ws.values()),'REPLACE')
 if not any(m.type=='ARMATURE' for m in o.modifiers):m=o.modifiers.new('Boss002 skin','ARMATURE');m.object=rig
def rigid(o,n):bind(o,[{n:1} for v in o.data.vertices])
def blend(t,n,fmt):
 t=max(0,min(n-1,t));i=int(t);f=t-i
 return {fmt%(i+1):1-f,fmt%(i+2):f} if i<n-1 else {fmt%n:1}
o=bpy.data.objects['Stand column'];me=o.data
for j in range(22):
 t=j/21*3;i=min(2,int(t));p=Vector(support[i]).lerp(Vector(support[i+1]),min(1,t-i));axis=(Vector(support[i+1])-Vector(support[i])).normalized();u=Vector((1,0,0));v=axis.cross(u).normalized()
 for k in range(12):me.vertices[j*12+k].co=p+.095*(u*math.cos(2*math.pi*k/12)+v*math.sin(2*math.pi*k/12))
bind(o,[blend((i//12)/21*3-.5,3,'support_%02d') for i in range(len(me.vertices))]);me.update()
for n in ['Portrait rotation hinge','Hinge cap']:
 o=bpy.data.objects[n];o.location.z+=1.14;o.location.y-=.18;rigid(o,'rear_axle')
for o in list(s.objects):
 if o.type!='MESH':continue
 if o.name.startswith('Continuous spring'):
  sign=1 if sum((o.matrix_world@v.co).x for v in o.data.vertices)>0 else -1;side='L' if sign==1 else 'R'
  bind(o,[blend((sign*(o.matrix_world@v.co).x-.91)/1.32*6-.5,6,'arm_%02d.'+side) for v in o.data.vertices])
 elif o.name.startswith(('Rear arm grommet','Behind monitor cable')):rigid(o,'rear_axle')
# A transverse axle housing joins both rear arm roots to the central pivot.
bpy.ops.mesh.primitive_cube_add(size=1,location=(0,-.43,2.01));o=bpy.context.object;o.name='Rear axle crossbar';o.scale=(1.40,.18,.17);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
for c in list(o.users_collection):c.objects.unlink(o)
bpy.data.collections['03_ARMS_default'].objects.link(o);o.data.materials.append(bpy.data.objects['Portrait rotation hinge'].data.materials[0]);rigid(o,'rear_axle')
# Shared palette: per-polygon UVs select the old material's solid base color.
body=bpy.data.materials.new('BOSS002_01_BodyPalette');body.use_nodes=True;nt=body.node_tree;bs=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Roughness'].default_value=.46;bs.inputs['Metallic'].default_value=.18
colors=[];indices={};objects=[o for o in bpy.data.objects if o.type=='MESH' and not o.name.startswith('Texture ') and o.name!='Screen code texture']
for o in objects:
 for mat in o.data.materials:
  if not mat or mat.name in indices:continue
  n=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None) if mat.use_nodes else None
  color=tuple(n.inputs['Base Color'].default_value) if n else tuple(mat.diffuse_color)
  if color not in colors:colors.append(color)
  indices[mat.name]=colors.index(color)
assert len(colors)<=64,len(colors)
T=B/'source/textures_v006';T.mkdir(exist_ok=True);size=256;grid=8
im=bpy.data.images.new('Boss002 body palette',width=size,height=size);im.colorspace_settings.name='Non-Color'
pixels=[]
for y in range(size):
 for x in range(size):pixels.extend(colors[min(len(colors)-1,(y//32)*grid+x//32)])
im.pixels.foreach_set(pixels);im.filepath_raw=str(T/'body_palette.png');im.file_format='PNG';im.save();im.pack();tex=nt.nodes.new('ShaderNodeTexImage');tex.image=im;tex.interpolation='Closest';nt.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
for o in objects:
 old=list(o.data.materials);uv=o.data.uv_layers.active or o.data.uv_layers.new(name='PaletteUV')
 for p in o.data.polygons:
  idx=indices.get(old[p.material_index].name,0) if old else 0;u=(idx%8+.5)/8;v=(idx//8+.5)/8
  for j,li in enumerate(p.loop_indices):uv.data[li].uv=(u+(.025 if j%2 else -.025),v+(.025 if j//2%2 else -.025))
  p.material_index=0
 o.data.materials.clear();o.data.materials.append(body)
(T/'body_palette.json').write_text(json.dumps({'colors_linear':colors,'material_swatches':indices,'grid':[8,8]},indent=2))
# One expression shader; a mesh attribute identifies eye/mouth UV registration.
face=bpy.data.materials.new('BOSS002_02_ExpressionAtlas');face.use_nodes=True;face.surface_render_method='DITHERED';nt=face.node_tree;nt.nodes.clear();ns=nt.nodes;ls=nt.links
uv=ns.new('ShaderNodeTexCoord');attr=ns.new('ShaderNodeAttribute');attr.attribute_name='expression_slot_id'
boxes=json.loads((B/'source/expression_library_v004.json').read_text())['per_expression_slot_boxes_pixels'];last=None
def driver(socket,vals):
 f=socket.driver_add('default_value');v=f.driver.variables.new();v.name='e';v.targets[0].id=ctrl;v.targets[0].data_path='["expression_index"]';f.driver.expression=str(tuple(vals))+'[min(5,max(0,int(e)))]'
for slot,name in enumerate(['large_eye','round_eye','mouth']):
 o=bpy.data.objects['Texture '+name];o.data.materials.clear();o.data.materials.append(face);a=o.data.attributes.new('expression_slot_id','FLOAT','POINT')
 for d in a.data:d.value=slot
 b=boxes[name];scale=ns.new('ShaderNodeCombineXYZ');off=ns.new('ShaderNodeCombineXYZ')
 driver(scale.inputs[0],[(q[2]-q[0])/1536 for q in b]);driver(scale.inputs[1],[(q[3]-q[1])/1024 for q in b]);driver(off.inputs[0],[q[0]/1536 for q in b]);driver(off.inputs[1],[1-q[3]/1024 for q in b])
 mul=ns.new('ShaderNodeVectorMath');mul.operation='MULTIPLY';ls.new(uv.outputs['UV'],mul.inputs[0]);ls.new(scale.outputs[0],mul.inputs[1]);add=ns.new('ShaderNodeVectorMath');add.operation='ADD';ls.new(mul.outputs[0],add.inputs[0]);ls.new(off.outputs[0],add.inputs[1])
 eq=ns.new('ShaderNodeMath');eq.operation='COMPARE';eq.inputs[1].default_value=slot;eq.inputs[2].default_value=.1;ls.new(attr.outputs['Fac'],eq.inputs[0]);weighted=ns.new('ShaderNodeVectorMath');weighted.operation='SCALE';ls.new(add.outputs[0],weighted.inputs[0]);ls.new(eq.outputs[0],weighted.inputs[3])
 if last:
  acc=ns.new('ShaderNodeVectorMath');acc.operation='ADD';ls.new(last,acc.inputs[0]);ls.new(weighted.outputs[0],acc.inputs[1]);last=acc.outputs[0]
 else:last=weighted.outputs[0]
tex=ns.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(B/'source/textures_v004/expressions_atlas.png'),check_existing=True);tex.image.pack();tex.extension='CLIP';ls.new(last,tex.inputs[0]);em=ns.new('ShaderNodeEmission');em.inputs[1].default_value=.85;ls.new(tex.outputs['Color'],em.inputs[0]);tr=ns.new('ShaderNodeBsdfTransparent');mix=ns.new('ShaderNodeMixShader');alpha=ns.new('ShaderNodeMath');alpha.operation='GREATER_THAN';alpha.inputs[1].default_value=.65;ls.new(tex.outputs['Alpha'],alpha.inputs[0]);ls.new(alpha.outputs[0],mix.inputs[0]);ls.new(tr.outputs[0],mix.inputs[1]);ls.new(em.outputs[0],mix.inputs[2]);out=ns.new('ShaderNodeOutputMaterial');ls.new(mix.outputs[0],out.inputs[0])
# Negative sampling offset makes the visible terminal text travel upward.
screen=bpy.data.objects['Screen code texture'].data.materials[0];screen.name='BOSS002_03_ScrollingCode';nt=screen.node_tree;ns=nt.nodes;ls=nt.links;tex=next(n for n in ns if n.type=='TEX_IMAGE');tex.extension='REPEAT';uv=ns.new('ShaderNodeTexCoord');off=ns.new('ShaderNodeCombineXYZ');off.name='Code scroll offset';add=ns.new('ShaderNodeVectorMath');add.operation='ADD';ls.new(uv.outputs['UV'],add.inputs[0]);ls.new(off.outputs[0],add.inputs[1]);ls.new(add.outputs[0],tex.inputs[0])
rig['code_scroll']=0.0;rig.id_properties_ui('code_scroll').update(description='Positive value moves visible code upward; animate linearly. 1 = one texture height')
f=off.inputs[1].driver_add('default_value');v=f.driver.variables.new();v.name='scroll';v.targets[0].id=rig;v.targets[0].data_path='["code_scroll"]';f.driver.expression='-scroll'
for m in list(bpy.data.materials):
 if m not in [body,face,screen]:bpy.data.materials.remove(m)
rig['skeleton_id']='SKEL-MONITOR002-002';arm.name=rig['skeleton_id'];rig['controls']='rear_axle: shared rear pivot; monitor_spin local Y: independent screen roll; arm_01..06.L/R: FK bend; stretch_L/R: spring length; support_01..03: stand bend; code_scroll: upward UV motion'
s['asset_version']='v006';s['skeleton_id']=rig['skeleton_id'];bpy.context.view_layer.update()
tri=0
for o in s.objects:
 if o.type=='MESH':o.data.calc_loop_triangles();tri+=len(o.data.loop_triangles)
assert tri<20000
sig=hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,list(b.head_local),list(b.tail_local),b.use_deform) for b in arm.bones],sort_keys=True).encode()).hexdigest()
contract={'asset_id':'ENM-BOSS-MONITOR002-3D','version':'v006','skeleton_id':rig['skeleton_id'],'skeleton_signature':sig,'bone_count':len(arm.bones),'triangles':tri,'materials':[m.name for m in [body,face,screen]],'pivot':support[-1],'arm_segments_per_side':6,'runtime_integration':False,'expression_states':dict(zip(['default','suspicious','angry','sleepy','taunting','glitched'],range(6))),'controls':rig['controls'],'export_note':'Bake bone drivers/constraints for GLB. Shared expression attribute and scrolling UV require runtime shader adapter; not yet integrated.'}
(B/'source/rig_contract_v006.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v006.blend'))
rig.animation_data_create()
tests={'QA_arm_bend':[('arm_02.L',(0,0,.45)),('arm_04.L',(0,0,.45)),('arm_03.R',(.4,0,0))],'QA_monitor_spin':[('monitor_spin',(0,1.1,0))],'QA_forward_slam':[('support_01',(-.35,0,0)),('support_02',(-.4,0,0)),('monitor_tilt',(-.4,0,0))]}
for name,channels in tests.items():
 act=bpy.data.actions.new(name);act.use_fake_user=True;rig.animation_data.action=act
 for bn,value in channels:
  pb=rig.pose.bones[bn]
  for frame,val in [(1,(0,0,0)),(36,value),(72,(0,0,0))]:pb.rotation_euler=val;pb.keyframe_insert('rotation_euler',frame=frame)
for name,prop,val in [('QA_spring_extend','stretch_L',1.7),('QA_code_scroll','code_scroll',1.0)]:
 act=bpy.data.actions.new(name);act.use_fake_user=True;rig.animation_data.action=act
 for frame,value in [(1,1.0 if prop.startswith('stretch') else 0.0),(72,val)]:rig[prop]=value;rig.keyframe_insert(data_path='["'+prop+'"]',frame=frame)
 rig[prop]=1.0 if prop.startswith('stretch') else 0.0
rig.animation_data.action=None;s.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v006.blend'))
print('V006_BUILT',json.dumps(contract))


