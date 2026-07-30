import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const projectRoot = "/Users/summercards/ShellStorm2";
const registryPath = `${projectRoot}/assets/registry/ShellStorm2_美术资产台账_v001.xlsx`;
const outputPath = `${projectRoot}/outputs/019facd3-bb17-7462-8504-0210c0919463/ShellStorm2_美术资产台账_v001.xlsx`;
const workDir = `${projectRoot}/outputs/019facd3-bb17-7462-8504-0210c0919463/registry_work`;

const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(registryPath));
const assetSheet = workbook.worksheets.getItem("资产主表");
const assetValues = assetSheet.getUsedRange(true).values;
const rowById = new Map();
for (let index = 0; index < assetValues.length; index += 1) {
  const assetId = String(assetValues[index][0] ?? "");
  if (assetId) rowById.set(assetId, index + 1);
}

const rootRow = rowById.get("ENV-TOWER-DESCENT-KIT-3D");
const wallRow = rowById.get("ENV-TOWER-WALL-SOLID-5M");
const doorRow = rowById.get("ENV-TOWER-WALL-DOOR-5M");
if (!rootRow || !wallRow || !doorRow) {
  throw new Error("PH37 tower parent/module rows are missing");
}

assetSheet.getRange(`J${rootRow}`).values = [[
  "335m楼顶/99层基地/98—95层种子化探索关卡/六个GLB运行时子资产",
]];
assetSheet.getRange(`P${rootRow}`).values = [[
  "env_tower_descent_kit_top3d_v006.blend; export_env_tower_5m_modules_v001.py; export_env_tower_stairwells_v001.py; docs/PH37_摩天楼99至95层深度玩法与楼梯资产接入.md; verify_tower_descent_flow.tscn",
]];
assetSheet.getRange(`V${rootRow}`).values = [[new Date(Date.UTC(2026, 6, 30))]];
assetSheet.getRange(`V${rootRow}`).format.numberFormat = "yyyy-mm-dd";
assetSheet.getRange(`X${rootRow}`).values = [[
  "v006 Blender母版已导出四个5m模块GLB与两套用户手调楼梯GLB。Godot首批运行楼顶、99层基地、98—95层；四个战斗层按种子从十字、南北回形与折线模板中选取，每层六房含固定电梯。楼顶/基地交通门免费无命运，98层入口免费并触发命运；Blender楼梯支持真实下行回爬、智能剖切和≤5层流送。",
]];

assetSheet.getRange(`J${wallRow}`).values = [[
  "整层外墙/65m核心/探索房内墙/5m正交走廊",
]];
assetSheet.getRange(`X${wallRow}`).values = [[
  "Godot已导入；满高墙严格到9m层高，与上一层0.30m楼板收口。房间和正交走廊使用该模块；楼梯间墙体改由两套Blender楼梯GLB直接提供。摄像机射线剖切不改变碰撞与逻辑视野。",
]];
assetSheet.getRange(`V${wallRow}`).values = [[new Date(Date.UTC(2026, 6, 30))]];
assetSheet.getRange(`V${wallRow}`).format.numberFormat = "yyyy-mm-dd";

assetSheet.getRange(`X${doorRow}`).values = [[
  "Godot已导入；导入门扇隐藏，由RoomDoor3D承担动画、4m通行碰撞和关闭视野。楼顶→99、99→98为免费无命运交通门；98入口门免费并触发命运；其余探索门维持清房、钥匙与命运循环，门楣补满至9m天花板。",
]];
assetSheet.getRange(`V${doorRow}`).values = [[new Date(Date.UTC(2026, 6, 30))]];
assetSheet.getRange(`V${doorRow}`).format.numberFormat = "yyyy-mm-dd";

