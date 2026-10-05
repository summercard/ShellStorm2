import bpy,math,json,hashlib
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
R=Path.cwd();B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/cable_v024';P.mkdir(exist_ok=True)
def signatures():
 return {a.name:hashlib.sha256(repr([(f.data_path,f.array_index,[tuple(k.co) for k in f.keyframe_points]) for f in a.fcurves]).encode()).hexdigest() for a in bpy.data.actions if a.name in ['idle','move','melee_keyboard','heavy_spin_slam']}
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v022.blend'))
for sc in bpy.data.scenes:sc['asset_version']='v024'
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v024.blend'))
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v022.blend'));old=signatures()
oldscene=bpy.data.scenes['BOSS002_STUDIO'];oldscene.name='BOSS002_HEAVY_PREVIEW';s=oldscene.copy();s.name='BOSS002_STUDIO';s.use_fake_user=True;s.collection.children.unlink(bpy.data.collections['BOSS002_IMPACT_PREVIEW']);bpy.context.window.scene=s
rig=bpy.data.objects['Boss002_Rig'];arm=rig.data;rig.animation_data.action=bpy.data.actions['melee_keyboard'];s.frame_set(1)
base={p.name:(p.location.copy(),p.rotation_quaternion.copy(),p.scale.copy()) for p in rig.pose.bones};neutral={side:rig.pose.bones['hand.'+side].matrix.copy() for side in ['L','R']};stretch={side:rig['stretch_'+side] for side in ['L','R']}
cn=['cable_%02d'%i for i in range(1,17)];lengths=[arm.bones[n].length for n in cn];attach=neutral['R'].inverted()@rig.pose.bones[cn[0]].head
rest_dirs=[neutral['R'].to_3x3().inverted()@(rig.pose.bones[n].tail-rig.pose.bones[n].head).normalized() for n in cn]
helpers=(R/'scripts/blender/animate_boss002_heavy_v017.py').read_text(encoding='utf-8');exec(helpers[helpers.index('def smooth('):helpers.index('for frame in range(1,98):')])
act=bpy.data.actions.new('melee_cable');act.use_fake_user=True;act['duration_seconds']=2.;act['impact_frame']=28;act['active_frames']=[25,32];act['hold_frames']=[21,24];act['description']='windup, four-frame hold, front fan sweep, cable lag, settle';rig.animation_data.action=act

def vec(keys,f):return Vector([sample([(k[0],k[1][i]) for k in keys],f) for i in range(3)])
def wrist_pose(side):
 angle=sample([(0,0),(20,-35),(23,-35),(26,35),(29,95),(34,110),(43,40),(51,-12),(60,0)],f if side=='R' else max(0,f-4))
 return root_motion.to_quaternion().to_matrix().to_4x4()@Matrix.Rotation(math.radians(angle if side=='R' else -angle*.35),4,'Z')@Matrix.Rotation(math.radians(-12*math.sin(math.pi*f/60)),4,'X')@neutral[side]
