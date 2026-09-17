import fs from 'node:fs/promises';import crypto from 'node:crypto';import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
const R='/Users/summercards/ShellStorm2',O=R+'/assets/art/environments/tower_zones/rooftop/source/reference_components/v002',file=R+'/assets/registry/ShellStorm2_美术资产台账_v001.xlsx';
const sha=crypto.createHash('sha256').update(await fs.readFile(O+'/天台区块_参考组件库_v002.blend')).digest('hex');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(file));wb.worksheets.getItem('资产主表').getRange('T429').values=[[sha]];
const p=wb.worksheets.getItem('3D-场景通用').getRange('P97');p.values=[[p.values[0][0].replace(/SHA256=[a-f0-9]+/,'SHA256='+sha)]];
wb.recalculate();await (await SpreadsheetFile.exportXlsx(wb)).save(file);
const meta=JSON.parse(await fs.readFile(O+'/qa/registry_update.json','utf8'));meta.sha256=sha;await fs.writeFile(O+'/qa/registry_update.json',JSON.stringify(meta,null,2));console.log(sha);
