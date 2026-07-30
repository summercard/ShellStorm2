import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const projectRoot = "/Users/summercards/ShellStorm2";
const registryPath = `${projectRoot}/assets/registry/ShellStorm2_美术资产台账_v001.xlsx`;
const outputPath =
  `${projectRoot}/outputs/019facd3-bb17-7462-8504-0210c0919463/ShellStorm2_美术资产台账_v001.xlsx`;
const workDir =
  `${projectRoot}/outputs/019facd3-bb17-7462-8504-0210c0919463/registry_work`;
const sourcePath =
  "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source/chr_player_capsule01_bunny01_top3d_v005.blend";
const componentRoot =
  "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components";
const rootPath =
  "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/chr_player_capsule01_bunny01_root_top3d_v005.tscn";

const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(registryPath));
const assetSheet = workbook.worksheets.getItem("资产主表");
const assetValues = assetSheet.getUsedRange(true).values;
const rowById = new Map();
for (let index = 0; index < assetValues.length; index += 1) {
  const assetId = String(assetValues[index][0] ?? "");
  if (assetId) rowById.set(assetId, index + 1);
}

const updates = {
  "CHR-PLY-CAPSULE01-3D-BUNNY01": {
    spec: "0.689×1.000×0.430 m / 完整视觉含耳",
    path: rootPath,
    hash: "d75eeba6e278310f741353da65978f1e46f05485c26713595c4698249deb00b0",
    note: "PH39 v005：Blender与Godot静态完整视觉高度统一为1.000m；真实分体网格和关节均按0.404040404缩放，未使用运行时根节点假缩放。Player3D不可见碰撞为0.477778×1.000000×0.400000m，顶部与双耳视觉顶部同为1m；持枪视觉、VFX、可穿戴与所有米制动画位移同步缩放。verify_bunny_v005_bounds、武器姿势/碰撞、六态动画、DIY与塔楼回归通过。",
  },
  "CHR-PLY-CAPSULE01-3D-BUNNY01-BODY": {
    spec: "GLB / 1,958 verts / pivot-local / 1m总高比例",
    path: `${componentRoot}/chr_player_capsule01_bunny01_body_top3d_v005.glb`,
    hash: "53d5367aca64951d0e2454964d711f45c0bc17172148c015fd5da3e1979887f1",
    note: "PH39 v005：身体网格及底部中心原点按0.404040404真实缩放；Godot BodyJoint=(-0.000020,0.103348,-0.000423)。",
  },
  "CHR-PLY-CAPSULE01-3D-BUNNY01-HEAD": {
    spec: "GLB / 5,936 verts / pivot-local / 头顶0.735593m",
    path: `${componentRoot}/chr_player_capsule01_bunny01_head_top3d_v005.glb`,
    hash: "706b52578cc487262cf19fd7fc0f96d7080375369d22abb30f9127bc7edabb26",
    note: "PH39 v005：头部网格及下沿中心原点真实缩放；不含耳头顶为0.735593m，完整双耳顶部为1.000m。",
  },
  "CHR-PLY-CAPSULE01-3D-BUNNY01-EARS": {
    spec: "单 GLB / 1,536 verts / pivot-local / 双实例",
    path: `${componentRoot}/chr_player_capsule01_bunny01_ear_top3d_v005.glb`,
    hash: "e05bb0f2133562e22d442ceec49ddd7a7cc104055e3d0167a7cea0a7a2dc58ee",
    note: "PH39 v005：耳朵网格与耳根原点真实缩放；左右挂点继续复用单资产，装配后最高点严格为1.000m。",
  },
  "CHR-PLY-CAPSULE01-3D-BUNNY01-HAND": {
    spec: "双 GLB / 左右各1,058 verts / pivot-local / 1m角色比例",
    path: `${componentRoot}/chr_player_capsule01_bunny01_hand_l_top3d_v005.glb; ${componentRoot}/chr_player_capsule01_bunny01_hand_r_top3d_v005.glb`,
    hash: "f9544066d56e9eaa468f5235cdb03da441dc5dbbcd0e32faa18daf7f7d9fbd03 / e7d55ec3b66e3acae3fb67271b7eb27b61a4353349e948aa586a83b49f207795",
    note: "PH39 v005：左右手网格、手腕原点、单手/双手握持目标和动作平移统一缩放；持枪模型作为角色子表现同步缩放，枪械数据不变。",
  },
  "CHR-PLY-CAPSULE01-3D-BUNNY01-FOOT-L": {
    spec: "GLB / 5,396 verts / pivot-local / 1m角色比例",
    path: `${componentRoot}/chr_player_capsule01_bunny01_foot_l_top3d_v005.glb`,
    hash: "dcf44081e13e75aa6f688955fb7e651f4b3ededd31ad7cde96107ee1c6b65448",
    note: "PH39 v005：左脚网格、脚底原点与步态平移统一缩放；静态最低点Y=0。",
  },
  "CHR-PLY-CAPSULE01-3D-BUNNY01-FOOT-R": {
    spec: "GLB / 5,396 verts / pivot-local / 1m角色比例",
    path: `${componentRoot}/chr_player_capsule01_bunny01_foot_r_top3d_v005.glb`,
    hash: "8c34224f6d0995c082b5be019753232a867e88e6b1a120622a7153fa02ccfabc",
    note: "PH39 v005：右脚网格、脚底原点与步态平移统一缩放；静态最低点Y=0。",
  },
};

