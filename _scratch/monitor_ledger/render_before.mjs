import fs from 'node:fs/promises';
import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
const jobs=JSON.parse(await fs.readFile(new URL('./changes.json',import.meta.url),'utf8'));
for (const [i,path,sheet,range] of [[0,jobs[0].path,'3D-敌人','A4:F9'],[3,jobs[3].path,'怪物与Boss','A4:I8']]){
 const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(path));
 const blob=await wb.render({sheetName:sheet,range,scale:1});
 await fs.writeFile(new URL(`./before${i}.png`,import.meta.url),new Uint8Array(await blob.arrayBuffer()));
 console.log((await wb.inspect({kind:'table',sheetId:sheet,range,tableMaxRows:3,tableMaxCols:4,maxChars:500})).ndjson);
}
