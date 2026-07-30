import fs from "node:fs/promises";
import path from "node:path";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const projectRoot = "/Users/summercards/ShellStorm2";
const canonicalPath = path.join(
  projectRoot,
  "assets/registry/ShellStorm2_美术资产台账_v001.xlsx",
);
const workDir = path.join(
  projectRoot,
  "outputs/019facd3-bb17-7462-8504-0210c0919463/registry_work",
);
const phase = process.argv[2] || "inspect";

const input = await FileBlob.load(canonicalPath);
const workbook = await SpreadsheetFile.importXlsx(input);

if (phase === "inspect") {
  const sheetSummary = await workbook.inspect({
    kind: "sheet",
    include: "id,name",
    maxChars: 10000,
  });
  const assetMatches = await workbook.inspect({
    kind: "match",
    searchTerm: "ENV-TOWER-DESCENT-KIT-3D",
    options: { maxResults: 20 },
    maxChars: 12000,
  });
  const mainPreview = await workbook.render({
    sheetName: "资产主表",
    autoCrop: "all",
    scale: 0.75,
    format: "png",
  });
  const namingPreview = await workbook.render({
    sheetName: "命名与查重",
    autoCrop: "all",
    scale: 0.75,
    format: "png",
  });
  await fs.writeFile(
    path.join(workDir, "before_asset_main.png"),
    new Uint8Array(await mainPreview.arrayBuffer()),
  );
  await fs.writeFile(
    path.join(workDir, "before_naming.png"),
    new Uint8Array(await namingPreview.arrayBuffer()),
  );
  console.log(sheetSummary.ndjson);
  console.log(assetMatches.ndjson);
}

if (phase === "inspect-detail") {
  const rowDetail = await workbook.inspect({
    kind: "table",
    range: "资产主表!A160:X163",
    include: "values,formulas",
    tableMaxRows: 10,
    tableMaxCols: 24,
    maxChars: 20000,
  });
  const rowStyle = await workbook.inspect({
    kind: "computedStyle",
    sheetId: "资产主表",
    range: "A162:X163",
    maxChars: 12000,
  });
  const versionDetail = await workbook.inspect({
    kind: "table",
    range: "版本记录!A1:G21",
    include: "values,formulas",
    tableMaxRows: 30,
    tableMaxCols: 10,
    maxChars: 20000,
  });
  console.log(rowDetail.ndjson);
  console.log(rowStyle.ndjson);
  console.log(versionDetail.ndjson);
}

