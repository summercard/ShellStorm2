import fs from "node:fs/promises";
import path from "node:path";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const root = "/Users/summercards/ShellStorm2";
const canonicalPath =
  `${root}/assets/registry/ShellStorm2_美术资产台账_v001.xlsx`;
const outputPath =
  `${root}/outputs/019fb2a5-6bc8-7d10-a214-90288a5f7e80/ShellStorm2_美术资产台账_v001.xlsx`;
const workDir =
  `${root}/outputs/019fb2a5-6bc8-7d10-a214-90288a5f7e80/registry_work`;
await fs.mkdir(workDir, { recursive: true });

const workbook = await SpreadsheetFile.importXlsx(
  await FileBlob.load(canonicalPath),
);
const changedDate = new Date(Date.UTC(2026, 6, 30));

function firstRow(address) {
  const match = String(address).match(/[A-Z]+(\d+)/);
  return match ? Number(match[1]) : 1;
}

function findRow(sheet, assetId) {
  const used = sheet.getUsedRange(true);
  const start = firstRow(used.address);
  const index = used.values.findIndex(
    (values) => String(values[0] ?? "") === assetId,
  );
  if (index < 0) {
    throw new Error(`AssetID not found: ${assetId}`);
  }
  return start + index;
}

const main = workbook.worksheets.getItem("资产主表");
const changes = {
  "ENV-TOWER-DESCENT-KIT-3D": {
    J: "250×250m整层；99层30×30m/6×6格基地；98—95层终局路线；2.2×2.5m门",
    K: "已接入",
    M: "v007",
    N: "Blender 4.2源文件/1单位=1m/PH49运行时布局审阅集合",
    O: "assets/art/environments/tower_descent_3d/source/env_tower_descent_kit_top3d_v007.blend",
    P: "assets/art/environments/tower_descent_3d/source/sync_env_tower_descent_kit_top3d_v007.py; assets/art/environments/tower_descent_3d/source/validate_env_tower_descent_kit_top3d_v007.py; outputs/019fb2a5-6bc8-7d10-a214-90288a5f7e80/previews/env_tower_descent_v007_base99.png; outputs/019fb2a5-6bc8-7d10-a214-90288a5f7e80/previews/env_tower_descent_v007_floors98_95.png",
    T: "ef19c00e61478f0b3268edd9746e7fcf6704a2865aac0b4121474ab9b98e7552",
    W: "用户楼梯资产 + Codex PH49运行时同步",
    X: "PH49：保留99→98楼梯间位置，并在99层基地墙边补17.5m连接走廊；基地改为精确30×30m、6×6个5m地砖。98层入口门位于楼梯间左侧语义方向，关卡改刷在门的内侧而不是对侧。98—95层均含探索、搜刮、战斗、撤离及种子化随机房间/掉落；五处电梯为房间树之外的独立墙边设施。v007 Blender母版同步了基地、两条走廊、46个房间占位、5个独立电梯与2.2×2.5m门合同。",
  },
  "ENV-TOWER-WALL-DOOR-5M": {
    J: "5m墙位/2.2m净宽/2.5m净高/独立门扇",
    K: "已接入",
    M: "v002",
    N: "Blender 4.2 GLB/7个Mesh部件/2.2×2.5m净开口",
    O: "assets/art/environments/tower_descent_3d/components/env_tower_wall_door_5m_top3d_v002.glb",
    P: "assets/art/environments/tower_descent_3d/source/export_env_tower_door_5m_v002.py; assets/art/environments/tower_descent_3d/source/env_tower_descent_kit_top3d_v007.blend",
    T: "75f03e2bc785b0d957df9e27940ac9a024097ce6f2c371ae947b2c48cce69ca1",
    W: "Codex Blender导出 + Godot运行时接入",
    X: "PH49：门洞合同统一为2.2m宽、2.5m高；RoomDoor3D门扇、碰撞、开门抬升距离和四向墙垛均按同一尺寸更新。门开启后禁用门扇碰撞，角色可通过；98—95层全部逻辑门执行双向目标验收。",
  },
  "ENV-DUNGEON-RUNTIME-3D": {
    K: "已接入",
    X: "PH49：塔楼98—95层形成可闭环的搜打撤流程；普通层每层同时含战斗房和搜刮房，容器按种子掉落。Boss房清理后现在按房间类型正确解锁撤离，不再依赖固定room_id。生成快照增加门连通与全息小地图实时状态，测试覆盖100→99→98实机楼梯路径、95层Boss和撤离完成。",
  },
  "PRP-BASE-FACILITY-3D": {
    K: "已接入",
    X: "PH49：BaseFacility3D复用于五个独立电梯设施（99—95层各一处），设施挂在走廊设施层级而非房间内部，放置在基地房间墙边或楼层走廊边。电梯解锁、目标楼层和到达点从邻接的elevator_access房间读取。",
  },
  "PRP-WASTELAND-LIGHT-3D": {
    K: "已接入",
    X: "PH49：灯具最大作用范围提升到64m；普通房按房间短边约94%设置可感知范围并提高能量。基地采用四盏冷暖混合顶灯、26m范围；95层90m Boss区采用四区顶灯。两者默认开启但都保留墙边总开关，楼梯大厅也提供基础照明。",
  },
  "PRP-ROOM-LIGHT-SWITCH-3D": {
    K: "已接入",
    X: "PH49：开关新增灯组控制，同一开关可统一切换多盏房间灯；基地四灯共用一个墙边开关并在快照中报告控制灯数量。单灯房继续兼容原接口。",
  },
  "UI-SCREEN-HUD": {
    K: "已接入",
    M: "v002",
    X: "PH49：主游戏HUD升级为深色半透明青色全息面板，危险/撤离信息使用琥珀与绿色分层；小地图以20Hz实时更新当前楼层，显示玩家位置与朝向、扫描扇区、脉冲环、透视网格、已发现房间/连线和楼层纵向索引。",
  },
  "CHR-PLY-CAPSULE01-3D": {
    X: "PH49：原先项目外shellstorm2-art/blender中的三份角色Blender源已按稳定命名归档到assets/art/characters/player/chr_player_capsule01_3d/source/，SHA-256与原件一致；运行时场景路径不变，后续不再依赖仓库外资产。",
  },
};

