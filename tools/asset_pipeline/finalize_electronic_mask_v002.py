"""Promote verified component metadata and synchronize its final evidence only."""
import json,hashlib,re,sys,shutil,openpyxl
from pathlib import Path
from copy import deepcopy
from register_electronic_mask import ROOT,ASSET,ID,BASE,sha,rel,cells,LedgerIndex,read_source_rows,_row_digest,col_digest,CONTENT_COLUMNS,sheet_digest

def main():
    output=ROOT/'outputs/electronic_mask'
    flow=(output/'flow_v002.log').read_text('utf-8',errors='replace')
    render=(output/'render_v002.log').read_text('utf-8',errors='replace')
    checks=int(re.search(r'ELECTRONIC_MASK_FLOW_OK checks=(\d+)',flow)[1])
    render_checks=int(re.search(r'ELECTRONIC_MASK_FLOW_OK checks=(\d+)',render)[1])
    pixels=int(re.search(r'ELECTRONIC_MASK_RENDER blue_pixels=(\d+)',render)[1])
    source=json.loads((ASSET/'source_validation.json').read_text('utf-8'))
    assert source['result']=='pass' and source['authored_animation_curves_match']
    regression=json.loads((output/'regression_v002.json').read_text('utf-8-sig'))
    assert all(test['exit_code']==0 for test in regression)
    for path in [output/'flow_v002.log',output/'render_v002.log',*output.glob('v002_verify*.log')]:
        text=path.read_text('utf-8',errors='replace')
        assert not re.search(r'(?:SCRIPT ERROR:|(?:^|\s)ERROR:)',text),path
    original=json.loads((output/'v001/asset_manifest.json').read_text('utf-8'))
    original_entries=[e for e in original['files'] if e['role']=='dependency' or e['path'].endswith('_model_v001.blend')]
    assert all(sha(ROOT/e['path'])==e['sha256'] for e in original_entries),'Original source drift'
    validation={'source':'pass','headless_exit':0,'headless_checks':checks,'render_exit':0,'render_checks':render_checks,'real_renderer':'Forward+','blue_eye_pixels':pixels,'regression_scenes':[x['scene'] for x in regression],'regression_exit_codes':[x['exit_code'] for x in regression],'collision_unchanged':True,'original_model_and_animation_unchanged':True,'authored_clip_timing_and_sampling':'pass','autoplay':'pass','per_instance_material':'pass','registry_structure':'pass','ledger_split':'pass','date':'2026-10-01'}
    for name in ['asset_manifest.json','character_transfer_ledger.json']:
        path=ASSET/name; manifest=json.loads(path.read_text('utf-8'))
        for entry in manifest['files']: assert sha(ROOT/entry['path'])==entry['sha256'],entry['path']
        manifest.update(status='active',validation_status='pass',validation=validation)
        path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    # Only this asset's evidence cell/fingerprint changes; no other frozen asset is rebaselined.
    index=LedgerIndex.load(ROOT); path=index.path_for_category('角色')
    backup=output/'ledger_v002/before_final.xlsx'; shutil.copy2(path,backup)
    wb=openpyxl.load_workbook(path); before=cells(wb)
    baseline=json.loads(BASE.read_text('utf-8')); old=deepcopy(baseline)
    shutil.copy2(BASE,output/'ledger_v002/before_final_baseline.json')
    w=wb['资产主表']; row=next(r for r,v in read_source_rows(w) if v[0]==ID)
    w.cell(row,25).value=w.cell(row,25).value.replace('无头72项、Forward+75项',f'无头{checks}项、Forward+{render_checks}项')
    changed={k for k in set(before)|set(cells(wb)) if before.get(k)!=cells(wb).get(k)}
    assert changed<={('资产主表',f'Y{row}')}
    baseline['assets'][ID]={'v':_row_digest(next(v for _,v in read_source_rows(w) if v[0]==ID)),'c':'角色','d':'characters'}
    union=[]
    for domain in index.domains: union.extend(read_source_rows((wb if domain.key=='characters' else openpyxl.load_workbook(domain.path))['资产主表']))
    baseline['column_digests']={str(c):col_digest(union,c) for c in CONTENT_COLUMNS}
    assert all(baseline['assets'][k]==v for k,v in old['assets'].items() if k!=ID)
    temp=path.with_suffix('.mask_final_tmp.xlsx'); wb.save(temp)
    assert cells(openpyxl.load_workbook(temp))==cells(wb)
    temp.replace(path); BASE.write_text(json.dumps(baseline,ensure_ascii=False,indent=1)+'\n',encoding='utf-8')
    prior=openpyxl.load_workbook(output/'ledger_v002/before_main.xlsx')
    assert [c.value for c in prior['资产主表'][21]]==[c.value for c in wb['资产主表'][21]],'Unrelated chibi debt was changed'
    report={'version':'v002','source':source,'headless_flow':{'exit':0,'checks':checks},'forward_plus_render':{'exit':0,'checks':render_checks,'blue_eye_pixels':pixels,'blink_height_and_flicker_energy':'pass','animation_gif':'previews/godot_expression.gif'},'regression':regression,'expected_failures':[],'unexpected_script_errors':[],'unexecuted':['full game verification suite','mobile-device performance'],'logs_no_unexpected_errors':True,'asset_guard':'version_increment pass','ledger_structure':'pass','ledger_split':'pass','original_model_animation_and_v001_source_hashes_unchanged':True,'global_limits':{'documentation_exit':1,'unregistered_existing_tests':['verify_base99_swivel_chairs','verify_expedition01_spawn_ramp','verify_pushable_base_chairs'],'registry_full_exit':1,'registry_full_existing_issue':'chibi head r21 SHA mismatch; before/after row unchanged','runtime_naming_exit':1,'runtime_naming_existing_debt':True,'new_mask_runtime_paths_stable':True},'date':'2026-10-01'}
    (ASSET/'verification_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (output/'ledger_v002/final_transaction.json').write_text(json.dumps({'changed_cells':sorted(changed),'other_asset_fingerprints_preserved':len(old['assets'])-1},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('ELECTRONIC_MASK_V002_FINALIZED',checks,render_checks)

if __name__=='__main__': main()
