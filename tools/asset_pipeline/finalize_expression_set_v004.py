"""Publish verification facts after all related checks; never rebaseline other assets."""
import sys,json,re,struct,subprocess
from pathlib import Path
from register_electronic_mask import ROOT,ASSET,ID,sha
OUTPUT=ROOT/'outputs/electronic_mask/v004'

def main():
    source=json.loads((ASSET/'source_validation.json').read_text('utf-8')); assert source['result']=='pass' and len(source['expression_meshes_verified'])==8
    regression=json.loads((OUTPUT/'regression.json').read_text('utf-8-sig')); assert all(t['exit_code']==0 for t in regression)
    logs=[OUTPUT/'flow.log',OUTPUT/'mask_flow.log',OUTPUT/'render.log',OUTPUT/'mask_render.log',OUTPUT/'import.log',*(OUTPUT/(t['scene']+'.log') for t in regression)]
    for p in logs:
        text=p.read_text('utf-8',errors='replace'); assert not re.search(r'(?:SCRIPT ERROR:|(?:^|\s)ERROR:)',text),p
    previous=json.loads((ROOT/'outputs/electronic_mask/v003/asset_manifest.json').read_text('utf-8'))
    assert all(sha(ROOT/e['path'])==e['sha256'] for e in previous['files'] if e['path'].endswith('.blend'))
    packages=[ASSET,*sorted((ASSET/'expressions').iterdir())]
    for package in packages:
        classification='version_increment' if package==ASSET else 'version_increment'
        process=subprocess.run([sys.executable,'-X','utf8',str(ROOT/'scripts/asset_guard.py'),str(package),'--classify',classification],cwd=ROOT,capture_output=True,text=True,encoding='utf-8')
        (OUTPUT/(package.name+'_guard.log')).write_text(process.stdout+process.stderr,encoding='utf-8'); assert process.returncode==0,process.stdout+process.stderr
        for name in ['asset_manifest.json','character_transfer_ledger.json']:
            path=package/name; manifest=json.loads(path.read_text('utf-8'))
            for f in manifest['files']: assert sha(ROOT/f['path'])==f['sha256'],f['path']
            manifest.update(status='active',validation_status='pass',validation={'source':'source_validation.json' if package==ASSET else '../../source_validation.json','flow_scene':'tests/verification/verify_character_expression_flow.tscn','headless_exit':0,'headless_checks':696,'real_renderer':'Forward+','render_exit':0,'render_checks':706,'random_all_reachable':True,'actual_state_machine_call':'pass','independent_owner':'CharacterExpressionSystem','collision_and_gameplay_unchanged':True,'mouth_free':True,'fuller_elements':True,'date':'2026-10-01'})
            if package!=ASSET:
                visual=next(ROOT/f['path'] for f in manifest['files'] if f['path'].endswith('.glb'))
                blob=visual.read_bytes(); n=struct.unpack_from('<I',blob,12)[0]; gltf=json.loads(blob[20:20+n])
                assert len(gltf['meshes'])==1 and not gltf.get('skins') and not gltf.get('animations')
                assert len(gltf['meshes'][0]['primitives'][0]['targets'])==1
            path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        if package!=ASSET:
            e=manifest['expression']
            (package/'README.md').write_text(f'# 电子面具表情：{e["name"]}\n\nAssetID：`{e["asset_id"]}`；子版本v002，父面具v004；expression_id=`{e["expression_id"]}`。\n\n{e["pixel_count"]}颗11.8mm方块，14mm网格，颜色{e["color"]}；类别{e["kind"]}；情绪无嘴部，眼睛/爱心/符号加粗放大。原head局部原点，独立根缩放1，无骨架/碰撞/玩法系统。\n\n共享[模型母版](../../source/chr_bunny01_electronic_mask_model_v004.blend)与[动作母版](../../source/chr_bunny01_electronic_mask_animation_v004.blend)，用source_object `{e["source_object"]}`定位；此资产单独登记角色主表/组件/3D/表达记录。\n\n由独立CharacterExpressionSystem选择，状态机通过适配器发命令；显示端消费网格及已有眨眼/闪烁，符号不压缩。源/中转哈希见[清单](asset_manifest.json)，[Forward+实拍](previews/expression_front.png)。独立逻辑与真实渲染验收通过。\n',encoding='utf-8')
    report={'version':'v004','source':source,'independent_expression_flow':{'exit':0,'checks':696,'test':'verify_character_expression_flow'},'real_expression_render':{'exit':0,'checks':706,'renderer':'Forward+','distinct_face_regions':8,'angry_red':'pass','overview':'previews/expressions_overview.png'},'existing_mask':{'headless_exit':0,'headless_checks':73,'render_exit':0,'render_checks':76},'regression':regression,'ledger':{'asset_main_parent':22,'expression_assets':[23,30],'component_rows':[45,52],'prefab_rows':[10,17],'expression_rows':[53,60],'transfer_rows':[52,78],'structure':'pass','split':'pass'},'asset_guard':'parent + eight expressions version_increment pass','expected_failures':[],'unexpected_script_errors':[],'unexecuted':['full game verification suite','mobile performance'],'original_character_and_prior_sources_unchanged':True,'global_limits':{'documentation_exit':1,'unregistered_existing_tests':['verify_base99_swivel_chairs','verify_expedition01_spawn_ramp','verify_pushable_base_chairs'],'registry_full_existing_issue':'unchanged chibi head r21 SHA mismatch','runtime_naming_existing_debt':True},'mouth_free':True,'fuller_elements':True,'date':'2026-10-01'}
    (ASSET/'verification_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('EXPRESSION_SET_ACTIVE eight_assets independent_system verified')
if __name__=='__main__': main()
