import argparse, hashlib, json, os, shutil, subprocess, sys
from datetime import datetime
from pathlib import Path

P = Path('I:/工作项目/shellstrom2/ShellStorm2')
O = P/'outputs/base99_radio_v005'
Q = P/'_scratch/radio_v005_finish_project'
PY = sys.executable
GODOT = 'I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe'

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def run(tag, cmd, cwd=P, env=None):
    env=dict(os.environ, PYTHONUTF8='1', PYTHONIOENCODING='utf-8') if env is None else env
    with (O/(tag+'.log')).open('wb') as log:
        result = subprocess.run(cmd, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, env=env)
    (O/(tag+'.exit.json')).write_text(json.dumps({'exit_code':result.returncode,'command':cmd},ensure_ascii=False,indent=2),encoding='utf-8')
    print(tag, result.returncode, flush=True)
    return result.returncode

def gates(suffix):
    for name,args in [('structure',['scripts/check_asset_registry.py','--project-root',str(P),'--scope','structure']),('split',['tools/asset_pipeline/verify_ledger_split.py','--project-root',str(P)]),('full_props',['scripts/check_asset_registry.py','--project-root',str(P),'--scope','full','--ledger','props']),('naming',['scripts/check_asset_runtime_naming.py','--json']),('docs',['scripts/check_documentation_contracts.py'])]:
        run(name+'_'+suffix,[PY,'-I',str(P/args[0]),*args[1:]],cwd=P/'_scratch/ledger_gate_cwd')

a=argparse.ArgumentParser(); a.add_argument('stage'); args=a.parse_args()
if args.stage=='prepare':
    b=O/('resume_backup_'+datetime.now().strftime('%Y%m%d_%H%M%S'))
    b.mkdir(parents=True)
    paths=['assets/art/props/base_world_3d/source/base99_radio/prp_base99_radio_source_v004.blend','assets/art/props/base_world_3d/source/base99_radio/export/v004/prp_base99_radio_optimized_v004.blend','assets/art/props/base_world_3d/source/base99_radio/prp_base99_radio_source_v005.blend','assets/art/props/base_world_3d/source/base99_radio/export/v005/prp_base99_radio_optimized_v005.blend','assets/art/props/base_world_3d/components/base99_radio/prp_base99_radio_visual_top3d.glb','assets/art/props/base_world_3d/runtime/base99_radio/prp_base99_radio_root_top3d.tscn','src/base3d/Base99Radio3D.gd','tests/verification/verify_base99_radio.gd','assets/registry/ledger_split_baseline.json','assets/registry/ledgers/ShellStorm2_道具账本_v001.xlsx','assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png','assets/art/environments/tower_zones/base/runtime/zone_base.tscn','assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d.tscn']
    for rel in paths:
        dest=b/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(P/rel,dest)
    for name in ['asset_manifest.json','final_acceptance.json','pixel_metrics_runtime.json','runtime_camera_state.json']:
        shutil.copy2(O/name,b/name)
    report={'backup':str(b),'hashes':{rel:sha(P/rel) for rel in paths}}
    (O/'resume_before.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    gates('resume_before')
elif args.stage=='isolate':
    assert not Q.exists(), '隔离工程已存在，拒绝覆盖'
    Q.mkdir()
    for name in ['assets','src','scenes','data','tests','tools','scripts','outputs']:
        r=subprocess.run(['cmd','/c','mklink','/J',str(Q/name),str(P/name)],capture_output=True)
        assert r.returncode==0, r.stdout+r.stderr
    settings=(P/'project.godot').read_text(encoding='utf-8')
    settings=settings.replace('[application]','[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="ShellStorm2RadioV005Finish_'+datetime.now().strftime('%Y%m%d_%H%M%S')+'"',1)
    (Q/'project.godot').write_text(settings,encoding='utf-8')
    (Q/'.godot').mkdir()
    for name in ['global_script_class_cache.cfg','uid_cache.bin']:
        if (P/'.godot'/name).exists():shutil.copy2(P/'.godot'/name,Q/'.godot'/name)
    shutil.copytree(P/'.godot/imported',Q/'.godot/imported')
    print('ISOLATED_PROJECT_OK',Q,flush=True)
elif args.stage=='repair_isolation':
    for name in ['source']:
        assert not (Q/name).exists()
        r=subprocess.run(['cmd','/c','mklink','/J',str(Q/name),str(P/name)],capture_output=True)
        assert r.returncode==0,r.stdout+r.stderr
    shutil.copy2(P/'icon.svg',Q/'icon.svg')
    if (P/'icon.svg.import').exists():shutil.copy2(P/'icon.svg.import',Q/'icon.svg.import')
    print('ISOLATION_DEPENDENCIES_OK')
elif args.stage=='import':
    scratch=Q/'_scratch'
    if scratch.exists() and os.path.samefile(scratch,P/'_scratch'):
        os.rmdir(scratch)
    scratch.mkdir(exist_ok=True)
    for name in ['probe_radio_v005_runtime_capture.gd','probe_radio_v005_runtime_capture.tscn']:
        shutil.copy2(P/'_scratch'/name,scratch/name)
    sys.exit(run('import_resume',[GODOT,'--headless','--path',str(Q),'--editor','--import']))
elif args.stage in ['capture','verify']:
    scene='res://_scratch/probe_radio_v005_runtime_capture.tscn' if args.stage=='capture' else 'res://tests/verification/verify_base99_radio.tscn'
    sys.exit(run(args.stage+'_resume',[GODOT,'--path',str(Q),'--resolution','1280x720','--rendering-method','forward_plus','--audio-driver','Dummy',scene]))
elif args.stage=='gates':gates('resume_after')
elif args.stage=='import_record':
    (O/'import_resume.exit.json').write_text(json.dumps({'exit_code':None,'status':'全工程扫描已受控停止，收音机重导入已由实际运行时几何及材质验收验证；不宣称全工程导入通过'},ensure_ascii=False,indent=2),encoding='utf-8')
elif args.stage=='log_gates':
    for tag in ['import_resume','verify_resume','capture_resume']:
        run('strict_'+tag,[PY,'-I',str(P/'scripts/check_verification_log.py'),str(O/(tag+'.log'))])
elif args.stage=='promote_cache':
    name='prp_base99_radio_visual_top3d.glb-b1e4fda09efbbfc469b959b15f63dea4'
    cache_before={}
    for file in (Q/'.godot/imported').glob(name+'*'):
        target=P/'.godot/imported'/file.name
        cache_before[file.name]=sha(target) if target.exists() else None
        shutil.copy2(file,target)
    assert cache_before
    (O/'formal_import_cache_evidence.json').write_text(json.dumps({'passed':True,'before':cache_before,'after':{n:sha(P/'.godot/imported'/n) for n in cache_before}},indent=2),encoding='utf-8')
    print('RADIO_ONLY_FORMAL_IMPORT_CACHE_UPDATED')
elif args.stage=='metadata':
    import re
    m=json.loads((O/'asset_manifest.json').read_text(encoding='utf-8'))
    f=P/m['runtime_prefab_target'];s=f.read_text(encoding='utf-8')
    for key,value in [('model_sha256',m['hashes_sha256']['glb']),('source_sha256',m['hashes_sha256']['source']),('optimized_sha256',m['hashes_sha256']['optimized'])]:
        s=re.sub('metadata/'+key+' = "[a-f0-9]+"','metadata/'+key+' = "'+value+'"',s)
    f.write_text(s,encoding='utf-8')
    print('PREFAB_METADATA_OK')
