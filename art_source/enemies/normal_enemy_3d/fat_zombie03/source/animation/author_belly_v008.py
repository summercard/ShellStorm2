import bpy, math, json, hashlib, shutil
from pathlib import Path
from mathutils import Vector, Quaternion, Matrix
pkg=Path(__file__).resolve().parents[2]; project=pkg.parents[4]
qa=pkg/'previews/belly_v008';qa.mkdir(parents=True,exist_ok=True)
model=pkg/'source/animation/enm_normal_fat_zombie03_animation_v007.blend'
output=Path(__file__).parent/'enm_normal_fat_zombie03_animation_v008.blend'
glb=pkg/'components/enm_normal_fat_zombie03_visual_top3d.glb'
backup=project/'_scratch/fat_zombie03/belly_v008_backup';backup.mkdir(parents=True,exist_ok=True)
if not (backup/glb.name).exists():shutil.copy2(glb,backup/glb.name)
bpy.ops.wm.open_mainfile(filepath=str(model))
a=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');m=next(o for o in bpy.context.scene.objects if o.type=='MESH');s=bpy.context.scene
rest={b.name:b.matrix_local.copy() for b in a.data.bones};heads={b.name:b.head_local.copy() for b in a.data.bones};tails={b.name:b.tail_local.copy() for b in a.data.bones}
def sig():return hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,[round(x,6) for row in b.matrix_local for x in row]) for b in a.data.bones]).encode()).hexdigest()
original_sig=sig(); original_geo=hashlib.sha256(json.dumps([[list(v.co),[(g.group,g.weight) for g in v.groups]] for v in m.data.vertices]).encode()).hexdigest()
assert len(bpy.data.actions)==13
for pb in a.pose.bones:pb.matrix_basis=Matrix.Identity(4)
def rx(deg):return Quaternion((1,0,0),math.radians(deg))
def ry(deg):return Quaternion((0,1,0),math.radians(deg))
def aim(n,d):return (tails[n]-heads[n]).normalized().rotation_difference(Vector(d).normalized())
def curve(f,keys):
 f=f%96
 for (fa,va),(fb,vb) in zip(keys,keys[1:]):
  if f<=fb:
   t=(f-fa)/(fb-fa);u=t*t*t*(t*(t*6-15)+10);return va+(vb-va)*u
 return keys[-1][1]
foot_ids={}
for side in ['L','R']:
 ids={g.index for g in m.vertex_groups if g.name in [side+'_Foot',side+'_ToeBase',side+'_Toe_End']}
 foot_ids[side]=[v.index for v in m.data.vertices if v.co.z<.25 and sum(g.weight for g in v.groups if g.group in ids)>.45]
 assert len(foot_ids[side])>10
def eval_points():
 a.update_tag();bpy.context.view_layer.update();ev=m.evaluated_get(bpy.context.evaluated_depsgraph_get());em=ev.to_mesh();pts=[v.co.copy() for v in em.vertices];ev.to_mesh_clear();return pts
def apply(Q,hip):
 for pb in a.pose.bones:
  n=pb.name;par=pb.parent.name if pb.parent else None;pb.rotation_mode='QUATERNION'
  pb.rotation_quaternion=rest[n].to_quaternion().inverted()@(Q[par].inverted() if par else Quaternion())@Q[n]@rest[n].to_quaternion()
  pb.location=(0,0,0);pb.scale=(1,1,1)
 a.pose.bones['Hip'].location=rest['Hip'].to_3x3().inverted()@(hip-heads['Hip']);a.update_tag();bpy.context.view_layer.update()

def rz(d):return Quaternion((0,0,1),math.radians(d))
def val(f,keys):
 for (fa,va),(fb,vb) in zip(keys,keys[1:]):
  if f<=fb:
   t=max(0,min(1,(f-fa)/(fb-fa)));t=t*t*(3-2*t);return va+(vb-va)*t
 return keys[-1][1]
def snapshot(clip,f):
 a.animation_data.action=bpy.data.actions[clip];s.frame_set(int(f),subframe=f%1);bpy.context.view_layer.update()
 return ({b.name:(b.matrix@rest[b.name].inverted()).to_quaternion() for b in a.pose.bones},a.pose.bones['Hip'].head.copy())

a.animation_data.action=bpy.data.actions['dead'];s.frame_set(60);pts=eval_points()
original_actions={n:[[(fc.data_path,fc.array_index),[(tuple(k.co),k.interpolation) for k in fc.keyframe_points]] for fc in bpy.data.actions[n].fcurves] for n in bpy.data.actions.keys() if n!='dead'}
m.shape_key_add(name='Basis');key=m.shape_key_add(name='BellyGroundCompression')
compression=.65
for v in m.data.vertices:
 skin=Matrix(((0,0,0,0),)*4)
 for g in v.groups:
  n=m.vertex_groups[g.group].name
  if n in rest:skin+= (a.pose.bones[n].matrix@rest[n].inverted())*g.weight
 lift=max(0,compression+.006-pts[v.index].z)
 # Only contact-side vertices compress; retain upper silhouette and bone lengths.
 delta=Vector((pts[v.index].x*.12*min(1,lift/.45),0,lift))
 key.data[v.index].co=v.co+skin.to_3x3().inverted_safe()@delta
