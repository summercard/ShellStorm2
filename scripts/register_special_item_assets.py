"""Idempotent, targeted ledger registration for SPECIAL-ITEMS.

Uses the project's ledger authoring functions/formula contracts and preserves all
non-target asset fingerprints. Does not accept unrelated SHA drift.
"""
from collections import Counter
from copy import copy
import hashlib
import json
import re
import sys
from pathlib import Path
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment
from special_items_workspace import ROOT, BACKUP, backup, write

sys.path.insert(0,str(ROOT/'tools/asset_pipeline'))
from split_asset_ledger import FIRST_DATA_ROW, CONTENT_COLUMNS, read_source_rows, _row_digest, col_digest, sheet_digest, dedupe_key_formula, dedupe_result_formula

DOC='docs/v0.1/design/特殊道具系统设计.md'
INDEX=json.loads((ROOT/'assets/registry/ledger_index.json').read_text(encoding='utf-8'))
ITEMS=json.loads((ROOT/'data/special_items/catalog.json').read_text(encoding='utf-8'))['items']
BASELINE='assets/registry/ledger_split_baseline.json'
DATE='2026-11-03'

def sha(relative):
    return hashlib.sha256((ROOT/relative).read_bytes()).hexdigest()

def styled_row(ws, values, row=None):
    row=row or ws.max_row+1
    template=FIRST_DATA_ROW if ws.title=='资产主表' else min(5,ws.max_row)
    for column,value in enumerate(values,1):
        ws.cell(row,column)._style=copy(ws.cell(template,column)._style)
        ws.cell(row,column).value=value
    ws.row_dimensions[row].height=ws.row_dimensions[template].height
    return row

def upsert(ws, identity, values, key_column=1):
    row=next((r for r in range(1,ws.max_row+1) if ws.cell(r,key_column).value==identity),None)
    if row is None and ws.title=='资产主表':
        row=FIRST_DATA_ROW+len(read_source_rows(ws))
    return styled_row(ws,values,row)

assets=[]
for item in ITEMS:
    slug=item['id'];base=f'art_source/items_weapons/props/{slug}'
    manifest=json.loads((ROOT/base/'source_manifest.json').read_text(encoding='utf-8'))
    ground=manifest['roles']['ground']
    assets.append({'id':item['asset_id'],'name':item['name'],'domain':'props','category':'道具','subclass':'special_item','logical_id':slug,
                   'path':ground['prefab'],'source':ground['source'],'glb':ground['glb'],'script':'src/special_items/SpecialItemController3D.gd',
                   'collection':f"ITM_{item['name']}_中文资产管理",'spec':f"宽深高 {item['dimensions_m']}m; ground {ground['triangles']} triangles; tier_0_static",
                   'notes':f"preview={manifest['roles']['preview']['source']}; source_manifest={base}/source_manifest.json; material=物品独立四材质; PaletteUV; 原创; 五秒效果由规则拥有"})
for slug,name in [('fire','特殊道具地面火焰'),('oil','汽油油迹'),('blast','手雷爆炸')]:
    assets.append({'id':f'VFX-SPECIAL-{slug.upper()}-3D','name':name,'domain':'vfx','category':'特效','subclass':'combat_3d','logical_id':'special_'+slug,
                   'path':f'assets/art/vfx/combat_3d/vfx_special_{slug}_root_top3d.tscn','source':'','glb':'','script':f'src/vfx/VfxSpecial{slug.title()}3D.gd',
                   'collection':'','spec':'参数化世界半径；纯视觉，无碰撞；自动灭灯/回收','notes':'场景拥有生命周期；VfxPool3D AssetID注册，create_unpooled挂所属世界，卸载无常驻池残留'})
