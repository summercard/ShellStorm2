import { FileBlob, SpreadsheetFile } from "/Users/summercards/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";

const path = "/Users/summercards/ShellStorm2/assets/registry/ShellStorm2_美术资产台账_v001.xlsx";
const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(path));
for (const [sheetId, range] of [["资产主表", "A226:X234"], ["版本记录", "A14:G14"], ["总览", "A5:J18"]]) {
  const result = await workbook.inspect({kind:"table", sheetId, range, include:"values,formulas", tableMaxRows:20, tableMaxCols:24, maxChars:30000});
  console.log(result.ndjson);
}
const errors = await workbook.inspect({kind:"match", searchTerm:"#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options:{useRegex:true,maxResults:100}, summary:"formula error scan", maxChars:10000});
console.log(errors.ndjson);
