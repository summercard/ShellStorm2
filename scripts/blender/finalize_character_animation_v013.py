"""Portable library path plus preservation and non-static-loop regression checks."""
from pathlib import Path
import bpy, json, hashlib
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production'
TARGET=BASE/'v013/source/animation/chr_bunny01_animation_v013.blend'
def curves(action):
    return [(c.data_path,c.array_index,[(tuple(k.co),tuple(k.handle_left),tuple(k.handle_right),k.interpolation) for k in c.keyframe_points]) for c in action.fcurves]
bpy.ops.wm.open_mainfile(filepath=str(BASE/'v012/source/animation/chr_bunny01_animation_v012.blend'))
old=curves(bpy.data.actions['anim_bunny01_moving_v012'])
bpy.ops.wm.open_mainfile(filepath=str(TARGET))
assert curves(bpy.data.actions['anim_bunny01_walking_v013'])==old,'Original walk curves changed'
variation={}
for scene in bpy.data.scenes:
    bpy.context.window.scene=scene
    r=next(o for o in scene.objects if o.type=='ARMATURE')
    def pose(frame):
        scene.frame_set(frame)
        e=r.evaluated_get(bpy.context.evaluated_depsgraph_get())
        return {p.name:p.matrix.copy() for p in e.pose.bones}
    a=pose(1); b=pose(1+scene.frame_end//4)
    difference=max(abs(a[n][i][j]-b[n][i][j]) for n in a for i in range(4) for j in range(4))
    assert difference>.001,'Static action masquerading as loop'
    variation[scene['preview_clip']]=difference
    scene.frame_set(1)
for lib in bpy.data.libraries:
    if 'chr_bunny01_model' in lib.filepath: lib.filepath='//../model/chr_bunny01_model_v013.blend'
bpy.context.window.scene=bpy.data.scenes['02_正常移动_小跑']
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(TARGET),relative_remap=False)
bpy.ops.wm.open_mainfile(filepath=str(TARGET))
assert all(not lib.is_missing for lib in bpy.data.libraries)
report_path=ROOT/'outputs/character_pipeline/v013/animation_validation.json'
report=json.loads(report_path.read_text()); report['original_walk_fcurves_preserved']=True
report['non_static_pose_variation']=variation; report['relative_model_library_reopen']=True
report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2))
ledger_path=BASE/'v013/character_transfer_ledger_v013.json'
ledger=json.loads(ledger_path.read_text()); ledger['validation']=report
for entry in ledger['files']: entry['sha256']=hashlib.sha256((ROOT/entry['path']).read_bytes()).hexdigest()
ledger_path.write_text(json.dumps(ledger,ensure_ascii=False,indent=2))
print('PORTABLE_V013_PRESERVED_WALK_AND_NONSTATIC_LOOPS_PASS')