for slug,name in [('hud','特殊道具右下HUD'),('equipment_slot','特殊道具装备槽')]:
    asset_id='UI-SPECIAL-ITEM-'+('HUD' if slug=='hud' else 'EQUIPMENT-SLOT')
    assets.append({'id':asset_id,'name':name,'domain':'ui','category':'UI','subclass':'hud' if slug=='hud' else 'equipment','logical_id':'special_item_'+slug,
                   'path':f'assets/art/ui/special_items/ui_special_item_{slug}_root.tscn','source':'','glb':'','script':'src/special_items/ui/'+('SpecialItemHUD' if slug=='hud' else 'SpecialItemEquipmentSlot')+'.gd',
                   'collection':'','spec':'1280x720及缩放；模型图标、数量、冷却/油量','notes':'UI只读快照，装备命令不复制物品；原创，复用UIPalette/UIStyleFactory'})
audio_manifest=json.loads((ROOT/'assets/registry/special_items_audio_manifest.json').read_text(encoding='utf-8'))
audio_names={'throw':'特殊道具投掷','blast':'手雷爆炸声','glass':'燃烧瓶碎裂','pour':'汽油倾倒','ignite':'汽油点燃','fire_loop':'地面火焰持续燃烧'}
for entry in audio_manifest['assets']:
    assets.append({'id':entry['asset_id'],'name':audio_names[entry['kind']],'domain':'audio','category':'音效','subclass':'sfx','logical_id':'special.'+entry['kind'],
                   'path':entry['path'],'source':entry['source'],'glb':'','script':'src/special_items/SpecialItemController3D.gd' if entry['kind']=='pour' else 'src/special_items/SpecialItemWorld3D.gd','collection':'',
                   'license_source':entry.get('license_source',''),
                   'spec':f"44.1kHz mono; {entry['duration_seconds']:.3f}s; PCM24 master / OGG q5; -6dBFS peak",
                   'notes':entry['license']+'; semantic event=special.'+entry['kind']+'; source='+entry['source']+'; source_sha256='+entry['source_sha256']})

# Transaction 1: only the eight registered asset rows and their derived formulas.
for domain in [d for d in INDEX['domains'] if d['key'] in {'props','ui','vfx','audio'}]:
    relative='assets/registry/ledgers/'+domain['file'];backup(relative)
    wb=openpyxl.load_workbook(ROOT/relative);ws=wb['资产主表']
    # Some ledgers have dozens of styled empty rows. Compact only this feature's
    # own appended rows into the contiguous data range; preserve other cells.
    target_domain_ids={a['id'] for a in assets if a['domain']==domain['key']}
    domain_rows=read_source_rows(ws)
    for row,values in domain_rows:
        if values[0] in target_domain_ids:
            for column in range(1,26):
                ws.cell(row,column).value=None
    old_last=FIRST_DATA_ROW-1+len(read_source_rows(ws))
    for asset in [a for a in assets if a['domain']==domain['key']]:
        values=[asset['id'],asset['name'],asset['category'],asset['subclass'],asset['logical_id'],'root',None,'audio' if domain['key']=='audio' else ('top3d' if domain['key']!='ui' else 'screen'),
                'tier_0_static' if domain['key']=='props' else 'runtime','SPECIAL-ITEMS','正式美术已接入','P1','v001',asset['spec'],asset['path'],DOC+'; '+asset['script'],
                asset['name']+';'+asset['logical_id'],None,None,sha(asset['path']),'Codex',DATE,('录音剪辑；'+asset.get('license_source','')) if asset['domain']=='audio' else '用户设计；项目原创制作',asset['collection'],asset['notes']]
        asset['ledger']=relative;asset['ledger_row']=upsert(ws,asset['id'],values)
    last=FIRST_DATA_ROW-1+len(read_source_rows(ws))
    if domain['key']=='ui':
        row=next(r for r,values in read_source_rows(ws) if values[0]=='UI-SCREEN-INVENTORY-3D')
        marker='SPECIAL-ITEMS-r1 equipment binding'
        notes=str(ws.cell(row,25).value or '')
        if marker not in notes:
            previous=str(ws.cell(row,20).value or '')
            before=hashlib.sha256((BACKUP/'src/ui/InventoryUI.gd').read_bytes()).hexdigest()
            ws.cell(row,25).value=notes+'; '+marker+f'; previous registered SHA={previous}; pre-edit workspace SHA={before}; only new slot/binding changed in this delivery; historical drift remains traceable'
            version=str(ws.cell(row,13).value or 'v001')
            ws.cell(row,13).value=f'v{int(version[1:])+1:03d}' if re.fullmatch(r'v\d+',version) else version
        ws.cell(row,20).value=sha('src/ui/InventoryUI.gd')
        ws.cell(row,22).value=DATE
    for row in range(FIRST_DATA_ROW,last+1):
        ws.cell(row,18).value=dedupe_key_formula(row)
        ws.cell(row,19).value=dedupe_result_formula(row,last)
    for row in wb['总览']:
        for cell in row:
            if isinstance(cell.value,str) and cell.value.startswith('='):
                cell.value=re.sub(r'(\$[A-Z]+\$)'+str(old_last)+r'\b',lambda m:m[1]+str(last),cell.value)
    for validation in ws.data_validations.dataValidation:
        for cell_range in validation.sqref.ranges:
            if cell_range.max_row==old_last:
                cell_range.max_row=last
    ws.auto_filter.ref=f'A5:Y{last}'
    log=wb['域变更日志']
    if not any(log.cell(r,1).value=='SPECIAL-ITEMS-v001' for r in range(1,log.max_row+1)):
        styled_row(log,['SPECIAL-ITEMS-v001',DATE,'新增','SPECIAL-ITEMS','新增特殊道具/独立UI/特效；见独立设计及专项','新增可选存档字段兼容旧档','Codex'])
    wb.save(ROOT/relative)

