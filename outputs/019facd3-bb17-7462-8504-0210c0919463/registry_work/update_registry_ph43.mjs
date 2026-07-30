import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const root = "/Users/summercards/ShellStorm2";
const inputPath = `${root}/assets/registry/ShellStorm2_美术资产台账_v001.xlsx`;
const workDir = `${root}/outputs/019facd3-bb17-7462-8504-0210c0919463/registry_work/ph43`;
await fs.mkdir(workDir, { recursive: true });

const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(inputPath));
const overview = await workbook.inspect({
  kind: "sheet",
  include: "id,name",
  maxChars: 5000,
});
console.log(overview.ndjson);

for (const sheetName of ["资产主表", "角色组件", "动画与状态", "命名与查重", "版本记录"]) {
  const sheet = workbook.worksheets.getItem(sheetName);
  const used = sheet.getUsedRange(true);
  const region = await workbook.inspect({
    kind: "region",
    sheetId: sheetName,
    range: used.address,
    maxChars: 16000,
    tableMaxRows: 220,
    tableMaxCols: 24,
    tableMaxCellChars: 120,
  });
  await fs.writeFile(`${workDir}/${sheetName}.ndjson`, region.ndjson);
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
  console.log(`${sheetName}: ${used.address}`);
}

function firstRow(address) {
  const match = String(address).match(/[A-Z]+(\d+)/);
  return match ? Number(match[1]) : 1;
}

function findRow(sheet, predicate) {
  const used = sheet.getUsedRange(true);
  const values = used.values;
  const start = firstRow(used.address);
  const index = values.findIndex(predicate);
  if (index < 0) throw new Error(`Registry row not found in ${sheet.name}`);
  return start + index;
}

const changedDate = new Date(Date.UTC(2026, 6, 30));
const main = workbook.worksheets.getItem("资产主表");
const mainUpdates = {
  "CHR-PLY-CAPSULE01-3D-BUNNY01":
    "PH43：继续复用v006 1.5m模型与稳定AssetID；Player3D玩法碰撞升级为高1.5m、半径0.34m的VirtualCollisionCapsule。顶层状态扩展为idle/moving/dashing/hurt/locked/falling/landing/dead；下落收腿、耳后扬与落地压缩/回弹均由既有刚性节点程序驱动，不新增GLB或贴图。",
  "CHR-PLY-CAPSULE01-3D-BUNNY01-FOOT-L":
    "PH43：v006网格与AssetID不变；FootJointL除moving步态外新增falling收腿与landing压缩恢复职责，动作由PlayerAvatar3D程序变换驱动。",
  "CHR-PLY-CAPSULE01-3D-BUNNY01-FOOT-R":
    "PH43：v006网格与AssetID不变；FootJointR除moving步态外新增falling收腿与landing压缩恢复职责，动作由PlayerAvatar3D程序变换驱动。",
  "ENV-TOWER-DESCENT-KIT-3D":
    "PH43：Godot直接为两套v006楼梯各六块*Walkable网格生成常驻StaticBody3D三角碰撞，围护墙沿用EnclosureWall同形碰撞；取消程序路径承重面和按XZ每帧强制写Y。楼顶洞口由25×35m收紧为约15×30m模块范围；镜头固定为角色相对坐标(0,8,5.5)、FOV 55°和既定斜俯视目标，不响应外力、墙体或家具碰撞，不收镜、侧移或左右旋转。进入特殊楼梯围护体立即开启角色探照灯，固定太阳不变。",
  "ENV-TOWER-FLOOR-TILE-5M":
    "PH43：六层仍以67×67个5m格MultiMesh铺设；四向楼梯洞口按实际双跑外廓收紧到约15×30m，承重楼板与楼梯连续三角面共同消除多挖黑洞和边缘坠落。",
  "ENV-TOWER-STAIRWELL-GENERIC-9M":
    "PH43：继续直接使用用户v006通用楼梯视觉；Godot为UpperFlight、TurnLanding、LowerFlight、上下门厅与核心连接板等六块*Walkable网格分别生成同形三角碰撞，导入EnclosureWall生成围护碰撞，取消程序路径承重面和Y坐标吸附。支持四向旋转、真实重力双向通行与流送时承重常驻；固定镜头不受楼梯碰撞推动或旋转。",
  "ENV-TOWER-STAIRWELL-ROOFTOP-9M":
    "PH43：保留用户v006特殊墙高与开口；Godot直接为六块*Walkable网格生成同形常驻碰撞，导入EnclosureWall围护碰撞，并保留带阴影楼顶天空反弹光。洞口收紧后不再出现墙外大面积黑洞或接缝坠落；8m镜头固定在(0,8,5.5)，不再侧向避障、碰撞位移或左右旋转。",
};
for (const [assetId, note] of Object.entries(mainUpdates)) {
  const row = findRow(main, (values) => String(values[0] ?? "") === assetId);
  main.getRange(`V${row}`).values = [[changedDate]];
  main.getRange(`V${row}`).format.numberFormat = "yyyy-mm-dd";
  main.getRange(`X${row}`).values = [[note]];
  main.getRange(`A${row}:X${row}`).format.wrapText = true;
  main.getRange(`A${row}:X${row}`).format.verticalAlignment = "center";
  main.getRange(`A${row}:X${row}`).format.rowHeight = 132;
}

