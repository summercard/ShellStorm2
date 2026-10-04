import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2];B=R/'assets/art/enemies/bosses/enm_boss_monitor002'
def actions():
 return {name:hashlib.sha256(repr([(fc.data_path,fc.array_index,[(tuple(k.co),k.interpolation) for k in fc.keyframe_points]) for fc in bpy.data.actions[name].fcurves]).encode()).hexdigest() for name in ['idle','move']}
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v012.blend'));old=actions()
bpy.ops.wm.open_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v014.blend'));checks={'idle_move_curves_preserved':old==actions()}
s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window.scene=s;fx=bpy.data.collections['BOSS002_IMPACT_PREVIEW'];minz=999
for i in range(217):
 frame=1+i/4;s.frame_set(int(frame),subframe=frame%1)
 for name in ['Keyboard outer shell','Sculpted glove L']:
  ev=bpy.data.objects[name].evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();minz=min(minz,min((ev.matrix_world@v.co).z for v in me.vertices));ev.to_mesh_clear()
checks['quarter_frame_no_ground_penetration']=minz>-.005
counts={}
for f in [1,22,24,29,33,36,44,55]:
 s.frame_set(f);counts[f]=sum(not ob.hide_render and max(ob.scale)>.001 for ob in fx.objects)
checks['fx_quiet_before_and_after']=all(counts[f]==0 for f in [1,22,44,55])
checks['fx_anticipation_swing_impact']=all(counts[f]>0 for f in [24,29,33,36])
checks['all_fx_export_excluded']=all(ob.get('preview_only') and ob.get('export')==False for ob in fx.objects)
report={'passed':all(checks.values()),'checks':checks,'quarter_frame_min_z':minz,'visible_fx_counts':counts}
(B/'previews/keyboard_v014/presentation_audit.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2));assert report['passed']
s.camera.location=(5,12,5.5);s.camera.rotation_euler=(Vector((0,.3,2))-s.camera.location).to_track_quat('-Z','Y').to_euler();s.camera.data.ortho_scale=9
s.frame_set(1);s['preview_instructions']='Play frames 1-55: melee_keyboard + 2D VFX. Source character scene excludes VFX. Switch rig Action to idle/move with their respective frame ranges.'
bpy.ops.wm.save_as_mainfile(filepath=str(B/'source/enm_boss_monitor002_animation_v014.blend'))