const changedRows = [];
for (const [assetId, fields] of Object.entries(changes)) {
  const row = findRow(main, assetId);
  for (const [column, value] of Object.entries(fields)) {
    main.getRange(`${column}${row}`).values = [[value]];
  }
  main.getRange(`V${row}`).values = [[changedDate]];
  main.getRange(`V${row}`).format.numberFormat = "yyyy-mm-dd";
  main.getRange(`A${row}:X${row}`).format.wrapText = true;
  main.getRange(`A${row}:X${row}`).format.verticalAlignment = "center";
  main.getRange(`A${row}:X${row}`).format.rowHeight = 155;
  changedRows.push(row);
}

const versions = workbook.worksheets.getItem("版本记录");
const versionUsed = versions.getUsedRange(true);
const versionStart = firstRow(versionUsed.address);
let versionRow = versionStart + versionUsed.values.length;
let versionNumber = 1;
for (const row of versionUsed.values) {
  const match = String(row[0] ?? "").match(/^v1\.(\d+)$/);
  if (match) {
    versionNumber = Math.max(versionNumber, Number(match[1]) + 1);
  }
}
const existingIndex = versionUsed.values.findIndex(
  (row) => String(row[2] ?? "") === "PH49九十八至九十五层终局关卡与全局系统验收",
);
if (existingIndex >= 0) {
  versionRow = versionStart + existingIndex;
  const existingMatch = String(versionUsed.values[existingIndex][0] ?? "")
    .match(/^v1\.(\d+)$/);
  if (existingMatch) {
    versionNumber = Number(existingMatch[1]);
  }
} else {
  versions
    .getRange(`A${versionRow}:G${versionRow}`)
    .copyFrom(versions.getRange(`A${versionRow - 1}:G${versionRow - 1}`), "all");
}
versions.getRange(`A${versionRow}:G${versionRow}`).values = [[
  `v1.${versionNumber}`,
  changedDate,
  "PH49九十八至九十五层终局关卡与全局系统验收",
  "ENV-TOWER-DESCENT-KIT-3D; ENV-TOWER-WALL-DOOR-5M; ENV-DUNGEON-RUNTIME-3D; PRP-BASE-FACILITY-3D; PRP-WASTELAND-LIGHT-3D; PRP-ROOM-LIGHT-SWITCH-3D; UI-SCREEN-HUD; CHR-PLY-CAPSULE01-3D",
  "完成98—95层怪物、搜刮、随机房间/掉落与95层Boss撤离闭环；基地30×30m/6×6格；修正98层入口内外侧；电梯改为墙边独立设施；门统一2.2×2.5m；环境光改为全局固定；关闭会让墙体概率消失的相机材质淡出；基地四灯组和开关；实时3D全息小地图与游戏化HUD。",
  "Blender v007与Godot布局同步；导出门v002 GLB；三份仓库外角色Blender源归档进项目且不新增重复AssetID。主流程、全部楼层门、实际楼梯、灯光开关、随机种子、Boss撤离、相机遮挡和性能预算均有自动验收。",
  "Codex",
]];
versions.getRange(`B${versionRow}`).format.numberFormat = "yyyy-mm-dd";
versions.getRange(`A${versionRow}:G${versionRow}`).format.wrapText = true;
versions.getRange(`A${versionRow}:G${versionRow}`).format.verticalAlignment =
  "center";