const newAssets = [
  [
    "ENV-TOWER-STAIRWELL-GENERIC-9M",
    "塔楼9米通用双跑楼梯间",
    "场景",
    "room_kit",
    "tower_descent",
    "stairwell_generic_9m",
    "ENV-TOWER-DESCENT-KIT-3D",
    "俯视3D",
    "godot_runtime",
    "99层以下通用楼梯/四向旋转/上下楼交通",
    "原型已接入",
    "P0",
    "v001",
    "GLB / 14.751×27.617×约18.41m包围 / 9m层差 / 48子对象",
    "assets/art/environments/tower_descent_3d/components/env_tower_stairwell_generic_9m_top3d_v001.glb",
    "Blender根=Stair_Generic_Rotatable_ROOT; env_tower_descent_kit_top3d_v006.blend; export_env_tower_stairwells_v001.py; TowerDescent3D.gd; verify_tower_descent_flow.tscn",
    "塔楼;通用楼梯;双跑楼梯;折角平台;9米层高;四向旋转;Blender直出",
    null,
    null,
    "b0416e02b70673bb4cc38a58436210ff04343f6d68b4f5b80f8e1a0c5daaf844",
    "Codex",
    new Date(Date.UTC(2026, 6, 30)),
    "用户手工Blender模型",
    "直接导入用户在v006中调整的通用楼梯总成；局部+X朝核心外侧，上层门轴为原点、下层标高-9m。Godot仅补不可见碰撞、连续高度吸附、摄像机剖切与楼层流送，不再生成第二套踏步视觉。",
  ],
  [
    "ENV-TOWER-STAIRWELL-ROOFTOP-9M",
    "塔楼楼顶特殊双跑楼梯间",
    "场景",
    "room_kit",
    "tower_descent",
    "stairwell_rooftop_9m",
    "ENV-TOWER-DESCENT-KIT-3D",
    "俯视3D",
    "godot_runtime",
    "楼顶至99层特殊交通/保留手调墙高",
    "原型已接入",
    "P0",
    "v001",
    "GLB / 14.751×27.617×约15.36m包围 / 9m层差 / 47子对象",
    "assets/art/environments/tower_descent_3d/components/env_tower_stairwell_rooftop_9m_top3d_v001.glb",
    "Blender根=Stair_Special_Rooftop_ROOT; env_tower_descent_kit_top3d_v006.blend; export_env_tower_stairwells_v001.py; TowerDescent3D.gd; verify_tower_descent_flow.tscn",
    "塔楼;楼顶楼梯;特殊楼梯;双跑楼梯;特殊墙高;9米层高;Blender直出",
    null,
    null,
    "88198a579cc846974f17f5203b46b568b7ab2421fd7bb63c0b7868ddd05684a2",
    "Codex",
    new Date(Date.UTC(2026, 6, 30)),
    "用户手工Blender模型",
    "直接导入用户在v006中调整的楼顶特殊楼梯，保留特殊墙体高度与开口朝向。只用于楼顶→99层；门免费、无钥匙、无命运，关闭时仍阻挡角色与视野。",
  ],
];

const firstNewRow = rowById.get("ENV-TOWER-STAIRWELL-GENERIC-9M")
  ?? Math.max(
    assetSheet.getUsedRange(true).rowIndex + assetSheet.getUsedRange(true).rowCount + 1,
    168,
  );
for (let index = 0; index < newAssets.length; index += 1) {
  const row = rowById.get(String(newAssets[index][0])) ?? firstNewRow + index;
  assetSheet.getRange(`A${row}:X${row}`).copyFrom(
    assetSheet.getRange(`A${doorRow}:X${doorRow}`),
    "all",
  );
  assetSheet.getRange(`A${row}:X${row}`).values = [newAssets[index]];
  assetSheet.getRange(`R${row}`).formulas = [[
    `=LOWER(TRIM(C${row})&"|"&TRIM(D${row})&"|"&TRIM(E${row})&"|"&TRIM(F${row})&"|"&TRIM(H${row})&"|"&TRIM(I${row}))`,
  ]];
  assetSheet.getRange(`S${row}`).formulas = [[
    `=IF(COUNTIF($R:$R,R${row})>1,"重复","唯一")`,
  ]];
  assetSheet.getRange(`V${row}`).format.numberFormat = "yyyy-mm-dd";
  assetSheet.getRange(`A${row}:X${row}`).format.rowHeight = 112;
  assetSheet.getRange(`A${row}:X${row}`).format.wrapText = true;
  assetSheet.getRange(`A${row}:X${row}`).format.verticalAlignment = "center";
}

