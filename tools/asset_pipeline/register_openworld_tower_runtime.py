"""Promote ONLY accepted tower assets; append actual component/crane prefabs.

Uses the project's ledger-specific openpyxl contract; preserves unrelated hashes.
"""
import hashlib
import json
import re
import shutil
import sys
from copy import copy
from collections import Counter
from datetime import date
from pathlib import Path
from openpyxl import load_workbook

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
from ledger_registry import LedgerIndex
from split_asset_ledger import FIRST_DATA_ROW, CONTENT_COLUMNS, _row_digest, col_digest, dedupe_key_formula, dedupe_result_formula, read_source_rows, sheet_digest


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value, indent=2):
    path.write_text(json.dumps(value,ensure_ascii=False,indent=indent)+'\n',encoding='utf-8',newline='\r\n')


def main():
    index=LedgerIndex.load(ROOT)
    domain=next(d for d in index.domains if d.key=='scenes')
    baseline_path=ROOT/'assets/registry/ledger_split_baseline.json'
    base=ROOT/'assets/art/environments/open_world'
    acceptance=json.loads((base/'runtime/import_acceptance.json').read_text(encoding='utf8'))
    assert not acceptance['failures'] and acceptance['checks'] >= 2769
    backup=ROOT/'_scratch/openworld_runtime_ledger_backup'
    backup.mkdir(parents=True,exist_ok=True)
    for p in [domain.path,index.master_path,baseline_path]:
        if not (backup/p.name).exists(): shutil.copy2(p,backup/p.name)
    wb=load_workbook(domain.path)
    ws=wb['资产主表']
    old=ws.max_row
    known={ws.cell(r,1).value:r for r in range(FIRST_DATA_ROW,old+1)}
    changed=set()
    registrations=[]
    for slug,version in [('tower_02','v003'),('tower_03','v001')]:
        manifest=json.loads((base/'source'/slug/'export'/version/'export_manifest.json').read_text(encoding='utf8'))
        catalog_path=base/'source'/slug/version/'catalog.json'
        catalog=json.loads(catalog_path.read_text(encoding='utf8'))
        assert sha(ROOT/manifest['source'])==manifest['source_sha256']
        tower_path=f'assets/art/environments/open_world/runtime/{slug}/env_{slug}_root_top3d.tscn'
        registrations.append(dict(asset_id=catalog['asset_id'],name=ws.cell(known[catalog['asset_id']],2).value,
                                  path=tower_path,glb='',source=manifest['source'],version=version,
                                  slug=slug,slot='building_root',spec='主体'+('70×50m；施工屋顶' if slug=='tower_02' else '70×44m；屋顶40m、机房8m'),parent=None))
        for record in manifest['records']:
            assert (ROOT/record['prefab']).is_file()
            registrations.append(dict(asset_id=record['asset_id'],name=('塔2 ' if slug=='tower_02' else '塔楼03 ')+record['display_name'],
                                      path=record['prefab'],glb=record['glb'],source=manifest['source'],version=version,
                                      slug=slug,slot=record['slug'],spec='×'.join('%.3f'%v for v in record['dimensions'])+'m (Blender XYZ)',parent=catalog['asset_id']))
        for crane in catalog.get('crane_assemblies',[]):
            cs=crane['assembly_id'].split('/')[-1]
            path=f'assets/art/environments/open_world/runtime/{slug}/cranes/{cs}/env_{slug}_{cs}_root_top3d.tscn'
            registrations.append(dict(asset_id=catalog['asset_id']+'-'+cs.upper().replace('_','-'),name='塔2 '+crane['collection'],
                                      path=path,glb='',source=manifest['source'],version=version,slug=slug,slot=cs,
                                      spec='独立塔吊；7个可编辑组件；底部塔身中心原点',parent=catalog['asset_id']))
        catalog.update(runtime_integrated=True,ledger_status='已导入；优化完成',runtime_prefab=tower_path)
        lookup={r['slug']:r for r in manifest['records']}
        for package in catalog['packages']:
            record=lookup[package['slug']]
            package.update(exported=True,runtime_prefab=record['prefab'],runtime_glb=record['glb'],runtime_asset_id=record['asset_id'],collision_status='none_visual_only')
            package_path=catalog_path.parent/package.get('manifest_path',f"component_packages/{package['category']}/{package['slug']}/asset_manifest.json")
            if package_path.exists():
                package_manifest=json.loads(package_path.read_text(encoding='utf-8-sig'))
                package_manifest.update(exported=True,runtime_prefab=record['prefab'],runtime_glb=record['glb'],runtime_asset_id=record['asset_id'],collision_status='none_visual_only')
                write_json(package_path,package_manifest)
        for crane in catalog.get('crane_assemblies',[]): crane['exported']=True
        write_json(catalog_path,catalog)
    for record in registrations:
        aid=record['asset_id']
        r=known.get(aid)
        if r is None:
            r=ws.max_row+1
            for col in range(1,26): ws.cell(r,col)._style=copy(ws.cell(old,col)._style)
            ws.row_dimensions[r].height=ws.row_dimensions[old].height
            values={1:aid,2:record['name'],3:'场景',4:'environment_module_3d',5:'open_world_'+record['slug'],6:record['slot'],
                    7:record['parent'],8:'Top3D / Godot Y-up',9:'default',10:'开放世界塔楼独立可复用组件',12:'P1',
                    16:'docs/v0.1/development/2026-09-30_openworld_towers_runtime_import.md',17:record['name'],
                    23:'用户参考图；项目自制模型',24:record['slot']}
            for col,value in values.items(): ws.cell(r,col,value)
        else:
            ws.cell(r,6,record['slot'])
            ws.cell(r,8,'Top3D / Godot Y-up')
        updates={11:'已导入；优化完成',13:record['version'],14:record['spec'],15:record['path'],20:sha(ROOT/record['path']),
                 21:'Codex',22:date.today(),25:'仅表现；无碰撞、导航或玩法脚本；原始Blender保留不变。源：'+record['source']}
        for col,value in updates.items(): ws.cell(r,col,value)
        changed.add(aid)
    last=ws.max_row
    for r in range(FIRST_DATA_ROW,last+1):
        ws.cell(r,18,dedupe_key_formula(r));ws.cell(r,19,dedupe_result_formula(r,last))
    for row in wb['总览']:
        for cell in row:
            if cell.data_type=='f': cell.value=re.sub(r'(\$[A-Z]+\$)'+str(old)+r'\b',lambda m:m[1]+str(last),cell.value)
    for dv in ws.data_validations.dataValidation:
        ranges=[]
        for item in dv.sqref.ranges:
            item=copy(item)
            if item.max_row==old:item.max_row=last
            ranges.append(str(item))
        dv.sqref=' '.join(ranges)
    for cf in list(ws.conditional_formatting):
        rules=ws.conditional_formatting[cf]
        ranges=[]
        for item in cf.sqref.ranges:
            item=copy(item)
            if item.max_row==old:item.max_row=last
            ranges.append(str(item))
        del ws.conditional_formatting[' '.join(str(item) for item in cf.sqref.ranges)]
        for rule in rules:ws.conditional_formatting.add(' '.join(ranges),rule)
    ws.auto_filter.ref=f'A{FIRST_DATA_ROW-1}:Y{last}'
    log=wb['域变更日志']
    message='塔2 v003、塔楼03 v001；309组件、3独立塔吊、2建筑组合场景；只更新本批身份与哈希。'
    while log.cell(log.max_row,5).value==message and log.cell(log.max_row-1,5).value==message:
        log.delete_rows(log.max_row)
    if log.cell(log.max_row,5).value!=message:
        latest=log.cell(log.max_row,1).value
        bits=latest.split('.');bits[-1]=str(int(bits[-1])+1)
        log.append(['.'.join(bits),date.today(),'导入开放世界塔楼','关卡场景 / PackedScene',message,'仅表现，主场景由用户调用。','Codex'])
    # Transaction 1: identity/status rows + targeted baseline only.
    wb.save(domain.path)
    ws=load_workbook(domain.path)['资产主表']  # date serialization normalizes to datetime
    baseline=json.loads(baseline_path.read_text(encoding='utf8'))
    for _,values in read_source_rows(ws):
        if values[0] in changed:baseline['assets'][values[0]]={'v':_row_digest(values),'c':values[2],'d':'scenes'}
    all_rows=[]
    for d in index.domains:
        book=load_workbook(d.path)
        all_rows.extend((values[0],values) for _,values in read_source_rows(book['资产主表']))
    all_rows.sort(key=lambda item:item[0])
    baseline['asset_count']=len(baseline['assets'])
    baseline['category_counts']=dict(Counter(values[2] for _,values in all_rows))
    baseline['column_digests']={str(c):col_digest(all_rows,c) for c in CONTENT_COLUMNS}
    write_json(baseline_path,baseline,1)
    # Transaction 2: actual new Prefabs only, independently update their page digest.
    wb=load_workbook(domain.path)
    page=wb['3D-场景通用']
    page_old=page.max_row
    page_rows={page.cell(r,1).value:r for r in range(FIRST_DATA_ROW,page.max_row+1)}
    for record in registrations:
        r=page_rows.get(record['asset_id'],page.max_row+1)
        for col in range(1,17):page.cell(r,col)._style=copy(page.cell(page_old,col)._style)
        vals=[record['asset_id'],record['name'],record['path'],record['glb'],record['source'],'仅表现',None,
              '无','无','无',record['spec'],'底部中心；Blender -Y→Godot +Z','开放世界场景','已导入；优化完成',record['version'],
              '组合场景引用稳定组件Prefab；无功能碰撞。']
        for c,v in enumerate(vals,1):page.cell(r,c).value=v
        page.row_dimensions[r].height=page.row_dimensions[page_old].height
    page.auto_filter.ref=f'A{FIRST_DATA_ROW-1}:P{page.max_row}'
    wb.save(domain.path)
    baseline['sheet_digests']['3D-场景通用']=sheet_digest(page)
    write_json(baseline_path,baseline,1)
    master=load_workbook(index.master_path)
    for offset,d in enumerate(index.domains):
        if d.key=='scenes':master['分账本索引'].cell(FIRST_DATA_ROW+offset,7,last-FIRST_DATA_ROW+1)
    control=master['3D Prefab总控']
    for row in control:
        if any(c.value=='3D-场景通用' for c in row):
            actual=[values for values in page.values if isinstance(values[0],str) and re.fullmatch(r'[A-Z0-9]+(?:-[A-Z0-9]+)+',values[0])]
            row[2].value=len(actual)
            row[3].value=sum(bool(values[3]) for values in actual)
            row[4].value=sum(bool(values[6]) for values in actual)
            row[5].value=sum(values[7]=='开' for values in actual)
    master.save(index.master_path)
    print('OPENWORLD_RUNTIME_LEDGER_OK',len(registrations),'prefabs',last-FIRST_DATA_ROW+1,'scene rows')


if __name__=='__main__':main()