for (const [assetId, update] of Object.entries(updates)) {
  const row = rowById.get(assetId);
  if (!row) throw new Error(`Missing registry row: ${assetId}`);
  assetSheet.getRange(`M${row}:P${row}`).values = [[
    "v005",
    update.spec,
    update.path,
    sourcePath,
  ]];
  assetSheet.getRange(`T${row}`).values = [[update.hash]];
  assetSheet.getRange(`V${row}`).values = [[new Date(Date.UTC(2026, 6, 30))]];
  assetSheet.getRange(`V${row}`).format.numberFormat = "yyyy-mm-dd";
  assetSheet.getRange(`X${row}`).values = [[update.note]];
  assetSheet.getRange(`A${row}:X${row}`).format.rowHeight = 118;
  assetSheet.getRange(`A${row}:X${row}`).format.wrapText = true;
  assetSheet.getRange(`A${row}:X${row}`).format.verticalAlignment = "center";
}

const componentSheet = workbook.worksheets.getItem("角色组件");
const componentValues = componentSheet.getUsedRange(true).values;
const componentRow = new Map();
for (let index = 0; index < componentValues.length; index += 1) {
  if (String(componentValues[index][0] ?? "") !== "player_capsule01_bunny01_3d") continue;
  componentRow.set(String(componentValues[index][1] ?? ""), index + 1);
}
const componentUpdates = {
  root: [
    rootPath,
    "Node3D刚性骨架 / 完整视觉1.000m",
    "(0,0,0)",
    "v005：真实1m分体网格；Blender +X→Godot -Z；视觉层无碰撞。玩法碰撞仅为Player3D/VirtualCollisionBox（0.477778×1.000000×0.400000m），顶部匹配双耳最高点。",
  ],
  body: [
    `${componentRoot}/chr_player_capsule01_bunny01_body_top3d_v005.glb`,
    "pivot-local GLB / 1m比例",
    "(-0.000020,0.103348,-0.000423)",
    "Blender原点：身体底部中心；v005真实缩放。",
  ],
  head: [
    `${componentRoot}/chr_player_capsule01_bunny01_head_top3d_v005.glb`,
    "pivot-local GLB / 1m比例",
    "(-0.000019,0.318074,0.017621)",
    "Blender原点：头部下沿中心；不含耳头顶0.735593m。",
  ],
  ear_l: [
    `${componentRoot}/chr_player_capsule01_bunny01_ear_top3d_v005.glb`,
    "pivot-local GLB × -X / 1m比例",
    "Head local (-0.163371,0.333102,-0.001114)",
    "复用语义右耳资产并在左挂点镜像；完整视觉顶部1.000m。",
  ],
  ear_r: [
    `${componentRoot}/chr_player_capsule01_bunny01_ear_top3d_v005.glb`,
    "pivot-local GLB / 1m比例",
    "Head local (0.163408,0.333102,-0.001114)",
    "语义右耳标准实例；完整视觉顶部1.000m。",
  ],
  hand_l: [
    `${componentRoot}/chr_player_capsule01_bunny01_hand_l_top3d_v005.glb`,
    "pivot-local GLB / 1m比例",
    "Authored (-0.190556,0.214515,-0.009623); longgun support (0.080808,0.210101,-0.258586)",
    "手腕圆环近端轴心；网格、挂点与动作米制平移统一缩放。",
  ],
  hand_r: [
    `${componentRoot}/chr_player_capsule01_bunny01_hand_r_top3d_v005.glb`,
    "pivot-local GLB / 1m比例",
    "Authored (0.190556,0.214515,-0.009623); sidearm (0.032323,0.226263,-0.197980)+socket X0.096970; longgun (0.052525,0.226263,-0.197980)",
    "右手主握把；持枪视觉与手/挂点按同一0.404040404比例缩放。",
  ],
  foot_l: [
    `${componentRoot}/chr_player_capsule01_bunny01_foot_l_top3d_v005.glb`,
    "pivot-local GLB / 1m比例",
    "(-0.086002,0,-0.007258)",
    "Blender原点：脚底中心；静态最低点Y=0。",
  ],
  foot_r: [
    `${componentRoot}/chr_player_capsule01_bunny01_foot_r_top3d_v005.glb`,
    "pivot-local GLB / 1m比例",
    "(0.086002,0,-0.007258)",
    "Blender原点：脚底中心；静态最低点Y=0。",
  ],
};
for (const [slot, update] of Object.entries(componentUpdates)) {
  const row = componentRow.get(slot);
  if (!row) throw new Error(`Missing character component row: ${slot}`);
  componentSheet.getRange(`E${row}:G${row}`).values = [[update[0], update[1], update[2]]];
  componentSheet.getRange(`M${row}`).values = [[update[3]]];
  componentSheet.getRange(`A${row}:M${row}`).format.rowHeight = 104;
  componentSheet.getRange(`A${row}:M${row}`).format.wrapText = true;
  componentSheet.getRange(`A${row}:M${row}`).format.verticalAlignment = "center";
}

