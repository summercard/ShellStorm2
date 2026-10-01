"""Pre-register eight child components before Blender authoring; preserve other rows."""
import sys,json,shutil,openpyxl,re
from copy import copy,deepcopy
from collections import Counter
from pathlib import Path
from register_electronic_mask import ROOT,ASSET,ID,BASE,OUT,cells,rel,gates,LedgerIndex,read_source_rows,HEADER_ROW,FIRST_DATA_ROW,dedupe_key_formula,dedupe_result_formula,_row_digest,col_digest,CONTENT_COLUMNS
sys.path.insert(0,str(ROOT/'scripts/blender'))
from electronic_mask_expression_definitions_v003 import EXPRESSIONS,asset_id,slug,pixels

def main():
    path=LedgerIndex.load(ROOT).path_for_category('角色'); output=ROOT/'outputs/electronic_mask/v003'; output.mkdir(parents=True,exist_ok=True)
    shutil.copy2(path,output/'ledger_before_register.xlsx'); shutil.copy2(BASE,output/'baseline_before_register.json')
    wb=openpyxl.load_workbook(path); before=cells(wb); baseline=json.loads(BASE.read_text('utf-8')); old=deepcopy(baseline)
    w=wb['资产主表']; existing=read_source_rows(w); last=HEADER_ROW+len(existing); allowed=set()
    for i,(key,name,kind,color,_,blink) in enumerate(EXPRESSIONS,1):
        aid=asset_id(key); assert aid not in baseline['assets']
        row=last+i
        values=[aid,'电子面具表情：'+name,'角色','player_accessory','player_capsule01_expression_'+key,'glasses',ID,'3D/正面+俯视',key,'独立角色表情系统','待制作','P1','v001',f'{kind}；{len(pixels(key))}颗10.8mm方块；颜色{color}；blink={blink}；头部局部根缩放1','', 'docs/v0.1/design/character_expression_system.md',f'网格表情;情绪;符号;{name};{key}',dedupe_key_formula(row),dedupe_result_formula(row,last+8),'','Codex','2026-10-01','用户要求；原创方块网格排布','01_部件/眼镜/眼镜__electronic_mask/表情__'+key,'八种独立子组件逐项登记；父电子面具v003；共享角色骨架契约，纯视觉，无碰撞/玩法权威。']
        for c,value in enumerate(values,1):
            w.cell(row,c)._style=copy(w.cell(last,c)._style); w.cell(row,c).value=value if value!='' else None; allowed.add((w.title,w.cell(row,c).coordinate))
        w.row_dimensions[row].height=w.row_dimensions[last].height
    for row in range(FIRST_DATA_ROW,last+9):
        w.cell(row,19).value=dedupe_result_formula(row,last+8); allowed.add((w.title,f'S{row}'))
    for coordinate in ['A6','C6','E6','G6','B10','C10','B11','C11']:
        cell=wb['总览'][coordinate]; assert f'${last}' in cell.value
        cell.value=cell.value.replace(f'${last}',f'${last+8}'); allowed.add(('总览',coordinate))
    for dv in w.data_validations.dataValidation:
        for area in dv.sqref.ranges:
            if area.min_row==FIRST_DATA_ROW and area.max_row<last+8: area.max_row=last+8
    if w.auto_filter.ref: w.auto_filter.ref=f'A{HEADER_ROW}:Y{last+8}'
    for _,values in read_source_rows(w):
        if values[0] in [asset_id(e[0]) for e in EXPRESSIONS]: baseline['assets'][values[0]]={'v':_row_digest(values),'c':'角色','d':'characters'}
    index=LedgerIndex.load(ROOT); union=[]
    for domain in index.domains: union.extend(read_source_rows((wb if domain.key=='characters' else openpyxl.load_workbook(domain.path))['资产主表']))
    baseline['asset_count']=len(baseline['assets']); baseline['category_counts']=dict(sorted(Counter(v[2] for _,v in union).items()))
    baseline['column_digests']={str(c):col_digest(union,c) for c in CONTENT_COLUMNS}
    assert all(baseline['assets'][k]==v for k,v in old['assets'].items())
    changed={k for k in set(before)|set(cells(wb)) if before.get(k)!=cells(wb).get(k)}; assert changed<=allowed
    tmp=path.with_suffix('.expr_register_tmp.xlsx'); wb.save(tmp); assert cells(openpyxl.load_workbook(tmp))==cells(wb); tmp.replace(path)
    BASE.write_text(json.dumps(baseline,ensure_ascii=False,indent=1)+'\n',encoding='utf-8')
    (output/'register_transaction.json').write_text(json.dumps({'asset_rows':[last+1,last+8],'historical_fingerprints_preserved':len(old['assets']),'changed_cells':sorted(changed)},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    gates('expressions_v003_registered'); print('EXPRESSION_ASSETS_REGISTERED',last+1,last+8)
if __name__=='__main__': main()