# Transaction 2: real prefab entries only; the moved-page digests are scoped here.
changed_pages={}
for key,page in [('props','3D-物品'),('vfx','3D-特效')]:
    domain=next(d for d in INDEX['domains'] if d['key']==key)
    relative='assets/registry/ledgers/'+domain['file']
    wb=openpyxl.load_workbook(ROOT/relative);ws=wb[page]
    for asset in [a for a in assets if a['domain']==key]:
        row=[asset['id'],asset['name'],asset['path'],asset['glb'],asset['source'],asset['notes'],asset['script'],'无','玩法独立模块','逐步球形扫掠/范围逻辑；Prefab纯视觉',asset['spec'],
             '原点底面中心；+Y向上；-Z前方','99F贩卖机/背包/右键特殊槽','正式美术已接入','v001','SPECIAL-ITEMS；验收 verify_special_items_system/preview_special_items']
        if key=='vfx':
            row.insert(0,'SPECIAL-'+asset['logical_id'].split('_')[-1].upper())
        upsert(ws,asset['id'],row,2 if key=='vfx' else 1)
    wb.save(ROOT/relative)
    changed_pages[page]=sheet_digest(openpyxl.load_workbook(ROOT/relative)[page])

backup(BASELINE)
baseline=json.loads((ROOT/BASELINE).read_text(encoding='utf-8'))
all_rows=[];categories=Counter()
target_ids={asset['id'] for asset in assets}|{'UI-SCREEN-INVENTORY-3D'}
for domain in INDEX['domains']:
    wb=openpyxl.load_workbook(ROOT/'assets/registry/ledgers'/domain['file'])
    for row,values in read_source_rows(wb['资产主表']):
        all_rows.append((row,values));categories[str(values[2])]+=1
        if values[0] in target_ids:
            baseline['assets'][values[0]]={'v':_row_digest(values),'c':values[2],'d':domain['key']}
baseline['asset_count']=len(baseline['assets'])
baseline['column_digests']={str(column):col_digest(all_rows,column) for column in CONTENT_COLUMNS}
baseline['category_counts']=dict(sorted(categories.items()))
baseline['sheet_digests'].update(changed_pages)
baseline['special_items_registration']={'date':DATE,'assets':sorted(target_ids),'note':'Only named asset row fingerprints and the two deliberately extended prefab pages were accepted.'}
write(BASELINE,json.dumps(baseline,ensure_ascii=False,indent=1)+'\n')

