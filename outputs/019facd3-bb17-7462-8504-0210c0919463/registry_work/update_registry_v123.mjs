import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const inputPath = "/Users/summercards/ShellStorm2/assets/registry/ShellStorm2_美术资产台账_v001.xlsx";
const workDir = "/Users/summercards/ShellStorm2/outputs/019facd3-bb17-7462-8504-0210c0919463/registry_work";
const outputPath = "/Users/summercards/ShellStorm2/outputs/019facd3-bb17-7462-8504-0210c0919463/ShellStorm2_美术资产台账_v001.xlsx";

const input = await FileBlob.load(inputPath);
const workbook = await SpreadsheetFile.importXlsx(input);

const overview = await workbook.inspect({
  kind: "sheet",
  include: "id,name",
  maxChars: 10000,
});
console.log(overview.ndjson);

const bunnyRows = await workbook.inspect({
  kind: "match",
  searchTerm: "CHR-PLY-CAPSULE01-3D-BUNNY01",
  options: { useRegex: false, maxResults: 50 },
  summary: "bunny asset rows",
});
console.log(bunnyRows.ndjson);

const bunnyComponentRows = await workbook.inspect({
  kind: "match",
  searchTerm: "player_capsule01_bunny01_3d",
  options: { useRegex: false, maxResults: 50 },
  summary: "bunny component contract rows",
});
console.log(bunnyComponentRows.ndjson);

for (const [sheetId, range] of [
  ["资产主表", "A154:X162"],
  ["角色组件", "A1:M39"],
  ["版本记录", "A1:G28"],
]) {
  const detail = await workbook.inspect({
    kind: "table",
    sheetId,
    range,
    include: "values,formulas",
    tableMaxRows: 50,
    tableMaxCols: 24,
    maxChars: 30000,
  });
  console.log(detail.ndjson);
}

for (const sheetName of [
  "总览",
  "资产主表",
  "角色组件",
  "动画与状态",
  "分类与编码",
  "命名与查重",
  "原型角色",
  "版本记录",
]) {
  try {
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
  } catch (error) {
    console.log(`RENDER_SKIP ${sheetName}: ${error.message}`);
  }
}

const main = workbook.worksheets.getItem("资产主表");
main.getRange("M156:P162").values = [
  ["v006", "1.034×1.500×0.645 m / 完整视觉含耳", "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/chr_player_capsule01_bunny01_root_top3d_v006.tscn", "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source/chr_player_capsule01_bunny01_top3d_v006.blend"],
  ["v006", "GLB / 1,958 verts / pivot-local / 1.5m总高比例", "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_player_capsule01_bunny01_body_top3d_v006.glb", "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source/chr_player_capsule01_bunny01_top3d_v006.blend"],
  ["v006", "GLB / 5,936 verts / pivot-local / 头顶1.103390m", "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_player_capsule01_bunny01_head_top3d_v006.glb", "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source/chr_player_capsule01_bunny01_top3d_v006.blend"],
  ["v006", "单 GLB / 1,536 verts / pivot-local / 双实例", "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_player_capsule01_bunny01_ear_top3d_v006.glb", "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source/chr_player_capsule01_bunny01_top3d_v006.blend"],
  ["v006", "双 GLB / 左右各1,058 verts / pivot-local / 1.5m角色比例", "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_player_capsule01_bunny01_hand_l_top3d_v006.glb; assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_player_capsule01_bunny01_hand_r_top3d_v006.glb", "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source/chr_player_capsule01_bunny01_top3d_v006.blend"],
  ["v006", "GLB / 5,396 verts / pivot-local / 1.5m角色比例", "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_player_capsule01_bunny01_foot_l_top3d_v006.glb", "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source/chr_player_capsule01_bunny01_top3d_v006.blend"],
  ["v006", "GLB / 5,396 verts / pivot-local / 1.5m角色比例", "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_player_capsule01_bunny01_foot_r_top3d_v006.glb", "assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source/chr_player_capsule01_bunny01_top3d_v006.blend"],
];
main.getRange("T156:T162").values = [
  ["b88839fbe76eedddd48933ac1807867e7a4efbd683de36475215679d26e84998"],
  ["c574d76e0f19c1aaa4bee5f427a81028d7b3f0f50299f67b4dbf02a60fc5668d"],
  ["b8db86c722bb2ae4d760b8219051f492251f6b9fa29882c8e32453b020973c24"],
  ["ed3c7abe283166648fafb43373c1dc2222bf9134f3d7bb8e0ebd8d3a05242ebf"],
  ["2c6647c0e4f234e9312ba65e7c73f55c02627be9b7a2c35d1591d86a20cb5f16 / b3ada7b67d0224156d1c39af0bdc0e53af02cb5d26ba68d4746b7859a84a1d10"],
  ["52051cba0db701d977c8baa8d7ed9899825b10406803ac63e6a3f66efbd80b64"],
  ["d81e840f5c087b349fd6e19b4cb7e65eb79294edb937fdc75192b66967c29e2e"],
];
main.getRange("V156:V162").values = Array.from(
  { length: 7 },
  () => [new Date("2026-07-30T00:00:00Z")],
);
main.getRange("X156:X162").values = [
  ["PH41 v006：用户确认1.5m比例后，从一米v005等比烘焙真实1.5m Blender与Godot装配；Avatar3D运行时缩放为1。Player3D不可见碰撞为0.716667×1.500000×0.600000m；持枪、VFX、穿戴与米制动画使用0.606060606换算。Blender/Godot静态AABB、武器姿势/碰撞、六态、DIY、换弹、塔楼楼梯与PH40镜头回归通过。"],
  ["PH41 v006：身体网格与底部中心原点从v005等比放大1.5倍；Godot BodyJoint=(-0.000030,0.155022,-0.000635)。"],
  ["PH41 v006：头部与下沿中心原点真实1.5倍；不含耳头顶1.103390m，完整双耳顶部1.500m。"],
  ["PH41 v006：耳朵网格与耳根原点真实1.5倍；左右挂点复用单资产，装配后最高点严格1.500m。"],
  ["PH41 v006：左右手、手腕原点、单/双手握持目标和动作平移统一改用0.606060606米制比例；持枪外观与确认预览一致。"],
  ["PH41 v006：左脚网格、脚底原点与步态平移真实1.5倍；静态最低点Y=0。"],
  ["PH41 v006：右脚网格、脚底原点与步态平移真实1.5倍；静态最低点Y=0。"],
];