const components = workbook.worksheets.getItem("角色组件");
const componentUpdates = {
  root: {
    animation: "八态整体 + falling收束/landing压缩回弹 + 动作覆盖",
    note: "PH43：v006真实1.5m分体网格与AssetID不变；玩法碰撞位于Player3D/VirtualCollisionCapsule（height=1.5m、radius=0.34m）。falling/landing复用既有Body/Head/Hands/Feet/EarSocket关节。",
  },
  foot_l: {
    animation: "moving左脚/翻滚收腿/受击甩脚/falling收腿/landing压缩",
    note: "Blender原点：脚底中心；静态最低点Y=0；PH43复用同一v006网格增加下落与落地程序动作。",
  },
  foot_r: {
    animation: "moving右脚/翻滚收腿/受击甩脚/falling收腿/landing压缩",
    note: "Blender原点：脚底中心；静态最低点Y=0；PH43复用同一v006网格增加下落与落地程序动作。",
  },
};
for (const [slot, update] of Object.entries(componentUpdates)) {
  const row = findRow(
    components,
    (values) =>
      String(values[0] ?? "") === "player_capsule01_bunny01_3d" &&
      String(values[1] ?? "") === slot,
  );
  components.getRange(`J${row}`).values = [[update.animation]];
  components.getRange(`M${row}`).values = [[update.note]];
  components.getRange(`A${row}:M${row}`).format.wrapText = true;
  components.getRange(`A${row}:M${row}`).format.verticalAlignment = "center";
  components.getRange(`A${row}:M${row}`).format.rowHeight = 104;
}

const animation = workbook.worksheets.getItem("动画与状态");
const animationValues = animation.getUsedRange(true).values;
const hasFalling = animationValues.some((row) => String(row[1] ?? "") === "falling");
if (!hasFalling) {
  for (let row = 40; row >= 11; row -= 1) {
    animation
      .getRange(`A${row + 2}:L${row + 2}`)
      .copyFrom(animation.getRange(`A${row}:L${row}`), "all");
  }
  animation.getRange("A11:L11").copyFrom(animation.getRange("A10:L10"), "all");
  animation.getRange("A12:L12").copyFrom(animation.getRange("A10:L10"), "all");
}

// Row insertion by copy does not move XLSX merged ranges. Normalize the lower
// sections explicitly so this script is safe both on the original workbook and
// on a PH43 workbook that has already been exported once.
for (const address of [
  "A16:L16",
  "A18:L18",
  "A28:L28",
  "A29:L29",
  "A30:L30",
  "A31:L31",
  "A34:L34",
  "A35:L35",
  "A36:L36",
  "A37:L37",
  "A38:L38",
  "A39:L39",
  "A40:L40",
  "A41:L41",
]) {
  try {
    animation.unmergeCells(address);
  } catch {
    // The target may already be unmerged on an idempotent rerun.
  }
}

const emptyRow = [null, null, null, null, null, null, null, null, null, null, null, null];

animation.getRange("A16:L16").copyFrom(animation.getRange("A15:L15"), "all");
animation.getRange("A16:L16").values = [[
  "叠加", "invincible", "无敌", "dash/hurt", "不改变顶层",
  "闪烁", "闪烁", "保持当前动作", "保持当前动作", "闪烁",
  "透明闪烁", "InvincibleTimer 唯一解除",
]];
animation.getRange("A17:L17").copyFrom(animation.getRange("A15:L15"), "all");
animation.getRange("A17:L17").values = [[
  "叠加", "reloading", "换弹", "任意持枪存活态", "不改变顶层；完成/取消退出",
  "保持当前顶层", "保持当前顶层",
  "手枪左手近身取弹但不计握持；长枪左手离开护木服务",
  "右手持续握把并跟随 WeaponSocket 下压/回位",
  "保持当前顶层", "3D头顶billboard进度条；2D弹药栏",
  "WeaponModel3D 唯一计时源；WeaponPoseFSM 进入 sidearm_reload/longgun_reload；右手保持握把，左手按武器类型服务",
]];

