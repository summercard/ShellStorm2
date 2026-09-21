import bpy, math, json, hashlib
from pathlib import Path
from mathutils import Vector, Quaternion
P = Path('I:/工作项目/shellstrom2/outputs/zombie_walk_reference')
bpy.ops.wm.open_mainfile(filepath=str(P/'before_animation.blend'))
a=bpy.data.objects['enm_security_zombie_armature']; m=bpy.data.objects['enm_security_zombie_mesh']; s=bpy.context.scene
s.name='01_Walk_InPlace'; s.render.fps=24; s.frame_start=1; s.frame_end=120
rest={b.name:b.matrix_local.copy() for b in a.data.bones}
heads={b.name:b.head_local.copy() for b in a.data.bones}; tails={b.name:b.tail_local.copy() for b in a.data.bones}
def sig():return hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else '',[round(x,7) for row in b.matrix_local for x in row]) for b in a.data.bones]).encode()).hexdigest()
def geometry_sig():return hashlib.sha256(json.dumps({'v':[list(v.co) for v in m.data.vertices],'polys':[list(p.vertices) for p in m.data.polygons],'weights':[[(g.group,g.weight) for g in v.groups] for v in m.data.vertices]}).encode()).hexdigest()
original_sig=sig(); original_geo=geometry_sig()
for pb in a.pose.bones:pb.matrix_basis.identity()
a.animation_data_clear(); a.animation_data_create()
act=bpy.data.actions.new('Zombie_Walk_Reference_24fps_v001'); act.use_fake_user=True; a.animation_data.action=act
foot_indices={}
for side in ['L','R']:
 gi={g.index for g in m.vertex_groups if g.name in [side+'_Foot',side+'_ToeBase',side+'_Toe_End']}
 foot_indices[side]=[v.index for v in m.data.vertices if v.co.z<.22 and sum(g.weight for g in v.groups if g.group in gi)>.45]
 assert len(foot_indices[side])>10,(side,len(foot_indices[side]))
def rx(v):return Quaternion((1,0,0),math.radians(v))
def ry(v):return Quaternion((0,1,0),math.radians(v))
def rz(v):return Quaternion((0,0,1),math.radians(v))
def aim(n,d):return (tails[n]-heads[n]).normalized().rotation_difference(Vector(d).normalized())
def track(t,keys):
 for (ta,va),(tb,vb) in zip(keys,keys[1:]):
  if t<=tb:
   u=max(0,min(1,(t-ta)/(tb-ta)));return va+(vb-va)*u
 return keys[-1][1]
def apply(Q,hip):
 for pb in a.pose.bones:
  n=pb.name; par=pb.parent.name if pb.parent else None
  pb.rotation_mode='QUATERNION'; pb.rotation_quaternion=rest[n].to_quaternion().inverted()@(Q[par].inverted() if par else Quaternion())@Q[n]@rest[n].to_quaternion();pb.location=(0,0,0);pb.scale=(1,1,1)
 a.pose.bones['Hip'].location=rest['Hip'].to_3x3().inverted()@(hip-heads['Hip']);bpy.context.view_layer.update()
def lows():
 ev=m.evaluated_get(bpy.context.evaluated_depsgraph_get()); me=ev.to_mesh()
 result={side:min((m.matrix_world@me.vertices[i].co).z for i in ids) for side,ids in foot_indices.items()};ev.to_mesh_clear();return result
ik_errors=[]
def legs(Q,hip,targets,pitch):
 apply(Q,hip)
 for side in ['L','R']:
  n=side+'_Thigh'; k=side+'_Calf'; h=a.pose.bones[n].head.copy();delta=targets[side]-h
  l1=(tails[n]-heads[n]).length;l2=(tails[k]-heads[k]).length;d=min(max(delta.length,abs(l1-l2)+.00001),l1+l2-.00001)
  axis=delta.normalized();pole=Vector((0,1,0));pole=(pole-axis*pole.dot(axis)).normalized();along=(l1*l1-l2*l2+d*d)/(2*d); knee=h+axis*along+pole*math.sqrt(max(0,l1*l1-along*along)); ankle=h+axis*d
  Q[n]=aim(n,knee-h);Q[k]=aim(k,ankle-knee);Q[side+'_Foot']=rx(pitch[side])
  for name in [side+'_ToeBase',side+'_Toe_End']:Q[name]=Q[side+'_Foot']
 apply(Q,hip)

