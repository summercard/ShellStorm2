import bpy,math,json,hashlib
from pathlib import Path
from mathutils import Vector,Quaternion,Matrix
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/keyboard_v013';P.mkdir(exist_ok=True)
helpers=(R/'scripts/blender/animate_boss002_idle_v010.py').read_text(encoding='utf-8');helpers=helpers[helpers.index('def axis('):helpers.index('animated=[')]
for kind in ['model','animation']:
 bpy.ops.wm.open_mainfile(filepath=str(B/f'source/enm_boss_monitor002_{kind}_v011.blend'));s=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];bpy.context.window.scene=s;rig=bpy.data.objects['Boss002_Rig'];arm=rig.data;ctrl=bpy.data.objects['ExpressionController']
 rig['expression_state']=0;fc=ctrl.driver_add('["expression_index"]');v=fc.driver.variables.new();v.name='state';v.targets[0].id=rig;v.targets[0].data_path='["expression_state"]';fc.driver.expression='int(state)'
 s['asset_version']='v013'
 for ob in s.objects:
  if ob.type=='MESH' and ob.get('flat_sprite'):
   center=sum((v.co for v in ob.data.vertices),Vector())/len(ob.data.vertices)
   for v in ob.data.vertices:v.co=center+(v.co-center)*1.22

 # Preserve the coil-to-wrist connection under large axial extension.
 for o in s.objects:
  if o.type!='MESH' or not o.name.startswith('Continuous spring'):continue
  sign=1 if sum((o.matrix_world@v.co).x for v in o.data.vertices)>0 else -1;side='L' if sign>0 else 'R';hand=o.vertex_groups.get('hand.'+side) or o.vertex_groups.new(name='hand.'+side)
  for vert in o.data.vertices:
   x=sign*(o.matrix_world@vert.co).x;t=max(0,min(1,(x-2.0)/.115));t=t*t*(3-2*t)
   if t:
    weights=[(g.group,g.weight) for g in vert.groups]
    for group,w in weights:o.vertex_groups[group].add([vert.index],w*(1-t),'REPLACE')
    hand.add([vert.index],t,'REPLACE')
 if kind=='model':bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v013.blend'));continue
 for act in list(bpy.data.actions):
  rig.animation_data.action=act;rig['expression_state']=0;rig.keyframe_insert(data_path='["expression_state"]',frame=1,group='Expression state')
 rig.animation_data.action=None;exec(helpers);pose(1);bpy.context.view_layer.update()
 neutral={side:rig.pose.bones['hand.'+side].matrix.copy() for side in ['L','R']}
 act=bpy.data.actions.new('melee_keyboard');act.use_fake_user=True;rig.animation_data.action=act;act['duration_seconds']=1.8;act['impact_frame']=33;act['design_frame_offset']=1
 # Design F0 is Blender frame1. Large outer lift, fast downstroke, low exposure.
 keys=[(0,(2.3,-.08,1.9),0,1),(12,(2.2,-.35,3.9),-.09,1.08),(22,(1.9,-.05,4.25),-.11,1.08),(26,(1.9,-.05,4.25),-.11,1.08),(32,(.95,1.8,.5),.17,.78),(34,(1.0,1.85,.5),.19,.73),(40,(1.1,1.85,.6),.15,.78),(48,(2.3,1.0,2.2),.04,.96),(54,(2.3,-.08,1.9),0,1)]
 def interp(f):
  for a,b in zip(keys,keys[1:]):
   if f<=b[0]:
    t=max(0,(f-a[0])/(b[0]-a[0]));t=t*t*(3-2*t);return Vector(a[1]).lerp(Vector(b[1]),t),a[2]*(1-t)+b[2]*t,a[3]*(1-t)+b[3]*t
  return Vector(keys[-1][1]),0,1
 wrist_angle=0
 key=bpy.data.objects['Keyboard outer shell']
 normal=key.matrix_world.to_3x3()@max(key.data.polygons,key=lambda p:p.area).normal
 if normal.y<0:normal=-normal
 flat_rotation=normal.normalized().rotation_difference(Vector((0,0,-1)))
 flat_weight=0
 def wrist_matrix():
  q=Quaternion().slerp(flat_rotation,flat_weight)
  return q.to_matrix().to_4x4()@Matrix.Rotation(wrist_angle,4,'Y')@Matrix.Rotation(-wrist_angle*.45,4,'X')@neutral['L']

 def curve_arm(side,target):
  sign=1 if side=='L' else -1;bpy.context.view_layer.update();root=rig.pose.bones['rear_axle'].matrix@arm.bones['rear_axle'].matrix_local.inverted();start=root@arm.bones['arm_01.'+side].head_local
  desired=neutral[side].copy()
  if side=='L':desired=wrist_matrix()
  c1=start+Vector((sign*.8,-.05,.65));c2=target-desired.to_3x3().col[1].normalized()*.55;pts=[]
  for j in range(101):
   t=j/100;pts.append((1-t)**3*start+3*(1-t)**2*t*c1+3*(1-t)*t*t*c2+t**3*target)
  arc=[0.]
  for a,b in zip(pts,pts[1:]):arc.append(arc[-1]+(b-a).length)
  nodes=[]
  for j in range(7):
   dist=arc[-1]*j/6;i=next((i for i in range(100) if arc[i+1]>=dist),99);nodes.append(pts[i].lerp(pts[i+1],(dist-arc[i])/(arc[i+1]-arc[i])))
  # Chord sum matches the six authored segments and avoids IK solver ambiguity.
  rig['stretch_'+side]=sum((b-a).length for a,b in zip(nodes,nodes[1:]))/1.32;rig.update_tag();bpy.context.view_layer.update()
  for i in range(6):
   pb=rig.pose.bones['arm_%02d.%s'%(i+1,side)];direction=nodes[i+1]-nodes[i];q=direction.to_track_quat('Y','Z');mat=q.to_matrix().to_4x4();mat.translation=nodes[i];pb.matrix=mat;bpy.context.view_layer.update()
  pb=rig.pose.bones['hand_ctrl.'+side];mat=neutral[side].copy()
  if side=='L':mat=wrist_matrix()
  mat.translation=target;pb.matrix=mat;bpy.context.view_layer.update()
 def keyboard_min():
  ob=bpy.data.objects['Keyboard outer shell'];e=ob.evaluated_get(bpy.context.evaluated_depsgraph_get());me=e.to_mesh();z=min((e.matrix_world@v.co).z for v in me.vertices);e.to_mesh_clear();return z
 for frame in range(1,56):
  f=frame-1;pose(1);target,lean,compression=interp(f)
  basepose={p.name:(p.location.copy(),p.rotation_quaternion.copy(),p.scale.copy()) for p in rig.pose.bones};base_stretch={side:rig['stretch_'+side] for side in ['L','R']}
  flat_weight=min(1,max(0,(f-12)/10)) if f<=40 else max(0,(54-f)/14)
  flat_weight=flat_weight*flat_weight*(3-2*flat_weight)
  wrist_angle=math.radians(-25)*min(1,f/12)*(1-flat_weight)
  for i in range(1,4):
   pb=rig.pose.bones['support_%02d'%i];pb.rotation_quaternion=axis(pb,(1,0,0),-lean);pb.scale.y=compression
  curve_arm('L',target)
  # Broad face parallel to ground during the downstroke and contact; hand follows.
  if 32<=f<=40:
   target.z+=.025-keyboard_min();curve_arm('L',target)
  elif keyboard_min()<.06:
   target.z+=.06-keyboard_min();curve_arm('L',target)
  curve_arm('R',Vector((-2.55,-.25,1.95+.12*math.sin(f/54*math.pi))))
  for i in range(1,17):
   pb=rig.pose.bones['cable_%02d'%i];pb.rotation_quaternion=axis(pb,(1,0,0),.004*math.sin(f*.12-i*.15))
  rig['expression_state']=1 if f<22 else 2 if f<40 else 0;rig['code_scroll']=f/54
  blend=min(1,f/6,(54-f)/10);blend=max(0,blend);blend=blend*blend*(3-2*blend)
  if blend<1:
   for p in rig.pose.bones:
    loc,rot,scale=basepose[p.name];p.location=loc.lerp(p.location,blend);p.rotation_quaternion=rot.slerp(p.rotation_quaternion,blend);p.scale=scale.lerp(p.scale,blend)
   for side in ['L','R']:rig['stretch_'+side]=base_stretch[side]*(1-blend)+rig['stretch_'+side]*blend
  for pb in rig.pose.bones:
   if pb.name=='root':continue
   for path in ['location','rotation_quaternion','scale']:pb.keyframe_insert(path,frame=frame,group=pb.name)
  for prop in ['stretch_L','stretch_R','code_scroll','expression_state']:rig.keyframe_insert(data_path='["'+prop+'"]',frame=frame,group='Attack properties')
 for fc in act.fcurves:
  for k in fc.keyframe_points:k.interpolation='CONSTANT' if 'expression_state' in fc.data_path else 'LINEAR'
 for sc in bpy.data.scenes:sc.frame_start=1;sc.frame_end=55;sc.render.fps=30
 exec((R/'scripts/blender/boss002_flat_grip_v013.py').read_text(encoding='utf-8'))
 exec((R/'scripts/blender/boss002_impact_preview_v013.py').read_text(encoding='utf-8'))
 s.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v013.blend'))
c=json.loads((B/'source/rig_contract_v011.json').read_text());c.update(version='v013',formal_animations_authored=['idle','move','melee_keyboard'],melee_keyboard={'fps':30,'start':1,'end':55,'duration_seconds':1.8,'impact_frame':33,'state_property':'Boss002_Rig.expression_state','gameplay_damage':False,'flat_ground_contact':True,'expression_scale':1.22,'impact_vfx':'BOSS002_IMPACT_PREVIEW collection; source preview only'});(B/'source/rig_contract_v013.json').write_text(json.dumps(c,indent=2),encoding='utf-8')
scene=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=scene;cam=scene.camera;cam.location=(5,12,5.5);cam.rotation_euler=(Vector((0,.3,2))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=9;scene.cycles.samples=12;scene.render.resolution_x=960;scene.render.resolution_y=800
for f in [1,13,23,33,41,55]:
 scene.frame_set(f);scene.render.filepath=str(P/('pose_%03d.png'%f));bpy.ops.render.render(write_still=True)