handkeys=[(0,tuple(neutral['R'].translation)),(6,(-2.4,-.35,3.1)),(14,(-2.7,-.7,3.2)),(20,(-2.6,-1.1,3.)),(23,(-2.6,-1.1,3.)),(25,(-2.4,1.1,2.45)),(27,(-.2,2.9,1.95)),(29,(2.,2.0,2.)),(33,(2.5,.7,2.2)),(42,(.6,.8,2.7)),(50,(-2.25,.0,2.7)),(55,(-2.35,-.2,2.3)),(60,tuple(neutral['R'].translation))]
traj={};checks=[];previous_quats={}
for frame in range(1,62):
 f=frame-1
 for pb in rig.pose.bones:
  l,q,sc=base[pb.name];pb.location=l;pb.rotation_mode='QUATERNION';pb.rotation_quaternion=q;pb.scale=sc
 for side in ['L','R']:rig['stretch_'+side]=stretch[side]
 target=vec([(0,(0,-.52,2.02)),(16,(.35,-.85,1.8)),(20,(.35,-.85,1.8)),(28,(-.35,.0,1.9)),(34,(-.65,.1,1.75)),(40,(-.3,-.4,2.15)),(50,(.15,-.6,2.12)),(60,(0,-.52,2.02))],f);support(target)
 yaw=sample([(0,0),(16,-24),(23,-24),(27,12),(30,35),(36,27),(42,12),(49,-7),(60,0)],f);pitch=sample([(0,0),(16,10),(20,10),(30,-13),(35,-8),(45,6),(60,0)],f)
 root_motion=Matrix.Translation(target)@Matrix.Rotation(math.radians(yaw),4,'Z')@Matrix.Translation(-Vector((0,-.52,2.02)))
 pb=rig.pose.bones['rear_axle'];pb.matrix=root_motion@pb.bone.matrix_local;bpy.context.view_layer.update()
 pb=rig.pose.bones['monitor_tilt'];world=Quaternion((1,0,0),math.radians(pitch));basis=pb.bone.matrix_local.to_quaternion();pb.rotation_quaternion=basis.inverted()@world@basis;bpy.context.view_layer.update()
 for name in ['large_eye','round_eye','mouth']:
  pb=rig.pose.bones['face_anchor_'+name];m=rig.pose.bones['monitor_tilt'].matrix@arm.bones['monitor_tilt'].matrix_local.inverted()@pb.bone.matrix_local;pb.matrix=m
 spin_weight=min(smooth((f-3)/4),smooth((23-f)/3))
 phase=math.tau*1.5*smooth((f-5)/15)
 cable_hand=vec(handkeys,f)+Vector((0,.35*math.cos(phase)*spin_weight,.35*math.sin(phase)*spin_weight))
 off_hand=vec([(0,tuple(neutral['L'].translation)),(17,(2.65,-.35,2.55)),(23,(2.8,-.6,2.6)),(29,(2.6,-1.2,2.7)),(34,(2.4,-1.4,2.6)),(42,(2.45,-.4,2.25)),(53,(2.2,.1,2.4)),(60,tuple(neutral['L'].translation))],f)
 arm_curve('R',root_motion@cable_hand);arm_curve('L',root_motion@off_hand)
 hand=rig.pose.bones['hand.R'].matrix.copy();points=[hand@attach];weight=min(smooth(f/12),smooth((60-f)/16))
 for i,n in enumerate(cn):
  delay=i*.22;g=max(0,f-delay)
  angle=math.radians(sample([(0,220),(20,210),(23,210),(25,145),(27,78),(29,8),(33,-12),(43,80),(50,150),(60,220)],g))
  elevation=sample([(0,-.08),(16,.07),(20,.07),(29,-.03),(36,.05),(45,-.08),(60,-.1)],g)+.07*math.sin(g*.33-i*.4)
  direct=Vector((math.cos(angle),math.sin(angle),elevation)).normalized()
  phase_i=math.tau*1.5*smooth((g-5)/15)-i*.30
  spiral=Vector((-.6,.85*math.cos(phase_i),.85*math.sin(phase_i))).normalized()
  swirl=min(smooth((g-3)/4),smooth((23-g)/3))
  direct=root_motion.to_3x3()@direct.lerp(spiral,swirl).normalized();rest=hand.to_3x3()@rest_dirs[i];direction=rest.lerp(direct,weight).normalized();points.append(points[-1]+direction*lengths[i])
 chain(cn,points)
 # Blend entrance and recovery exactly into the existing neutral pose.
 blend=min(smooth(f/7),smooth((60-f)/7))
 if blend<1:
  for pb in rig.pose.bones:
   l,q,sc=base[pb.name];pb.location=l.lerp(pb.location,blend);pb.rotation_quaternion=q.slerp(pb.rotation_quaternion,blend);pb.scale=sc.lerp(pb.scale,blend)
  for side in ['L','R']:rig['stretch_'+side]=stretch[side]*(1-blend)+rig['stretch_'+side]*blend
 bpy.context.view_layer.update();traj[frame]=list(rig.pose.bones['cable_16'].tail)
 rig['expression_state']=2 if 12<=f<=40 else 1 if f<12 else 0;rig['code_scroll']=f/48
 for pb in rig.pose.bones:
  if pb.name=='root':continue
  if pb.name in previous_quats and previous_quats[pb.name].dot(pb.rotation_quaternion)<0:pb.rotation_quaternion.negate()
  previous_quats[pb.name]=pb.rotation_quaternion.copy()
  for path in ['location','rotation_quaternion','scale']:pb.keyframe_insert(path,frame=frame,group=pb.name)
 for prop in ['stretch_L','stretch_R','expression_state','code_scroll']:rig.keyframe_insert(data_path='["'+prop+'"]',frame=frame)
