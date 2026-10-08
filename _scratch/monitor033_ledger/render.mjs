import fs from 'node:fs/promises';
import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
const jobs=JSON.parse(await fs.readFile(new URL('./changes.json',import.meta.url),'utf8'));
for(const i of [0,2]){
 const w=await SpreadsheetFile.importXlsx(await FileBlob.load(jobs[i].path));
 const sn=i===0?'3D-敌人':Object.keys(jobs[i].sheets)[0];
 const b=await w.render({sheetName:sn,range:i===0?'N9:P10':'A20:C26',scale:1});
 await fs.writeFile(new URL(`./preview${i}.png`,import.meta.url),new Uint8Array(await b.arrayBuffer()));
}
