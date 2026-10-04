import bpy,math,json,hashlib
from pathlib import Path
from mathutils import Vector,Quaternion,Matrix
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/idle_v009';P.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v006.blend'))
s=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];bpy.context.window.scene=s;rig=bpy.data.objects['Boss002_Rig'];arm=rig.data
# Align the keyboard width with the finger row. The thumb and curled fingertips
# oppose across its thickness, rather than hanging the keyboard below a flat hand.
center=Vector((2.56,-.045,1.235));newcenter=Vector((2.74,-.08,1.29));rot=Matrix.Rotation(-math.pi/2,4,'Z')
keyboard=[o for o in s.objects if o.get('asset_role')=='hand_prop_keyboard']
for o in keyboard:
 w=o.matrix_world.copy();o.matrix_world=Matrix.Translation(newcenter)@rot@Matrix.Translation(-center)@w
bpy.context.view_layer.update()
# Reauthor the unsupported upward whip into a doubled gravity loop with a free,
# downward connector. Both upper passes go through the right hand grip.
points=[(-2.80,-.24,1.90),(-2.80,.14,1.90),(-2.90,.20,1.53),(-3.03,.19,.99),(-3.28,.16,.72),(-3.54,.11,.86),(-3.57,.05,1.28),(-3.36,-.01,1.72),(-2.98,-.08,1.91),(-2.80,-.14,1.88),(-2.73,-.18,1.58),(-2.75,-.18,1.30)]
points=list(map(Vector,points));samples=[]
for i in range(len(points)-1):
 a=points[max(0,i-1)];b=points[i];c=points[i+1];d=points[min(len(points)-1,i+2)]
 for k in range(8):
  t=k/8;samples.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t))
samples.append(points[-1]);arc=[0.0]
for a,b in zip(samples,samples[1:]):arc.append(arc[-1]+(b-a).length)
def at(t):
 target=t*arc[-1];i=next((i for i in range(len(arc)-1) if arc[i+1]>=target),len(arc)-2);return samples[i].lerp(samples[i+1],(target-arc[i])/(arc[i+1]-arc[i]))
chain=[at(i/16) for i in range(17)]
old=bpy.data.objects['Long data cable whip'];mat=old.data.materials[0];col=old.users_collection[0];bpy.data.objects.remove(old,do_unlink=True)
verts=[];faces=[];segments=8
for j,p in enumerate(samples):
 axis=(samples[min(j+1,len(samples)-1)]-samples[max(0,j-1)]).normalized();u=axis.cross(Vector((0,1,0))).normalized();v=axis.cross(u).normalized()
 for k in range(segments):verts.append(p+.048*(u*math.cos(k*math.tau/segments)+v*math.sin(k*math.tau/segments)))
for j in range(len(samples)-1):
 for k in range(segments):a=j*segments+k;b=j*segments+(k+1)%segments;faces.append((a,b,b+segments,a+segments))
faces.extend([tuple(range(segments-1,-1,-1)),tuple((len(samples)-1)*segments+k for k in range(segments))])
me=bpy.data.meshes.new('Gravity loop topology');me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new('Long data cable whip',me);col.objects.link(o);me.materials.append(mat)
palette=json.loads((B/'source/textures_v006/body_palette.json').read_text());idx=palette['material_swatches'].get('Rubber cables',0);uv=me.uv_layers.new(name='PaletteUV')
for p in me.polygons:
 p.use_smooth=True
 for li in p.loop_indices:uv.data[li].uv=((idx%8+.5)/8,(idx//8+.5)/8)
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='EDIT')
for b in list(arm.edit_bones):
 if b.name.startswith('cable_'):arm.edit_bones.remove(b)
for i in range(16):
 b=arm.edit_bones.new('cable_%02d'%(i+1));b.head=chain[i];b.tail=chain[i+1];b.parent=arm.edit_bones['hand.R' if i==0 else 'cable_%02d'%i];b.use_connect=i>0
bpy.ops.object.mode_set(mode='OBJECT')
for b in arm.bones:b.inherit_scale='NONE'
for i in range(16):o.vertex_groups.new(name='cable_%02d'%(i+1))
for j in range(len(samples)):
 t=max(0,min(15,arc[j]/arc[-1]*16-.5));a=int(t);f=t-a
 for bone,w in [(a,1-f),(min(15,a+1),f)]:
  if w>0:o.vertex_groups[bone].add(list(range(j*segments,(j+1)*segments)),w,'ADD')
m=o.modifiers.new('Boss002 skin','ARMATURE');m.object=rig
# The previous connector pointed upward; rotate around its cable attachment.
connector=[]
for o in s.objects:
 if o.type=='MESH' and any(c.name.startswith('06_') for c in o.users_collection) and o.name!='Long data cable whip':
  w=o.matrix_world.copy();o.matrix_world=Matrix.Translation(points[-1])@Matrix.Rotation(math.pi,4,'X')@Matrix.Translation((3.5,.08,-1.0))@w
  o.vertex_groups.clear();g=o.vertex_groups.new(name='cable_16');g.add(list(range(len(o.data.vertices))),1,'REPLACE');connector.append(o.name)
rig['skeleton_id']='SKEL-MONITOR002-004';arm.name=rig['skeleton_id'];s['skeleton_id']=rig['skeleton_id'];s['asset_version']='v009';rig['controls']=rig['controls'].replace('cable_01..05','cable_01..16')
# Smooth finger-root masks replace the old hard Y cutoffs, which kinked the
# thumb web when the flat authoring hand was closed for the first time.
def smooth(a,b,x):
 t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
for sign,side in [(1,'L'),(-1,'R')]:
 glove=bpy.data.objects['Sculpted glove '+side];glove.vertex_groups.clear();groups={}
 for v in glove.data.vertices:
  p=glove.matrix_world@v.co;x=sign*p.x;y=p.y
  thumb=smooth(.07,.23,y)*(1-smooth(2.72,2.91,x));digits=smooth(2.59,2.79,x)*(1-thumb);ws={'hand.'+side:max(0,1-thumb-digits)}
  tf=smooth(.17,.30,y);ws['digit4_01.'+side]=thumb*(1-tf);ws['digit4_02.'+side]=thumb*tf
  ys=[-.25,-.08,.09];raw=[math.exp(-((y-yy)/.075)**2) for yy in ys];total=sum(raw);f=smooth(2.87,3.08,x)
  for i,w in enumerate(raw):
   for j,mix in [(1,1-f),(2,f)]:ws['digit%d_%02d.%s'%(i+1,j,side)]=digits*w/total*mix
  for n,w in ws.items():
   if w>1e-7:
    if n not in groups:groups[n]=glove.vertex_groups.new(name=n)
    groups[n].add([v.index],w,'REPLACE')
for sc in bpy.data.scenes:sc.render.fps=30;sc.frame_start=1;sc.frame_end=96
bpy.context.view_layer.update();signature=hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,list(b.head_local),list(b.tail_local),b.use_deform) for b in arm.bones],sort_keys=True).encode()).hexdigest()
tri=0
for ob in s.objects:
 if ob.type=='MESH':ob.data.calc_loop_triangles();tri+=len(ob.data.loop_triangles)
