import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const projectRoot = "/Users/summercards/ShellStorm2";
const inputPath = `${projectRoot}/assets/registry/ShellStorm2_美术资产台账_v001.xlsx`;
const workDir = `${projectRoot}/outputs/019facd3-bb17-7462-8504-0210c0919463/registry_work`;

const input = await FileBlob.load(inputPath);
const workbook = await SpreadsheetFile.importXlsx(input);
const sheet = workbook.worksheets.getItem("资产主表");
const values = sheet.getUsedRange(true).values;
const rowById = new Map();
for (let rowIndex = 0; rowIndex < values.length; rowIndex += 1) {
  const assetId = String(values[rowIndex][0] ?? "");
  if (assetId) rowById.set(assetId, rowIndex + 1);
}

const updates = {
  "ENV-TOWER-DESCENT-KIT-3D": {
    I: "godot_runtime",
    J: "335m楼顶/99层基地/98—95层探索关卡/5m模块运行时",
    K: "原型已接入",
    P: "env_tower_descent_kit_top3d_v006.blend; export_env_tower_5m_modules_v001.py; docs/PH36_塔楼五米模块Godot关卡Demo.md; verify_tower_descent_flow.tscn",
    T: "a99ca6f01c875cdf9414a9f132bbb9d4c2a921b4b4871346170ee6e6701130a2",
    X: "v006 Blender母版已导出四个5m GLB并接入TowerDescent3D。首批生成楼顶、99层基地、98—95层；每探索层五房+固定电梯房，门后命运、刷怪、钥匙、Boss/撤离复用Dungeon3D。9m双跑楼梯支持真实下行与回爬；楼层窗口≤5；专项节点3390并通过视野/命运/性能回归。",
  },
  "ENV-TOWER-FLOOR-TILE-5M": {
    I: "godot_runtime",
    J: "塔楼六个物理层楼板/335m MultiMesh网格",
    K: "原型已接入",
    N: "GLB / 5×5×0.30m / 共享Mesh / MultiMesh平铺",
    O: "assets/art/environments/tower_descent_3d/components/env_tower_floor_tile_5m_top3d_v001.glb",
    P: "Blender集合=10A_MOD_FLOOR_TILE_5M_U01; export_env_tower_5m_modules_v001.py; TowerFloorStage3D.gd; verify_tower_descent_flow.tscn",
    T: "987b220bef57c4176590caf7568c909d90768450c00f7e4e27c4c61986e6ef2d",
    X: "Godot已导入；每层67×67个5m格由MultiMesh批量绘制，楼梯开口格剔除；承重碰撞与渲染分离，隐藏楼层仍保留FloorSupport。",
  },
  "ENV-TOWER-WALL-SOLID-5M": {
    I: "godot_runtime",
    J: "整层外墙/65m核心/探索房内墙/走廊与楼梯间",
    K: "原型已接入",
    N: "GLB / 5×0.30×9m / 共享Mesh / 可旋转",
    O: "assets/art/environments/tower_descent_3d/components/env_tower_wall_solid_5m_top3d_v001.glb",
    P: "Blender集合=10B_MOD_WALL_SOLID_5M_U01; export_env_tower_5m_modules_v001.py; DungeonRoom3D.gd; TowerFloorStage3D.gd",
    T: "5680bf2dedc964fcbfd5e5ee7d5ba86af5ba8a2c77c64a02151aee19a7f2cc33",
    X: "Godot已导入；满高墙严格到9m层高，与上一层0.30m楼板收口。塔楼房间使用摄像机—角色射线智能剖切，碰撞与逻辑视野不随表现隐藏。",
  },
  "ENV-TOWER-WALL-PARAPET-5M": {
    I: "godot_runtime",
    J: "335m楼顶四周边界/268段MultiMesh围栏",
    K: "原型已接入",
    N: "GLB / 5×0.30×1.50m / 共享Mesh",
    O: "assets/art/environments/tower_descent_3d/components/env_tower_wall_parapet_5m_top3d_v001.glb",
    P: "Blender集合=10C_MOD_WALL_PARAPET_5M_U01; export_env_tower_5m_modules_v001.py; TowerFloorStage3D.gd; verify_tower_descent_visual.tscn",
    T: "44fdb663487a9bf010d8fa249a2f9811843409c35d9f7ce8d09c48f7de7bf808",
    X: "Godot已导入；楼顶边界按每边67段、总计268段拼接，并与99层满高外立面及楼顶城市远景共同显示。",
  },
  "ENV-TOWER-WALL-DOOR-5M": {
    I: "godot_runtime",
    J: "塔楼房间门/走廊接口/楼梯门/命运触发",
    K: "原型已接入",
    N: "GLB / 5m墙位 / 4m净宽 / 4.5m净高 / 独立门扇",
    O: "assets/art/environments/tower_descent_3d/components/env_tower_wall_door_5m_top3d_v001.glb",
    P: "Blender集合=10D_MOD_WALL_DOOR_5M_U01; export_env_tower_5m_modules_v001.py; RoomDoor3D.gd; verify_tower_descent_flow.tscn",
    T: "da5c2938eaca6360d945cdeb19d7af47c5ec64462c9065211191a9cf37deafe3",
    X: "Godot已导入；导入门扇隐藏，由RoomDoor3D承担动画、4m通行碰撞、关闭视野阻挡和开门命运卡触发，门楣补满至9m天花板。",
  },
};

