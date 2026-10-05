import bpy,math,json
from pathlib import Path
from mathutils import Vector,Matrix
B=Path('I:/工作项目/shellstrom2/ShellStorm2/assets/art/enemies/bosses/enm_boss_monitor002');P=B/'previews/impact_electric_v027';P.mkdir(exist_ok=True)
assert 'ARCHIVE_stun_enter_v026' not in bpy.data.actions, 'Run only on a fresh v026 copy; v027 already exists in session'
s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;r=bpy.data.objects['Boss002_Rig'];bpy.ops.wm.save_as_mainfile(filepath='I:/工作项目/shellstrom2/ShellStorm2/_scratch/boss027_before_edit.blend',copy=True)
def pose_at(act,f):
 r.animation_data.action=bpy.data.actions[act];s.frame_set(int(f),subframe=f-int(f));return {p.name:(p.location.copy(),p.rotation_quaternion.copy(),p.scale.copy()) for p in r.pose.bones}
old=bpy.data.actions['stun_enter'];cache={}
hit=pose_at('hurt',5.5)
start=pose_at('stun_enter',1)
for step in range(169):
 t=step/4
 if t<=3:act='hurt';f=1+t
 elif t<=6:act='hurt';f=4+(t-3)*.5
 else:act='stun_enter';f=1+24*min(1,(t-9)/9)
 if 6<t<9:
  u=(t-6)/3;u=u*u*(3-2*u)
  cache[step]={n:(hit[n][0].lerp(start[n][0],u),hit[n][1].slerp(start[n][1],u),hit[n][2].lerp(start[n][2],u)) for n in hit}
 else:cache[step]=pose_at(act,f)
r.animation_data.action=None;old.name='ARCHIVE_stun_enter_v026';new=bpy.data.actions.new('stun_enter');new.use_fake_user=True;r.animation_data.action=new;new['duration_seconds']=1.4;new['first_impact_frame']=19;new['bounce_peak_frame']=24;new['settled_frame']=31
prev={}
for step,bases in cache.items():
 t=step/4
 for p in r.pose.bones:
  l,q,sc=bases[p.name];p.location=l;p.rotation_quaternion=q;p.scale=sc
 bpy.context.view_layer.update()
 # One ballistic rebound only, from contact at frame19 to second contact at31.
 bounce=.48*math.sin(math.pi*(t-18)/12) if 18<t<30 else 0
 if bounce:
  saved=r.pose.bones['rear_axle'].matrix.copy();saved.translation.z+=bounce
  for i in range(1,4):
   p=r.pose.bones['support_%02d'%i];m=p.matrix.copy();m.translation.z+=bounce*(i-1)/3;p.matrix=m;bpy.context.view_layer.update()
  r.pose.bones['rear_axle'].matrix=saved;bpy.context.view_layer.update()
 r['expression_state']=2 if t<4 else 5;r['code_scroll']=t/24
 for p in r.pose.bones:
  if p.name=='root':continue
  if p.name in prev and prev[p.name].dot(p.rotation_quaternion)<0:p.rotation_quaternion.negate()
  prev[p.name]=p.rotation_quaternion.copy()
  for attr in ['location','rotation_quaternion','scale']:p.keyframe_insert(attr,frame=t+1,group=p.name)
 for prop in ['expression_state','code_scroll']:r.keyframe_insert(data_path='["'+prop+'"]',frame=t+1)
for fc in new.fcurves:
 for k in fc.keyframe_points:k.interpolation='CONSTANT' if 'expression' in fc.data_path else 'LINEAR'
# Dizzy eyes remain active while seated and subside during recovery.
for name in ['stun_loop','stun_exit']:
 r.animation_data.action=bpy.data.actions[name]
 fc=next((f for f in r.animation_data.action.fcurves if f.data_path=='["expression_state"]'),None)
 if fc:
  for k in fc.keyframe_points:k.co.y=5 if name=='stun_loop' or k.co.x<20 else 0
# FX mode is explicitly reset by every action, preventing stale FX on clip switching.
for a in bpy.data.actions:
 if a.name.startswith(('QA','ARCHIVE')):continue
 if a.name not in ['idle','move','melee_keyboard','melee_cable','heavy_spin_slam','special_prepare','special_insert','special_channel','special_recover','hurt','stun_enter','stun_loop','stun_exit','turn_left','turn_right']:continue
 r.animation_data.action=a;mode=1 if a.name.startswith('stun') else 2 if a.name.startswith('special') else 0;r['preview_fx_mode']=mode;r.keyframe_insert(data_path='["preview_fx_mode"]',frame=1)
fx=bpy.data.collections.new('BOSS002_DIZZY_ELECTRIC_PREVIEW');s.collection.children.link(fx)
def mat(name,color,strength):
 m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;n.clear();e=n.new('ShaderNodeEmission');e.inputs[0].default_value=(*color,1);e.inputs[1].default_value=strength;o=n.new('ShaderNodeOutputMaterial');m.node_tree.links.new(e.outputs[0],o.inputs[0]);return m
