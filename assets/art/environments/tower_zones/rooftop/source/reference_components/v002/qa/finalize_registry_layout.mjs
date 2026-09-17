import fs from 'node:fs/promises';import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
const R='/Users/summercards/ShellStorm2',O=R+'/assets/art/environments/tower_zones/rooftop/source/reference_components/v002',file=R+'/assets/registry/ShellStorm2_美术资产台账_v001.xlsx';
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(file)),s=wb.worksheets.getItem('3D-场景通用'),m=wb.worksheets.getItem('资产主表');
s.getRange('A135:P141').format.wrapText=true;s.getRange('A135:P141').format.rowHeight=100;
s.getRange('E124:F124').format.wrapText=true;s.getRange('E124:F124').format.rowHeight=120;
m.getRange('M429:P429').format.wrapText=true;m.getRange('M429:P429').format.rowHeight=120;
wb.recalculate();
for(const [sheet,range,name] of [['3D-场景通用','A135:B141','registry_new'],['3D-场景通用','E124:F124','registry_door'],['资产主表','M429:P429','registry_master']]){const p=await wb.render({sheetName:sheet,range,scale:1.2});await fs.writeFile(O+'/qa/'+name+'.png',new Uint8Array(await p.arrayBuffer()));}
await (await SpreadsheetFile.exportXlsx(wb)).save(file);console.log('LAYOUT_FIXED');
