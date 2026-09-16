import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
import fs from 'node:fs/promises';
const root='/Users/summercards/ShellStorm2';
const ledger=root+'/assets/registry/ShellStorm2_美术资产台账_v001.xlsx';
const catalog=JSON.parse(await fs.readFile(root+'/source/art/whitebox/tower_zones/battle_level01/v003/data/component_packages/catalog.json','utf8'));
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(ledger));
const sheet=wb.worksheets.getItem('3D-场景通用');
const ids=sheet.getRange('A1:A500').values;
const rows=[];
for(const asset of catalog.assets){
 const row=ids.findIndex(r=>r[0]===asset.asset_id)+1;
 if(row)rows.push({row,asset_id:asset.asset_id,values:sheet.getRange(`E${row}:P${row}`).values[0]});
}
await fs.writeFile(root+'/source/art/whitebox/tower_zones/battle_level01/v003/qa/registry_inspection.json',JSON.stringify(rows,null,2));
console.log(JSON.stringify(rows));
console.log(JSON.stringify({headers:sheet.getRange('A5:S5').values[0],template:sheet.getRange('A89:S89').values[0]}));
