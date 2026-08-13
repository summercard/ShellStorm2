import { FileBlob, SpreadsheetFile } from "/Users/summercards/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";
const path="/Users/summercards/ShellStorm2/docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx";
const workbook=await SpreadsheetFile.importXlsx(await FileBlob.load(path));
for(const [sheetId,range] of [["怪物与Boss","A4:O14"],["精英怪","A1:O16"]]) console.log((await workbook.inspect({kind:"table",sheetId,range,include:"values,formulas",tableMaxRows:20,tableMaxCols:20,maxChars:30000})).ndjson);
console.log((await workbook.inspect({kind:"match",searchTerm:"#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",options:{useRegex:true,maxResults:100},summary:"formula error scan",maxChars:10000})).ndjson);
