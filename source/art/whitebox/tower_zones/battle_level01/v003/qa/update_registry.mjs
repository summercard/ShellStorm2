import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';

const root='/Users/summercards/ShellStorm2';
const out=root+'/source/art/whitebox/tower_zones/battle_level01/v003';
const ledger=root+'/assets/registry/ShellStorm2_美术资产台账_v001.xlsx';
const catalog=JSON.parse(await fs.readFile(out+'/data/component_packages/catalog.json','utf8'));
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(ledger));
const sheet=wb.worksheets.getItem('3D-场景通用');
const ids=sheet.getRange('A1:A500').values;
await fs.copyFile(ledger,out+'/qa/registry_before.xlsx');
const before=await wb.render({sheetName:'3D-场景通用',range:'A72:P91',scale:1.15});
await fs.writeFile(out+'/qa/registry_before.png',new Uint8Array(await before.arrayBuffer()));

const updated=[];
const skipped=[];
for(const asset of catalog.assets){
  let row=ids.findIndex(r=>r[0]===asset.asset_id)+1;
  if(asset.asset_id==='ENV-BATTLE-L01-ROOM-MAIN-02'){
    skipped.push({asset_id:asset.asset_id,reason:'正式机房美术源优先，不以白模覆盖'});
    continue;
  }
  if(asset.asset_id==='ENV-BATTLE-L01-CORRIDOR-WALL-5M' && !row){
    row=91;
    sheet.getRange('A89:P89').copyTo(sheet.getRange('A91:P91'),'all');
    sheet.getRange(`A${row}:P${row}`).values=[[asset.asset_id,asset.name_zh,'未制作','未制作',asset.source_blend,'走廊通用实墙白模模块；按5m网格重复拼接。','未接入','无','无','无','5×0.30×11.9m','底面中心；Godot -Z','局内关卡01 / Battle','白模源已完成；QA PASS','v003','']];
  }
  if(!row){skipped.push({asset_id:asset.asset_id,reason:'台账缺少行'});continue;}
  const blend=root+'/'+asset.source_blend;
  const sha=crypto.createHash('sha256').update(await fs.readFile(blend)).digest('hex');
  const kindSummary=asset.component_counts ?? {};
  sheet.getRange(`E${row}:F${row}`).values=[[asset.source_blend,'战局01白模v003；墙体按固定5m槽位拼装，带门墙完整占用5m槽并保留左右柱与门楣。']];
  sheet.getRange(`O${row}:P${row}`).values=[['v003',`2026-09-16：普通墙改为5m标准件；32个带门墙槽均为完整5m模块，保留左右柱与门楣；非整模数边缘使用2.5m固定收边。门中心、房间包络和地板组件与v002一致，Scale=1，无超过5m墙件。组件=${JSON.stringify(kindSummary)}。SHA256=${sha}。未导出GLB或接入Godot。`]];
  updated.push({row,asset_id:asset.asset_id,source_blend:asset.source_blend,sha256:sha});
}
wb.recalculate();
const errors=await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:300},summary:'battle v003 registry formula scan'});
await fs.writeFile(out+'/qa/registry_formula_scan.ndjson',errors.ndjson);
const after=await wb.render({sheetName:'3D-场景通用',range:'A72:P91',scale:1.15});
await fs.writeFile(out+'/qa/registry_after.png',new Uint8Array(await after.arrayBuffer()));
const file=await SpreadsheetFile.exportXlsx(wb);await file.save(ledger);
await fs.writeFile(out+'/qa/registry_update.json',JSON.stringify({sheet:'3D-场景通用',updated,skipped,added_row:91},null,2));
console.log(JSON.stringify({updated:updated.length,skipped,added_row:91}));
