import hashlib, json, re
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path('I:/工作项目/shellstrom2/ShellStorm2'); OUT=ROOT/'outputs/base99_radio_v005'
def load(name):return json.loads((OUT/name).read_text(encoding='utf-8'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def log(name):return (OUT/name).read_text(encoding='utf-8',errors='replace')
def result(name):return load(name+'.exit.json')['exit_code']
def json_log(name):
    raw=(OUT/name).read_bytes()
    try:text=raw.decode('utf-8')
    except UnicodeDecodeError:text=raw.decode('gbk')
    return json.JSONDecoder().raw_decode(text[text.index('{'):])[0]
manifest=load('asset_manifest.json'); pixels=load('pixel_metrics_runtime.json')
paths={'source':Path(manifest['source_blend']),'optimized':Path(manifest['optimized_blend']),'glb':Path(manifest['component_glb']),'prefab':ROOT/manifest['runtime_prefab_target']}
manifest['hashes_sha256'].update({key:sha(path) for key,path in paths.items()})
source=load('validation/validate_source_resume.json'); optimized=load('validation/validate_optimized_resume.json');locked=load('locked_geometry_current.json');geometry=load('lamp_geometry_assertions.json');audit=load('optimization_evidence_resume.json');ledger=load('ledger_v005_evidence.json')
interaction=log('verify_resume.log');capture=log('capture_resume.log')
strict={tag:result('strict_'+tag) for tag in ['import_resume','verify_resume','capture_resume']}
full=json_log('full_props_resume_after.log')
before=json_log('full_props_resume_before.log')
before_issues=before['issues']; after_issues=full['issues']
def signature(issues):
    return sorted((kind,str(x.get('asset_id')),str(x.get('recorded')),str(x.get('actual'))) for kind,values in issues.items() for x in values if x.get('asset_id')!=manifest['asset_id'])
existing_equal=signature(before_issues)==signature(after_issues)
radio_issues=[x for values in after_issues.values() for x in values if x.get('asset_id')==manifest['asset_id']]
ledger_hash_match=all(ledger[key+'_sha256']==manifest['hashes_sha256'][key] for key in paths)
gates={
 'source_uv_material':{'passed':source['passed'],'report':'validation/validate_source_resume.json'},
 'optimized_uv_material':{'passed':optimized['passed'],'report':'validation/validate_optimized_resume.json'},
 'locked_geometry':{'passed':locked['locked_match'],'report':'locked_geometry_current.json'},
 'independent_optimization':{'passed':audit['passed'],'report':'optimization_evidence_resume.json'},
 'lamp_geometry_orientation_occlusion':{'passed':geometry['passed'],'report':'lamp_geometry_assertions.json'},
 'structure':{'passed':result('structure_resume_after')==0,'exit':result('structure_resume_after'),'report':'structure_resume_after.log'},
 'split':{'passed':result('split_resume_after')==0,'exit':result('split_resume_after'),'report':'split_resume_after.log'},
 'full_props':{'passed':result('full_props_resume_after')==0,'exit':result('full_props_resume_after'),'existing_issues_unchanged':existing_equal,'radio_issues':radio_issues,'issues':after_issues,'report':'full_props_resume_after.log'},
 'runtime_interaction':{'passed':result('verify_resume')==0 and 'BASE99_RADIO_OK' in interaction and 'SCRIPT ERROR' not in interaction and 'BASE99_RADIO_FAIL' not in interaction,'exit':result('verify_resume'),'report':'verify_resume.log','real_input_dispatch':True,'mouse_E_cycle_floor_stop_music':True},
 'strict_engine_logs':{'passed':all(v==0 for v in strict.values()),'exits':strict},
 'formal_radio_import_cache':{'passed':load('formal_import_cache_evidence.json')['passed'],'report':'formal_import_cache_evidence.json'},
 'runtime_capture':{'passed':result('capture_resume')==0 and 'RUNTIME_CAPTURE_V005_OK' in capture and 'SCRIPT ERROR' not in capture,'exit':result('capture_resume'),'report':'capture_resume.log','renderer':'Vulkan Forward+ RTX4060Ti','resolution':[1280,720]},
 'ledger_current_hash':{'passed':ledger_hash_match,'report':'ledger_v005_evidence.json'},
 'normal_player_full_attic_visibility':{'passed':pixels['visibility_passed'],'report':'pixel_metrics_runtime.json','threshold':pixels['threshold']},
 'naming':{'passed':result('naming_resume_after')==0,'exit':result('naming_resume_after'),'report':'naming_resume_after.log'},
 'docs':{'passed':result('docs_resume_after')==0,'exit':result('docs_resume_after'),'report':'docs_resume_after.log'},
}
# 每张原图保持1280x720，横拼仅作为证据排版，不缩放游戏帧。
comparisons=[]
for mode,left,right in [('player_off','runtime_before_v004_player.png','runtime_after_off_player.png'),('player_green','runtime_before_v004_green_player.png','runtime_after_a_player.png'),('attic_off','runtime_before_v004_attic_off.png','attic_off.png'),('attic_green','runtime_before_v004_attic_green.png','attic_a.png')]:
    images=[Image.open(OUT/p).convert('RGB') for p in [left,right]]
    assert all(i.size==(1280,720) for i in images)
    canvas=Image.new('RGB',(2560,750),(20,24,32));canvas.paste(images[0],(0,30));canvas.paste(images[1],(1280,30))
    d=ImageDraw.Draw(canvas);d.text((15,9),'v004 | original 1280 x 720',fill='white');d.text((1295,9),'v005 | original 1280 x 720',fill='white')
    name='comparison_'+mode+'.png';canvas.save(OUT/name); comparisons.append(name)
naming_before=json_log('naming_resume_before.log'); naming_after=json_log('naming_resume_after.log')
gates['naming']['existing_issues_unchanged']=naming_before==naming_after
docs_before=json_log('docs_resume_before.log');docs_after=json_log('docs_resume_after.log')
gates['docs']['existing_issues_unchanged']=docs_before['issues']==docs_after['issues']
required=[v['passed'] for k,v in gates.items() if k not in ['full_props','naming','docs']]
passed=all(required) and existing_equal and not radio_issues and gates['naming']['existing_issues_unchanged'] and gates['docs']['existing_issues_unchanged']
manifest['gates']=gates;manifest['acceptance_status']='radio_accepted_with_existing_global_gate_debt' if passed else 'partial_delivery'
manifest['visual_evidence']={'resolution':[1280,720],'normal_player_fov':65,'attic_reference_fov':65,'attic_note':'全阁楼独立参考相机，保持玩家FOV与俯视角，不冒充玩家实际位置；前后完全同镜头。','camera_state':'runtime_camera_state.json','normal_off':'runtime_after_off_player.png','normal_green':'runtime_after_a_player.png','attic_off':'attic_off.png','attic_green':'attic_a.png','closeup_off':'runtime_after_off_closeup.png','closeup_green':'runtime_after_a_closeup.png','comparisons':comparisons}
manifest['pixel_measurement']=pixels
manifest['import_scope_note']='收音机专项重导入与实际运行验证完成；全工程--import扫描已受控停止，不宣称全工程导入或全量套件通过。'
manifest['visual_review']={'normal_player_and_attic_reviewed':True,'red_green_recognizable':True,'no_lamp_white_burnout':True,'source_geometry_only_no_ui_fake_lamp':True}
report={'import_scope_note':manifest['import_scope_note'],'visual_review':manifest['visual_review'],'asset_id':manifest['asset_id'],'version':'v005','passed':passed,'full_props_global_passed':gates['full_props']['passed'],'actual_geometry':{key:manifest[key] for key in ['faces','triangles','dimensions_width_depth_height_m','status_light','root_scale']},'gates':gates,'pixel_measurement':pixels,'visual_evidence':manifest['visual_evidence'],'ledger':ledger,'hashes_sha256':manifest['hashes_sha256'],'delivery':{key:path.as_posix() for key,path in paths.items()},'no_new_markdown':True,'unfinished':[k for k,v in gates.items() if not v['passed']]}
for name,value in [('asset_manifest.json',manifest),('final_acceptance.json',report)]:
    (OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('RADIO_V005_FINAL',passed,'FULL_PROPS',gates['full_props']['passed'])
print(json.dumps(pixels['same_camera_comparisons'],ensure_ascii=False,indent=2))
