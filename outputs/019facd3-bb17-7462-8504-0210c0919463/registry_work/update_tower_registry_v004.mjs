import fs from "node:fs/promises";
import path from "node:path";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const projectRoot = "/Users/summercards/ShellStorm2";
const canonicalPath = path.join(
  projectRoot,
  "assets/registry/ShellStorm2_美术资产台账_v001.xlsx",
);
const outputPath = path.join(
  projectRoot,
  "outputs/019facd3-bb17-7462-8504-0210c0919463/ShellStorm2_美术资产台账_v001.xlsx",
);
const workDir = path.join(
  projectRoot,
  "outputs/019facd3-bb17-7462-8504-0210c0919463/registry_work",
);

const input = await FileBlob.load(canonicalPath);
const workbook = await SpreadsheetFile.importXlsx(input);
const mainSheet = workbook.worksheets.getItem("资产主表");
const versionSheet = workbook.worksheets.getItem("版本记录");

mainSheet.getRange("A163:X163").values = [[
  "ENV-TOWER-DESCENT-KIT-3D",
  "向下爬楼塔楼3D中央核心与双楼梯母版",
  "场景",
  "room_kit",
  "tower_descent",
  "root_3d",
  "ENV-DUNGEON-RUNTIME-3D",
  "俯视3D",
  "blender_review",
  "335.410m空地图/67.082m核心/楼顶特殊梯/通用旋转梯",
  "待制作",
  "P0",
  "v004",
  "Blender 4.2源文件/1单位=1m/241 Mesh/6个顶层集合+2个楼梯子集合",
  "assets/art/environments/tower_descent_3d/source/env_tower_descent_kit_top3d_v004.blend",
  "assets/art/environments/tower_descent_3d/source/refine_env_tower_descent_kit_top3d_v004.py; assets/art/environments/tower_descent_3d/source/validate_env_tower_descent_kit_top3d_v004.py; outputs/019facd3-bb17-7462-8504-0210c0919463/previews/tower_blender_stair_core_plan_v004.png",
  "塔楼;向下爬楼;楼顶;基地层;战斗层;特殊楼梯;通用楼梯;中央核心;五倍边长;Blender",
  "场景|room_kit|tower_descent|root_3d|俯视3d|blender_review",
  "唯一",
  "946196e7151a5c589bfe893fd1619308c5cc8208a9af0714cac053e18c06679b",
  "Codex",
  new Date("2026-07-30T00:00:00+08:00"),
  "用户手工Blender结构 + Codex对齐与扩图",
  "v004为当前评审版，v003保留为用户手工现场快照。特殊楼顶楼梯保留手调墙高，消除复制漂移；通用楼梯整理为可绕ROOT旋转复用的总成。两套楼梯归入02_STAIRWELLS父集合，清理重复后缀并补齐核心门口短连接板。地图长宽各扩大5倍至335.410×335.410m，基地/战斗67.082m核心与楼顶111.803m建筑面不缩放，外围用12块空楼板补齐，核心围栏为楼梯保留开口。QA已验证259对象、241网格、ROOT父子关系、平台接缝、应用缩放、特殊墙高差和总占地。确认前不导出GLB、不修改Godot运行时。",
]];
mainSheet.getRange("V163").format.numberFormat = "yyyy-mm-dd";
mainSheet.getRange("A163:X163").format.wrapText = true;
mainSheet.getRange("A163:X163").format.rowHeight = 168;

const versionRow = versionSheet.getRange("A23:G23");
versionRow.copyFrom(versionSheet.getRange("A22:G22"), "all");
versionRow.values = [[
  "v1.17",
  new Date("2026-07-30T00:00:00+08:00"),
  "塔楼双楼梯与五倍边长地图登记",
  "ENV-TOWER-DESCENT-KIT-3D",
  "将用户手工v003保存为快照；登记v004特殊楼顶梯与通用旋转梯、02_STAIRWELLS集合层级、核心门口连接板、335.410m总占地、67.082m中央核心和空外围楼板。",
  "AssetID不变；v003可回退；只升级Blender评审源文件，确认前不导出GLB、不接入Godot。",
  "Codex",
]];
versionSheet.getRange("B23").format.numberFormat = "yyyy-mm-dd";
versionSheet.getRange("A23:G23").format.wrapText = true;
versionSheet.getRange("A23:G23").format.rowHeight = 78;

const mainPreview = await workbook.render({
  sheetName: "资产主表",
  range: "A160:X163",
  scale: 1.1,
  format: "png",
});
const versionPreview = await workbook.render({
  sheetName: "版本记录",
  range: "A18:G23",
  scale: 1.3,
  format: "png",
});
await fs.writeFile(
  path.join(workDir, "after_asset_main_v004.png"),
  new Uint8Array(await mainPreview.arrayBuffer()),
);
await fs.writeFile(
  path.join(workDir, "after_version_v004.png"),
  new Uint8Array(await versionPreview.arrayBuffer()),
);

const rowCheck = await workbook.inspect({
  kind: "table",
  range: "资产主表!A163:X163",
  include: "values,formulas",
  tableMaxRows: 3,
  tableMaxCols: 24,
  maxChars: 18000,
});
const versionCheck = await workbook.inspect({
  kind: "table",
  range: "版本记录!A22:G23",
  include: "values,formulas",
  tableMaxRows: 4,
  tableMaxCols: 8,
  maxChars: 14000,
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
