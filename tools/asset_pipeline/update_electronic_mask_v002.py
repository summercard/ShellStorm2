"""Targeted same-ID version promotion; main and locked-sheet transactions separate."""
import json,sys,shutil,openpyxl
from copy import deepcopy
from collections import Counter
from datetime import datetime
from register_electronic_mask import ROOT,ASSET,ID,PREFAB,GLB,BASE,rel,sha,cells,append,gates
from register_electronic_mask import LedgerIndex,read_source_rows,_row_digest,col_digest,CONTENT_COLUMNS,sheet_digest

OUT=ROOT/'outputs/electronic_mask/ledger_v002'

def main():
    phase=sys.argv[1]; assert phase in ['main','prefab']
    OUT.mkdir(parents=True,exist_ok=True)
    index=LedgerIndex.load(ROOT); path=index.path_for_category('角色')
    shutil.copy2(path,OUT/f'before_{phase}.xlsx'); shutil.copy2(BASE,OUT/f'before_{phase}_baseline.json')
    wb=openpyxl.load_workbook(path); before=cells(wb)
    baseline=json.loads(BASE.read_text('utf-8')); old=deepcopy(baseline)
    allowed=set(); rows_changed={}
    def setcell(w,row,col,value):
        cell=w.cell(row,col); cell.value=value; allowed.add((w.title,cell.coordinate))
    def row_for(w,column,value):
        found=[r for r in range(1,w.max_row+1) if w.cell(r,column).value==value]
        assert len(found)==1,(w.title,value,found)
        return found[0]
    def add(w,values,template):
        r=append(w,values,template)
        allowed.update((w.title,c.coordinate) for c in w[r] if c.value is not None)
        return r
    if phase=='main':
        w=wb['资产主表']; r=row_for(w,1,ID)
        updates={9:'mask_idle(12s循环) / mask_blink(0.26s) / mask_flicker(0.42s)；面饰局部剪辑，非玩家状态',13:'v002',14:'两组5×14共140颗；颗粒10.8mm/间距14mm；每眼66.8×192.8mm；Blink闭眼曲面形态键；Blender线性亮度曲线；独立AnimationPlayer；根缩放1/无碰撞',20:sha(PREFAB),22:datetime(2026,10,1),25:'v002同ID升级，version_increment；模型/动作双母版共享SKEL-BUNNY01-004签名。原角色11网格/骨架/头部动作及v001源保留；glasses默认与换装/读档沿用。源曲线核对、无头72项、Forward+75项通过；12秒循环自动眨眼及间歇闪烁；同演员独立材质。开发记录2026-10-01_bunny_electronic_mask_v002.md。'}
        for c,v in updates.items(): setcell(w,r,c,v)
        rows_changed['asset_main']=r
        log=wb['域变更日志']
        add(log,['v0.1.6','2026-10-01','电子面具眼睛放大与局部动画','角色 / Bunny01 / glasses',f'{ID}升级v002；140颗大方块，眨眼与间歇闪烁；原角色/旧源保留。','同ID同稳定运行路径升级；只修改本资产行与指纹，专表另事务登记。','Codex'],11)
        values=next(v for _,v in read_source_rows(w) if v[0]==ID)
        baseline['assets'][ID]={'v':_row_digest(values),'c':'角色','d':'characters'}
        union=[]
        for domain in index.domains:
            union.extend(read_source_rows((wb if domain.key=='characters' else openpyxl.load_workbook(domain.path))['资产主表']))
        baseline['column_digests']={str(c):col_digest(union,c) for c in CONTENT_COLUMNS}
        baseline['category_counts']=dict(sorted(Counter(v[2] for _,v in union).items()))
    else:
        w=wb['角色组件']; r=row_for(w,2,'glasses/electronic_mask')
        setcell(w,r,10,'继承head姿态；ExpressionPlayer消费Blender mask_idle(12s循环)、mask_blink(0.26s)、mask_flicker(0.42s)')
        setcell(w,r,13,f'{ID}；v002；140颗10.8mm方块；Blink形态键；每实例独立发光材质；纯局部表现，不增加玩家状态或碰撞。')
        rows_changed['component']=r; baseline['sheet_digests'][w.title]=sheet_digest(w)
        w=wb['3D-角色']; r=row_for(w,1,ID)
        setcell(w,r,5,rel(ASSET/'source/chr_bunny01_electronic_mask_model_v002.blend'))
        setcell(w,r,7,'src/player3d/PlayerAvatar3D.gd；src/player3d/customization/ElectronicMaskExpression3D.gd')
        setcell(w,r,15,'v002')
        setcell(w,r,16,'v002模型/动作双母版，共享原骨架且保留原角色。GLB内2网格及Blink形态键，曲线中转JSON→AnimationLibrary→局部AnimationPlayer；默认12s循环两次眨眼、两段闪烁。实际渲染及换装读档通过。')
        rows_changed['prefab']=r; baseline['sheet_digests'][w.title]=sheet_digest(w)
        w=wb['动画与状态']; rows_changed['clips']=[]
        for name,duration,loop,description in [('mask_idle',12,True,'2.8/7.2s眨眼；5.1/10.1s短闪；首尾张眼亮度1'),('mask_blink',.26,False,'0.09s闭眼→0.16s结束保持→0.26s张眼'),('mask_flicker',.42,False,'亮度1→0.18→1→0.35→1→0.55→1，0.42s回稳')]:
            assert not any(w.cell(r,2).value==name for r in range(1,w.max_row+1))
            rows_changed['clips'].append(add(w,['面饰局部剪辑（非玩家状态）',name,f'电子面具：{description}','ExpressionPlayer / Blender独立动作母版','局部剪辑结束恢复张眼/亮度1；不跳转玩家状态','保持原姿态','只对面具Blink与发光强度采样','不修改','不修改WeaponSocket','不修改',f'{duration}s；循环={loop}；glasses/electronic_mask',f'{ID} v002；LINEAR；AnimationLibrary来自Blender曲线；verify_electronic_mask_flow通过。'],6))
        baseline['sheet_digests'][w.title]=sheet_digest(w)
        w=wb['角色中转记录']; rows_changed['transfer']=[]
        manifest=json.loads((ASSET/'character_transfer_ledger.json').read_text('utf-8'))
        for entry in manifest['files']:
            if entry['role']=='dependency': continue
            rows_changed['transfer'].append(add(w,[f'电子面具v002/{PathRole(entry["path"])}',entry['path'],entry['sha256'],entry['bytes']],4))
        baseline['sheet_digests'][w.title]=sheet_digest(w)
    after=cells(wb); changed={k for k in set(before)|set(after) if before.get(k)!=after.get(k)}
    assert changed<=allowed,changed-allowed
    assert all(baseline['assets'][k]==v for k,v in old['assets'].items() if k!=ID),'Other asset fingerprint drift'
    assert set(old['assets'])==set(baseline['assets']),'Unexpected new asset'
    temp=path.with_suffix('.mask_v002_tmp.xlsx'); wb.save(temp)
    assert cells(openpyxl.load_workbook(temp))==after
    temp.replace(path); BASE.write_text(json.dumps(baseline,ensure_ascii=False,indent=1)+'\n',encoding='utf-8')
    report={'phase':phase,'rows':rows_changed,'changed_cells':sorted(changed),'other_asset_fingerprints_preserved':len(old['assets'])-1,'sha256':sha(path)}
    (OUT/f'{phase}_transaction.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    gates('v002_'+phase)
    print('ELECTRONIC_MASK_V002_LEDGER_OK',json.dumps(report,ensure_ascii=False))

def PathRole(path):
    if path.endswith('.blend'): return '动作母版' if '_animation_' in path else '模型母版'
    if path.endswith('.glb'): return '视觉与形态键'
    if path.endswith('.tres'): return '动画库'
    if path.endswith('.json'): return '曲线中转'
    if path.endswith('.gd'): return '局部表现适配器'
    return '运行包装'

if __name__=='__main__': main()
