import fs from 'node:fs/promises';
import {Workbook,SpreadsheetFile} from '@oai/artifact-tool';
import {fileURLToPath} from 'node:url';
const jobs=JSON.parse(await fs.readFile(new URL('./changes.json',import.meta.url),'utf8'));
for(let i=0;i<jobs.length;i++){
 const wb=Workbook.create();
 for(const [name,changes] of Object.entries(jobs[i].sheets)){
  const sheet=wb.worksheets.add(name);
  for(const [cell,value] of Object.entries(changes))sheet.getRange(cell).values=[[value]];
  for(const cell of Object.keys(changes)) {
   sheet.getRange(cell).format.wrapText=true;
   sheet.getRange(cell).format.verticalAlignment='top';
  }
  if(name==='Boss002技能设计'){
   sheet.getRange('A1:H37').format.font={name:'Microsoft YaHei',size:11,color:'#172232'};
   sheet.getRange('A1:H37').format.verticalAlignment='center';
   sheet.getRange('A1:H37').format.wrapText=true;
   sheet.getRange('A1:H37').format.columnWidth=22;
   sheet.getRange('A1:C37').format.columnWidth=32;
   sheet.getRange('D1:D37').format.columnWidth=14;
   sheet.getRange('E1:E37').format.columnWidth=18;
   sheet.getRange('F1:F37').format.columnWidth=21;
   sheet.getRange('G1:H37').format.columnWidth=42;
   sheet.getRange('A1:H37').format.rowHeight=26;
   sheet.mergeCells('A2:H2');sheet.getRange('A2').format.font={size:16,bold:true};
   sheet.getRange('A8:H8').format={fill:'#23324A',font:{bold:true,color:'#FFFFFF'}};
   sheet.getRange('A9:H12').format.rowHeight=64;
   sheet.getRange('A9:H12').format.fill='#F1F4F8';
   sheet.getRange('D9:E11').setNumberFormat('0.000');sheet.getRange('F9:F11').setNumberFormat('0.0');
   sheet.getRange('A15:H15').format={fill:'#23324A',font:{bold:true,color:'#FFFFFF'}};
   for(let r=15;r<=18;r++)sheet.mergeCells(`C${r}:H${r}`);
   for(let r=20;r<=32;r++){sheet.mergeCells(`B${r}:F${r}`);sheet.mergeCells(`G${r}:H${r}`);}
   sheet.getRange('A20:H20').format={fill:'#23324A',font:{bold:true,color:'#FFFFFF'}};
   for(const r of [34,36,37]){sheet.mergeCells(`B${r}:H${r}`);sheet.getRange(`A${r}:H${r}`).format.rowHeight=40;}
  }
 }
 wb.recalculate();
 console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?',options:{useRegex:true,maxResults:3},maxChars:400})).ndjson);
 const out=await SpreadsheetFile.exportXlsx(wb);await out.save(fileURLToPath(new URL(`./cells${i}.xlsx`,import.meta.url)));
 if(i===1){const blob=await wb.render({sheetName:'Boss002技能设计',range:'A20:H37',scale:1});await fs.writeFile(new URL('./boss_design.png',import.meta.url),new Uint8Array(await blob.arrayBuffer()));}
}
console.log('Authored targeted cells and standalone Boss002 design sheet');