if (phase === "update") {
  const mainSheet = workbook.worksheets.getItem("资产主表");
  const versionSheet = workbook.worksheets.getItem("版本记录");
  const assetRow = mainSheet.getRange("A163:X163");
  assetRow.copyFrom(mainSheet.getRange("A162:X162"), "all");
  assetRow.values = [[
    "ENV-TOWER-DESCENT-KIT-3D",
    "向下爬楼塔楼3D三层堆叠母版",
    "场景",
    "room_kit",
    "tower_descent",
    "root_3d",
    "ENV-DUNGEON-RUNTIME-3D",
    "俯视3D",
    "blender_review",
    "楼顶/基地层/战斗层/两段实际楼梯",
    "待制作",
    "P0",
    "v002",
    "Blender 4.2源文件/1单位=1m/215 Mesh/7 Collection",
    "assets/art/environments/tower_descent_3d/source/env_tower_descent_kit_top3d_v002.blend",
    "assets/art/environments/tower_descent_3d/source/build_env_tower_descent_kit_top3d_v002.py; outputs/019facd3-bb17-7462-8504-0210c0919463/previews/tower_blender_three_floor_stack_v002.png",
    "塔楼;向下爬楼;楼顶;基地层;怪物层;室内墙;门;西侧楼梯;东侧楼梯;Blender",
    "场景|room_kit|tower_descent|root_3d|俯视3d|blender_review",
    "唯一",
    "1576a0470fd22ffe037ad69b8ce9c1bde09b6bee241f2748b0ef14718195ccd6",
    "Codex",
    new Date("2026-07-29T00:00:00+08:00"),
    "原创Blender程序建模",
    "v002为当前评审版：三层按Z=0/-9/-18m真实堆叠；楼顶111.803×111.803m，基地/战斗层67.082×67.082m；西侧楼梯连接楼顶→基地，东侧楼梯连接基地→战斗，上下门同轴；含楼板、外墙、15扇门、室内隔墙与两段实际楼梯。已通过集合、网格、门位、层高、净宽和应用缩放QA。v001保留为旧横向组件评审板；确认前不导出GLB、不修改Godot运行时。",
  ]];
  mainSheet.getRange("V163").format.numberFormat = "yyyy-mm-dd";
  mainSheet.getRange("A163:X163").format.wrapText = true;
  mainSheet.getRange("A163:X163").format.rowHeight = 160;

  const versionRow = versionSheet.getRange("A22:G22");
  versionRow.copyFrom(versionSheet.getRange("A21:G21"), "all");
  versionRow.values = [[
    "v1.16",
    new Date("2026-07-29T00:00:00+08:00"),
    "塔楼Blender三层堆叠版登记",
    "ENV-TOWER-DESCENT-KIT-3D",
    "将旧v001横向组件评审板保留为历史版本；登记独立v002三层真实堆叠文件，含楼板、外墙、室内隔墙、15扇门及西/东两段实际楼梯，并修复同名文件覆盖导致的评审图不一致。",
    "AssetID不变；只升级Blender评审源文件版本；确认前不导出GLB、不接入Godot。",
    "Codex",
  ]];
  versionSheet.getRange("B22").format.numberFormat = "yyyy-mm-dd";
  versionSheet.getRange("A22:G22").format.wrapText = true;
  versionSheet.getRange("A22:G22").format.rowHeight = 72;

  const outputPath = path.join(
    projectRoot,
    "outputs/019facd3-bb17-7462-8504-0210c0919463/ShellStorm2_美术资产台账_v001.xlsx",
  );
  const mainPreview = await workbook.render({
    sheetName: "资产主表",
    range: "A158:X163",
    scale: 1.1,
    format: "png",
  });
  const versionPreview = await workbook.render({
    sheetName: "版本记录",
    range: "A1:G22",
    scale: 1.1,
    format: "png",
  });
  await fs.writeFile(
    path.join(workDir, "after_asset_main_v002.png"),
    new Uint8Array(await mainPreview.arrayBuffer()),
  );
  await fs.writeFile(
    path.join(workDir, "after_version_v002.png"),
    new Uint8Array(await versionPreview.arrayBuffer()),
  );

  const rowCheck = await workbook.inspect({
    kind: "table",
    range: "资产主表!A163:X163",
    include: "values,formulas",
    tableMaxRows: 3,
    tableMaxCols: 24,
    maxChars: 16000,
  });
  const versionCheck = await workbook.inspect({
    kind: "table",
    range: "版本记录!A21:G22",
    include: "values,formulas",
    tableMaxRows: 4,
    tableMaxCols: 8,
    maxChars: 12000,
  });
  const formulaErrors = await workbook.inspect({
    kind: "match",
    searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
    options: { useRegex: true, maxResults: 300 },
    summary: "final formula error scan",
    maxChars: 12000,
  });
  console.log(rowCheck.ndjson);
  console.log(versionCheck.ndjson);
  console.log(formulaErrors.ndjson);

  const outputWorkbook = await SpreadsheetFile.exportXlsx(workbook);
  await outputWorkbook.save(outputPath);
  const canonicalWorkbook = await SpreadsheetFile.exportXlsx(workbook);
  await canonicalWorkbook.save(canonicalPath);
  console.log(`OUTPUT=${outputPath}`);
  console.log(`CANONICAL=${canonicalPath}`);
}
