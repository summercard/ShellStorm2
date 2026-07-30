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
const sourcePath =
  "assets/art/environments/tower_descent_3d/source/env_tower_descent_kit_top3d_v006.blend";
const sourceSha =
  "a99ca6f01c875cdf9414a9f132bbb9d4c2a921b4b4871346170ee6e6701130a2";

const input = await FileBlob.load(canonicalPath);
const workbook = await SpreadsheetFile.importXlsx(input);
const mainSheet = workbook.worksheets.getItem("资产主表");
const versionSheet = workbook.worksheets.getItem("版本记录");

mainSheet.getRange("A163:X163").values = [[
  "ENV-TOWER-DESCENT-KIT-3D",
  "向下爬楼塔楼3D五米模块化母版",
  "场景",
  "room_kit",
  "tower_descent",
  "root_3d",
  "ENV-DUNGEON-RUNTIME-3D",
  "俯视3D",
  "blender_review",
  "335m整层/65m基地与战斗核心/5m地砖与墙体/楼顶特殊梯/通用旋转梯",
  "待制作",
  "P0",
  "v006",
  "Blender 4.2源文件/1单位=1m/432对象/114 Mesh/18个未应用Array",
  sourcePath,
  "assets/art/environments/tower_descent_3d/source/modularize_env_tower_descent_kit_top3d_v006.py; assets/art/environments/tower_descent_3d/source/validate_env_tower_descent_kit_top3d_v006.py; outputs/019facd3-bb17-7462-8504-0210c0919463/previews/tower_blender_facility_modular_core_v006.png",
  "塔楼;向下爬楼;楼顶;基地层;战斗层;特殊楼梯;通用楼梯;五米网格;模块化地砖;模块化墙;模块化门;Blender",
  "场景|room_kit|tower_descent|root_3d|俯视3d|blender_review",
  "唯一",
  sourceSha,
  "Codex",
  new Date("2026-07-30T00:00:00+08:00"),
  "用户手工Blender楼梯 + Codex五米模块化楼层",
  "v006从用户v005内存快照派生；建筑总占地规整为335×335m（67×67个5m网格），基地和战斗核心规整为65×65m（13×13格）。楼顶、基地、战斗层地砖和整层外边界由共享母网格的未应用Array组装，虚拟表达13,452块地砖和804段外墙/女儿墙；核心墙、内墙与门保留158个可编辑模块实例。基地核心使用满高墙完整围合；战斗层隔间和16扇门均按5m墙位拼装。楼梯梯跑、折角、特殊墙高及开口朝向不改，仅将根节点向核心内侧校正约1.041m。仍未导出GLB、未修改Godot运行时。",
]];
mainSheet.getRange("V163").format.numberFormat = "yyyy-mm-dd";
mainSheet.getRange("A163:X163").format.wrapText = true;
mainSheet.getRange("A163:X163").format.rowHeight = 190;

const componentRows = [
  [
    "ENV-TOWER-FLOOR-TILE-5M",
    "塔楼5米地砖模块",
    "场景",
    "room_kit",
    "tower_descent",
    "floor_tile_5m",
    "ENV-TOWER-DESCENT-KIT-3D",
    "俯视3D",
    "blender_review",
    "5×5×0.30m/四向接口/可无缝平铺",
    "程序占位",
    "P0",
    "v001",
    "Blender 4.2源集合/1单位=1m/共享Mesh/Array步长5m",
    sourcePath,
    "Blender集合=10A_MOD_FLOOR_TILE_5M_U01; outputs/019facd3-bb17-7462-8504-0210c0919463/previews/tower_blender_5m_module_library_v006.png",
    "塔楼;地砖;楼板;5米;模块化;平铺;四向接口",
    "场景|room_kit|tower_descent|floor_tile_5m|俯视3d|blender_review",
    "母版子集合",
    "",
    "Codex",
    new Date("2026-07-30T00:00:00+08:00"),
    "程序生成Blender源集合",
    "母对象MOD_FLOOR_TILE_5M_U01，四边各有规范Socket；v006三层通过18个未应用Array的一部分虚拟表达13,452块地砖。当前是母版内子集合，尚未导出独立GLB。",
  ],
  [
    "ENV-TOWER-WALL-SOLID-5M",
    "塔楼5米满高实墙模块",
    "场景",
    "room_kit",
    "tower_descent",
    "wall_solid_5m",
    "ENV-TOWER-DESCENT-KIT-3D",
    "俯视3D",
    "blender_review",
    "5×0.30×9m/左右接口/可旋转复用",
    "程序占位",
    "P0",
    "v001",
    "Blender 4.2源集合/1单位=1m/共享Mesh/5m墙位",
    sourcePath,
    "Blender集合=10B_MOD_WALL_SOLID_5M_U01; outputs/019facd3-bb17-7462-8504-0210c0919463/previews/tower_blender_5m_module_library_v006.png",
    "塔楼;实墙;满高墙;5米;模块化;室内隔墙;核心外墙",
    "场景|room_kit|tower_descent|wall_solid_5m|俯视3d|blender_review",
    "母版子集合",
    "",
    "Codex",
    new Date("2026-07-30T00:00:00+08:00"),
    "程序生成Blender源集合",
    "母对象MOD_WALL_SOLID_5M_U01，高度与9m层高一致；用于整层外墙、65m基地核心围合、战斗核心和室内隔间。当前是母版内子集合，尚未导出独立GLB。",
  ],
  [
    "ENV-TOWER-WALL-PARAPET-5M",
    "塔楼5米楼顶女儿墙模块",
    "场景",
    "room_kit",
    "tower_descent",
    "wall_parapet_5m",
    "ENV-TOWER-DESCENT-KIT-3D",
    "俯视3D",
    "blender_review",
    "5×0.30×1.50m/左右接口/楼顶边界",
    "程序占位",
    "P1",
    "v001",
    "Blender 4.2源集合/1单位=1m/共享Mesh/5m墙位",
    sourcePath,
    "Blender集合=10C_MOD_WALL_PARAPET_5M_U01; outputs/019facd3-bb17-7462-8504-0210c0919463/previews/tower_blender_5m_module_library_v006.png",
    "塔楼;女儿墙;护栏;5米;模块化;楼顶边界",
    "场景|room_kit|tower_descent|wall_parapet_5m|俯视3d|blender_review",
    "母版子集合",
    "",
    "Codex",
    new Date("2026-07-30T00:00:00+08:00"),
    "程序生成Blender源集合",
    "母对象MOD_WALL_PARAPET_5M_U01，与满高墙共享5m拼接接口；v006楼顶外边界虚拟表达268段女儿墙。当前是母版内子集合，尚未导出独立GLB。",
  ],
  [
    "ENV-TOWER-WALL-DOOR-5M",
    "塔楼5米带门墙模块",
    "场景",
    "room_kit",
    "tower_descent",
    "wall_door_5m",
    "ENV-TOWER-DESCENT-KIT-3D",
    "俯视3D",
    "blender_review",
    "5m墙位/4m净宽/4.5m净高/独立门扇",
    "程序占位",
    "P0",
    "v001",
    "Blender 4.2源集合/7个Mesh部件/左右与交互接口",
    sourcePath,
    "Blender集合=10D_MOD_WALL_DOOR_5M_U01; outputs/019facd3-bb17-7462-8504-0210c0919463/previews/tower_blender_5m_module_library_v006.png",
    "塔楼;门;门洞;5米;模块化;肉鸽触发;独立门扇",
    "场景|room_kit|tower_descent|wall_door_5m|俯视3d|blender_review",
    "母版子集合",
    "",
    "Codex",
    new Date("2026-07-30T00:00:00+08:00"),
    "程序生成Blender源集合",
    "母集合含左右墙垛、门楣、三段门框和独立DoorLeaf_OPEN；提供左右拼接Socket与交互Socket。v006实例化16个门模块，后续可在Godot拆分门扇动画、阻挡视野、碰撞和肉鸽卡片触发。尚未导出独立GLB。",
  ],
];