assert tri<20000,tri
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v009.blend'))
rig.animation_data_create();act=bpy.data.actions.new('idle');rig.animation_data.action=act;act.use_fake_user=True
def axis(pb,v,a):return Quaternion(pb.bone.matrix_local.to_3x3().inverted()@Vector(v),a)
def pose(frame):
 t=(frame-1)/96*math.tau
 for pb in rig.pose.bones:pb.location=(0,0,0);pb.rotation_mode='QUATERNION';pb.rotation_quaternion=(1,0,0,0)
 for sign,side in [(1,'L'),(-1,'R')]:
  phase=t+(0 if side=='L' else .35);rig['stretch_'+side]=.97+.007*math.sin(phase)
  for i,a in enumerate([.11,.14,.15,.12,.08,.035]):
   pb=rig.pose.bones['arm_%02d.%s'%(i+1,side)];pb.rotation_quaternion=axis(pb,(0,1,0),sign*(a+.008*math.sin(phase-i*.18)))
  pb=rig.pose.bones['hand_ctrl.'+side];pb.rotation_quaternion=axis(pb,(0,1,0),-sign*(.58+.015*math.sin(phase-.4)))@axis(pb,(0,0,1),math.radians(62 if side=='L' else 18))
  for d in [1,2,3]:
   for j,angle in [(1,48),(2,32)]:
    pb=rig.pose.bones['digit%d_%02d.%s'%(d,j,side)];pb.rotation_quaternion=axis(pb,(0,1,0),sign*math.radians(angle if side=='L' else (74 if j==1 else 84)))
  for j,angle in [(1,22),(2,30)]:
   pb=rig.pose.bones['digit4_%02d.'%j+side];pb.rotation_quaternion=axis(pb,(0,0,1),-sign*math.radians(46 if j==1 else 15))@axis(pb,(0,1,0),sign*math.radians(angle))
 for i in range(1,4):
  pb=rig.pose.bones['support_%02d'%i];pb.rotation_quaternion=axis(pb,(1,0,0),.004*math.sin(t-(i-1)*.12))
 # Small delayed pendulum, not a self-supporting floating whip. Grip stays firm.
 for i in range(1,17):
  pb=rig.pose.bones['cable_%02d'%i];pb.rotation_quaternion=axis(pb,(1,0,0),.0025*math.sin(t-i*.14))
 rig.update_tag();bpy.context.view_layer.update()
animated=[pb.name for pb in rig.pose.bones if pb.name.startswith(('arm_','hand_ctrl','digit','support_','cable_'))]
for f in range(1,98,4):
 pose(f)
 for n in animated:rig.pose.bones[n].keyframe_insert('rotation_quaternion',frame=f,group=n)
 for side in ['L','R']:rig.keyframe_insert(data_path='["stretch_'+side+'"]',frame=f,group='Spring length')
for fc in act.fcurves:
 for k in fc.keyframe_points:k.interpolation='BEZIER';k.handle_left_type='AUTO_CLAMPED';k.handle_right_type='AUTO_CLAMPED'
 fc.modifiers.new('CYCLES')
s.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v009.blend'))
c=json.loads((B/'source/rig_contract_v008.json').read_text());c.update(version='v009',skeleton_id=rig['skeleton_id'],bone_count=len(arm.bones),skeleton_signature=signature,triangles=tri,grip='keyboard top edge opposed thumb/fingers; doubled hanging cable with downward plug',cable_bones=16);(B/'source/rig_contract_v009.json').write_text(json.dumps(c,indent=2),encoding='utf-8')
scene=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=scene;cam=scene.camera;scene.cycles.samples=16;scene.render.resolution_x=1000;scene.render.resolution_y=800;scene.frame_set(1)
def render(name,loc,target,scale):
 cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale;scene.render.filepath=str(P/(name+'.png'));bpy.ops.render.render(write_still=True)
render('idle',(3,12,4.4),(0,0,1.8),8.0)
for side in ['L','R']:
 p=rig.pose.bones['hand.'+side].head;render('grip_'+side,p+Vector((1.2,3,1.5)),p+Vector((.2 if side=='L' else -.2,0,-.05)),1.8)
print('V009',tri,len(arm.bones))
