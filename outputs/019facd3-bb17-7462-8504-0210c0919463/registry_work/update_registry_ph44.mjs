import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const root = "/Users/summercards/ShellStorm2";
const inputPath = `${root}/assets/registry/ShellStorm2_美术资产台账_v001.xlsx`;
const outputPath =
  `${root}/outputs/019facd3-bb17-7462-8504-0210c0919463/ShellStorm2_美术资产台账_v001.xlsx`;
const workDir =
  `${root}/outputs/019facd3-bb17-7462-8504-0210c0919463/registry_work/ph44`;
await fs.mkdir(workDir, { recursive: true });

const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(inputPath));
const sheetOverview = await workbook.inspect({
  kind: "sheet",
  include: "id,name",
  maxChars: 5000,
});
await fs.writeFile(`${workDir}/sheet_overview.ndjson`, sheetOverview.ndjson);

const sheetNames = workbook.worksheets.items.map((sheet) => sheet.name);
for (const sheetName of sheetNames) {
  const preview = await workbook.render({
    sheetName,
    autoCrop: "all",
    scale: 1,
    format: "png",
  });
  await fs.writeFile(
    `${workDir}/before_${sheetName}.png`,
    new Uint8Array(await preview.arrayBuffer()),
  );
}

function firstRow(address) {
  const match = String(address).match(/[A-Z]+(\d+)/);
  return match ? Number(match[1]) : 1;
}

function findRow(sheet, predicate) {
  const used = sheet.getUsedRange(true);
  const start = firstRow(used.address);
  const index = used.values.findIndex(predicate);
  if (index < 0) throw new Error(`Registry row not found in ${sheet.name}`);
  return start + index;
}

const changedDate = new Date(Date.UTC(2026, 6, 30));
const main = workbook.worksheets.getItem("资产主表");
const mainUpdates = {
  "ENV-TOWER-DESCENT-KIT-3D":
    "PH44：Godot整层统一为50×50个5m网格，即250×250m、2500块地砖；65×65m基地核心保持不变，并以XZ各+2.5m对齐偶数整层网格。普通战斗层采用4×4槽位：12个45×45m外环房间，中央2×2槽位留给10m主走廊与上下楼梯。Boss层采用90×90m Boss区并保留9个普通房间。固定镜头仍为角色相对(0,8,5.5)、FOV 55°；新增仅隐藏镜头到角色射线所命中的墙体渲染的局部剖切，碰撞、门、视野阻挡与楼梯承重均不关闭。完整探索节点数2783。",
  "ENV-TOWER-FLOOR-TILE-5M":
    "PH44：整层由67×67调整为50×50个5m模块，物理尺寸250×250m、满铺2500块；地板仍由模块化MultiMesh渲染并保留独立StaticBody承重。四向楼梯洞口改用对齐5m世界矩形换算网格，避免尺寸与位移单位错位。",
  "ENV-TOWER-WALL-SOLID-5M":
    "PH44：继续复用同一5m实墙模块；45m战斗房每边按9个模块拼接。为控制250m楼层节点量，同方向连续实墙改为单个MultiMeshInstance3D批量渲染，碰撞按门洞两侧合并成长条StaticBody形状；视觉仍保持逐5m模块拼缝与命名语义。",
  "ENV-TOWER-WALL-PARAPET-5M":
    "PH44：继续复用同一5m围栏模块，按50×50网格环绕250×250m楼顶与整层边界，不新增大块整体网格；普通楼顶由统一太阳照明，楼梯口局部阴影不再靠提高全局环境亮度解决。",
  "ENV-TOWER-WALL-DOOR-5M":
    "PH44：继续作为独立5m门墙语义模块；门洞不并入实墙MultiMesh，确保RoomDoor3D、命运卡、房间清理锁定与上下楼梯接口仍可逐门控制。上下层连接支持两端独立开口朝向。",
  "ENV-TOWER-STAIRWELL-GENERIC-9M":
    "PH44：继续直接复用用户v006通用9m楼梯视觉与六块Walkable同形常驻碰撞；按5m世界矩形对齐250m整层中的四向楼梯洞口，可旋转通用。上下端门侧分别记录，避免楼梯开口朝向改变后沿用同一侧导致错位。",
  "ENV-TOWER-STAIRWELL-ROOFTOP-9M":
    "PH44：继续复用用户v006楼顶特殊楼梯、加高墙体及常驻Walkable/EnclosureWall碰撞。楼顶纯黑问题确认为固定斜俯视镜头被门墙整段遮挡；现仅剖切遮挡角色的墙体渲染，并联动同方向5m墙段，物理碰撞、门和楼梯围护保持有效；天空反弹光降至1.25，仅补兼容渲染器缺少实时天空GI。",
};

