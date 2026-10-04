import bpy,math,json,hashlib
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/rig_v005';P.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_source_v004.blend'))
s=bpy.data.scenes['BOSS002_SOURCE_TPOSE'];bpy.context.window.scene=s;s.frame_set(1)
ctrl=bpy.data.objects['ExpressionController'];ctrl.animation_data_clear();ctrl['expression_index']=0;ctrl['usage']='Persistent expression state 0..5; no timeline cycling. default/suspicious/angry/sleepy/taunting/glitched'
for a in list(bpy.data.actions):bpy.data.actions.remove(a)
for sc in bpy.data.scenes:sc.timeline_markers.clear();sc.frame_start=1;sc.frame_end=96
master=bpy.data.collections['BOSS002_MONITOR'];rc=bpy.data.collections.new('00_RIG');master.children.link(rc)
arm=bpy.data.armatures.new('SKEL-MONITOR002-001');rig=bpy.data.objects.new('Boss002_Rig',arm);rc.objects.link(rig);rig.show_in_front=True;arm.display_type='BBONE';rig['skeleton_id']='SKEL-MONITOR002-001'
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='EDIT')
def bone(n,h,t,parent=None,deform=True):
    b=arm.edit_bones.new(n);b.head=h;b.tail=t;b.use_deform=deform
    if parent:b.parent=arm.edit_bones[parent]
    return b
bone('root',(0,0,0),(0,0,.18))
support=[(0,-.08,.18),(0,-.11,.41),(0,-.23,.65),(0,-.34,.88)]
for i in range(3):bone('support_%02d'%(i+1),support[i],support[i+1],'root' if i==0 else 'support_%02d'%i)
bone('monitor_tilt',support[-1],(0,-.34,1.25),'support_03')
bone('monitor_spin',(0,0,2.02),(0,.4,2.02),'monitor_tilt')
for sign,side in [(1,'L'),(-1,'R')]:
    bone('hand_ctrl.'+side,(sign*2.23,-.08,2.01),(sign*2.6,-.08,2.01),'monitor_spin',False)
    bone('spring.'+side,(sign*.91,-.08,2.01),(sign*2.23,-.08,2.01),'monitor_spin')
    bone('hand.'+side,(sign*2.23,-.08,2.01),(sign*2.70,-.08,2.01),'root')
    for i,coords in enumerate([(2.70,-.225,3.04,-.33),(2.74,-.08,3.16,-.08),(2.70,.065,3.04,.17),(2.43,.08,2.64,.28)]):
        x,y,xx,yy=coords;a=Vector((sign*x,y,2.01));c=Vector((sign*xx,yy,2.01));mid=a.lerp(c,.52)
        bone('digit%d_01.%s'%(i+1,side),a,mid,'hand.'+side);bone('digit%d_02.%s'%(i+1,side),mid,c,'digit%d_01.%s'%(i+1,side))
    bone('prop_socket.'+side,(sign*2.53,-.08,1.96),(sign*2.53,-.08,1.81),'hand.'+side,False)
for name in ['large_eye','round_eye','mouth']:
    p=bpy.data.objects['Texture '+name].location.copy();bone('face_anchor_'+name,p,p+Vector((0,0,.12)),'monitor_spin',False);bone('face_'+name,p,p+Vector((0,0,.12)),'root')
cable=[(-2.53,-.02,1.96),(-2.59,.015,1.46),(-2.2,.01,.76),(-2.40,.10,.20),(-3.15,-.08,.26),(-3.5,-.08,1.43)]
for i in range(5):bone('cable_%02d'%(i+1),cable[i],cable[i+1],'hand.R' if i==0 else 'cable_%02d'%i)
bpy.ops.object.mode_set(mode='OBJECT')
for b in arm.bones:b.inherit_scale='NONE';b.bbone_x=.045;b.bbone_z=.045
for side in ['L','R']:
    pb=rig.pose.bones['spring.'+side];c=pb.constraints.new('STRETCH_TO');c.target=rig;c.subtarget='hand_ctrl.'+side;c.rest_length=arm.bones[pb.name].length;c.volume='NO_VOLUME';c.keep_axis='PLANE_Z'
    pb=rig.pose.bones['hand.'+side];c=pb.constraints.new('COPY_TRANSFORMS');c.target=rig;c.subtarget='hand_ctrl.'+side;c.owner_space='WORLD';c.target_space='WORLD'
for name in ['large_eye','round_eye','mouth']:
    pb=rig.pose.bones['face_'+name];c=pb.constraints.new('COPY_LOCATION');c.target=rig;c.subtarget='face_anchor_'+name;c.owner_space='WORLD';c.target_space='WORLD'
    c=pb.constraints.new('COPY_ROTATION');c.target=rig;c.subtarget='root';c.owner_space='WORLD';c.target_space='WORLD'
