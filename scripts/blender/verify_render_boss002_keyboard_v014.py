import bpy,json,hashlib,sys,math
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/keyboard_v014';F=P/'frames';F.mkdir(exist_ok=True)
def sig(r):return hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,list(b.head_local),list(b.tail_local),b.use_deform) for b in r.data.bones],sort_keys=True).encode()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v014.blend'));signature=sig(bpy.data.objects['Boss002_Rig']);checks={'static_model_no_actions':len(bpy.data.actions)==0}
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v014.blend'));rig=bpy.data.objects['Boss002_Rig'];s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s
checks['dual_master_signature']=signature==sig(rig);checks['all_three_actions']=all(bpy.data.actions.get(n) for n in ['idle','move','melee_keyboard']);checks['single_attack_no_cycles']=not any(fc.modifiers for fc in bpy.data.actions['melee_keyboard'].fcurves);checks['three_materials']=len({m.name for o in bpy.data.scenes['BOSS002_SOURCE_TPOSE'].objects if o.type=='MESH' for m in o.data.materials if m})==3
checks['normalized_weights']=all(abs(sum(g.weight for g in v.groups)-1)<1e-5 for o in bpy.data.scenes['BOSS002_SOURCE_TPOSE'].objects if o.type=='MESH' and o.vertex_groups for v in o.data.vertices)
tri=0
for o in bpy.data.scenes['BOSS002_SOURCE_TPOSE'].objects:
 if o.type=='MESH':o.data.calc_loop_triangles();tri+=len(o.data.loop_triangles)
checks['triangle_budget']=tri<20000
def vertices(o):
 e=o.evaluated_get(bpy.context.evaluated_depsgraph_get());me=e.to_mesh();v=[e.matrix_world@v.co for v in me.vertices];e.to_mesh_clear();return v
cam=s.camera;cam.location=(5,12,5.5);cam.rotation_euler=(Vector((0,.3,2))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=9;s.cycles.samples=8;s.render.resolution_x=800;s.render.resolution_y=660
flatness=[];positions=[];zmin=[];states=[];allmins={};contacts=[];poseframes={};scroll=[]
for f in range(1,56):
 s.frame_set(f);key=bpy.data.objects['Keyboard outer shell'];vs=vertices(key);positions.append(sum(vs,Vector())/len(vs));zmin.append(min(v.z for v in vs));states.append(int(bpy.data.objects['ExpressionController']['expression_index']));scroll.append(rig['code_scroll'])
 if 27<=f<=41:
  e=key.evaluated_get(bpy.context.evaluated_depsgraph_get());me=e.to_mesh();normal=e.matrix_world.to_3x3()@max(me.polygons,key=lambda p:p.area).normal;flatness.append(abs(normal.normalized().z));e.to_mesh_clear()
 checks.setdefault('root_fixed',True);checks['root_fixed'] &= rig.pose.bones['root'].location.length<1e-6
 for name in ['Keyboard outer shell','Long data cable whip','Data connector body','Portrait display','Crescent pedestal','Sculpted glove L']:
  v=vertices(bpy.data.objects[name]);allmins[name]=min(allmins.get(name,999),min(p.z for p in v))
 if f in [1,13,23,27,33,35,41,55]:
  e=key.evaluated_get(bpy.context.evaluated_depsgraph_get());me=e.to_mesh();bv=BVHTree.FromPolygons([e.matrix_world@v.co for v in me.vertices],[list(p.vertices) for p in me.polygons]);e.to_mesh_clear();hand=bpy.data.objects['Sculpted glove L'];hv=vertices(hand)
  for d in range(1,5):
   ids=[g.index for g in hand.vertex_groups if g.name.startswith('digit%d_'%d)];ds=[bv.find_nearest(hv[v.index])[3] for v in hand.data.vertices if sum(g.weight for g in v.groups if g.group in ids)>.4];contacts.append(min(ds))
  poseframes[f]=vs
 if '--audit-only' not in sys.argv and f<=54:s.render.filepath=str(F/('%04d.png'%(f-1)));bpy.ops.render.render(write_still=True)
checks['impact_in_front']=positions[32].y>3.0
checks['broad_face_horizontal']=min(flatness)>.999
checks['impact_collection_separate']='BOSS002_IMPACT_PREVIEW' not in [c.name for c in bpy.data.scenes['BOSS002_SOURCE_TPOSE'].collection.children]
checks['raised_above_display']=positions[22].z>3.7;checks['large_downstroke']=positions[22].z-positions[32].z>3;checks['anticipation_hold']=(positions[22]-positions[26]).length<.03
checks['ground_impact']=abs(zmin[32]-.025)<.015;checks['low_exposure']=max(zmin[32:41])<.08;checks['no_ground_penetration']=min(allmins.values())>-.005
checks['grip_retained']=max(contacts)<.055;checks['return_to_idle']=(positions[0]-positions[-1]).length<1e-4
checks['expression_flow']=states[0]==1 and states[22]==2 and states[39]==2 and states[40]==0 and states[-1]==0
checks['code_scroll_up']=all(b>a for a,b in zip(scroll,scroll[1:]))
checks['fast_hit_vs_windup']=(positions[26]-positions[32]).length/6>(positions[0]-positions[22]).length/22*2
rig.animation_data.action=bpy.data.actions['idle'];s.frame_set(1);checks['idle_restores_expression']=int(bpy.data.objects['ExpressionController']['expression_index'])==0
report={'passed':all(checks.values()),'checks':checks,'flat_normal_z_min':min(flatness),'triangles':tri,'keyboard_centers':{str(i):list(positions[i-1]) for i in [1,13,23,27,33,41,55]},'keyboard_minimum_z':zmin,'minimum_z':allmins,'maximum_grip_surface_distance':max(contacts),'skeleton_signature':signature,'not_executed':['Godot integration','damage events','other formal attacks']};(P/'audit.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2));assert report['passed']
