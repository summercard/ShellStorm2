import bpy,math,json,hashlib,sys
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/heavy_v017'
def digest():
 return {name:hashlib.sha256(repr([(fc.data_path,fc.array_index,[(tuple(k.co),k.interpolation) for k in fc.keyframe_points]) for fc in bpy.data.actions[name].fcurves]).encode()).hexdigest() for name in ['idle','move','melee_keyboard']}
def signature(r):return hashlib.sha256(repr([(b.name,b.parent.name if b.parent else None,tuple(b.head_local),tuple(b.tail_local)) for b in r.data.bones]).encode()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v015.blend'));old=digest()
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v017.blend'));sig=signature(bpy.data.objects['Boss002_Rig'])
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v017.blend'));r=bpy.data.objects['Boss002_Rig'];s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s
checks={'previous_three_actions_unchanged':old==digest(),'dual_master_signature':sig==signature(r),'four_actions':all(bpy.data.actions.get(n) for n in ['idle','move','melee_keyboard','heavy_spin_slam']),'single_no_cycles':not any(fc.modifiers for fc in bpy.data.actions['heavy_spin_slam'].fcurves)}
def verts(name):
 ev=bpy.data.objects[name].evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();vs=[ev.matrix_world@v.co for v in me.vertices];ev.to_mesh_clear();return vs
names=['Portrait display','Stand column','Keyboard outer shell','Long data cable whip','Data connector body','Sculpted glove L','Sculpted glove R','Crescent pedestal']
mins={n:999 for n in names};centers={};angles=[];face_rotation=0;pedestal_error=0;root_error=0;axle_spin_error=0;contact=[];poses={};hands={}
for i in range(385):
 f=1+i/4;s.frame_set(int(f),subframe=f%1)
 for n in names:
  vs=verts(n);mins[n]=min(mins[n],min(v.z for v in vs))
  if n=='Portrait display':
   c=sum(vs,Vector())/len(vs)
   if f in [1,19,49,55,65,69,81,97]:centers[int(f)]=list(c)
   if 65<=f<=81:contact.append(min(v.z for v in vs))
 root_error=max(root_error,r.pose.bones['root'].location.length)
 pedestal_error=max(pedestal_error,r.pose.bones['pedestal_motion'].location.length, r.pose.bones['pedestal_motion'].rotation_quaternion.angle)
 if 19<=f<=49:
  pb=r.pose.bones['monitor_spin'];q=pb.rotation_quaternion;angles.append(2*math.atan2(q.y,q.w))
  axle_spin_error=max(axle_spin_error,(r.pose.bones['rear_axle'].matrix.to_quaternion().rotation_difference(r.data.bones['rear_axle'].matrix_local.to_quaternion())).angle)
 for n in ['large_eye','round_eye','mouth']:face_rotation=max(face_rotation,r.pose.bones['face_'+n].matrix.to_quaternion().rotation_difference(r.data.bones['face_'+n].matrix_local.to_quaternion()).angle)
 if f in [1,49,55,59,61,63,65,67,69,72,75,81,97]:
  hands[int(f)]={side:list(r.pose.bones['hand.'+side].matrix.translation) for side in ['L','R']}
  poses[int(f)]={p.name:p.matrix.copy() for p in r.pose.bones}
total=sum((b-a+math.pi)%(2*math.pi)-math.pi for a,b in zip(angles,angles[1:]))
checks.update(three_screen_turns=abs(total-6*math.pi)<.01,rear_axle_not_spinning=axle_spin_error<.001,face_stays_forward=face_rotation<.001,root_fixed=root_error<1e-6,base_planted=pedestal_error<1e-6,no_ground_penetration=min(mins.values())>-.005,front_ground_contact=min(contact)>.015 and max(contact)<.19)
checks['backlean_pose_hold']=max((poses[55][n].translation-poses[59][n].translation).length for n in ['monitor_spin','rear_axle'])<1e-4
checks['screen_nearly_flat']=abs((poses[65]['monitor_spin'].to_3x3()@Vector((0,1,0))).normalized().z)>.99
checks['backlean_visible']=(poses[55]['monitor_tilt'].to_quaternion().rotation_difference(poses[49]['monitor_tilt'].to_quaternion())).angle>math.radians(15)
checks['hands_follow_through']=all(hands[75][side][1]-hands[59][side][1]>.8 for side in ['L','R'])
checks['fast_accelerating_downstroke']=(Vector(centers[65])-Vector(centers[55])).length/6 > 2*(Vector(centers[55])-Vector(centers[49])).length/6
checks['large_slam_drop']=centers[55][2]-centers[65][2]>1.3
checks['return_to_start']=max((poses[1][n].translation-poses[97][n].translation).length for n in poses[1])<1e-4
fx=bpy.data.collections['BOSS002_IMPACT_PREVIEW'];counts={}
for f in [1,29,55,64,65,69,83,97]:
 s.frame_set(f);counts[f]=sum(not ob.hide_render and max(ob.scale)>.001 for ob in fx.objects)
checks['fx_spin_and_hit']=counts[29]>0 and counts[65]>0 and counts[69]>0
checks['fx_hold_and_end_clear']=all(counts[f]==0 for f in [1,55,64,83,97])
checks['fx_separate_from_character']=not any(ob in bpy.data.scenes['BOSS002_SOURCE_TPOSE'].objects[:] for ob in fx.objects)
rotor_angles=[]
for f in range(20,50):
 s.frame_set(f);rotor_angles.append(bpy.data.objects['Dedicated rotor ribbon 00'].rotation_euler.y)
checks['rotor_continuously_tracks_spin']=all(b-a>.01 for a,b in zip(rotor_angles,rotor_angles[1:])) and rotor_angles[-1]-rotor_angles[0]>18
report={'passed':all(checks.values()),'checks':checks,'spin_degrees':math.degrees(total),'minimum_z':mins,'hand_positions':hands,'screen_centers':centers,'contact_range':[min(contact),max(contact)],'face_rotation_error':face_rotation,'rear_axle_spin_error':axle_spin_error,'fx_counts':counts,'not_executed':['Godot import','gameplay damage','full mesh-to-mesh collision']}
(P/'audit.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2));assert report['passed']
if '--render' in sys.argv:
 F=P/'frames';F.mkdir(exist_ok=True);s.cycles.samples=8;s.render.resolution_x=800;s.render.resolution_y=660
 for f in (range(19,52) if '--rotor-only' in sys.argv else range(1,97)):s.frame_set(f);s.render.filepath=str(F/('%04d.png'%(f-1)));bpy.ops.render.render(write_still=True)
