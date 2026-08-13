import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "/Users/summercards/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";

const root = "/Users/summercards/ShellStorm2";
const path = `${root}/docs/v0.1/data/ShellStorm2_游戏内容数据库_v010.xlsx`;
const outDir = `${root}/outputs/artifacts/v01_completion_20260813`;
const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(path));
const monsters = workbook.worksheets.getItem("怪物与Boss");
monsters.getRange("A6:O6").values = [["monster_boss_generic","Boss（通用回退模板）","boss",520,1.72,24,9.5,1.45,"无独立内容ID时使用的确定性弹幕/召唤回退","测试/未来未配置Boss楼层","boss_floor_*","[已实装]","正式3D低模回退；不作为95/90/85正式内容","src/enemy3d/Enemy3D.gd；src/map/MonsterInjector.gd","正式Boss由BossContentCatalog替换模型和阶段技能袋"]];
const bossRows = [
  ["boss_abyss_archivist_95","深渊档案官","boss",520,1.72,24,9.5,1.45,"archive_fan / index_beam / archive_storm；召唤档案侍从","95F不可绕过Boss竞技场","boss_floor_5；专用下行权限","[已实装]","独立Boss内容/模型/竞技场","src/enemy3d/BossContentCatalog.gd；assets/art/enemies/bosses_v01/enm_boss_archivist_95_top3d_v001.glb","独立三阶段技能袋；档案竞技场8组掩体"],
  ["boss_furnace_warden_90","熔炉狱监","boss",520,1.72,24,9.5,1.45,"molten_volley / hammer_drive / furnace_burst；召唤余烬","90F不可绕过Boss竞技场","boss_floor_10；专用下行权限","[已实装]","独立Boss内容/模型/竞技场","src/enemy3d/BossContentCatalog.gd；assets/art/enemies/bosses_v01/enm_boss_furnace_warden_90_top3d_v001.glb","独立三阶段技能袋；熔炉竞技场6组掩体"],
  ["boss_hollow_choir_85","空洞合唱团","boss",520,1.72,24,9.5,1.45,"choir_wave / silence_chord / echo_burst；召唤回声","85F不可绕过Boss竞技场","boss_floor_15；专用下行权限","[已实装]","独立Boss内容/模型/竞技场","src/enemy3d/BossContentCatalog.gd；assets/art/enemies/bosses_v01/enm_boss_hollow_choir_85_top3d_v001.glb","独立三阶段技能袋；合唱竞技场5组掩体"],
];
for (let i=0;i<bossRows.length;i++) {
  const row=12+i;
  monsters.getRange("A11:O11").copyTo(monsters.getRange(`A${row}:O${row}`),"all");
  monsters.getRange(`A${row}:O${row}`).values=[bossRows[i]];
}
const elites = workbook.worksheets.getItem("精英怪");
for (let row=5;row<=16;row++) {
  elites.getRange(`M${row}`).values=[["[已实装]"]];
  elites.getRange(`N${row}`).values=[["src/enemy3d/EliteRosterService.gd；src/enemy3d/Enemy3D.gd"]];
  elites.getRange(`O${row}`).values=[["稳定名册、预约唯一性、跨局成长/结算、夺械转译与独立实时行为已通过专项；正式高模可后续替换"]];
}
elites.getRange("A2:O2").values=[["名册固定12只并由用户设计冻结。2026-08-13已全部接入EliteRosterService、BaseData 1.7和各自实时行为；内容名称可迭代但稳定ID不可改变。",null,null,null,null,null,null,null,null,null,null,null,null,null,null]];
await fs.mkdir(outDir,{recursive:true});
const blob=await SpreadsheetFile.exportXlsx(workbook);
await blob.save(path);
await blob.save(`${outDir}/ShellStorm2_游戏内容数据库_v010.xlsx`);
for(const sheetName of ["怪物与Boss","精英怪"]){const preview=await workbook.render({sheetName,autoCrop:"all",scale:1,format:"png"});await fs.writeFile(`${outDir}/${sheetName}.png`,new Uint8Array(await preview.arrayBuffer()));}
console.log("GAME_CONTENT_DB_UPDATE_OK bosses=3 elites=12");
