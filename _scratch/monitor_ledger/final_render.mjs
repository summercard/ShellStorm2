import fs from 'node:fs/promises';
import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
const path='I:/工作项目/shellstrom2/ShellStorm2/docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx';
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(path));
for(const [name,range,out] of [['Boss002技能设计','A1:H18','final_skills.png'],['Boss002技能设计','A20:H37','final_states.png']]){
 const image=await wb.render({sheetName:name,range,scale:1});await fs.writeFile(new URL('./'+out,import.meta.url),new Uint8Array(await image.arrayBuffer()));
}
console.log((await wb.inspect({kind:'match',sheetId:'Boss002技能设计',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?',options:{useRegex:true,maxResults:3},maxChars:400})).ndjson);
