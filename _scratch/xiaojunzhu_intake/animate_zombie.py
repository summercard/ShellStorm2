import bpy,math,json,hashlib
from mathutils import Vector,Quaternion,Matrix
from pathlib import Path
P=Path(__file__).parent;R=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/normal_enemy_3d/melee_chaser');model=R/'source/model/enm_melee_fungboar01_model_v002.blend';out=R/'source/animation/enm_melee_fungboar01_animation_v001.blend'
bpy.context.preferences.filepaths.save_version=0
a=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');m=next(o for o in bpy.context.scene.objects if o.type=='MESH');s=bpy.context.scene;s.render.fps=30
rest={b.name:b.matrix_local.copy() for b in a.data.bones};heads={b.name:b.head_local.copy() for b in a.data.bones};tails={b.name:b.tail_local.copy() for b in a.data.bones}
def sig():return hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,[round(x,7) for row in b.matrix_local for x in row]) for b in a.data.bones]).encode()).hexdigest()
signature=sig();clips=[('idle',96,True,'01_待机_驼背晃身'),('walking',48,True,'02_慢走_跛脚拖步'),('running',24,True,'03_跑步_失衡前冲'),('attack',51,False,'04_近战_挥臂迟缓收势'),('hurt',24,False,'05_受击_踉跄回神'),('dead',72,False,'06_死亡_后躺砸地回弹')]
def rx(v):return Quaternion((1,0,0),math.radians(v))
def ry(v):return Quaternion((0,1,0),math.radians(v))
def rz(v):return Quaternion((0,0,1),math.radians(v))
def smooth(t):t=max(0,min(1,t));return t*t*(3-2*t)
def track(t,keys):
 for (ta,va),(tb,vb) in zip(keys,keys[1:]):
  if t<=tb:return va+(vb-va)*smooth((t-ta)/(tb-ta))
 return keys[-1][1]