animation.getRange("A18:L18").values = [[
  "Enemy3D 九态状态机 × 模块表现 × 模型轮廓碰撞",
  null, null, null, null, null, null, null, null, null, null, null,
]];
animation.getRange("A28:L28").copyFrom(animation.getRange("A27:L27"), "all");
animation.getRange("A28:L28").values = [[
  "顶层", "dead", "死亡", "任意存活态", "无（终态）",
  "熄灭", "压扁", "停止", "爆散/淡出", "掉落与计数",
  "不可回存活态", "终态 + Tween",
]];
animation.getRange("A29:L29").values = [[...emptyRow]];

animation.getRange("A30:L30").copyFrom(animation.getRange("A18:L18"), "all");
animation.getRange("A30:L30").values = [[
  "Player3D 动作覆盖层 × 组件表现（不新增顶层状态）",
  null, null, null, null, null, null, null, null, null, null, null,
]];
animation.getRange("A31:L31").values = [[
  "层级｜状态ID｜中文名｜唯一来源｜退出｜Body｜Head｜Hand L（停用）｜Hand（握持）｜Scarf｜VFX/UI｜首版实现",
  null, null, null, null, null, null, null, null, null, null, null,
]];
animation.getRange("A34:L34").copyFrom(animation.getRange("A33:L33"), "all");
animation.getRange("A34:L34").values = [[
  "叠加", "knockback", "受击击飞", "Player3D 命中方向/强度/时长",
  "冲量归零或死亡", "反向位移/压缩/弹回", "夸张后仰甩头/回正",
  "手枪自由左手外甩；长枪左手回护木",
  "右手与 WeaponSocket 同相后退/回正", "滞后甩动",
  "红闪/短轨迹", "hurt 消费递减XZ冲量；双耳/双脚/双手分层过冲，不新增顶层状态",
]];
animation.getRange("A35:L35").values = [[...emptyRow]];

animation.getRange("A36:L36").copyFrom(animation.getRange("A18:L18"), "all");
animation.getRange("A36:L36").values = [[
  "Player3D DIY 外观槽 × 动态继承（不影响八态/玩法）",
  null, null, null, null, null, null, null, null, null, null, null,
]];
animation.getRange("A37:L37").values = [[
  "槽位｜候选变体｜父组件｜移动｜射击/蓄力｜受击/击飞｜换弹｜死亡｜挂点契约｜验收｜复用范围｜首版实现",
  null, null, null, null, null, null, null, null, null, null, null,
]];
animation.getRange("A38:L38").copyFrom(animation.getRange("A42:L42"), "all");
animation.getRange("A38:L38").values = [[
  "body/head/hand/feet/hat/glasses", "4+4+4+4+3+3",
  "Body/Head/Hand/Feet/Wearables", "身体弹性+双脚交替+圆短尾轻摆",
  "手/枪同相后坐；头前探", "整体后仰/脚随根回正", "Hand+Socket同相",
  "四主模块随根倾倒", "唯一手/挂点相对向量固定",
  "四主模块+双眼双耳短尾+八态覆盖", "3D玩家/预览场",
  "Godot原生方体/三角耳/圆尾；Player3D.set_avatar_customization",
]];
animation.getRange("A39:L39").values = [[...emptyRow]];

animation.getRange("A40:L40").copyFrom(animation.getRange("A18:L18"), "all");
animation.getRange("A40:L40").values = [[
  "PH33 方形猫子组件 × 动作归属（不新增状态）",
  null, null, null, null, null, null, null, null, null, null, null,
]];
animation.getRange("A41:L41").values = [[
  "父模块｜子组件｜节点数量｜Idle｜Moving｜Dashing｜Hurt/Knockback｜Reload/Fire｜Dead｜图形语言｜禁止事项｜验收",
  null, null, null, null, null, null, null, null, null, null, null,
]];
animation.getRange("A42:L42").values = [[
  "Head / Body / Feet", "Eyes / Ears / TailStub / FootL / FootR", "2 / 2 / 1 / 2",
  "双眼双耳稳定；短尾微摆", "双脚交替抬起；短尾轻摆", "随VisualRoot压缩",
  "随父模块后仰回正", "手/枪动作不牵动脚；头部继承", "随父模块倾倒",
  "方头方身方手方脚；圆尾唯一例外", "嘴/鼻/第二手/长尾/烘焙跨模块",
  "节点路径+数量+步态+持枪+视觉",
]];