def solve(f):
 # Reference front section: alternating shoe-forward peaks approximately every 12 frames.
 t=((f-1)/24+.10)%1;ph=2*math.pi*t
 Q={n:Quaternion() for n in rest};hip=heads['Hip'].copy();hip.z-=.039+.007*math.cos(2*ph);hip.x+=.013*math.sin(ph)
 Q['Hip']=ry(1.2*math.sin(ph))@rz(1.6*math.sin(ph));Q['Waist']=rx(-3)@ry(1.8*math.sin(ph));Q['Spine01']=rx(-4)@ry(2.4*math.sin(ph));Q['Spine02']=rx(-5)@ry(3*math.sin(ph))@rz(-2.3*math.sin(ph))
 Q['Neck']=rx(-2)@ry(1.5*math.sin(ph));Q['Head']=rx(-1+.8*math.sin(ph-.3))@ry(1.4*math.sin(ph-.25));Q['HeadTop_End']=Q['Head']
 for side,sgn,off in [('L',-1,0),('R',1,.5)]:
  u=(t+off)%1; swing=math.sin(2*math.pi*u)
  Q[side+'_Clavicle']=Q['Spine02']
  Q[side+'_Upperarm']=Q['Spine02']@aim(side+'_Upperarm',(sgn*.60,.72+.14*swing,-.27))
  Q[side+'_Forearm']=Q['Spine02']@aim(side+'_Forearm',(sgn*.27,.91+.16*swing,-.23))
  Q[side+'_Hand']=Q['Spine02']@aim(side+'_Hand',(sgn*.20,.94+.12*swing,-.35))
  for b in a.data.bones:
   if b.name.startswith(side+'_') and any(x in b.name for x in ['Thumb','Index','Middle','Ring','Pinky']):
    Q[b.name]=Q[side+'_Hand']
 targets={};pitch={};desired_low={};states={}
 for side,off in [('L',0),('R',.5)]:
  u=(t+off)%1; stance=.57
  target=heads[side+'_Foot'].copy()
  if u<stance:
   v=u/stance;target.y+=.075-.15*v
   pitch[side]=track(v,[(0,-9),(.16,0),(.80,0),(1,10)])
   desired_low[side]=.001;states[side]='stance'
  else:
   v=(u-stance)/(1-stance);target.y+=-.075+.15*(v*v*(3-2*v))
   desired_low[side]=.001+.039*math.sin(math.pi*v)**1.4
   target.z+=desired_low[side]-.001
   pitch[side]=track(v,[(0,10),(.28,16),(.65,-12),(1,-9)]);states[side]='swing'
  targets[side]=target
 for iteration in range(5):
  legs(Q,hip,targets,pitch)
  low=lows()
  for side in ['L','R']:targets[side].z+=desired_low[side]-low[side]
 legs(Q,hip,targets,pitch)
 return states
prev={};phases=[]
for f in range(1,122):
 states=solve(f);phases.append(states)
 for pb in a.pose.bones:
  if pb.name=='Root':continue
  q=pb.rotation_quaternion.copy();q.normalize()
  if pb.name in prev and q.dot(prev[pb.name])<0:q.negate()
  pb.rotation_quaternion=q;prev[pb.name]=q.copy();pb.keyframe_insert('rotation_quaternion',frame=f,group=pb.name)
  if pb.name=='Hip':pb.keyframe_insert('location',frame=f,group=pb.name)
act.use_frame_range=True;act.frame_start=1;act.frame_end=121;act.use_cyclic=True
for fc in act.fcurves:
 for kp in fc.keyframe_points:kp.interpolation='LINEAR'
 fc.modifiers.new('CYCLES')
act['reference']='User video, manually reconstructed; not measured 3D motion capture';act['cycle_frames']=24;act['duration_seconds']=5.0
# One self-contained preview scene, with view rotation isolated on the camera.
s.render.engine='BLENDER_EEVEE_NEXT';s.render.resolution_x=735;s.render.resolution_y=630;s.render.resolution_percentage=100
s.render.image_settings.file_format='PNG';s.world=bpy.data.worlds.new('WalkPreviewWorld');s.world.use_nodes=True
wn=s.world.node_tree.nodes; wn.clear(); bg=wn.new('ShaderNodeBackground'); bg.inputs[0].default_value=(.045,.045,.045,1); bg.inputs[1].default_value=.35; wo=wn.new('ShaderNodeOutputWorld'); s.world.node_tree.links.new(bg.outputs['Background'],wo.inputs['Surface'])
s.view_settings.view_transform='AgX'
col=bpy.data.collections.new('90_Preview_only');s.collection.children.link(col)
def add_obj(name,data,loc):
 o=bpy.data.objects.new(name,data);col.objects.link(o);o.location=loc;o['preview_only']=True;return o
