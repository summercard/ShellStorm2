import json,hashlib,subprocess,sys
from pathlib import Path
from PIL import Image,ImageDraw,ImageChops
P=Path('I:/工作项目/shellstrom2/ShellStorm2');O=P/'outputs/base99_radio_v004'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def load(n):
 data=(O/n).read_bytes()
 try:text=data.decode('utf-8')
 except UnicodeDecodeError:text=data.decode('gb18030')
 return json.JSONDecoder().raw_decode(text.lstrip())[0]
results=[]
for name,args in [('structure',['scripts/check_asset_registry.py','--project-root',str(P),'--scope','structure']),('full_props',['scripts/check_asset_registry.py','--project-root',str(P),'--scope','full','--ledger','props']),('split',['tools/asset_pipeline/verify_ledger_split.py','--project-root',str(P)]),('naming',['scripts/check_asset_runtime_naming.py','--json']),('docs',['scripts/check_documentation_contracts.py'])]:
 r=subprocess.run([sys.executable,'-I',str(P/args[0]),*args[1:]],cwd=P,capture_output=True)
 (O/(name+'_after.log')).write_bytes(r.stdout+r.stderr)
 results.append({'name':name,'exit_code':r.returncode,'log':name+'_after.log'})
 print(name,r.returncode)
a=load('full_props_before.log');b=load('full_props_after.log')
assert a['issues']==b['issues'], '其他道具红项改变，禁止接受'
assert all(sha(Path(issue['path']))==issue['actual'] for issue in a['issues']['sha_mismatch']), '既有红项的实际文件哈希改变'
assert all(x['asset_id']!='PRP-BASE99-RADIO-3D' for x in b['issues']['sha_mismatch'])
assert next(r['exit_code'] for r in results if r['name']=='structure')==0
assert next(r['exit_code'] for r in results if r['name']=='split')==0
existing_gate_comparison={}
for name in ['naming','docs']:
 before=load(name+'_before.log');after=load(name+'_after.log')
 keys=['new_versioned_files','new_versioned_dirs','new_backup_residue','reference_count_increase','remaining'] if name=='naming' else ['issues']
 assert all(before[k]==after[k] for k in keys), '既有门禁问题发生变化：'+name
 existing_gate_comparison[name]={'issue_records_unchanged':True,'compared_fields':keys}
for name in ['validate_source_final.json','validate_optimized_final.json','optimization_evidence.json','registration_evidence.json']:
 assert load(name)['passed'],name
runtime=[]
for filename,marker in [('verify_window_final.log','BASE99_RADIO_OK'),('placement.log','PLACEMENT_ACCEPTED=true'),('facility_regression_final.log','TOWER_BASE_FACILITY_PERSISTENT_OK'),('native_visual_complete.log','RADIO_VISUAL_STATE=b')]:
 text=(O/filename).read_text(encoding='utf-8',errors='replace');assert marker in text
 assert 'ObjectDB instances leaked at exit' not in text and 'resources still in use at exit' not in text, '退出资源泄漏：'+filename
 r=subprocess.run([sys.executable,'-I',str(P/'scripts/check_verification_log.py'),str(O/filename)],capture_output=True)
 runtime.append({'log':filename,'exit_code':r.returncode,'marker':marker,'audit_output':r.stdout.decode('utf-8',errors='replace')})
 assert r.returncode==0,(filename,r.stdout,r.stderr)
protected=load('before_hashes.json')
locked=[p for p in protected if 'layout_top3d' in p or 'zone_base.tscn' in p or 'shared/palette' in p or 'v003.blend' in p]
assert all(sha(P/p)==protected[p] for p in locked)
images={};radio_box=(525,260,750,445)
for n in ['before_v003_closeup','radio_off_closeup','radio_a_closeup','radio_b_closeup','attic_off','attic_a','attic_b']:
 im=Image.open(O/(n+'.png')).convert('RGB')
 roi=im.crop(radio_box) if 'closeup' in n else im
 pixels=list(roi.getdata());clipped=sum(min(v)>=250 for v in pixels)
 images[n]={'size':list(im.size),'region':list(radio_box) if 'closeup' in n else 'whole','white_clipped_pixels':clipped,'pixels':len(pixels),'white_clipped_fraction':clipped/len(pixels)}
# 对照图仅排版，不代替原生PNG。
items=['before_v003_closeup','radio_off_closeup','radio_a_closeup','radio_b_closeup']
# 采用原生帧不缩放的两列对照。
board=Image.new('RGB',(2560,1480),(15,18,25));draw=ImageDraw.Draw(board)
for i,n in enumerate(items):
 x=(i%2)*1280;y=(i//2)*740
 board.paste(Image.open(O/(n+'.png')).convert('RGB'),(x,y+20));draw.text((x+12,y+3),n,fill='white')
board.save(O/'comparison.png')
m=load('asset_manifest.json')
for key,path in [('source',Path(m['source_blend'])),('optimized',Path(m['optimized_blend'])),('glb',Path(m['component_glb'])),('prefab',P/m['runtime_prefab_target'])]:
 assert sha(path)==m['hashes_sha256'][key], '最终资产哈希漂移：'+key
accept={'asset_id':m['asset_id'],'version':'v004','radio_acceptance_passed':True,'project_all_gates_passed':False,'faces':m['faces'],'triangles':m['triangles'],'dimensions_width_depth_height_m':m['dimensions_width_depth_height_m'],'materials':m['materials'],'hashes_sha256':m['hashes_sha256'],'status_light':m['status_light'],'antenna':m['antenna'],'registration_evidence':'registration_evidence.json','strict_uv_valid_faces':load('validate_source_final.json')['valid_island_polygon_count'],'tests':results,'existing_gate_comparison':existing_gate_comparison,'runtime_log_audits':runtime,'remaining_props_sha_mismatch':len(b['issues']['sha_mismatch']),'remaining_props_issue_records_exactly_unchanged':True,'locked_files_hashes_unchanged':{p:protected[p] for p in locked},'image_metrics':images,'visual_review':'同实际主相机俯视轴；机身铜橙与黑柜可分辨，护框金属局部高光，天线单根可见；仅小灯红/绿发光，未调整场景曝光、环境灯或共享色盘。','not_executed':['全项目core/full完整游戏套件','人工硬件鼠标操作；本次为真实引擎事件派发'],'no_new_markdown':True}
(O/'final_acceptance.json').write_text(json.dumps(accept,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('RADIO_V004_FINAL_ACCEPTANCE_OK')