for (const address of [
  "A18:L18",
  "A30:L30",
  "A31:L31",
  "A36:L36",
  "A37:L37",
  "A40:L40",
  "A41:L41",
]) {
  animation.mergeCells(address);
}
animation.getRange("A3").values = [[
  "Player3D 八态状态机 × 组件表现（falling/landing为真实垂直物理顶层状态）",
]];
animation.getRange("A11:L11").values = [[
  "顶层", "falling", "下落",
  "idle/moving/dashing/hurt/locked",
  "landing,hurt,dead",
  "随下落速度轻微纵向拉长",
  "滞后上扬，保持头重感",
  "手枪自由手收束；长枪托举手不脱离",
  "握持手与WeaponSocket保持同相",
  "向上滞后",
  "无新增VFX",
  "真实重力+0.10s离地容错；双脚收起、双耳后压；楼梯接缝不误触发",
]];
animation.getRange("A12:L12").values = [[
  "顶层", "landing", "落地",
  "falling",
  "idle,moving,locked,falling,hurt,dead",
  "按冲击速度压缩并回弹",
  "轻微下压后恢复",
  "随整体吸收冲击",
  "握持手与WeaponSocket同相稳定",
  "短促回摆",
  "落地停顿",
  "冲击速度映射0.12—0.30s硬直；状态计时结束后恢复地面移动",
]];
for (const [row, sources, targets] of [
  [6, "start/moving/hurt/locked/landing", "moving,dashing,hurt,locked,falling,dead"],
  [7, "idle/dashing/hurt/locked/landing", "idle,dashing,hurt,locked,falling,dead"],
  [8, "idle/moving", "idle,moving,hurt,locked,falling,dead"],
  [9, "任意存活态", "idle,moving,locked,falling,dead"],
  [10, "任意存活态/landing", "idle,moving,hurt,falling,dead"],
]) {
  animation.getRange(`D${row}:E${row}`).values = [[sources, targets]];
}
const animationUsed = animation.getUsedRange(true);
for (let rowIndex = 0; rowIndex < animationUsed.values.length; rowIndex += 1) {
  for (let colIndex = 0; colIndex < animationUsed.values[rowIndex].length; colIndex += 1) {
    const value = animationUsed.values[rowIndex][colIndex];
    if (typeof value === "string" && value.includes("六态")) {
      const row = firstRow(animationUsed.address) + rowIndex;
      const col = String.fromCharCode("A".charCodeAt(0) + colIndex);
      animation.getRange(`${col}${row}`).values = [[value.replaceAll("六态", "八态")]];
    }
  }
}
animation.getRange("A3:L42").format.wrapText = true;
animation.getRange("A3:L42").format.verticalAlignment = "center";
animation.getRange("A11:L12").format.rowHeight = 92;

const versions = workbook.worksheets.getItem("版本记录");
const versionUsed = versions.getUsedRange(true);
const versionStart = firstRow(versionUsed.address);
let versionRow = versionStart + versionUsed.values.length;
const existingVersion = versionUsed.values.findIndex(
  (row) => String(row[0] ?? "") === "v1.25",
);
if (existingVersion >= 0) versionRow = versionStart + existingVersion;
else versions
  .getRange(`A${versionRow}:G${versionRow}`)
  .copyFrom(versions.getRange(`A${versionRow - 1}:G${versionRow - 1}`), "all");
versions.getRange(`A${versionRow}:G${versionRow}`).values = [[
  "v1.25",
  changedDate,
  "PH43楼梯Walkable根因修复与固定镜头",
  "Player3D / bunny01 v006 / 两套9m楼梯 / 楼顶洞口与镜头",
  "六态扩展为八态falling/landing；1.5m玩法碰撞改胶囊；楼梯取消Y吸附与程序路径承重面，直接采用v006每套六块*Walkable网格同形常驻碰撞；掉落/钥匙向下找承重面；EnclosureWall补围护碰撞；楼顶洞口收紧并加物理天空反弹光；镜头固定(0,8,5.5)、FOV 55°，每物理帧覆盖外部位移与旋转；进入特殊楼梯围护体立即启用角色探照灯。",
  "不新增角色/楼梯AssetID、GLB或贴图；v006模型尺寸和单太阳参数不变；原战斗/命运/枪械/流送兼容。",
  "Codex",
]];
versions.getRange(`B${versionRow}`).format.numberFormat = "yyyy-mm-dd";
versions.getRange(`A${versionRow}:G${versionRow}`).format.wrapText = true;
versions.getRange(`A${versionRow}:G${versionRow}`).format.verticalAlignment = "center";
versions.getRange(`A${versionRow}:G${versionRow}`).format.rowHeight = 118;

const errorScan = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 100 },
  summary: "PH43 formula error scan",
});
console.log(errorScan.ndjson);

for (const sheetName of ["资产主表", "角色组件", "动画与状态", "版本记录"]) {
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

const outputPath = `${root}/outputs/019facd3-bb17-7462-8504-0210c0919463/ShellStorm2_美术资产台账_v001.xlsx`;
const exported = await SpreadsheetFile.exportXlsx(workbook);
await exported.save(outputPath);
const canonical = await SpreadsheetFile.exportXlsx(workbook);
await canonical.save(inputPath);
console.log(`PH43 registry exported: ${outputPath}`);
