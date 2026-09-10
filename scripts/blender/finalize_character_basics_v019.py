"""Read-only source audit; append verified handoff evidence to the v019 ledger."""
from pathlib import Path
import json
import bpy
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production'
PACKAGE=BASE/'v019'
bpy.ops.wm.open_mainfile(filepath=str(PACKAGE/'source/animation/chr_bunny01_animation_v019.blend'))
report_path=ROOT/'outputs/character_pipeline/v019/validation.json'
report=json.loads(report_path.read_text())
assert (PACKAGE/'source/model/chr_bunny01_model_v019.blend').read_bytes()==(BASE/'v018/source/model/chr_bunny01_model_v018.blend').read_bytes()
report['model_byte_identical_to_v018']=True
poses={}; root_error=0
for scene in bpy.data.scenes:
    state=scene.get('preview_clip')
    if state not in report['clips']: continue
    bpy.context.window.scene=scene
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    for frame in range(1,scene.frame_end+1):
        scene.frame_set(frame)
        er=rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
        root_error=max(root_error,max(abs(er.pose.bones['root'].matrix[a][b]-rig.data.bones['root'].matrix_local[a][b]) for a in range(4) for b in range(4)))
        if (state=='falling' and frame==scene.frame_end) or (state=='landing' and frame==1):
            poses[state]={p.name:p.matrix.copy() for p in er.pose.bones}
    if state=='dead':
        dg=bpy.context.evaluated_depsgraph_get(); bottom=10
        for obj in scene.objects:
            if obj.type!='MESH' or obj.hide_render: continue
            eo=obj.evaluated_get(dg); mesh=eo.to_mesh()
            bottom=min(bottom,min((eo.matrix_world@v.co).z for v in mesh.vertices)); eo.to_mesh_clear()
        assert abs(bottom)<.001
        report['death_final_contact_z']=bottom
seam=max(abs(poses['falling'][n][a][b]-poses['landing'][n][a][b]) for n in poses['falling'] for a in range(4) for b in range(4))
assert seam<1e-5 and root_error<1e-5
report['fall_to_landing_pose_error']=seam
report['new_clips_root_motion_error']=root_error
report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2))
ledger_path=PACKAGE/'character_transfer_ledger_v019.json'
ledger=json.loads(ledger_path.read_text()); ledger['validation']=report
ledger_path.write_text(json.dumps(ledger,ensure_ascii=False,indent=2))
print('FINAL_SOURCE_CHECKS_PASS',seam,root_error,report['death_final_contact_z'])