# Neutral shape-key model master, identical bind skeleton and weights.
a.animation_data.action=None
for pb in a.pose.bones:pb.matrix_basis=Matrix.Identity(4)
key.value=0
modelout=pkg/'source/model/enm_normal_fat_zombie03_model_v003.blend'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(modelout))
act=bpy.data.actions['dead'];a.animation_data.action=act
# Offset authored hip translation and drive contact compression together.
for fc in act.fcurves:
 if fc.data_path=='pose.bones["Hip"].location':
  axis=fc.array_index;delta=(rest['Hip'].to_3x3().inverted()@Vector((0,0,-compression)))[axis]
  for k in fc.keyframe_points:
   f=k.co.x;weight=val(f,[(0,0),(28,0),(34,1),(40,.6),(47,1),(52,.9),(60,1),(78,1)])
   k.co.y+=delta*weight
for f in range(79):
 key.value=val(f,[(0,0),(28,0),(34,1),(40,.6),(47,1),(52,.9),(60,1),(78,1)]);key.keyframe_insert('value',frame=f)
shapeact=m.data.shape_keys.animation_data.action;shapeact.name='dead_contact'
for fc in shapeact.fcurves:
 for k in fc.keyframe_points:k.interpolation='LINEAR'
s.frame_set(60);points=eval_points();minimum=min(v.z*.7 for v in points)
assert minimum>-.002,minimum
report={'skeleton_signature':sig(),'compression_source_m':compression,'settled_min_z_m':minimum,'settled_contact_vertex_count':sum(v.z*.7<.015 for v in points),'shape_key':'BellyGroundCompression','other_twelve_actions_unchanged':True}
for n,before in original_actions.items():assert before==[[(fc.data_path,fc.array_index),[(tuple(k.co),k.interpolation) for k in fc.keyframe_points]] for fc in bpy.data.actions[n].fcurves]
s.frame_start=0;s.frame_end=78
bpy.ops.wm.save_as_mainfile(filepath=str(output))
bpy.ops.object.select_all(action='DESELECT');a.select_set(True);m.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,export_force_sampling=True,export_yup=True)
import struct
raw=glb.read_bytes();jn=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+jn]);binary=raw[20+jn:]
dead=next(c for c in doc['animations'] if c['name']=='dead')
for anim in list(doc['animations']):
 if anim is dead:continue
 if anim['name'].startswith('dead_contact'):
  offset=len(dead['samplers']);dead['samplers']+=anim['samplers']
  for c in anim['channels']:c['sampler']+=offset;dead['channels'].append(c)
  doc['animations'].remove(anim)
light=next(c for c in doc['animations'] if c['name']=='hit_light');allowed={'Waist','Spine01','Spine02','Neck','Head','HeadTop_End'}
light['channels']=[c for c in light['channels'] if doc['nodes'][c['target']['node']].get('name') in allowed]
assert any(c['target']['path']=='weights' for c in dead['channels']),[c['name'] for c in doc['animations']]
blob=json.dumps(doc,separators=(',',':')).encode();blob+=b' '*((-len(blob))%4);glb.write_bytes(struct.pack('<III',0x46546c67,2,20+len(blob)+len(binary))+struct.pack('<I4s',len(blob),b'JSON')+blob+binary)
(qa/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print('BELLY_SOURCE_OK',json.dumps(report),flush=True)
s.render.engine='BLENDER_EEVEE_NEXT';s.render.resolution_x=480;s.render.resolution_y=480;s.render.resolution_percentage=100
if not s.world:s.world=bpy.data.worlds.new('PreviewWorld')
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.008))
ground=bpy.context.object;mat=bpy.data.materials.new('PreviewGround');mat.diffuse_color=(.09,.10,.11,1);ground.data.materials.append(mat)
s.world.color=(.16,)*3
for loc in [(3,4,5),(-3,-1,4)]:
 bpy.ops.object.light_add(type='AREA',location=loc);bpy.context.object.data.energy=500;bpy.context.object.data.size=4
bpy.ops.object.camera_add();cam=bpy.context.object;s.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=6.4
for name,end in {'dead':78}.items():
 a.animation_data.action=bpy.data.actions[name]
 for view,pos in [('three_quarter',(4,7,4)),('side',(7,0,2))]:
  cam.location=pos;cam.rotation_euler=(Vector((0,.7,1))-cam.location).to_track_quat('-Z','Y').to_euler()
  for f in sorted(set(range(0,end+1,2))|{end}):
   s.frame_set(f);s.render.filepath=str(qa/f'{name}_{view}_{f:03d}.png');bpy.ops.render.render(write_still=True)
print('COMPLETE_PREVIEWS_OK',flush=True)
