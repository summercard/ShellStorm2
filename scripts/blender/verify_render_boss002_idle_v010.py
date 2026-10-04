import bpy,json,hashlib,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002';P=B/'previews/idle_v010';F=P/'frames';F.mkdir(exist_ok=True)
def sig(r):return hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,list(b.head_local),list(b.tail_local),b.use_deform) for b in r.data.bones],sort_keys=True).encode()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_model_v010.blend'));signature=sig(bpy.data.objects['Boss002_Rig']);checks={'static_model_no_action':len(bpy.data.actions)==0,'face_restored':all(abs(bpy.data.objects['Texture '+n].location.z-z)<1e-5 for n,z in {'large_eye':3.055,'round_eye':2.91,'mouth':2.015}.items())}
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v010.blend'));rig=bpy.data.objects['Boss002_Rig'];checks['dual_master_signature']=signature==sig(rig);checks['formal_idle_active']=rig.animation_data.action.name=='idle';checks['3_materials']=len(bpy.data.materials)==3
s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;cam=s.camera;cam.location=(3,12,4.5);cam.rotation_euler=(Vector((-.4,0,1.8))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=8.0;s.cycles.samples=8;s.render.resolution_x=752;s.render.resolution_y=600;s.render.resolution_percentage=100
mins={};first={};last={};motion=0;tri=0
contact={};cable_contact={};plug_down=[];grip_drift=0;local_grip=None;heights={n:[] for n in ["hand.L","hand.R","monitor_spin","face_anchor_large_eye","face_anchor_round_eye","face_anchor_mouth"]};float_offsets=[];scroll=[]
checks['weights_normalized']=all(abs(sum(g.weight for g in v.groups)-1)<1e-5 for o in bpy.data.scenes['BOSS002_SOURCE_TPOSE'].objects if o.type=='MESH' and o.vertex_groups for v in o.data.vertices)
for o in bpy.data.scenes['BOSS002_SOURCE_TPOSE'].objects:
 if o.type=='MESH':o.data.calc_loop_triangles();tri+=len(o.data.loop_triangles)
checks['under_20k']=tri<20000
checks['cable_16_bones']=len([b for b in rig.data.bones if b.name.startswith('cable_')])==16
checks['grip_fingers_animated']=all(any('digit%d_01.%s'%(d,side) in fc.data_path for fc in rig.animation_data.action.fcurves) for side in ['L','R'] for d in range(1,5))
for f in range(1,98):
 s.frame_set(f)
 for n in heights:heights[n].append(rig.pose.bones[n].head.z)
 float_offsets.append(rig.pose.bones['face_anchor_mouth'].location.length)
 scroll.append(bpy.data.materials['BOSS002_03_ScrollingCode'].node_tree.nodes['Code scroll offset'].inputs[1].default_value)
 dg=bpy.context.evaluated_depsgraph_get()
 for n in ['Keyboard outer shell','Long data cable whip','Data connector body','Crescent pedestal','Sculpted glove L','Sculpted glove R']:
  o=bpy.data.objects[n];e=o.evaluated_get(dg);me=e.to_mesh();vs=[e.matrix_world@v.co for v in me.vertices];e.to_mesh_clear();mins[n]=min(mins.get(n,999),min(v.z for v in vs))
  if f==1:first[n]=vs
  if f==97:last[n]=vs
  if 'glove' in n:motion=max(motion,max((a-b).length for a,b in zip(vs,first[n])))
 # Verify the visible grasp from evaluated finger surfaces, not just parenting.
 if f in [1,25,49,73,97]:
  ob=bpy.data.objects['Keyboard outer shell'];e=ob.evaluated_get(dg);me=e.to_mesh();bv=BVHTree.FromPolygons([e.matrix_world@v.co for v in me.vertices],[list(p.vertices) for p in me.polygons]);e.to_mesh_clear()
  hand=bpy.data.objects['Sculpted glove L'];e=hand.evaluated_get(dg);me=e.to_mesh()
  for d in range(1,5):
   ids=[g.index for g in hand.vertex_groups if g.name.startswith('digit%d_'%d)]
   ds=[bv.find_nearest(e.matrix_world@me.vertices[v.index].co)[3] for v in hand.data.vertices if sum(g.weight for g in v.groups if g.group in ids)>.4]
   contact.setdefault(str(d),[]).append(min(ds))
  e.to_mesh_clear()
  wire=bpy.data.objects['Long data cable whip'];e=wire.evaluated_get(dg);me=e.to_mesh();bv=BVHTree.FromPolygons([e.matrix_world@v.co for v in me.vertices],[list(p.vertices) for p in me.polygons]);e.to_mesh_clear()
  hand=bpy.data.objects['Sculpted glove R'];e=hand.evaluated_get(dg);me=e.to_mesh()
  for d in range(1,5):
   ids=[g.index for g in hand.vertex_groups if g.name.startswith('digit%d_'%d)]
   ds=[bv.find_nearest(e.matrix_world@me.vertices[v.index].co)[3] for v in hand.data.vertices if sum(g.weight for g in v.groups if g.group in ids)>.4]
   cable_contact.setdefault(str(d),[]).append(min(ds))
  e.to_mesh_clear()
  plug=rig.pose.bones['cable_16'];plug_down.append((plug.tail-plug.head).normalized().z)
 checks.setdefault('root_fixed'  ,True);checks['root_fixed'] &= (rig.pose.bones['root'].matrix-rig.data.bones['root'].matrix_local).to_translation().length<1e-6
 if '--audit-only' not in sys.argv and f<97 and f%2==1:s.render.filepath=str(F/('%04d.png'%((f-1)//2)));bpy.ops.render.render(write_still=True)
checks['clear_ground']=all(v>.03 for n,v in mins.items() if n!='Crescent pedestal');checks['loop_closes']=max(max((a-b).length for a,b in zip(first[n],last[n])) for n in first)<1e-5;checks['idle_has_motion']=motion>.01
checks['keyboard_contact_all_four_fingers']=all(max(v)<.055 for v in contact.values())
checks['cable_grip_contact']=all(max(v)<.06 for v in cable_contact.values())
checks['connector_points_down']=max(plug_down)<-.8
ranges={n:max(v)-min(v) for n,v in heights.items()}
checks['display_breathing_visible']=ranges['monitor_spin']>.20
checks['hands_bob_visible']=min(ranges['hand.L'],ranges['hand.R'])>.20
checks['face_independent_float']=max(float_offsets)-min(float_offsets)>.04
checks['uv_rises_continuously']=all(b<a for a,b in zip(scroll,scroll[1:])) and abs(scroll[-1]-scroll[0]+1)<1e-5
checks['uv_loop_seamless']=abs((scroll[-1]-scroll[0])%1)<1e-5
report={'vertical_ranges':ranges,'uv_scroll_range':[scroll[0],scroll[-1]],'cable_contact_distance':cable_contact,'connector_direction_z':plug_down,'triangles':tri,'keyboard_contact_distance':contact,'passed':all(checks.values()),'checks':checks,'minimum_z':mins,'maximum_hand_motion':motion,'skeleton_signature':signature,'not_executed':['Godot integration','other formal animation clips']};(P/'audit.json').write_text(json.dumps(report,indent=2));print(json.dumps(report));assert report['passed']