for fc in act.fcurves:
 for k in fc.keyframe_points:k.interpolation='CONSTANT' if 'expression_state' in fc.data_path else 'LINEAR'
# Actual tip trajectory drives the swept ribbon: colors match keyboard cyan/magenta/white accents.
fx=bpy.data.collections.new('BOSS002_CABLE_PREVIEW');s.collection.children.link(fx)
def mat(name,color):
 m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;n.clear();e=n.new('ShaderNodeEmission');e.inputs[0].default_value=color;e.inputs[1].default_value=1.1;o=n.new('ShaderNodeOutputMaterial');m.node_tree.links.new(e.outputs[0],o.inputs[0]);return m
mats=[mat('Cable slash cyan',(0,.5,1,1)),mat('Cable slash magenta',(1,.015,.35,1)),mat('Cable slash white',(.66,.86,.94,1))]
def interpolated_tip(t):
 i=int(t);u=t-i
 p0=Vector(traj[max(1,i-1)]);p1=Vector(traj[max(1,i)]);p2=Vector(traj[min(61,i+1)]);p3=Vector(traj[min(61,i+2)])
 return .5*((2*p1)+(-p0+p2)*u+(2*p0-5*p1+4*p2-p3)*u*u+(-p0+3*p1-3*p2+p3)*u*u*u)
for fr in list(range(9,21))+list(range(25,35)):
 for lane in range(3):
  verts=[];faces=[];start=max(1,fr-(3 if fr>=25 else 2));seq=[start+(fr-start)*k/64 for k in range(65)]
  for j,t in enumerate(seq):
   v=interpolated_tip(t);tangent=(interpolated_tip(min(60.99,t+.02))-interpolated_tip(max(1,t-.02))).normalized();rad=tangent.cross(Vector((0,0,1))).normalized();width=(.16 if lane==0 else .035)*math.sin(math.pi*(j+.1)/len(seq))**.65*(1 if fr>=25 else .4);center=v-rad*(.05+lane*.25)
   verts.extend([tuple(center-rad*width),tuple(center+rad*width)])
   if j:faces.append((2*j-2,2*j-1,2*j+1,2*j))
  me=bpy.data.meshes.new('Swept tip ribbon');me.from_pydata(verts,[],faces);me.materials.append(mats[lane]);o=bpy.data.objects.new('Cable trail F%03d lane%d'%(fr,lane),me);fx.objects.link(o);o['preview_only']=True;o['export']=False;o.visible_shadow=False
  for t in [1,fr-1,fr,fr+1,61]:o.hide_render=t!=fr;o.keyframe_insert('hide_render',frame=t)
  for fc in o.animation_data.action.fcurves:
   for k in fc.keyframe_points:k.interpolation='CONSTANT'
for sc in [s,bpy.data.scenes['BOSS002_SOURCE_TPOSE']]:sc.frame_start=1;sc.frame_end=61;sc.render.fps=30;sc['asset_version']='v024'
s.camera=s.camera.copy();s.collection.objects.link(s.camera);s.camera.data=s.camera.data.copy();s.camera.location=(6,13,8);s.camera.rotation_euler=(Vector((0,.5,1.65))-s.camera.location).to_track_quat('-Z','Y').to_euler();s.camera.data.ortho_scale=14
assert signatures()==old;s.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v024.blend'))
(P/'trajectory.json').write_text(json.dumps(traj,indent=2));(P/'initial_audit.json').write_text(json.dumps({'old_actions_unchanged':True,'action':'melee_cable','duration_seconds':2,'held_cable_hand':'hand.R (existing cable hand)','total_cable_length':sum(lengths),'palette':'keyboard cyan / magenta / white','hold_frames':[21,24],'active_frames':[25,32],'spiral_turns':1.5,'hand_space':'rear axle relative + local overlap'},indent=2))
s.cycles.samples=8;s.render.resolution_x=960;s.render.resolution_y=800
for f in [11,17,24,28,31,37]:s.frame_set(f);s.render.filepath=str(P/('pose_%03d.png'%f));bpy.ops.render.render(write_still=True)