def solve(clip,t):
 # Desired world-space orientations, converted to parent-relative pose rotations below.
 phase=2*math.pi*t;Q={n:Quaternion() for n in rest};hip=Vector((-.012,.073,.43));body=-10;lean=0;twist=0;headnod=4;arms={'L':[-65,-15,0,25],'R':[62,12,0,35]};knees={'L':5,'R':10};legs={'L':0,'R':0};bounce=0
 if clip=='idle':
  body=-11+3*math.sin(phase);lean=3*math.sin(phase);twist=4*math.sin(phase+.7);headnod=5+5*math.sin(phase-.6);bounce=.008*math.sin(phase);arms['L'][1]+=8*math.sin(phase-.5);arms['R'][1]+=10*math.sin(phase+.6)
 elif clip in ['walking','running']:
  running=clip=='running';amp=34 if running else 22;body=-19 if running else -12
  # asymmetrical phase warp creates short lame support and long drag recovery.
  u=(t/.58*.5) if t<.58 else .5+(t-.58)/.42*.5;ph=2*math.pi*u
  legs={'L':amp*math.sin(ph),'R':-.72*amp*math.sin(ph)};knees={'L':max(0,-math.sin(ph))*(58 if running else 32)+5,'R':max(0,math.sin(ph))*(40 if running else 22)+12};bounce=(.035 if running else .018)*(1-math.cos(2*ph))-.012;lean=5*math.sin(ph);twist=7*math.sin(ph);headnod=6+5*math.sin(ph-.4)
  arms['L']=[-60,-35+22*math.sin(ph+.4),-8,35];arms['R']=[63,30+18*math.sin(ph+.4),7,44];hip.x+=.018*math.sin(ph)
 elif clip=='attack':
  wind=track(t,[(0,0),(.28,1),(.38,1),(.48,-1),(.58,-.8),(1,0)]);body=track(t,[(0,-11),(.35,0),(.48,-28),(.60,-24),(1,-11)]);twist=40*wind;lean=-5*wind
  arms['R']=[track(t,[(0,62),(.30,12),(.38,8),(.48,100),(.62,88),(1,62)]),track(t,[(0,12),(.3,65),(.38,70),(.48,-65),(.62,-45),(1,12)]),0,track(t,[(0,35),(.35,75),(.48,12),(.65,18),(1,35)])];arms['L']=[-60,-25-15*wind,0,35];headnod=-8*wind;hip.y+=.09*smooth(t/.48)*(1-smooth((t-.6)/.4));knees={'L':18,'R':25}
 elif clip=='hurt':
  hit=track(t,[(0,0),(.13,1),(.28,.75),(.52,-.25),(1,0)]);body=-11+32*hit;twist=-15*hit;lean=7*hit;headnod=-22*hit;arms['L']=[-65+25*hit,-15-35*hit,0,25+30*hit];arms['R']=[62-25*hit,12+40*hit,0,35+30*hit];hip.y-=.08*hit;knees={'L':5+15*hit,'R':10+20*hit}
 elif clip=='dead':
  body=track(t,[(0,-11),(.10,15),(.23,30),(.40,86),(.47,70),(.58,90),(.64,83),(.74,90),(1,90)]);twist=track(t,[(0,0),(.23,-9),(.40,-5),(.58,0),(1,0)]);headnod=track(t,[(0,4),(.13,-22),(.35,-8),(.43,16),(.54,-6),(.70,0),(1,0)]);lean=0;arms['L']=[track(t,[(0,-65),(.2,-5),(.4,-30),(.48,-8),(.63,-32),(1,-35)]),-12,0,20];arms['R']=[track(t,[(0,62),(.2,3),(.4,32),(.48,12),(.63,35),(1,38)]),15,0,28];knees={'L':track(t,[(0,5),(.25,38),(.45,20),(.6,5),(1,8)]),'R':track(t,[(0,10),(.25,50),(.45,25),(.6,8),(1,12)])};hip.y-=track(t,[(0,0),(.25,.1),(.4,.45),(1,.45)])
 base=rx(body)@ry(lean)@rz(twist);Q['Hip']=base if clip=='dead' else ry(lean)@rz(twist*.3);Q['Waist']=base;Q['Spine02']=base@rx(-5 if clip!='dead' else 0);Q['Neck']=Q['Spine02']@rx(6);Q['Head']=Q['Neck']@rx(headnod)@rz(3*math.sin(phase) if clip=='idle' else 0)
 for side in ['L','R']:
  ab,fw,rot,elbow=arms[side];Q[side+'_Clavicle']=Q['Spine02'];Q[side+'_Upperarm']=Q['Spine02']@ry(ab)@rz(fw)@rx(rot);Q[side+'_Forearm']=Q[side+'_Upperarm']@rz(elbow if side=='L' else -elbow);Q[side+'_Hand']=Q[side+'_Forearm']@rx(12)
  for finger in ['Thumb','Index','Middle','Pinky']:
   for j in [1,2]:Q[side+'_'+finger+str(j)]=Q[side+'_Hand']@rx((-1 if side=='L' else 1)*(18+(j-1)*15+(5*math.sin(phase) if clip=='idle' else 0)))
  lb=base if clip=='dead' else Quaternion();Q[side+'_Thigh']=lb@rx(-legs[side]);Q[side+'_Calf']=Q[side+'_Thigh']@rx(knees[side]);Q[side+'_Foot']=lb@rx(-3 if side=='L' else 4)
 hip.z+=bounce
 # Global delta Q converted exactly to local basis; rest bone orientations are not world XYZ.
 for pb in a.pose.bones:
  n=pb.name;par=pb.parent.name if pb.parent else None;local=rest[n].to_quaternion().inverted()@(Q[par].inverted() if par else Quaternion())@Q[n]@rest[n].to_quaternion();pb.rotation_mode='QUATERNION';pb.rotation_quaternion=local;pb.location=(0,0,0);pb.scale=(1,1,1)
 a.pose.bones['Hip'].location=rest['Hip'].to_3x3().inverted()@(hip-heads['Hip'])
 bpy.context.view_layer.update()
 # Ground stabilization from evaluated mesh, not bone ankle assumptions.
 ev=m.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=ev.to_mesh();low=min((m.matrix_world@v.co).z for v in mesh.vertices);ev.to_mesh_clear()
 lift=.002-low
 if clip=='dead':lift+=track(t,[(0,0),(.38,0),(.40,0),(.47,.085),(.58,0),(.64,.025),(.74,0),(1,0)])
 elif clip=='running':lift+=.025*max(0,math.sin(4*math.pi*t))**2
 a.pose.bones['Hip'].location+=rest['Hip'].to_3x3().inverted()@Vector((0,0,lift))
 bpy.context.view_layer.update()