# Rebuild the short rear support with enough axial loops to actually bend.
old=bpy.data.objects['Stand column'];mat=old.data.materials[0];col=old.users_collection[0];bpy.data.objects.remove(old,do_unlink=True)
verts=[];faces=[];rings=22;seg=12
for j in range(rings):
    t=j/(rings-1)*3;i=min(2,int(t));p=Vector(support[i]).lerp(Vector(support[i+1]),min(1,t-i));axis=(Vector(support[i+1])-Vector(support[i])).normalized();u=Vector((1,0,0));v=axis.cross(u).normalized()
    for k in range(seg):verts.append(tuple(p+.095*(u*math.cos(2*math.pi*k/seg)+v*math.sin(2*math.pi*k/seg))))
for j in range(rings-1):
    for k in range(seg):a=j*seg+k;b=j*seg+(k+1)%seg;faces.append((a,b,b+seg,a+seg))
faces+=[tuple(range(seg-1,-1,-1)),tuple((rings-1)*seg+k for k in range(seg))]
me=bpy.data.meshes.new('Flexible support topology');me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new('Stand column',me);col.objects.link(o);me.materials.append(mat)
for p in me.polygons:p.use_smooth=True
def bind(o,weights):
    for vg in list(o.vertex_groups):o.vertex_groups.remove(vg)
    groups={}
    for idx,ws in enumerate(weights):
        total=sum(ws.values())
        for name,w in ws.items():
            if w<1e-8:continue
            if name not in groups:groups[name]=o.vertex_groups.new(name=name)
            groups[name].add([idx],w/total,'REPLACE')
    m=o.modifiers.new('Boss002 skin','ARMATURE');m.object=rig;m.use_deform_preserve_volume=False
def rigid(o,name):bind(o,[{name:1} for _ in o.data.vertices])
def smooth_chain(t,n,prefix):
    t=max(0,min(n-1,t));i=int(t);f=t-i
    return {prefix%(i+1):1-f,prefix%(min(n-1,i+1)+1):f} if i<n-1 else {prefix%n:1}
for o in list(s.objects):
    if o.type!='MESH':continue
    n=o.name;group=next((c.name[:2] for c in o.users_collection if c.name[:2].isdigit()),'')
    if group=='05':
        # Keyboard remains a detachable prop, following hand socket without skin deformation.
        w=o.matrix_world.copy();o.parent=rig;o.parent_type='BONE';o.parent_bone='prop_socket.L';bpy.context.view_layer.update();o.matrix_world=w;o['asset_role']='hand_prop_keyboard';continue
    if n.startswith('Texture '):rigid(o,'face_'+n[8:]);continue
    if n=='Stand column':
        bind(o,[smooth_chain(((o.matrix_world@v.co).z-.18)/.7*3-.5,3,'support_%02d') for v in o.data.vertices]);continue
    if group=='07':rigid(o,'monitor_tilt' if n.startswith(('Portrait rotation hinge','Hinge cap')) else 'root');continue
    if group=='01':rigid(o,'monitor_spin');continue
    if group=='03':
        side='L' if sum((o.matrix_world@v.co).x for v in o.data.vertices)/len(o.data.vertices)>0 else 'R'
        if n.startswith('Continuous spring'):rigid(o,'spring.'+side)
        elif n.startswith(('Metal wrist','Wrist sleeve')):rigid(o,'hand.'+side)
        else:rigid(o,'monitor_spin')
        continue
    if group=='04':
        side='L' if o.location.x>0 else 'R';sgn=1 if side=='L' else -1
        if not n.startswith('Sculpted glove'):rigid(o,'hand.'+side);continue
        weights=[]
        for v in o.data.vertices:
            p=o.matrix_world@v.co;x=sgn*p.x;y=p.y
            if y>.13 and x<2.84:d=4;t=max(0,min(1,(y-.07)/.22));split=(y-.18)/.13
            else:
                d=1 if y<-.17 else 3 if y>.025 else 2;t=max(0,min(1,(x-2.60)/.18));split=(x-2.88)/.20
            f=max(0,min(1,split));weights.append({'hand.'+side:1-t,'digit%d_01.%s'%(d,side):t*(1-f),'digit%d_02.%s'%(d,side):t*f})
        bind(o,weights);continue
    if group=='06':
        if n!='Long data cable whip':rigid(o,'cable_05');continue
        weights=[]
        for v in o.data.vertices:
            p=o.matrix_world@v.co;best=None
            for i in range(5):
                a=Vector(cable[i]);d=Vector(cable[i+1])-a;t=max(0,min(1,(p-a).dot(d)/d.length_squared));dist=(p-(a+d*t)).length
                if best is None or dist<best[0]:best=(dist,i+t)
            weights.append(smooth_chain(best[1]-.5,5,'cable_%02d'))
        bind(o,weights)