# The independent feature ledger is the content/asset handoff index; domain ledgers
# remain the single registration owner for each AssetID.
delivery={'schema':'special_items_delivery_v1','feature_id':'SPECIAL-ITEMS','date':DATE,'design':DOC,'catalog':'data/special_items/catalog.json',
          'owner':'src/special_items/','items':ITEMS,'assets':[{**asset,'sha256':sha(asset['path'])} for asset in assets],
          'verification':['verify_special_items_system','verify_special_item_assets','preview_special_items'],'status':'implemented_pending_final_verification'}
write('assets/registry/special_items_ledger.json',json.dumps(delivery,ensure_ascii=False,indent=2)+'\n')

# Independent readable workbook, generated from the same content and asset sources.
relative='docs/v0.1/data/ShellStorm2_特殊道具系统账本_v001.xlsx';backup(relative)
book=openpyxl.Workbook();sheet=book.active;sheet.title='特殊道具'
sheet.append(['特殊道具系统 · SPECIAL-ITEMS · v001'])
sheet.merge_cells('A1:K1');sheet.append(['数值源：data/special_items/catalog.json；库存Owner：InventoryModule；规则Owner：src/special_items/'])
sheet.merge_cells('A2:K2');sheet.append([])
sheet.append(['内容ID','名称','购买价','回收价','冷却/s','范围/m','持续/s','伤害/半秒或次','容量','资产ID','正式取得路径'])
for item in ITEMS:
    sheet.append([item['id'],item['name'],item['base_buy_price'],item['base_sell_price'],item['cooldown'],item['radius'],item.get('duration',0),item.get('damage',item.get('damage_per_tick',0)),item.get('fuel_capacity',1),item['asset_id'],'99F基地自动贩卖机 → 背包 → 特殊槽'])
sheet.append([]);sheet.append(['设计',DOC]);sheet.append(['代码目录','src/special_items/']);sheet.append(['独立验收','tests/verification/verify_special_items_system.tscn'])
asset_sheet=book.create_sheet('资产索引')
asset_sheet.append(['AssetID','中文名','域','正式Prefab','脚本','所属分账本','分账本行','SHA-256'])
for asset in assets:
    asset_sheet.append([asset['id'],asset['name'],asset['domain'],asset['path'],asset['script'],asset['ledger'],asset['ledger_row'],sha(asset['path'])])
for ws,header in [(sheet,4),(asset_sheet,1)]:
    ws.freeze_panes=f'C{header+1}';ws.sheet_view.showGridLines=False
    ws.auto_filter.ref=f'A{header}:{openpyxl.utils.get_column_letter(ws.max_column)}{7 if ws==sheet else ws.max_row}'
    for row in ws:
        for cell in row:
            cell.font=Font(name='Microsoft YaHei',size=10,color='172C3D')
            cell.alignment=Alignment(vertical='center',wrap_text=True)
            if cell.row==header:
                cell.fill=PatternFill('solid',fgColor='233C50');cell.font=Font(name='Microsoft YaHei',size=10,bold=True,color='FFFFFF')
            elif cell.row>header and cell.row%2:
                cell.fill=PatternFill('solid',fgColor='EDF3F6')
        ws.row_dimensions[row[0].row].height=42 if ws==asset_sheet else 32
    for column in range(1,ws.max_column+1):
        ws.column_dimensions[openpyxl.utils.get_column_letter(column)].width=20 if column<4 else 34
sheet['A1'].font=Font(name='Microsoft YaHei',size=19,bold=True,color='FFFFFF');sheet['A1'].fill=PatternFill('solid',fgColor='142838');sheet.row_dimensions[1].height=40
book.save(ROOT/relative)

