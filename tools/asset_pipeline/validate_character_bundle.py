"""Validate hashed transfer records and run character regressions before acceptance."""
import argparse
import hashlib
import json
import struct
import subprocess
from pathlib import Path

TESTS=['verify_character_authoring_bundle','verify_player3d_avatar_bounds','verify_player3d_animation_flow','verify_player3d_diy_flow','verify_player3d_head_accessory_flow','verify_player3d_lower_body_socket_flow','verify_player3d_weapon_pose_collision_flow','verify_player3d_state_gallery_flow','verify_3d_reload_state_flow','verify_3d_melee_feedback_flow','verify_avatar_return_persistence_flow']

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('package',type=Path)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[2]
    package=args.package.resolve()
    ledger_path=package/f'character_transfer_ledger_{package.name}.json'
    ledger=json.loads(ledger_path.read_text())
    for entry in ledger['files']+ledger['runtime_files']:
        path=root/entry['path']
        assert path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest()==entry['sha256'], 'Stale file '+str(path)
    library=json.loads((package/f'exports/anim_bunny01_library_{package.name}.json').read_text())
    assert library['skeleton_sha256']==ledger['skeleton_sha256']
    required={'idle','moving','dashing','hurt','locked','falling','landing','dead','walking','armed_walking','armed_moving','armed_idle'}
    assert set(library['clips'])==required, 'Incomplete or unexpected v021 clip set'
    expected_loops={'idle','moving','locked','walking','armed_walking','armed_moving','armed_idle'}
    assert {name for name,clip in library['clips'].items() if clip['loop']}==expected_loops
    for name,clip in library['clips'].items():
        if clip['loop']:
            for bone in clip['frames'][0]:
                for prop in ['p','q','s']:
                    assert max(abs(a-b) for a,b in zip(clip['frames'][0][bone][prop],clip['frames'][-1][bone][prop]))<0.0001, 'Loop seam '+name
    animation_glb=(package/f'exports/anim_bunny01_library_{package.name}.glb').read_bytes()
    assert animation_glb[:4] == b'glTF', 'Invalid animation GLB header'
    json_length,json_type=struct.unpack_from('<II',animation_glb,12)
    assert json_type == 0x4E4F534A, 'Animation GLB has no JSON chunk'
    gltf=json.loads(animation_glb[20:20+json_length].decode('utf-8').rstrip(' \x00'))
    assert not gltf.get('meshes'), 'Animation GLB contains preview/model meshes'
    assert gltf.get('animations'), 'Animation GLB contains no bone animation'
    logs=root/'outputs/character_pipeline/validation'/package.name
    logs.mkdir(parents=True,exist_ok=True)
    imported=subprocess.run(['godot','--headless','--path',str(root),'--editor','--quit'],capture_output=True,text=True,timeout=180)
    assert imported.returncode==0 and 'SCRIPT ERROR' not in imported.stdout+imported.stderr
    results=[]
    for test in TESTS:
        run=subprocess.run(['godot','--headless','--path',str(root),'--scene',f'res://tests/verification/{test}.tscn'],capture_output=True,text=True,timeout=90)
        output=run.stdout+run.stderr
        (logs/(test+'.log')).write_text(output)
        passed=run.returncode==0 and 'ERROR:' not in output
        results.append({'test':test,'passed':passed,'log':str((logs/(test+'.log')).relative_to(root))})
        print(test,'PASS' if passed else 'FAIL',flush=True)
    ledger['validation']=results
    ledger['validation_status']='passed' if all(r['passed'] for r in results) else 'failed'
    if package.name=='v011':
        source_report=root/'outputs/character_pipeline/v011/source_validation.json'
        report=json.loads(source_report.read_text())
        assert report['skeleton_sha256']==ledger['skeleton_sha256']
        for role in ['model','animation']:
            source=package/f'source/{role}/chr_bunny01_{role}_v011.blend'
            assert report[role+'_sha256']==hashlib.sha256(source.read_bytes()).hexdigest(),'Stale source validation'
        ledger['source_validation']=report
        ledger['forward_contract']={'blender':'+Y','godot':'-Z','additional_yaw_degrees':0}
        dep=root/'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v009/exports/anim_bunny01_library_v009.json'
        ledger['dependencies']=[{'path':str(dep.relative_to(root)),'sha256':hashlib.sha256(dep.read_bytes()).hexdigest(),'purpose':'six retained non-locomotion states'}]
    elif package.name=='v021':
        source_report=root/'outputs/character_pipeline/v021/validation.json'
        report=json.loads(source_report.read_text())
        assert report['skeleton_sha256']==ledger['skeleton_sha256']
        assert report['model_unchanged'] and max(v.get('grip_error',0) for v in report['clips'].values())<0.0001
        ledger['source_validation']=report
        ledger['forward_contract']={'blender':'+Y','godot':'-Z','additional_yaw_degrees':0}
        ledger['dependencies']=[]
    ledger['status']='validated' if all(r['passed'] for r in results) else 'imported_pending_validation'
    consumer=root/'scenes/Player3D.tscn'
    wrapper=str((package/f'runtime/chr_bunny01_root_{package.name}.tscn').relative_to(root))
    if ledger['status']=='validated' and ('res://'+wrapper) in consumer.read_text():
        ledger['status']='active'
        ledger['active_consumer']='scenes/Player3D.tscn'
    else:
        ledger.pop('active_consumer',None)
    ledger['remaining_work']=['武器动作覆盖仍采用现有实时程序姿势；后续可逐项替换为Blender剪辑并保留握持约束。','帽子/眼镜既有程序占位未重新建模。']
    ledger_path.write_text(json.dumps(ledger,ensure_ascii=False,indent=2))
    assert ledger['status'] in ('validated','active'),'Do not activate a failing bundle'

if __name__=='__main__':main()