gd=bpy.data.meshes.new('PreviewGround');gd.from_pydata([(-50,-50,-.002),(50,-50,-.002),(50,50,-.002),(-50,50,-.002)],[],[(0,1,2,3)])
g=add_obj('PreviewGround',gd,(0,0,0));mat=bpy.data.materials.new('PreviewGroundMaterial');mat.diffuse_color=(.022,.022,.022,1);mat.use_nodes=True;next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Base Color'].default_value=(.022,.022,.022,1);next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Roughness'].default_value=.85;g.data.materials.append(mat)
for name,loc,energy,size in [('Key',(-2,3,4),360,3),('Fill',(2,2,2.5),180,3),('Rim',(0,-3,3),380,2)]:
 d=bpy.data.lights.new('Preview'+name,'AREA');d.energy=energy;d.shape='DISK';d.size=size;o=add_obj('Preview'+name,d,loc);o.rotation_euler=(Vector((0,0,.9))-o.location).to_track_quat('-Z','Y').to_euler()
cam=add_obj('Reference_View',bpy.data.cameras.new('Reference_View'),(0,5,1.18));cam.data.type='ORTHO';cam.data.ortho_scale=2.35;s.camera=cam
for f,deg in [(1,0),(61,0),(67,-55),(73,-70),(87,-72),(95,180),(121,180)]: 
 rad=math.radians(deg);cam.location=(5*math.sin(rad),5*math.cos(rad),1.18);cam.rotation_euler=(Vector((0,0,.91))-cam.location).to_track_quat('-Z','Y').to_euler();cam.keyframe_insert('location',frame=f);cam.keyframe_insert('rotation_euler',frame=f)
# Camera Euler unwrap prevents a long spin at back view.
for fc in cam.animation_data.action.fcurves:
 for kp in fc.keyframe_points:kp.interpolation='LINEAR'
# Full body evaluated checks at quarter-frame resolution.
checks=[];first=None;seam=0;min_ground=1;max_contact=0;air=0;scaleerr=0;rooterr=0
for i in range(481):
 f=1+i/4;s.frame_set(int(f),subframe=f%1);bpy.context.view_layer.update();low=lows();min_ground=min(min_ground,min(low.values()));max_contact=max(max_contact,min(low.values()));air+=int(min(low.values())>.003)
 scaleerr=max(scaleerr,max(max(abs(v-1) for v in pb.scale) for pb in a.pose.bones));rooterr=max(rooterr,max(abs(a.pose.bones['Root'].matrix_basis[r][c]-(1 if r==c else 0)) for r in range(4) for c in range(4)))
 if i==0:first={pb.name:pb.matrix.copy() for pb in a.pose.bones}
 if i==480:seam=max(abs(pb.matrix[r][c]-first[pb.name][r][c]) for pb in a.pose.bones for r in range(4) for c in range(4))
 if i%4==0:checks.append({'frame':f,'foot_min_z':low,'hip':list(a.pose.bones['Hip'].head)})
report={'status':'pending_visual_review','source':str(P/'before_animation.blend'),'skeleton_unchanged':sig()==original_sig,'mesh_weights_unchanged':geometry_sig()==original_geo,'bone_count':len(a.data.bones),'sample_count':481,'loop_matrix_error':seam,'root_matrix_error':rooterr,'scale_error':scaleerr,'min_ground_m':min_ground,'max_lowest_foot_m':max_contact,'airborne_samples':air,'foot_vertex_samples':{k:len(v) for k,v in foot_indices.items()},'samples':checks,'limitations':['Manual interpretation of monocular AI-generated video; not exact 3D motion capture','Camera follows front/side/back presentation separately from in-place action']}
(P/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
s.frame_set(1)
a.select_set(True);m.select_set(False);bpy.context.view_layer.objects.active=a
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.shading.type='MATERIAL'
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(P/'zombie_reference_walk_v001.blend'))
print('AUTHOR_OK',json.dumps({k:v for k,v in report.items() if k!='samples'}))
for f in [1,7,13,19,67,79,97,109]:
 s.frame_set(f);s.render.filepath=str(P/('pose_%03d.png'%f));bpy.ops.render.render(write_still=True)
