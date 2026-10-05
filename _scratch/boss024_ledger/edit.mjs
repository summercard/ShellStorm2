import {fileURLToPath} from 'node:url';
import fs from 'node:fs/promises';
import {Workbook,SpreadsheetFile} from '@oai/artifact-tool';
const jobs=JSON.parse(await fs.readFile(new URL('./changes.json',import.meta.url),'utf8'));
for(let i=0;i<jobs.length;i++){
 const wb=Workbook.create();
 for(const [name,changes] of Object.entries(jobs[i].sheets)){
  const sheet=wb.worksheets.add(name);
  for(const [cell,value] of Object.entries(changes))sheet.getRange(cell).values=[[value]];
 }
 const out=await SpreadsheetFile.exportXlsx(wb);await out.save(fileURLToPath(new URL(`./cells${i}.xlsx`,import.meta.url)));
}
console.log('Authored exact ledger cell updates');