# Each controller has an explicit authoring role.
for pb in rig.pose.bones:pb.rotation_mode='XYZ'
rig['controls']='support_01..03 bend; monitor_tilt pitch; monitor_spin local Y roll; hand_ctrl.L/R translate to stretch springs; digit1..4 close hands; cable_01..05 FK'
rig['expression_state_owner']='ExpressionController[expression_index] persistent integer 0..5'
s['asset_version']='v005';s['stage']='authored_rigged';s['skeleton_id']='SKEL-MONITOR002-001'
sig=hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,list(b.head_local),list(b.tail_local),b.use_deform) for b in arm.bones],sort_keys=True).encode()).hexdigest()
tri=0
for ob in s.objects:
    if ob.type=='MESH':ob.data.calc_loop_triangles();tri+=len(ob.data.loop_triangles)
assert tri<20000,tri
contract={'asset_id':'ENM-BOSS-MONITOR002-3D','version':'v005','skeleton_id':'SKEL-MONITOR002-001','skeleton_signature':sig,'bone_count':len(arm.bones),'deform_bones':[b.name for b in arm.bones if b.use_deform],'triangles':tri,'expression_states':{'default':0,'suspicious':1,'angry':2,'sleepy':3,'taunting':4,'glitched':5},'expression_mode':'persistent selectable visual state, no automatic cycling, no gameplay-state mapping assigned','spring':'STRETCH_TO hand_ctrl, NO_VOLUME; axial pitch changes, radius preserved','face':'anchors move with monitor_spin; face deform bones copy anchor world location but root world rotation','support':'3 FK joints, smooth normalized weights; geometry rebuilt with axial loops','keyboard':'bone-parented prop_socket.L, detachable unskinned prop','model_source':'source/enm_boss_monitor002_model_v005.blend','animation_source':'source/enm_boss_monitor002_animation_v005.blend','runtime_integration':False,'export_note':'Blender constraints must be baked on deform bones; material states require runtime UV adapter. This is source rig validation only.'}
(B/'source/rig_contract_v005.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
# Static model master, no preview actions or auto-playing expression.
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v005.blend'))
# Separate animation master contains proof poses only, clearly named non-gameplay tests.
rig.animation_data_create()
tests=[('QA_spring_extend','spring'),('QA_monitor_spin','spin'),('QA_forward_slam','forward'),('QA_down_slam','down'),('QA_finger_curl','fingers')]
for aname,kind in tests:
    for pb in rig.pose.bones:pb.location=(0,0,0);pb.rotation_euler=(0,0,0);pb.scale=(1,1,1)
    act=bpy.data.actions.new(aname);act.use_fake_user=True;rig.animation_data.action=act
    channels=[]
    if kind=='spring':channels=[('hand_ctrl.L','location',(0,1.0,0)),('hand_ctrl.R','location',(0,.7,0))]
    if kind=='spin':channels=[('monitor_spin','rotation_euler',(0,math.radians(65),0))]
    if kind=='forward':channels=[('support_01','rotation_euler',(math.radians(-20),0,0)),('support_02','rotation_euler',(math.radians(-25),0,0)),('support_03','rotation_euler',(math.radians(-10),0,0)),('monitor_tilt','rotation_euler',(math.radians(-25),0,0))]
    if kind=='down':channels=[('support_01','rotation_euler',(0,0,math.radians(38))),('support_02','rotation_euler',(0,0,math.radians(-65))),('support_03','rotation_euler',(0,0,math.radians(27))),('monitor_tilt','location',(0,-.10,0))]
    if kind=='fingers':channels=[('digit%d_%02d.%s'%(d,j,side),'rotation_euler',(math.radians(40),0,0)) for side in ['L','R'] for d in range(1,5) for j in [1,2]]
    for bn,path,value in channels:
        pb=rig.pose.bones[bn];setattr(pb,path,(0,0,0));pb.keyframe_insert(path,frame=1);setattr(pb,path,value);pb.keyframe_insert(path,frame=36);setattr(pb,path,(0,0,0));pb.keyframe_insert(path,frame=72)
rig.animation_data.action=bpy.data.actions['QA_spring_extend'];s.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v005.blend'))
scene=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=scene;scene.cycles.samples=24;cam=scene.camera;cam.location=(4,11,5);cam.rotation_euler=(Vector((0,0,1.8))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=9.2
for aname,kind in tests[:4]:
    for pb in rig.pose.bones:pb.location=(0,0,0);pb.rotation_euler=(0,0,0);pb.scale=(1,1,1)
    rig.animation_data.action=bpy.data.actions[aname];scene.frame_set(36);scene.render.filepath=str(P/(kind+'.png'));bpy.ops.render.render(write_still=True)
print(json.dumps(contract,indent=2))