blue=mat('FX_Electric_Blue',(.08,.55,1),2);white=mat('FX_Electric_Core',(.65,.93,1),3);yellow=mat('FX_Dizzy_Gold',(1,.62,.08),1.5);pink=mat('FX_Dizzy_Pink',(.7,.15,.4),1.3)
def mode_driver(ob,mode):
 ob['preview_only']=True;ob['export']=False;ob.visible_shadow=False
 d=ob.driver_add('hide_render').driver;v=d.variables.new();v.name='mode';v.targets[0].id=r;v.targets[0].data_path='["preview_fx_mode"]';d.expression='mode != %d'%mode
 d=ob.driver_add('hide_viewport').driver;v=d.variables.new();v.name='mode';v.targets[0].id=r;v.targets[0].data_path='["preview_fx_mode"]';d.expression='mode != %d'%mode
# Bind dizzy orbit to the screen axle, not world coordinates. Time-driven loop survives action changes.
for j in range(5):
 verts=[]
 for i in range(10):
  a=math.tau*i/10;rad=.18 if i%2==0 else .075;verts.append((rad*math.cos(a),0,rad*math.sin(a)))
 me=bpy.data.meshes.new('Dizzy star');me.from_pydata(verts,[],[tuple(range(10))]);me.materials.append(yellow if j%2==0 else pink);o=bpy.data.objects.new('Dizzy orbit %d'%j,me);fx.objects.link(o);mode_driver(o,1)
 con=o.constraints.new('COPY_LOCATION');con.target=r;con.subtarget='rear_axle';con.use_offset=True
 for prop in ['hide_render','hide_viewport']:
  d=o.driver_add(prop).driver;v=d.variables.new();v.name='active';v.targets[0].id=r;v.targets[0].data_path='["dizzy_active"]';d.expression='mode != 1 or active < .1'
 for axis,expr in [(0,'1.05*cos(frame*0.13+%f)'%(j*math.tau/5)),(1,'.48*sin(frame*0.13+%f)'%(j*math.tau/5)),(2,'1.85+.08*sin(frame*.26+%f)'%(j*math.tau/5))]:o.driver_add('location',axis).driver.expression=expr
# Electric zig-zags each inherit a real cable bone, so the current follows the grounded cable.
for j in range(1,17):
 for lane in range(2):
  curve=bpy.data.curves.new('Electric filament','CURVE');curve.dimensions='3D';curve.bevel_depth=.019 if lane==0 else .009;curve.bevel_resolution=2;sp=curve.splines.new('POLY');sp.points.add(5);length=r.data.bones['cable_%02d'%j].length
  for i,p in enumerate(sp.points):p.co=((.075 if i%2 else -.035)*(1 if lane==0 else -1),length*i/5,.04+lane*.012,1)
  curve.materials.append(blue if lane==0 else white);o=bpy.data.objects.new('Cable current %02d.%d'%(j,lane),curve);fx.objects.link(o);o.parent=r;o.parent_type='BONE';o.parent_bone='cable_%02d'%j;o.location=(0,-length,0);mode_driver(o,2)
  # Only energize while connector is seated; ripple alternate segments.
  for prop in ['hide_render','hide_viewport']:
   d=o.driver_add(prop).driver;[d.variables.remove(x) for x in list(d.variables)];v=d.variables.new();v.name='mode';v.targets[0].id=r;v.targets[0].data_path='["preview_fx_mode"]';v=d.variables.new();v.name='active';v.targets[0].id=r;v.targets[0].data_path='["electric_active"]';d.expression='mode != 2 or active < .1 or ((frame+%d)%%6)>3'%j
for name in ['idle','move','melee_keyboard','melee_cable','heavy_spin_slam','special_prepare','special_insert','special_channel','special_recover','hurt','stun_enter','stun_loop','stun_exit','turn_left','turn_right']:
 r.animation_data.action=bpy.data.actions[name]
 keys=[(1,0)]
 if name=='special_insert':keys=[(1,0),(14,0),(15,1),(19,1)]
 if name=='special_channel':keys=[(1,1),(25,1)]
 if name=='special_recover':keys=[(1,1),(8,1),(9,0),(28,0)]
 for f,val in keys:r['electric_active']=val;r.keyframe_insert(data_path='["electric_active"]',frame=f)
 keys=[(1,0)]
 if name=='stun_enter':keys=[(1,0),(4,0),(5,1),(43,1)]
 if name=='stun_loop':keys=[(1,1),(49,1)]
 if name=='stun_exit':keys=[(1,1),(19,1),(20,0),(31,0)]
 for f,val in keys:r['dizzy_active']=val;r.keyframe_insert(data_path='["dizzy_active"]',frame=f)
 for fc in r.animation_data.action.fcurves:
  if fc.data_path in ['["electric_active"]','["preview_fx_mode"]','["dizzy_active"]']:
   for k in fc.keyframe_points:k.interpolation='CONSTANT'
for sc in bpy.data.scenes:sc['asset_version']='v027'
r.animation_data.action=new;s.frame_start=1;s.frame_end=43;s.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v027.blend'))
(P/'build.json').write_text(json.dumps({'stun_enter_frames':43,'first_contact':19,'bounce_peak':25,'second_contact':31,'dizzy_expression':5,'electric_contact_on':15,'electric_release_off':9},indent=2))
print('V027 saved, current scene ready')
