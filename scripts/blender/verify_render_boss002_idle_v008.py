import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/idle_v008';F=P/'frames';F.mkdir(exist_ok=True)
def sig(r):return hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,list(b.head_local),list(b.tail_local),b.use_deform) for b in r.data.bones],sort_keys=True).encode()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v008.blend'));signature=sig(bpy.data.objects['Boss002_Rig']);checks={'static_model_no_action':len(bpy.data.actions)==0,'face_restored':all(abs(bpy.data.objects['Texture '+n].location.z-z)<1e-5 for n,z in {'large_eye':3.055,'round_eye':2.91,'mouth':2.015}.items())}
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v008.blend'));rig=bpy.data.objects['Boss002_Rig'];checks['dual_master_signature']=signature==sig(rig);checks['formal_idle_active']=rig.animation_data.action.name=='idle';checks['3_materials']=len(bpy.data.materials)==3
s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;cam=s.camera;cam.location=(3,12,4.5);cam.rotation_euler=(Vector((-.4,0,1.8))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=9.4;s.cycles.samples=8;s.render.resolution_x=752;s.render.resolution_y=600;s.render.resolution_percentage=100
mins={};first={};last={};motion=0;tri=0
for f in range(1,98):
 s.frame_set(f);dg=bpy.context.evaluated_depsgraph_get()
 for n in ['Keyboard outer shell','Long data cable whip','Data connector body','Crescent pedestal','Sculpted glove L','Sculpted glove R']:
  o=bpy.data.objects[n];e=o.evaluated_get(dg);me=e.to_mesh();vs=[e.matrix_world@v.co for v in me.vertices];e.to_mesh_clear();mins[n]=min(mins.get(n,999),min(v.z for v in vs))
  if f==1:first[n]=vs
  if f==97:last[n]=vs
  if 'glove' in n:motion=max(motion,max((a-b).length for a,b in zip(vs,first[n])))
 checks.setdefault('root_fixed',True);checks['root_fixed'] &= (rig.pose.bones['root'].matrix-rig.data.bones['root'].matrix_local).to_translation().length<1e-6
 if f<97 and f%2==1:s.render.filepath=str(F/('%04d.png'%((f-1)//2)));bpy.ops.render.render(write_still=True)
checks['clear_ground']=all(v>.03 for n,v in mins.items() if n!='Crescent pedestal');checks['loop_closes']=max(max((a-b).length for a,b in zip(first[n],last[n])) for n in first)<1e-5;checks['idle_has_motion']=motion>.01
report={'passed':all(checks.values()),'checks':checks,'minimum_z':mins,'maximum_hand_motion':motion,'skeleton_signature':signature,'not_executed':['Godot integration','other formal animation clips']};(P/'audit.json').write_text(json.dumps(report,indent=2));print(json.dumps(report));assert report['passed']