for (let index = 0; index < componentRows.length; index += 1) {
  const row = 164 + index;
  const rowRange = mainSheet.getRange(`A${row}:X${row}`);
  rowRange.copyFrom(mainSheet.getRange("A163:X163"), "all");
  rowRange.values = [componentRows[index]];
  rowRange.format.wrapText = true;
  rowRange.format.rowHeight = 145;
  mainSheet.getRange(`V${row}`).format.numberFormat = "yyyy-mm-dd";
}

const versionRow = versionSheet.getRange("A25:G25");
versionRow.copyFrom(versionSheet.getRange("A24:G24"), "all");
versionRow.values = [[
  "v1.19",
  new Date("2026-07-30T00:00:00+08:00"),
  "塔楼五米模块化楼层与墙体",
  "ENV-TOWER-DESCENT-KIT-3D; ENV-TOWER-FLOOR-TILE-5M; ENV-TOWER-WALL-SOLID-5M; ENV-TOWER-WALL-PARAPET-5M; ENV-TOWER-WALL-DOOR-5M",
  "登记v006：335m整层与65m基地/战斗核心全部对齐5m网格；地砖、满高墙、楼顶女儿墙、带门墙成为四个稳定子资产，基地完整围合，战斗内墙和门可独立拼装。",
  "v005用户内存状态另存快照；楼梯手调结构不重做。四个子资产当前仅为Blender程序占位，未导出GLB、未接入Godot。",
  "Codex",
]];
versionSheet.getRange("B25").format.numberFormat = "yyyy-mm-dd";
versionSheet.getRange("A25:G25").format.wrapText = true;
versionSheet.getRange("A25:G25").format.rowHeight = 115;

const mainPreview = await workbook.render({
  sheetName: "资产主表",
  range: "A163:X167",
  scale: 1.1,
  format: "png",
});
const versionPreview = await workbook.render({
  sheetName: "版本记录",
  range: "A22:G25",
  scale: 1.3,
  format: "png",
});
await fs.writeFile(
  path.join(workDir, "after_asset_main_v006.png"),
  new Uint8Array(await mainPreview.arrayBuffer()),
);
await fs.writeFile(
  path.join(workDir, "after_version_v006.png"),
  new Uint8Array(await versionPreview.arrayBuffer()),
);

const rowCheck = await workbook.inspect({
  kind: "table",
  range: "资产主表!A163:X167",
  include: "values,formulas",
  tableMaxRows: 8,
  tableMaxCols: 24,
  maxChars: 28000,
});
const versionCheck = await workbook.inspect({
  kind: "table",
  range: "版本记录!A24:G25",
  include: "values,formulas",
  tableMaxRows: 4,
  tableMaxCols: 8,
  maxChars: 16000,
});
const formulaErrors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 300 },
  summary: "final formula error scan",
  maxChars: 12000,
});
const finalInspection = [
  rowCheck.ndjson,
  versionCheck.ndjson,
  formulaErrors.ndjson,
].join("\n");
await fs.writeFile(
  path.join(workDir, "v006_final_inspect.ndjson"),
  finalInspection,
);
console.log(finalInspection);

const outputWorkbook = await SpreadsheetFile.exportXlsx(workbook);
await outputWorkbook.save(outputPath);
const canonicalWorkbook = await SpreadsheetFile.exportXlsx(workbook);
await canonicalWorkbook.save(canonicalPath);
console.log(`OUTPUT=${outputPath}`);
console.log(`CANONICAL=${canonicalPath}`);
