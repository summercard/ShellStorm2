// 只读校验：账本已分册化，逐本 inspect 资产主表/总览；版本记录在总目录。
// 路径一律经 assets/registry/ledger_index.json 解析（与 scripts/ledger_registry.py 同一真源）。
import fs from "node:fs/promises";
import path from "node:path";
import { FileBlob, SpreadsheetFile } from "/Users/summercards/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";

const root = process.cwd();
const index = JSON.parse(await fs.readFile(`${root}/assets/registry/ledger_index.json`, "utf8"));
const masterPath = `${root}/${index.master.path}`;
const ledgerPaths = index.domains.map(d => `${root}/${index.ledger_dir}/${d.file}`);

let workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(masterPath));
for (const [sheetId, range] of [["版本记录", "A14:G14"]]) {
  const result = await workbook.inspect({kind:"table", sheetId, range, include:"values,formulas", tableMaxRows:20, tableMaxCols:24, maxChars:30000});
  console.log(result.ndjson);
}
for (const ledgerPath of ledgerPaths) {
  workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(ledgerPath));
  for (const [sheetId, range] of [["总览", "A5:J18"]]) {
    const result = await workbook.inspect({kind:"table", sheetId, range, include:"values,formulas", tableMaxRows:20, tableMaxCols:24, maxChars:30000});
    console.log(`${path.basename(ledgerPath)} ${sheetId}`);
    console.log(result.ndjson);
  }
  const errors = await workbook.inspect({kind:"match", searchTerm:"#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options:{useRegex:true,maxResults:100}, summary:"formula error scan", maxChars:10000});
  console.log(errors.ndjson);
}