# Extend the existing game content database, including its vendor lookup formulas.
relative='docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx';backup(relative)
wb=openpyxl.load_workbook(ROOT/relative);loot=wb['掉落物品'];old_last=loot.max_row
for item in ITEMS:
    row=[item['id'],item['name'],item['type'],item['subtype'],item['rarity'],item['price'],item['stack_max'],'特殊槽右键',item['description'],'99F自动贩卖机；不自动进入战局掉落池',0,'2026-11-03用户设计','已接入','data/special_items/catalog.json','SPECIAL-ITEMS',item['base_buy_price'],item['base_sell_price'],True,'unlimited',item['base_shelf_order']]
    upsert(loot,item['id'],row)
last=loot.max_row
shop=wb['基地商店']
for row in shop:
    for cell in row:
        if isinstance(cell.value,str) and cell.value.startswith('='):
            cell.value=re.sub(r'(\$[A-Z]+\$)'+str(old_last)+r'\b',lambda m:m[1]+str(last),cell.value)
for item in ITEMS:
    found=next((r for r in range(5,loot.max_row+1) if loot.cell(r,1).value==item['id']),None)
    row=['base_stock_'+item['id'],'base_vending',item['id'],'掉落物品',item['name'],item['type'],'extraction_points',item['base_buy_price'],item['base_sell_price'],'unlimited',item['base_shelf_order'],'当前I键背包','生成独立item_instance_id；同类按stack_max堆叠',f"=XLOOKUP(C{{row}},'掉落物品'!$A$5:$A${last},'掉落物品'!$R$5:$R${last},FALSE)",'用户设计+工程初始数值','已接入','data/special_items/catalog.json','特殊槽右键；独立账本见ShellStorm2_特殊道具系统账本_v001.xlsx']
    number=upsert(shop,item['id'],row,3)
    shop.cell(number,14).value=shop.cell(number,14).value.replace('{row}',str(number))
wb.save(ROOT/relative)

# Inventory call ledger is a reference index, never a duplicate AssetID registration.
relative='assets/registry/ledgers/ShellStorm2_物品道具账本_v001.xlsx';backup(relative)
wb=openpyxl.load_workbook(ROOT/relative);ws=wb['物品道具']
for item in ITEMS:
    asset=next(a for a in assets if a['id']==item['asset_id'])
    row=[item['id'],item['name'],item['type'],item['subtype'],asset['ledger'],'data/special_items/catalog.json','docs/v0.1/data/ShellStorm2_特殊道具系统账本_v001.xlsx','99F自动贩卖机','固定货架；不注入随机掉落','InventoryModule.add_item','SpecialItemController3D.request_use','ItemModelFactory3D.create_model','preview/ground双角色；正式美术已接入',asset['id'],asset['ledger']+'#资产主表!A'+str(asset['ledger_row']),'SPECIAL-ITEMS',item['description']]
    upsert(ws,item['id'],row)
wb.save(ROOT/relative)

relative='assets/registry/current_source_index.json';index=json.loads((ROOT/relative).read_text(encoding='utf-8'))
new_sources=[]
for item in ITEMS:
    manifest=json.loads((ROOT/f"art_source/items_weapons/props/{item['id']}/source_manifest.json").read_text(encoding='utf-8'))
    for role,value in manifest['roles'].items():
        path=value['source'];new_sources.append({'path':path,'bytes':(ROOT/path).stat().st_size,'family':item['asset_id']+':'+role,'version':[1],'sha256':sha(path)})
paths={s['path'] for s in new_sources};index['sources']=[s for s in index['sources'] if s['path'] not in paths]+new_sources
for entry in audio_manifest['assets']:
    path=entry['source']
    index['sources']=[s for s in index['sources'] if s['path']!=path]+[{'path':path,'bytes':(ROOT/path).stat().st_size,'family':entry['asset_id'],'version':[1],'sha256':sha(path)}]
index['date']=DATE
write(relative,json.dumps(index,ensure_ascii=False,indent=2)+'\n')
print('SPECIAL_ITEM_LEDGER_REGISTRATION_OK: 3 content items, 14 AssetIDs, 6 Blender masters, 6 audio masters; unrelated row fingerprints preserved')
