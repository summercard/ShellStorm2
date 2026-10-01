"""Verified eight-expression promotion: main rows and locked sheets separately."""
import sys,json,shutil,openpyxl
from pathlib import Path
from copy import deepcopy
from collections import Counter
from register_electronic_mask import ROOT,ASSET,ID,PREFAB,GLB,BASE,rel,sha,cells,append,gates,LedgerIndex,read_source_rows,_row_digest,col_digest,CONTENT_COLUMNS,sheet_digest
sys.path.insert(0,str(ROOT/'scripts/blender'))
from electronic_mask_expression_definitions import EXPRESSIONS,asset_id,slug,pixels
OUTPUT=ROOT/'outputs/electronic_mask/v005'

def main():
    phase=sys.argv[1]; assert phase in ['main','tables']
    index=LedgerIndex.load(ROOT); path=index.path_for_category('角色')
    shutil.copy2(path,OUTPUT/f'ledger_before_{phase}.xlsx'); shutil.copy2(BASE,OUTPUT/f'baseline_before_{phase}.json')
    wb=openpyxl.load_workbook(path); before=cells(wb); baseline=json.loads(BASE.read_text('utf-8')); old=deepcopy(baseline)
    allowed=set(); rows={}; touched=[ID]+[asset_id(e[0]) for e in EXPRESSIONS]
    def change(w,r,c,value):
        w.cell(r,c).value=value; allowed.add((w.title,w.cell(r,c).coordinate))
    def find(w,c,value):
        matches=[r for r in range(1,w.max_row+1) if w.cell(r,c).value==value]; assert len(matches)==1,(w.title,value); return matches[0]
    def add(w,values,template):
        if phase=='tables' and w.title in ['角色组件','3D-角色','动画与状态']:
            column=1 if w.title=='3D-角色' else 2
            if w.title=='动画与状态':
                matches=[r for r in range(1,w.max_row+1) if w.cell(r,1).value==values[0] and w.cell(r,2).value==values[1]]
                assert len(matches)==1; r=matches[0]
            else: r=find(w,column,values[column-1])
            for c,value in enumerate(values,1): change(w,r,c,value)
            return r
        r=append(w,values,template); allowed.update((w.title,c.coordinate) for c in w[r] if c.value is not None); return r
    manifests=[json.loads((ASSET/'expressions'/slug(e[0])/'asset_manifest.json').read_text('utf-8')) for e in EXPRESSIONS]
    if phase=='main':
        w=wb['资产主表']; r=find(w,1,ID)
        for c,v in {9:'8种网格表情；mask_idle/blink/flicker；独立系统随机与状态事件调用',13:'v005',14:'原黑色面具+8种独立方块网格；自发光1.25（降低75%）；情绪无嘴；眼睛/爱心/符号饱满加粗；11.8mm颗粒/14mm网格；生气红色；单位根/原head契约',20:sha(PREFAB),25:'v005同ID version_increment；独立CharacterExpressionSystem拥有选择/随机/保持，PlayerExpressionStateAdapter消费真实状态事件，面具只显示。8种表情自发光1.25；无嘴部且图案饱满；原11网格/骨架及v001–v004源保留；8种表情分别登记子资产。源、8种Forward+图、独立系统/实际状态调用和眨眼/闪烁/换装专项通过。'}.items(): change(w,r,c,v)
        for entry in manifests:
            expression=entry['expression']; r=find(w,1,entry['asset_id']); root=ROOT/expression['scene']
            for c,v in {11:'正式美术已接入',13:'v003',14:f'{expression["pixel_count"]}颗11.8mm方块/14mm网格；自发光1.25；情绪无嘴部；图案加粗放大；{expression["color"]}；独立根缩放1',15:rel(root),16:'docs/v0.1/design/character_expression_system.md；src/presentation/expressions/CharacterExpressionSystem.gd',20:sha(root),25:f'version_increment；父{ID} v005；共享v005模型/动作双母版与SKEL-BUNNY01-004签名；独立稳定GLB/Prefab；{expression["pixel_count"]}颗方块，颜色{expression["color"]}，符号不闭眼；随机可达/命令/实际状态事件/Forward+真实渲染通过。'}.items(): change(w,r,c,v)
        rows['assets']={aid:find(w,1,aid) for aid in touched}
        log=wb['域变更日志']; rows['log']=add(log,['v0.1.9','2026-10-01','降低8种表情自发光与光晕','角色 / Bunny01 / 面饰', '父面具升级v005，八个既有表情子资产升级v003；八种材质自发光5→1.25，降低75%；保持无嘴部、饱满网格、11.8mm颗粒及眨眼/闪烁、独立系统和状态调用。','保留其余资产指纹；父/八子主行与组件/动画/3D/中转专表分事务更新。','Codex'],12)
        for _,values in read_source_rows(w):
            if values[0] in touched: baseline['assets'][values[0]]={'v':_row_digest(values),'c':'角色','d':'characters'}
        union=[]
        for domain in index.domains: union.extend(read_source_rows((wb if domain.key=='characters' else openpyxl.load_workbook(domain.path))['资产主表']))
        baseline['column_digests']={str(c):col_digest(union,c) for c in CONTENT_COLUMNS}
        baseline['category_counts']=dict(sorted(Counter(v[2] for _,v in union).items()))
    else:
        model=ASSET/'source/chr_bunny01_electronic_mask_model_v005.blend'
        w=wb['角色组件']; r=find(w,2,'glasses/electronic_mask')
        change(w,r,10,'继承head姿态；局部Blink/闪烁；独立CharacterExpressionSystem选择8种网格，状态事件适配器调用')
        change(w,r,13,f'{ID} v005；8种发光强度1.25；8个无嘴部表达子组件；11.8mm颗粒、加粗眼睛/爱心/符号；生气红色，?和!为符号；无玩法/碰撞权威。')
        rows['components']=[]
        for entry in manifests:
            e=entry['expression']; visual=next(f['path'] for f in entry['files'] if f['path'].endswith('.glb'))
            rows['components'].append(add(w,['player_capsule01_bunny01_3d','glasses/expression/'+e['expression_id'],'HeadJoint/FaceAccessorySocket/ElectronicMask/Visual/ExpressionPixels','head',visual,'14mm网格/11.8mm颗粒；发光1.25；运行时继承角色比例','HeadJoint原点；原脸曲面前移9mm','Blender +Y / Godot -Z；独立根缩放1',5,'无嘴部；加粗眼睛/爱心/符号；独立系统命令/随机/状态调用；共用Blender局部剪辑','只替换面具表情，不更换面饰配置','否',f'{e["asset_id"]}；{e["name"]}；{e["kind"]}；{e["color"]}；{e["pixel_count"]}颗；v003；共享父v005双母版'],44))
        baseline['sheet_digests'][w.title]=sheet_digest(w)
        w=wb['3D-角色']; r=find(w,1,ID)
        for c,v in {5:rel(model),7:'src/presentation/expressions/CharacterExpressionSystem.gd；src/player3d/PlayerExpressionStateAdapter.gd；src/player3d/customization/ElectronicMaskExpression3D.gd',15:'v005',16:'原头部/骨架/动作不变；8独立表达子Prefab/GLB，选择/随机/保持由独立系统拥有，真实状态事件只发命令；显示共用Blink/亮度剪辑。'}.items(): change(w,r,c,v)
        rows['prefabs']=[]
        for entry in manifests:
            e=entry['expression']; visual=next(f['path'] for f in entry['files'] if f['path'].endswith('.glb'))
            rows['prefabs'].append(add(w,[e['asset_id'],'电子面具表情：'+e['name'],e['scene'],visual,rel(model),'独立无嘴部方块网格表达组件','src/presentation/expressions/CharacterExpressionSystem.gd；src/player3d/customization/ElectronicMaskExpression3D.gd','无','Player3D玩法根','不增加任何玩法碰撞','14mm网格/11.8mm颗粒；根缩放1','HeadJoint局部；Blender +Y / Godot -Z','独立角色表情系统；可移植到其他显示端','正式美术已接入','v003',f'父{ID} v005；{e["kind"]}；{e["color"]}；{e["pixel_count"]}颗；发光1.25；8种随机可达与Forward+独立渲染通过；依赖父v005双母版。'],9))
        change(w,2,1,'玩家、NPC、角色表现/玩法根、制作母版与独立表情组件；表情逐项登记。')
        baseline['sheet_digests'][w.title]=sheet_digest(w)
        w=wb['动画与状态']; rows['expressions']=[]
        for r in range(1,w.max_row+1):
            if w.cell(r,2).value in ['mask_idle','mask_blink','mask_flicker']:
                change(w,r,12,w.cell(r,12).value.replace('v004','v005'))
        for entry in manifests:
            e=entry['expression']
            rows['expressions'].append(add(w,['面饰网格表情（非玩法状态）',e['expression_id'],e['name'],'独立系统request_expression / 随机 / 状态适配命令','其他表情；保持结束恢复背景随机','保持原动作','只显示面具方块网格','不改变','不改变武器','不改变',e['color']+'；'+e['kind'],e['asset_id']+f'；子v003/父v005；{e["pixel_count"]}颗11.8mm方块；无嘴部且图案加粗；独立Prefab；随机不重复；保持/拒绝/状态调用/真实渲染通过。'],50))
        baseline['sheet_digests'][w.title]=sheet_digest(w)
        w=wb['角色中转记录']; rows['transfer']=[]
        parent=json.loads((ASSET/'character_transfer_ledger.json').read_text('utf-8'))
        for entry in [parent,*manifests]:
            for f in entry['files']:
                if f['role']=='dependency': continue
                rows['transfer'].append(add(w,[entry['asset_id']+' '+entry['version'],f['path'],f['sha256'],f['bytes']],4))
        baseline['sheet_digests'][w.title]=sheet_digest(w)
    changed={k for k in set(before)|set(cells(wb)) if before.get(k)!=cells(wb).get(k)}; assert changed<=allowed
    assert all(baseline['assets'][k]==v for k,v in old['assets'].items() if k not in touched)
    assert set(old['assets'])==set(baseline['assets'])
    tmp=path.with_suffix('.expr_promote_tmp.xlsx'); wb.save(tmp); assert cells(openpyxl.load_workbook(tmp))==cells(wb); tmp.replace(path)
    BASE.write_text(json.dumps(baseline,ensure_ascii=False,indent=1)+'\n',encoding='utf-8')
    (OUTPUT/f'ledger_{phase}_transaction.json').write_text(json.dumps({'phase':phase,'rows':rows,'changed_cells':sorted(changed),'other_asset_fingerprints_preserved':len(old['assets'])-len(touched)},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    gates('expressions_v005_'+phase); print('EXPRESSION_LEDGER_PROMOTED',phase,json.dumps(rows,ensure_ascii=False))
if __name__=='__main__': main()