const updatedRows = [];
for (const [assetId, note] of Object.entries(mainUpdates)) {
  const row = findRow(main, (values) => String(values[0] ?? "") === assetId);
  main.getRange(`V${row}`).values = [[changedDate]];
  main.getRange(`V${row}`).format.numberFormat = "yyyy-mm-dd";
  main.getRange(`X${row}`).values = [[note]];
  main.getRange(`A${row}:X${row}`).format.wrapText = true;
  main.getRange(`A${row}:X${row}`).format.verticalAlignment = "center";
  main.getRange(`A${row}:X${row}`).format.rowHeight = 132;
  updatedRows.push(row);
}

const relevantStyle = await workbook.inspect({
  kind: "computedStyle",
  sheetId: "资产主表",
  range: `A${Math.min(...updatedRows)}:X${Math.max(...updatedRows)}`,
  maxChars: 5000,
});
await fs.writeFile(`${workDir}/updated_rows_style.ndjson`, relevantStyle.ndjson);

const versions = workbook.worksheets.getItem("版本记录");
const versionUsed = versions.getUsedRange(true);
const versionStart = firstRow(versionUsed.address);
let versionRow = versionStart + versionUsed.values.length;
const existingVersion = versionUsed.values.findIndex(
  (row) => String(row[0] ?? "") === "v1.26",
);
if (existingVersion >= 0) {
  versionRow = versionStart + existingVersion;
} else {
  versions
    .getRange(`A${versionRow}:G${versionRow}`)
    .copyFrom(versions.getRange(`A${versionRow - 1}:G${versionRow - 1}`), "all");
}
versions.getRange(`A${versionRow}:G${versionRow}`).values = [[
  "v1.26",
  changedDate,
  "PH44二百五十米塔楼与四乘四战斗层重构",
  "塔楼整层 / 5m地砖与墙体 / 两套9m楼梯 / 固定镜头局部剖切",
  "整层统一50×50格（250×250m、2500砖）；65×65m基地核心不变并偏移2.5m对齐；普通层12个45×45m房间，Boss层90×90m Boss区+9个普通房；实墙按方向MultiMesh批渲染并合并碰撞；上下楼梯分别记录两端门侧；固定8m镜头只剖切挡住角色的墙体渲染；楼顶天空反弹光降至1.25。",
  "不新增AssetID、GLB或贴图；v006楼梯与既有5m模块继续复用；碰撞、房门、命运卡、刷怪、流送和固定镜头角度保持兼容。完整探索节点数2783。",
  "Codex",
]];
versions.getRange(`B${versionRow}`).format.numberFormat = "yyyy-mm-dd";
versions.getRange(`A${versionRow}:G${versionRow}`).format.wrapText = true;
versions.getRange(`A${versionRow}:G${versionRow}`).format.verticalAlignment = "center";
versions.getRange(`A${versionRow}:G${versionRow}`).format.rowHeight = 118;

const mainCheck = await workbook.inspect({
  kind: "region",
  sheetId: "资产主表",
  range: `A${Math.min(...updatedRows)}:X${Math.max(...updatedRows)}`,
  maxChars: 14000,
  tableMaxRows: 80,
  tableMaxCols: 24,
  tableMaxCellChars: 180,
});
await fs.writeFile(`${workDir}/updated_rows.ndjson`, mainCheck.ndjson);
const versionCheck = await workbook.inspect({
  kind: "region",
  sheetId: "版本记录",
  range: `A${versionRow}:G${versionRow}`,
  maxChars: 5000,
  tableMaxRows: 4,
  tableMaxCols: 7,
  tableMaxCellChars: 300,
});
await fs.writeFile(`${workDir}/version_v126.ndjson`, versionCheck.ndjson);
const errorScan = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 100 },
  summary: "PH44 formula error scan",
});
await fs.writeFile(`${workDir}/formula_error_scan.ndjson`, errorScan.ndjson);
console.log(errorScan.ndjson);

for (const sheetName of sheetNames) {
  const preview = await workbook.render({
    sheetName,
    autoCrop: "all",
    scale: 1,
    format: "png",
  });
  await fs.writeFile(
    `${workDir}/after_${sheetName}.png`,
    new Uint8Array(await preview.arrayBuffer()),
  );
}

const exported = await SpreadsheetFile.exportXlsx(workbook);
await exported.save(outputPath);
const canonical = await SpreadsheetFile.exportXlsx(workbook);
await canonical.save(inputPath);
console.log(`PH44 registry exported: ${outputPath}`);
