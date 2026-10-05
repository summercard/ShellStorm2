from pathlib import Path
import hashlib,json
import openpyxl
root=Path(r'I:/工作项目/shellstrom2/ShellStorm2')
basep=root/'assets/registry/ledger_split_baseline.json'
prop=root/'assets/registry/ledgers/ShellStorm2_道具账本_v001.xlsx'
def digest(ws):
 parts=[]
 for rng in sorted(str(r) for r in ws.merged_cells.ranges): parts.append('merge:'+rng)
 cells=[(c.row,c.column,c.coordinate,c.value) for row in ws.iter_rows() for c in row if c.value not in (None,'')]
 parts.append(f'bbox={min(c[0] for c in cells)}:{max(c[0] for c in cells)}x{min(c[1] for c in cells)}:{max(c[1] for c in cells)}' if cells else 'bbox=empty')
 parts += [f'{a}={v!r}' for _,_,a,v in sorted(cells,key=lambda x:(x[0],x[1]))]
 return hashlib.sha256('\n'.join(parts).encode('utf-8')).hexdigest()
b=json.loads(basep.read_text(encoding='utf-8'))
w=openpyxl.load_workbook(prop,data_only=False)
b['sheet_digests']['3D-道具']=digest(w['3D-道具'])
basep.write_text(json.dumps(b,ensure_ascii=False,indent=1)+'\n',encoding='utf-8')
(root/'outputs/base99_radio_v001/prefab_baseline_transaction.json').write_text(json.dumps({'transaction':'独立Prefab分页基线更新','sheet':'3D-道具','ledger':str(prop),'new_row':8,'baseline':str(basep),'captured_at':'2026-10-05','reason':'本次新增正式PackedScene，按专表摘要锁规则单独事务处理'},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(root/'outputs/base99_radio_v001/prefab_baseline_transaction.txt').write_text(f'独立事务：更新 3D-道具 专表摘要\n账本：{prop}\n新增行：8\n基线：{basep}\n原因：新增正式PackedScene，按专表摘要锁规则单独事务处理\n',encoding='utf-8')
