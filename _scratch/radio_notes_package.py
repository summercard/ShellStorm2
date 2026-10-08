from pathlib import Path
import json,hashlib,re,subprocess,sys
R=Path('I:/工作项目/shellstrom2/ShellStorm2');O=R/'outputs/base99_radio_music_notes'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def dump(p,v):p.write_bytes((json.dumps(v,ensure_ascii=False,indent=2)+'\n').replace('\n','\r\n').encode())
rt=json.loads((O/'runtime_acceptance.json').read_text(encoding='utf-8'));assert rt['passed'];assert len(rt['checks'])>=44
nlog=(O/'testlogs/notes.log').read_text(encoding='utf-8');olog=(O/'testlogs/original_final.log').read_text(encoding='utf-8')
assert 'BASE99_RADIO_MUSIC_NOTES_OK' in nlog and 'ERROR:' not in nlog
assert 'BASE99_RADIO_OK' in olog and 'ERROR:' not in olog
protected=json.loads((O/'protected_before.json').read_text(encoding='utf-8'))
for rel,hashval in protected.items():assert sha(R/rel)==hashval,rel
files=['src/vfx/VfxRadioMusicNotes3D.gd','src/base3d/Base99Radio3D.gd','tests/verification/verify_base99_radio_music_notes.gd','tests/verification/verify_base99_radio_music_notes.tscn','tests/verification/verify_base99_radio.gd','assets/art/props/base_world_3d/runtime/base99_radio/prp_base99_radio_root_top3d.tscn','docs/v0.1/14.6_特效系统与制作规范.md','docs/v0.1/MODULE_INDEX.md']
files += [p.relative_to(R).as_posix() for p in (R/'assets/art/vfx/environment_3d/radio_music_notes').glob('*') if p.suffix in {'.tres','.tscn'}]
for rel in files:
 b=(R/rel).read_bytes();assert b.count(b'\n')==b.count(b'\r\n') and b'\r\r\n' not in b,rel
assert 'RADIO_INPUT_RECEIVED' not in (R/'src/base3d/Base99Radio3D.gd').read_text(encoding='utf-8')
assert not re.search(r'\bprint\s*\(', (R/'src/base3d/Base99Radio3D.gd').read_text(encoding='utf-8'))
script=(R/'src/vfx/VfxRadioMusicNotes3D.gd').read_text(encoding='utf-8')
assert all(x not in script for x in ['Mesh.new','QuadMesh.new','Image.create','add_child','queue_free'])
for rel in ['src/vfx/VfxRadioMusicNotes3D.gd','tests/verification/verify_base99_radio_music_notes.gd']:
 assert (R/(rel+'.uid')).exists()
cache=(R/'.godot/global_script_class_cache.cfg').read_text(encoding='utf-8');assert 'VfxRadioMusicNotes3D' in cache
manifest={'asset_id':'VFX-RADIO-MUSIC-NOTES-3D','asset_version':'v001','radio_runtime_version':'v005.1','model_version':'v005','prefab':'assets/art/vfx/environment_3d/radio_music_notes/vfx_radio_music_notes_root_top3d.tscn','implementation':'Godot离线生成ImageTexture三种音符剪影+五槽位QuadMesh PackedScene；独立脚本只驱动动画','budget':{'fixed_slots':5,'max_live':5,'triangles':10,'draws_max':5,'textures':3,'texture_size':[256,256],'radio_body_faces':599,'radio_body_triangles':1190},'parameters':{'births_per_second':2.5,'lifetime_seconds':1.8,'rise_m':1.1,'sway_m':0.09,'birth_lateral_m':0.22,'quad_size_m':[0.46,0.52],'scale_range':[0.88,1.06],'fade_in_s':0.16,'fade_out_s':0.45,'alpha_max':0.88,'local_anchor':[0,1.42,0]},'lifecycle':'radio child唯一宿主；不进VfxPool3D/CombatEffectPool3D；off隐藏所有五槽位并清空age和alpha','protected_hashes_unchanged':protected,'files':{rel:sha(R/rel) for rel in files}}
dump(O/'asset_manifest.json',manifest)
# 门禁逐项对照，不把全局既有红项写成全绿。
def report(name):return json.JSONDecoder().raw_decode((O/f'testlogs/{name}').read_text(encoding='utf-8').lstrip())[0]
gates={}
for d in ['props','vfx']:
 before=report(d+'_before.log');after=report(d+'_after.log');assert before['issues']==after['issues']
 gates[d]={'before_issues':before['issue_counts'],'after_issues':after['issue_counts'],'no_new_issues':True,'asset_count':after['asset_count']}
nb=report('naming_before.log');na=report('naming_after.log');assert nb==na
gates['naming']={'existing_debt_unchanged':True}
db=report('docs_before.log');da=report('docs_after.log');assert db['issues']==da['issues']
gates['docs']={'existing_issues_unchanged':True,'issues':da['issues']}
ex=json.loads((O/'testlogs/gates_after.json').read_text());assert ex['structure']==0 and ex['split']==0
final={'passed':True,'scope':'收音机持续音乐音符附件专项；不是全项目门禁全绿','runtime_checks':len(rt['checks']),'runtime_snapshot':'runtime_acceptance.json','original_radio':{'passed':True,'log':'testlogs/original_final.log','errors':0},'music_notes':{'passed':True,'log':'testlogs/notes.log','errors':0},'renderer':'Godot 4.6.3 Forward+ / RTX4060Ti真实窗口，正常Player3D相机','screenshots':[s['png'] for s in rt['samples']],'visual_review':'正常玩家镜头可见淡青绿/暖金音符；关闭图无音符；多帧位置上升；无新增发光/灯光，灯帽红绿逻辑不变','body_and_placement_unchanged':True,'ledger_evidence':'ledger_evidence.json','gates':gates,'structure_passed':True,'split_passed':True,'class_cache_and_uid_present':True,'CRLF_passed':True,'no_debug_print_added':True,'known_import_warnings':'旧GLB共享色盘缓存invalid UID，运行时按现有真路径加载；无新资源UID警告；本轮未修改GLB','retry_note':'一次并行真实窗口运行在资源加载期间退出3489660927，保留notes_final.log；最终单独复跑为依据。'}
dump(O/'final_acceptance.json',final)
print('RADIO_NOTES_FINAL_ACCEPTANCE_OK',len(rt['checks']))
