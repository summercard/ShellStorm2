import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
const root='/Users/summercards/ShellStorm2';
const out=root+'/assets/art/environments/tower_zones/battle/source/common_components/v001';
const ledger=root+'/assets/registry/ShellStorm2_美术资产台账_v001.xlsx';
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(ledger));
const sheet=wb.worksheets.getItem('3D-场景通用');
const id='ENV-BATTLE-L01-COMMON-COMPONENT-LIBRARY';
const existing=sheet.getRange('A1:A150').values.findIndex(r=>r[0]===id)+1;
const row=existing||90;
const blend=out+'/战局区块_通用组件库_v001.blend';
const sha=crypto.createHash('sha256').update(await fs.readFile(blend)).digest('hex');
try { await fs.access(out+'/qa/registry_before.xlsx'); } catch { await fs.copyFile(ledger,out+'/qa/registry_before.xlsx'); }
if(!existing)sheet.getRange(`A${row}:P${row}`).copyFrom(sheet.getRange('A89:P89'),'all');
sheet.getRange(`A${row}:P${row}`).values=[[
 id,'战局区块 通用组件库','未制作','未制作',
 'assets/art/environments/tower_zones/battle/source/common_components/v001/战局区块_通用组件库_v001.blend',
 '从主路内容房02抽取43个可复用设施与环境支持包；按7类展开陈列，每包独立根节点。',
 '未接入','无','无','无','按组件清单','单包局部坐标：X/Y居中；底面Z=0；Godot -Z','局内关卡01 / Battle',
 'Blender通用组件源已完成；未接入Godot','v001',
 `2026-09-16：服务器14、终端4、设备岛3、维修与机箱10、门框与标识3、环境陈设3、环境支持6；四材质、共享外链色盘、逐面PaletteUV验收通过。SHA256=${sha}。源和验收=assets/art/environments/tower_zones/battle/source/common_components/v001/。`
]];
wb.recalculate();
const inspect=await wb.inspect({kind:'region',sheetId:'3D-场景通用',range:'A89:P90',maxChars:5000});
await fs.writeFile(out+'/qa/registry_inspect.ndjson',inspect.ndjson);
const pic=await wb.render({sheetName:'3D-场景通用',range:'A89:P90',scale:1.5});
await fs.writeFile(out+'/qa/registry_after.png',new Uint8Array(await pic.arrayBuffer()));
const file=await SpreadsheetFile.exportXlsx(wb);await file.save(ledger);
await fs.writeFile(out+'/qa/registry_update.json',JSON.stringify({sheet:'3D-场景通用',row,asset_id:id,source_sha256:sha},null,2));
console.log('Added row',row,sha);