for (const [assetId, fields] of Object.entries(updates)) {
  const row = rowById.get(assetId);
  if (!row) throw new Error(`Missing registry row: ${assetId}`);
  for (const [column, value] of Object.entries(fields)) {
    sheet.getRange(`${column}${row}`).values = [[value]];
  }
  sheet.getRange(`V${row}`).values = [[new Date(Date.UTC(2026, 6, 30))]];
  sheet.getRange(`V${row}`).format.numberFormat = "yyyy-mm-dd";
}

const versionSheet = workbook.worksheets.getItem("版本记录");
const versionUsed = versionSheet.getUsedRange(true);
const existingVersionIndex = versionUsed.values.findIndex((row) => String(row[0] ?? "") === "v1.20");
const nextVersionRow = existingVersionIndex >= 0 ? existingVersionIndex + 1 : versionUsed.values.length + 1;
if (existingVersionIndex < 0) {
  versionSheet.getRange(`A${nextVersionRow}:G${nextVersionRow}`).copyFrom(
    versionSheet.getRange(`A${nextVersionRow - 1}:G${nextVersionRow - 1}`),
    "all",
  );
}
versionSheet.getRange(`A${nextVersionRow}:G${nextVersionRow}`).values = [[
  "v1.20",
  new Date(Date.UTC(2026, 6, 30)),
  "塔楼5m GLB与99—95层Godot首批关卡接入",
  "ENV-TOWER-DESCENT-KIT-3D及四个5m子资产",
  "四个Blender模块导出独立GLB并接入335m楼顶、99层基地、98—95层五房+电梯探索关卡；登记9m双跑楼梯、门后命运、Boss/撤离、城市日照、智能剖切与≤5层流送验收。",
  "AssetID与v006 Blender母版不变；子资产状态由程序占位升级为原型已接入；旧四主题Dungeon3D玩法继续共用。",
  "Codex",
]];
versionSheet.getRange(`B${nextVersionRow}`).format.numberFormat = "yyyy-mm-dd";
versionSheet.getRange(`A${nextVersionRow}:G${nextVersionRow}`).format.rowHeight = 118;
versionSheet.getRange(`A${nextVersionRow}:G${nextVersionRow}`).format.wrapText = true;
versionSheet.getRange(`A${nextVersionRow}:G${nextVersionRow}`).format.verticalAlignment = "center";

const outputPath = `${projectRoot}/outputs/019facd3-bb17-7462-8504-0210c0919463/ShellStorm2_美术资产台账_v001.xlsx`;
const registryPath = `${projectRoot}/assets/registry/ShellStorm2_美术资产台账_v001.xlsx`;
const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);
await output.save(registryPath);

const check = await workbook.inspect({
  kind: "table",
  sheetId: "资产主表",
  range: "A163:X167",
  include: "values,formulas",
  tableMaxRows: 8,
  tableMaxCols: 24,
  maxChars: 12000,
});
console.log(check.ndjson);
const versionCheck = await workbook.inspect({
  kind: "table",
  sheetId: "版本记录",
  range: `A${nextVersionRow}:G${nextVersionRow}`,
  include: "values,formulas",
  tableMaxRows: 3,
  tableMaxCols: 7,
  maxChars: 4000,
});
console.log(versionCheck.ndjson);
const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 300 },
  summary: "final formula error scan",
});
console.log(errors.ndjson);
const preview = await workbook.render({
  sheetName: "资产主表",
  range: "A163:X167",
  scale: 1,
  format: "png",
});
await fs.writeFile(`${workDir}/registry_after_ph36.png`, new Uint8Array(await preview.arrayBuffer()));
const versionPreview = await workbook.render({
  sheetName: "版本记录",
  range: `A20:G${nextVersionRow}`,
  scale: 1,
  format: "png",
});
await fs.writeFile(`${workDir}/registry_version_after_ph36.png`, new Uint8Array(await versionPreview.arrayBuffer()));