const versionSheet = workbook.worksheets.getItem("版本记录");
const versionValues = versionSheet.getUsedRange(true).values;
const existingV121 = versionValues.findIndex((row) => String(row[0] ?? "") === "v1.21");
const previousVersionIndex = versionValues.findIndex((row) => String(row[0] ?? "") === "v1.20");
const versionRow = existingV121 >= 0
  ? existingV121 + 1
  : previousVersionIndex >= 0
    ? previousVersionIndex + 2
    : versionValues.length + 1;
if (existingV121 < 0) {
  versionSheet.getRange(`A${versionRow}:G${versionRow}`).copyFrom(
    versionSheet.getRange(`A${versionRow - 1}:G${versionRow - 1}`),
    "all",
  );
}
versionSheet.getRange(`A${versionRow}:G${versionRow}`).values = [[
  "v1.21",
  new Date(Date.UTC(2026, 6, 30)),
  "Blender楼梯直入与99—95层种子化关卡",
  "ENV-TOWER-DESCENT-KIT-3D; ENV-TOWER-STAIRWELL-GENERIC-9M; ENV-TOWER-STAIRWELL-ROOFTOP-9M",
  "两套用户手调楼梯从v006根节点直接导出GLB并接入Godot；登记前三段门禁差异、四类种子化房间模板、固定电梯、95层Boss、城市/室内光、智能遮挡与≤5层流送。",
  "新增两个楼梯子AssetID，不复制程序踏步；四个5m模块ID和母版ID不变；运行时碰撞/吸附与Blender视觉职责分离。",
  "Codex",
]];
versionSheet.getRange(`B${versionRow}`).format.numberFormat = "yyyy-mm-dd";
versionSheet.getRange(`A${versionRow}:G${versionRow}`).format.rowHeight = 118;
versionSheet.getRange(`A${versionRow}:G${versionRow}`).format.wrapText = true;
versionSheet.getRange(`A${versionRow}:G${versionRow}`).format.verticalAlignment = "center";

const exported = await SpreadsheetFile.exportXlsx(workbook);
await exported.save(registryPath);
await exported.save(outputPath);

const assetCheck = await workbook.inspect({
  kind: "table",
  sheetId: "资产主表",
  range: `A${rootRow}:X${firstNewRow + newAssets.length - 1}`,
  include: "values,formulas",
  tableMaxRows: 12,
  tableMaxCols: 24,
  maxChars: 30000,
});
console.log(assetCheck.ndjson);
const versionCheck = await workbook.inspect({
  kind: "table",
  sheetId: "版本记录",
  range: `A${versionRow - 1}:G${versionRow}`,
  include: "values,formulas",
  tableMaxRows: 4,
  tableMaxCols: 7,
  maxChars: 8000,
});
console.log(versionCheck.ndjson);
const formulaErrors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 300 },
  summary: "PH37 final formula error scan",
});
console.log(formulaErrors.ndjson);

const assetPreview = await workbook.render({
  sheetName: "资产主表",
  range: `A${rootRow}:X${firstNewRow + newAssets.length - 1}`,
  scale: 1,
  format: "png",
});
await fs.writeFile(
  `${workDir}/registry_after_ph37.png`,
  new Uint8Array(await assetPreview.arrayBuffer()),
);
const versionPreview = await workbook.render({
  sheetName: "版本记录",
  range: `A${versionRow - 2}:G${versionRow}`,
  scale: 1,
  format: "png",
});
await fs.writeFile(
  `${workDir}/registry_version_after_ph37.png`,
  new Uint8Array(await versionPreview.arrayBuffer()),
);
