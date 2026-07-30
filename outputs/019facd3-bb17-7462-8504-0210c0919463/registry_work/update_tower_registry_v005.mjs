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
  "向下爬楼塔楼3D整层外壳与中央核心母版",
  "场景",
  "room_kit",
  "tower_descent",
  "root_3d",
  "ENV-DUNGEON-RUNTIME-3D",
  "俯视3D",
  "blender_review",
  "335.410m整层外壳/67.082m核心/楼顶特殊梯/通用旋转梯",
  "待制作",
  "P0",
  "v005",
  "Blender 4.2源文件/1单位=1m/255对象/237 Mesh/12段总边界外壳",
  "assets/art/environments/tower_descent_3d/source/env_tower_descent_kit_top3d_v005.blend",
  "assets/art/environments/tower_descent_3d/source/expand_env_tower_descent_kit_top3d_v005.py; assets/art/environments/tower_descent_3d/source/validate_env_tower_descent_kit_top3d_v005.py; outputs/019facd3-bb17-7462-8504-0210c0919463/previews/tower_blender_full_building_shell_v005.png",
  "塔楼;向下爬楼;楼顶;基地层;战斗层;特殊楼梯;通用楼梯;中央核心;五倍边长;整层外墙;Blender",
  "场景|room_kit|tower_descent|root_3d|俯视3d|blender_review",
  "唯一",
  "c473a4db24d68be5ceecbc0b4a5b6c3ff39848153f7d26cf06ebbdbc5fa27934",
  "Codex",
  new Date("2026-07-30T00:00:00+08:00"),
  "用户手工Blender结构 + Codex外壳边界修正",
  "v005从v004派生，v004继续保留为楼梯细化与楼板扩大基线。按用户复核把“长宽扩大5倍”修正为整座楼层：三层楼板和建筑外壳统一为335.410×335.410m，外墙外表面精确落在X/Y=±167.705m。移除旧±55.902m楼顶女儿墙和旧±33.541m基地/战斗满高外墙；新增4段楼顶女儿墙、4段基地外墙、4段战斗层外墙。67.082m中央功能核心、两套手调楼梯、门、设施、内部隔墙、12块外围楼板和11段核心围栏均未缩放或位移。QA验证255对象、237网格、12段总边界外壳、12块外围楼板、ROOT父子关系、应用缩放、楼层高度和外墙边界。仍未导出GLB、未修改Godot运行时。",
]];
mainSheet.getRange("V163").format.numberFormat = "yyyy-mm-dd";
mainSheet.getRange("A163:X163").format.wrapText = true;
mainSheet.getRange("A163:X163").format.rowHeight = 180;

const versionRow = versionSheet.getRange("A24:G24");
versionRow.copyFrom(versionSheet.getRange("A23:G23"), "all");
versionRow.values = [[
  "v1.18",
  new Date("2026-07-30T00:00:00+08:00"),
  "塔楼整层外壳五倍边长修正",
  "ENV-TOWER-DESCENT-KIT-3D",
  "登记v005：楼顶女儿墙、基地外墙、战斗层外墙全部移到335.410m总楼层边界；旧核心满高外墙取消，67.082m中央核心、楼梯、门、设施和内部隔墙保持原尺寸。",
  "AssetID不变；v004可回退；只修正Blender评审母版，确认前不导出GLB、不接入Godot。",
  "Codex",
]];
versionSheet.getRange("B24").format.numberFormat = "yyyy-mm-dd";
versionSheet.getRange("A24:G24").format.wrapText = true;
versionSheet.getRange("A24:G24").format.rowHeight = 100;

const mainPreview = await workbook.render({
  sheetName: "资产主表",
  range: "A160:X163",
  scale: 1.1,
  format: "png",
});
const versionPreview = await workbook.render({
  sheetName: "版本记录",
  range: "A21:G24",
  scale: 1.3,
  format: "png",
});
await fs.writeFile(
  path.join(workDir, "after_asset_main_v005.png"),
  new Uint8Array(await mainPreview.arrayBuffer()),
);
await fs.writeFile(
  path.join(workDir, "after_version_v005.png"),
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
  range: "版本记录!A23:G24",
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