versions.getRange(`A${versionRow}:G${versionRow}`).format.rowHeight = 128;

const changedMin = Math.min(...changedRows);
const changedMax = Math.max(...changedRows);
const changedCheck = await workbook.inspect({
  kind: "region",
  sheetId: "资产主表",
  range: `A${changedMin}:X${changedMax}`,
  tableMaxRows: changedMax - changedMin + 1,
  tableMaxCols: 24,
  tableMaxCellChars: 240,
  maxChars: 42000,
});
await fs.writeFile(`${workDir}/ph49_changed_rows.ndjson`, changedCheck.ndjson);
const versionCheck = await workbook.inspect({
  kind: "region",
  sheetId: "版本记录",
  range: `A${versionRow}:G${versionRow}`,
  tableMaxRows: 2,
  tableMaxCols: 7,
  tableMaxCellChars: 500,
  maxChars: 8000,
});
await fs.writeFile(`${workDir}/ph49_version.ndjson`, versionCheck.ndjson);
const formulaErrors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 200 },
  summary: "PH49 formula error scan",
  maxChars: 12000,
});
await fs.writeFile(
  `${workDir}/ph49_formula_error_scan.ndjson`,
  formulaErrors.ndjson,
);

const previewRanges = {
  "资产主表": `A1:X${main.getUsedRange(true).values.length}`,
  "分类与编码": workbook.worksheets.getItem("分类与编码").getUsedRange(true).address,
  "角色组件": workbook.worksheets.getItem("角色组件").getUsedRange(true).address,
  "动画与状态": workbook.worksheets.getItem("动画与状态").getUsedRange(true).address,
  "命名与查重": workbook.worksheets.getItem("命名与查重").getUsedRange(true).address,
  "版本记录": `A1:G${versions.getUsedRange(true).values.length}`,
};
for (const [sheetName, range] of Object.entries(previewRanges)) {
  const preview = await workbook.render({
    sheetName,
    range,
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
await canonical.save(canonicalPath);

console.log(
  JSON.stringify({
    changedRows,
    version: `v1.${versionNumber}`,
    versionRow,
    formulaErrors: formulaErrors.ndjson,
    outputPath,
    canonicalPath,
  }),
);