const animationSheet = workbook.worksheets.getItem("动画与状态");
animationSheet.getRange("A3").values = [[
  "2D/3D共用六态ID与转换白名单；Low HP / Silenced / Invincible / Reloading / Firing / Charging / Knockback为叠加层。兔子武器姿势状态机不变；PH39 v005将所有米制平移、关节、手/枪挂点、VFX与可穿戴统一按0.404040404缩放到完整视觉1m，角度、时长与状态来源不变。",
]];
animationSheet.getRange("A3:L3").format.rowHeight = 74;
animationSheet.getRange("A3:L3").format.wrapText = true;

const versionSheet = workbook.worksheets.getItem("版本记录");
const versionValues = versionSheet.getUsedRange(true).values;
const existing = versionValues.findIndex((row) => String(row[0] ?? "") === "v1.22");
const previous = versionValues.findIndex((row) => String(row[0] ?? "") === "v1.21");
const versionRow = existing >= 0
  ? existing + 1
  : previous >= 0
    ? previous + 2
    : versionValues.length + 1;
if (existing < 0) {
  versionSheet.getRange(`A${versionRow}:G${versionRow}`).copyFrom(
    versionSheet.getRange(`A${versionRow - 1}:G${versionRow - 1}`),
    "all",
  );
}
versionSheet.getRange(`A${versionRow}:G${versionRow}`).values = [[
  "v1.22",
  new Date(Date.UTC(2026, 6, 30)),
  "bunny01完整视觉与碰撞统一为1米",
  "CHR-PLY-CAPSULE01-3D-BUNNY01及六个稳定组件AssetID",
  "从v004派生真实1m Blender v005与七个pivot-local GLB；Godot改用v005装配，碰撞体高1m，持枪视觉、挂点、可穿戴、VFX和全部米制动作平移同步缩放。",
  "不新增角色AssetID；v004保留回退。静态AABB、六态、武器姿势、碰撞、DIY、换弹、塔楼与性能验收通过。",
  "Codex",
]];
versionSheet.getRange(`B${versionRow}`).format.numberFormat = "yyyy-mm-dd";
versionSheet.getRange(`A${versionRow}:G${versionRow}`).format.rowHeight = 118;
versionSheet.getRange(`A${versionRow}:G${versionRow}`).format.wrapText = true;
versionSheet.getRange(`A${versionRow}:G${versionRow}`).format.verticalAlignment = "center";

const exported = await SpreadsheetFile.exportXlsx(workbook);
await exported.save(registryPath);
await exported.save(outputPath);

const mainStart = rowById.get("CHR-PLY-CAPSULE01-3D-BUNNY01");
const mainEnd = rowById.get("CHR-PLY-CAPSULE01-3D-BUNNY01-FOOT-R");
const assetCheck = await workbook.inspect({
  kind: "table",
  sheetId: "资产主表",
  range: `A${mainStart}:X${mainEnd}`,
  include: "values,formulas",
  tableMaxRows: 10,
  tableMaxCols: 24,
  maxChars: 30000,
});
console.log(assetCheck.ndjson);
const componentCheck = await workbook.inspect({
  kind: "table",
  sheetId: "角色组件",
  range: `A${componentRow.get("root")}:M${componentRow.get("foot_r")}`,
  include: "values,formulas",
  tableMaxRows: 12,
  tableMaxCols: 13,
  maxChars: 24000,
});
console.log(componentCheck.ndjson);
const formulaErrors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 300 },
  summary: "PH39 final formula error scan",
});
console.log(formulaErrors.ndjson);

for (const [name, sheetName, range] of [
  ["registry_bunny_after_ph39.png", "资产主表", `A${mainStart}:X${mainEnd}`],
  ["registry_character_components_after_ph39.png", "角色组件", `A${componentRow.get("root")}:M${componentRow.get("foot_r")}`],
  ["registry_version_after_ph39.png", "版本记录", `A${versionRow - 2}:G${versionRow}`],
]) {
  const preview = await workbook.render({ sheetName, range, scale: 1, format: "png" });
  await fs.writeFile(`${workDir}/${name}`, new Uint8Array(await preview.arrayBuffer()));
}