meta=[]
for clip,frames,loop,label in clips:
 act=bpy.data.actions.new('anim_melee_fungboar01_'+clip+'_v001');a.animation_data_create();a.animation_data.action=act;act.use_fake_user=True
 for f in range(frames+1):
  solve(clip,f/frames)
  for pb in a.pose.bones:
   if pb.name=='Root':continue
   pb.keyframe_insert('rotation_quaternion',frame=f+1,group=pb.name)
   if pb.name=='Hip':pb.keyframe_insert('location',frame=f+1,group=pb.name)
 act.use_frame_range=True;act.frame_start=1;act.frame_end=frames+1;act.use_cyclic=loop;act['loop']=loop;act['clip_id']=clip;act['duration_seconds']=frames/30
 for fc in act.fcurves:
  fc.extrapolation='CONSTANT'
  for k in fc.keyframe_points:k.interpolation='LINEAR'
  if loop:fc.modifiers.new('CYCLES')
 meta.append({'id':clip,'action':act.name,'frames':frames,'duration':frames/30,'loop':loop,'scene':label})
# Separate scenes for foolproof playback and range selection; mesh data linked to model library below.
for idx,entry in enumerate(meta):
 scene=s if idx==0 else bpy.data.scenes.new(entry['scene']);scene.name=entry['scene'];scene.render.fps=30;scene.frame_start=1;scene.frame_end=entry['frames'] if entry['loop'] else entry['frames']+1
 if idx==0:arm=a;mesh=m
 else:
  arm=a.copy();arm.data=a.data;scene.collection.objects.link(arm);mesh=m.copy();mesh.data=m.data;scene.collection.objects.link(mesh);mesh.parent=arm
  for mod in mesh.modifiers:
   if mod.type=='ARMATURE':mod.object=arm
 arm.animation_data_create();arm.animation_data.action=bpy.data.actions[entry['action']];scene.frame_set(1)
 scene['clip_id']=entry['id'];scene['preview_only_scene']=True
# Link mesh geometry and materials from exact model source; independent armatures preserve editable Actions.
meshname=m.data.name
bpy.ops.wm.save_as_mainfile(filepath=str(out))
with bpy.data.libraries.load(str(model),link=True) as (src,dst):dst.meshes=[meshname]
linked=dst.meshes[0]
for obj in bpy.data.objects:
 if obj.type=='MESH':obj.data=linked
text=bpy.data.texts.new('动画使用说明');text.write('小僵尸六动作源 / 30fps\n顶部场景下拉切换六段，空格播放。前三段循环，后三段单次/末帧保持。\n模型链接 ../model/enm_melee_fungboar01_model_v002.blend，不移动单文件，请保留source目录结构。\nRoot不移动；Hip为表现位移。模型/UV/静止骨架未改。\nattack：1-20蓄势，20-26挥击，26-52迟缓恢复。\ndead：约30帧首次落地，两次衰减回弹，末帧保持。\n没有接入Godot，不改变伤害/AI时序。\n')
for lib in bpy.data.libraries:lib.filepath=bpy.path.relpath(lib.filepath,start=str(out.parent))
bpy.context.window.scene=s;s.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(out));(P/'animation_meta.json').write_text(json.dumps({'skeleton_signature':signature,'model':str(model),'animation':str(out),'clips':meta},ensure_ascii=False,indent=2));print('SIX_ANIMATIONS_AUTHORED',out)
