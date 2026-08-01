import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const root = "/Users/summercards/ShellStorm2";
const inputPath = `${root}/assets/registry/ShellStorm2_美术资产台账_v001.xlsx`;
const outputPath = `${root}/outputs/019fbb91-20c2-7573-bd89-4731b032103d/ShellStorm2_美术资产台账_v001.xlsx`;
const previewDir = `${root}/.codex-tmp/registry-work/previews`;
const inspectOnly = process.argv.includes("--inspect-only");

const input = await FileBlob.load(inputPath);
const workbook = await SpreadsheetFile.importXlsx(input);
const overview = await workbook.inspect({
  kind: "workbook,sheet,table",
  maxChars: 12000,
  tableMaxRows: 8,
  tableMaxCols: 12,
  tableMaxCellChars: 100,
});
process.stdout.write(`${overview.ndjson}\n`);

await fs.mkdir(previewDir, { recursive: true });
const sheetNames = ["资产台账", "制作规范", "版本记录"];
for (const sheetName of sheetNames) {
  try {
    const preview = await workbook.render({ sheetName, autoCrop: "all", scale: 1.2, format: "png" });
    await fs.writeFile(`${previewDir}/${sheetName}.png`, new Uint8Array(await preview.arrayBuffer()));
  } catch (error) {
    process.stdout.write(`RENDER_SKIP ${sheetName}: ${error.message}\n`);
  }
}

if (inspectOnly) process.exit(0);

const history = workbook.worksheets.getItem("版本记录");
const used = history.getUsedRange(true);
const rowCount = used.rowCount;
const nextRow = rowCount + 1;
history.getRange(`A${nextRow}:F${nextRow}`).values = [[
  "v1.29",
  new Date("2026-08-01T00:00:00+08:00"),
  "关卡组件坐标与玩家灯光自投影修复",
  "基底层改为合法6×6组件边界；98—95层30×25房间按5m格线重排；门墙、交互门与走廊端点由两端真实门槽求交；楼梯只挖上层楼板；玩家/配件/手持武器禁投影，前向灯仍保留环境与怪物阴影。",
  "Codex",
  "TOWER_GRID_COMPONENT_ALIGNMENT_OK；TOWER_DESCENT_FLOW_OK；94门通行；灯光/性能/视觉回归通过",
]];
history.getRange(`B${nextRow}`).setNumberFormat("yyyy-mm-dd");
history.getRange(`A${nextRow}:F${nextRow}`).format.wrapText = true;
history.getRange(`A${nextRow}:F${nextRow}`).format.rowHeight = 54;

const errorScan = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 300 },
  summary: "final formula error scan",
});
process.stdout.write(`${errorScan.ndjson}\n`);
const finalCheck = await workbook.inspect({
  kind: "table",
  sheetId: "版本记录",
  range: `A${Math.max(1, nextRow - 3)}:F${nextRow}`,
  include: "values,formulas",
  tableMaxRows: 6,
  tableMaxCols: 6,
  maxChars: 8000,
});
process.stdout.write(`${finalCheck.ndjson}\n`);

const finalPreview = await workbook.render({
  sheetName: "版本记录",
  range: `A${Math.max(1, nextRow - 5)}:F${nextRow}`,
  scale: 1.5,
  format: "png",
});
await fs.writeFile(`${previewDir}/版本记录_final.png`, new Uint8Array(await finalPreview.arrayBuffer()));
await fs.mkdir(new URL(".", `file://${outputPath}`).pathname, { recursive: true });
const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);
await output.save(inputPath);
process.stdout.write(`EXPORTED ${outputPath}\nROW ${nextRow}\n`);
