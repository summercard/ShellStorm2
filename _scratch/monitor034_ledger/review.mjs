import fs from 'node:fs/promises';
import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
const jobs=JSON.parse(await fs.readFile(new URL('./changes.json',import.meta.url),'utf8'));
for(const [i,sheet,range] of [[0,'3D-敌人','M9:P10'],[1,'', 'A20:C26'],[2,'Boss002技能设计','A20:H37']]){
 const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(jobs[i].path));
 const sn=sheet||Object.keys(jobs[i].sheets)[0];
 const blob=await wb.render({sheetName:sn,range,scale:1});
 await fs.writeFile(new URL(`./final${i}.png`,import.meta.url),new Uint8Array(await blob.arrayBuffer()));
 console.log('REVIEWED',i,sn);
}