const components = workbook.worksheets.getItem("角色组件");
components.getRange("E31:G39").values = [
  ["assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/chr_player_capsule01_bunny01_root_top3d_v006.tscn", "Node3D刚性骨架 / 完整视觉1.500m", "(0,0,0)"],
  ["assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_player_capsule01_bunny01_body_top3d_v006.glb", "pivot-local GLB / 1.5m比例", "(-0.000030,0.155022,-0.000635)"],
  ["assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_player_capsule01_bunny01_head_top3d_v006.glb", "pivot-local GLB / 1.5m比例", "(-0.000028,0.477110,0.026431)"],
  ["assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_player_capsule01_bunny01_ear_top3d_v006.glb", "pivot-local GLB × -X / 1.5m比例", "Head local (-0.245056,0.499653,-0.001671)"],
  ["assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_player_capsule01_bunny01_ear_top3d_v006.glb", "pivot-local GLB / 1.5m比例", "Head local (0.245112,0.499653,-0.001671)"],
  ["assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_player_capsule01_bunny01_hand_l_top3d_v006.glb", "pivot-local GLB / 1.5m比例", "Authored (-0.285833,0.321773,-0.014435); longgun support (0.121212,0.315152,-0.387879)"],
  ["assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_player_capsule01_bunny01_hand_r_top3d_v006.glb", "pivot-local GLB / 1.5m比例", "Authored (0.285833,0.321773,-0.014435); sidearm (0.048485,0.339394,-0.296970)+socket X0.145455; longgun (0.078788,0.339394,-0.296970)"],
  ["assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_player_capsule01_bunny01_foot_l_top3d_v006.glb", "pivot-local GLB / 1.5m比例", "(-0.129002,0,-0.010887)"],
  ["assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_player_capsule01_bunny01_foot_r_top3d_v006.glb", "pivot-local GLB / 1.5m比例", "(0.129002,0,-0.010887)"],
];
components.getRange("M31:M39").values = [
  ["v006：真实1.5m分体网格；Blender +X→Godot -Z；Avatar3D缩放为1。玩法碰撞仅为Player3D/VirtualCollisionBox（0.716667×1.500000×0.600000m），顶部匹配双耳最高点。"],
  ["Blender原点：身体底部中心；v006真实1.5m几何。"],
  ["Blender原点：头部下沿中心；不含耳头顶1.103390m。"],
  ["复用语义右耳并在左挂点镜像；完整视觉顶部1.500m。"],
  ["语义右耳标准实例；完整视觉顶部1.500m。"],
  ["手腕圆环近端轴心；网格、挂点与动作米制平移使用0.606060606比例。"],
  ["右手主握把；持枪视觉与手/挂点使用同一0.606060606比例。"],
  ["Blender原点：脚底中心；静态最低点Y=0。"],
  ["Blender原点：脚底中心；静态最低点Y=0。"],
];

const versions = workbook.worksheets.getItem("版本记录");
versions.getRange("A29:G29").copyFrom(versions.getRange("A28:G28"), "all");
versions.getRange("A29:G29").values = [[
  "v1.23",
  new Date("2026-07-30T00:00:00Z"),
  "bunny01正式定版为1.5米",
  "CHR-PLY-CAPSULE01-3D-BUNNY01及六个稳定组件AssetID",
  "从一米v005等比烘焙真实1.5m Blender v006、七个pivot-local GLB与Godot v006装配；取消Avatar3D临时1.5倍缩放，碰撞、挂点、附件与米制动画固定为1.5m契约。",
  "不新增AssetID；v005保留回退。Blender/Godot AABB、武器姿势、碰撞、六态、DIY、换弹、塔楼楼梯和PH40镜头验收通过。",
  "Codex",
]];
versions.getRange("A29:G29").format.autofitRows();
versions.getRange("A29:G29").format.wrapText = true;
versions.getRange("A29:G29").format.verticalAlignment = "center";
versions.getRange("A29:G29").format.rowHeight = 84;
versions.getRange("B29").format.numberFormat = "yyyy-mm-dd";

const keyCheck = await workbook.inspect({
  kind: "table",
  sheetId: "资产主表",
  range: "M156:X162",
  include: "values,formulas",
  tableMaxRows: 10,
  tableMaxCols: 12,
  maxChars: 12000,
});
console.log(keyCheck.ndjson);

const componentCheck = await workbook.inspect({
  kind: "table",
  sheetId: "角色组件",
  range: "E31:M39",
  include: "values,formulas",
  tableMaxRows: 12,
  tableMaxCols: 10,
  maxChars: 12000,
});
console.log(componentCheck.ndjson);

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 300 },
  summary: "final formula error scan",
});
console.log(errors.ndjson);

for (const sheetName of [
  "总览",
  "资产主表",
  "角色组件",
  "动画与状态",
  "分类与编码",
  "命名与查重",
  "原型角色",
  "版本记录",
]) {
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

const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);
await output.save(inputPath);
console.log(`REGISTRY_V123_SAVED ${outputPath}`);
