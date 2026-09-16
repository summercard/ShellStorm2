import fs from 'node:fs/promises';import crypto from 'node:crypto';import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
const root='/Users/summercards/ShellStorm2',out=root+'/assets/art/environments/tower_zones/battle/source/common_components/v003';
const ledger=root+'/assets/registry/ShellStorm2_美术资产台账_v001.xlsx',id='ENV-BATTLE-L01-COMMON-COMPONENT-LIBRARY';
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(ledger)),sheet=wb.worksheets.getItem('3D-场景通用');
const row=sheet.getRange('A1:A150').values.findIndex(r=>r[0]===id)+1;if(!row)throw Error('Missing common library registry row');
await fs.copyFile(ledger,out+'/qa/registry_before.xlsx');
const blend=out+'/战局区块_通用组件库_v003.blend',sha=crypto.createHash('sha256').update(await fs.readFile(blend)).digest('hex');
sheet.getRange(`E${row}:F${row}`).values=[[
 'assets/art/environments/tower_zones/battle/source/common_components/v003/战局区块_通用组件库_v003.blend',
 '按指定编号精简为23个独立包、9类：服务器机柜保留正常/损坏各1，标准墙仅1个5×0.3×11.9m，地板仅保留前2个，统一朝本地+Y。']];
sheet.getRange(`O${row}:P${row}`).values=[['v003',`2026-09-16：按人工选定序号清理v002重复项；04首件摆正，06仅留1件，08仅留5×0.3×11.9m标准墙且禁止横向拉伸墙，09仅留前2块地板。最终23包/9类；四材质、共享外链色盘、逐面PaletteUV、朝向与尺寸验收通过。SHA256=${sha}。源和验收=assets/art/environments/tower_zones/battle/source/common_components/v003/。`]];
wb.recalculate();
const pic=await wb.render({sheetName:'3D-场景通用',range:`A${row}:P${row}`,scale:1.5});await fs.writeFile(out+'/qa/registry_after.png',new Uint8Array(await pic.arrayBuffer()));
const file=await SpreadsheetFile.exportXlsx(wb);await file.save(ledger);
await fs.writeFile(out+'/qa/registry_update.json',JSON.stringify({sheet:'3D-场景通用',row,asset_id:id,modified_columns:['E','F','O','P'],source_sha256:sha},null,2));
console.log('Updated row',row,sha);
