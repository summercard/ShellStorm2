import fs from 'node:fs/promises';
import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
const jobs=JSON.parse(await fs.readFile(new URL('./changes.json',import.meta.url),'utf8'));
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(jobs[0].path));
for(const [name,range,out] of [['3D-敌人','M10:P10','placement.png'],['资产主表','V20:Y20','master.png'],['域变更日志','A52:G52','log.png']]){
 const img=await wb.render({sheetName:name,range,scale:1.3});
 await fs.writeFile(new URL('./'+out,import.meta.url),new Uint8Array(await img.arrayBuffer()));
}
console.log((await wb.inspect({kind:'match',sheetId:'资产主表',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?',options:{useRegex:true,maxResults:5},maxChars:500})).ndjson);
