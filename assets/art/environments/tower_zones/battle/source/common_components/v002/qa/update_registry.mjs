import fs from 'node:fs/promises';import crypto from 'node:crypto';import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
const root='/Users/summercards/ShellStorm2',out=root+'/assets/art/environments/tower_zones/battle/source/common_components/v002';
const ledger=root+'/assets/registry/ShellStorm2_美术资产台账_v001.xlsx',id='ENV-BATTLE-L01-COMMON-COMPONENT-LIBRARY';
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(ledger)),sheet=wb.worksheets.getItem('3D-场景通用');
const row=sheet.getRange('A1:A150').values.findIndex(r=>r[0]===id)+1;if(!row)throw Error('Missing common library registry row');
await fs.copyFile(ledger,out+'/qa/registry_before.xlsx');
const blend=out+'/战局区块_通用组件库_v002.blend',sha=crypto.createHash('sha256').update(await fs.readFile(blend)).digest('hex');
sheet.getRange(`E${row}:F${row}`).values=[[
 'assets/art/environments/tower_zones/battle/source/common_components/v002/战局区块_通用组件库_v002.blend',
 '统一组件正面为+Y，旋转规范化后移除完全相同副本；77个独立包按9类陈列，含墙壁7和地板30。']];
sheet.getRange(`O${row}:P${row}`).values=[['v002',`2026-09-16：82个来源包中排除房间专属30×25m底板；81个候选统一朝向后移除4个旋转重复件，保留77包。墙壁7、地板30；四材质、共享外链色盘、逐面PaletteUV验收通过。SHA256=${sha}。源和验收=assets/art/environments/tower_zones/battle/source/common_components/v002/。`]];
wb.recalculate();
const pic=await wb.render({sheetName:'3D-场景通用',range:`A${row}:P${row}`,scale:1.5});await fs.writeFile(out+'/qa/registry_after.png',new Uint8Array(await pic.arrayBuffer()));
const file=await SpreadsheetFile.exportXlsx(wb);await file.save(ledger);
await fs.writeFile(out+'/qa/registry_update.json',JSON.stringify({sheet:'3D-场景通用',row,asset_id:id,modified_columns:['E','F','O','P'],source_sha256:sha},null,2));
console.log('Updated row',row,sha);
