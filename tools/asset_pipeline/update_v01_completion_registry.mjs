import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "/Users/summercards/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";

const root = "/Users/summercards/ShellStorm2";
const registryPath = `${root}/assets/registry/ShellStorm2_美术资产台账_v001.xlsx`;
const outputDir = `${root}/outputs/artifacts/v01_completion_20260813`;
const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(registryPath));
const sheet = workbook.worksheets.getItem("资产主表");
const dateSerial = 46247;
const rows = [
  ["ENM-BOSS-ARCHIVIST-95","深渊档案官","敌人","boss","boss_abyss_archivist_95","root",null,"Top3D","default / 三阶段","95层Boss","正式美术已接入","P0","v001","GLB；主体/发光/附肢语义拆分","assets/art/enemies/bosses_v01/enm_boss_archivist_95_top3d_v001.glb","source/art/blender/bosses_v01/enm_boss_archivist_95_top3d_v001.blend; src/enemy3d/BossContentCatalog.gd","深渊档案官; archive; 95F; 三阶段",null,"唯一","d48dbdef27c500895471b8e14e4d07ae8f733b511ea67bf44cf0dffe959d781c","Codex",dateSerial,"原创程序建模","独立正式模型；阶段技能袋 archive_fan/index_beam/archive_storm；通过Boss专项验收。"],
  ["ENM-BOSS-FURNACE-WARDEN-90","熔炉狱监","敌人","boss","boss_furnace_warden_90","root",null,"Top3D","default / 三阶段","90层Boss","正式美术已接入","P0","v001","GLB；主体/发光/附肢语义拆分","assets/art/enemies/bosses_v01/enm_boss_furnace_warden_90_top3d_v001.glb","source/art/blender/bosses_v01/enm_boss_furnace_warden_90_top3d_v001.blend; src/enemy3d/BossContentCatalog.gd","熔炉狱监; furnace; 90F; 三阶段",null,"唯一","77469ad543d9265ffcc32198c06e25dd3ea8b793b79da4afeb7bd5e56f09d24c","Codex",dateSerial,"原创程序建模","独立正式模型；阶段技能袋 molten_volley/hammer_drive/furnace_burst；通过Boss专项验收。"],
  ["ENM-BOSS-HOLLOW-CHOIR-85","空洞合唱团","敌人","boss","boss_hollow_choir_85","root",null,"Top3D","default / 三阶段","85层Boss","正式美术已接入","P0","v001","GLB；主体/发光/附肢语义拆分","assets/art/enemies/bosses_v01/enm_boss_hollow_choir_85_top3d_v001.glb","source/art/blender/bosses_v01/enm_boss_hollow_choir_85_top3d_v001.blend; src/enemy3d/BossContentCatalog.gd","空洞合唱团; choir; 85F; 三阶段",null,"唯一","c7d1bade328047877d64770b2c534cbd930fc377ce8a00e19873fc108a73a56f","Codex",dateSerial,"原创程序建模","独立正式模型；阶段技能袋 choir_wave/silence_chord/echo_burst；通过Boss专项验收。"],
  ["ENV-BOSS-ARENA-ARCHIVE-95","档案回廊竞技场组件","场景","boss_arena","arena_archive_95","dressing",null,"Top3D","default / 高模流式","95层Boss场地","正式美术已接入","P0","v001","GLB；8组柱体与掩体","assets/art/environments/boss_arenas_v01/env_boss_arena_archive_95_top3d_v001.glb","source/art/blender/bosses_v01/env_boss_arena_archive_95_top3d_v001.blend; src/world3d/DungeonRoom3D.gd","档案竞技场; 95F; arena; cover",null,"唯一","ff10424d3c6898385aad9eaf0de32b644eb282a567b36aa422c4dd9decff7d69","Codex",dateSerial,"原创程序建模","高模装饰可流式；对应8组碰撞掩体。永久楼板/关卡墙/外墙不隐藏。"],
  ["ENV-BOSS-ARENA-FURNACE-90","熔炉竞技场组件","场景","boss_arena","arena_furnace_90","dressing",null,"Top3D","default / 高模流式","90层Boss场地","正式美术已接入","P0","v001","GLB；熔炉核心与6组掩体","assets/art/environments/boss_arenas_v01/env_boss_arena_furnace_90_top3d_v001.glb","source/art/blender/bosses_v01/env_boss_arena_furnace_90_top3d_v001.blend; src/world3d/DungeonRoom3D.gd","熔炉竞技场; 90F; arena; cover",null,"唯一","d376fba6190728dc8bf50664f4082b954a077fa96799d68f118ead53cb7aa63c","Codex",dateSerial,"原创程序建模","高模装饰可流式；对应6组碰撞掩体。永久楼板/关卡墙/外墙不隐藏。"],
  ["ENV-BOSS-ARENA-CHOIR-85","共鸣合唱竞技场组件","场景","boss_arena","arena_choir_85","dressing",null,"Top3D","default / 高模流式","85层Boss场地","正式美术已接入","P0","v001","GLB；共鸣环与5组掩体","assets/art/environments/boss_arenas_v01/env_boss_arena_choir_85_top3d_v001.glb","source/art/blender/bosses_v01/env_boss_arena_choir_85_top3d_v001.blend; src/world3d/DungeonRoom3D.gd","合唱竞技场; 85F; arena; cover",null,"唯一","d2aae2a6fd2f091d5cb9c05d103a4512179bdc6ef0e9d77ba5834efc723eba3a","Codex",dateSerial,"原创程序建模","高模装饰可流式；对应5组碰撞掩体。永久楼板/关卡墙/外墙不隐藏。"],
  ["AUD-SFX-FLASHLIGHT-CHARGE-UP","手电筒充能音效","音频","sfx","flashlight_charge_up","runtime",null,"全局/非空间","default","手电筒系统","正式接入","P0","v001","0.950s；44.1kHz；stereo OGG","src/assets/audio/sfx/flashlight_charge_up_v001.ogg","src/assets/audio/sfx/flashlight_charge_up.wav; tools/asset_pipeline/create_flashlight_sfx.py","flashlight; charge; 手电筒; 充能",null,"唯一","eee07c1942c32004dd750f670630d087e3491f5007537ba742cd102032ade878","Codex",dateSerial,"原创程序合成","WAV母版；OGG运行；桌面/Android统一路径。"],
  ["AUD-SFX-FLASHLIGHT-DEPLETED","手电筒耗尽音效","音频","sfx","flashlight_depleted","runtime",null,"全局/非空间","default","手电筒系统","正式接入","P0","v001","0.850s；44.1kHz；stereo OGG","src/assets/audio/sfx/flashlight_depleted_v001.ogg","src/assets/audio/sfx/flashlight_depleted.wav; tools/asset_pipeline/create_flashlight_sfx.py","flashlight; depleted; 手电筒; 耗尽",null,"唯一","c1aa6d3eb619bd1b714689118442e873af08a05e9ebc64cd56161b96a91fa095","Codex",dateSerial,"原创程序合成","WAV母版；OGG运行；桌面/Android统一路径。"],
  ["AUD-SFX-FLASHLIGHT-LOW-BATTERY","手电筒低电量音效","音频","sfx","flashlight_low_battery","runtime",null,"全局/非空间","default","手电筒系统","正式接入","P0","v001","0.650s；44.1kHz；stereo OGG","src/assets/audio/sfx/flashlight_low_battery_v001.ogg","src/assets/audio/sfx/flashlight_low_battery.wav; tools/asset_pipeline/create_flashlight_sfx.py","flashlight; low battery; 手电筒; 低电量",null,"唯一","e9fb880d366d90b203569bae843c30bfc02541bd03b16e56a30cbd440b61fb4a","Codex",dateSerial,"原创程序合成","WAV母版；OGG运行；桌面/Android统一路径。"],
];

for (let i = 0; i < rows.length; i++) {
  const rowNumber = 226 + i;
  sheet.getRange(`A225:X225`).copyTo(sheet.getRange(`A${rowNumber}:X${rowNumber}`), "all");
  sheet.getRange(`A${rowNumber}:X${rowNumber}`).values = [rows[i]];
  sheet.getRange(`R${rowNumber}`).formulas = [[`=LOWER(TRIM(C${rowNumber})&"|"&TRIM(D${rowNumber})&"|"&TRIM(E${rowNumber})&"|"&TRIM(F${rowNumber})&"|"&TRIM(H${rowNumber})&"|"&TRIM(I${rowNumber}))`]];
}

const overview = workbook.worksheets.getItem("总览");
overview.getRange("A6").formulas = [["=COUNTA('资产主表'!$A$6:$A$234)"]];
overview.getRange("C6").formulas = [["=COUNTIF('资产主表'!$K$6:$K$234,\"已完成\")+COUNTIF('资产主表'!$K$6:$K$234,\"原型已接入\")+COUNTIF('资产主表'!$K$6:$K$234,\"正式接入\")+COUNTIF('资产主表'!$K$6:$K$234,\"正式美术已接入\")"]];
overview.getRange("E6").formulas = [["=COUNTIF('资产主表'!$K$6:$K$234,\"待制作\")+COUNTIF('资产主表'!$K$6:$K$234,\"程序占位\")"]];
overview.getRange("G6").formulas = [["=COUNTIF('资产主表'!$S$6:$S$234,\"重复\")"]];
for (let row = 10; row <= 18; row++) {
  overview.getRange(`B${row}`).formulas = [[`=COUNTIF('资产主表'!$C$6:$C$234,A${row})`]];
  overview.getRange(`C${row}`).formulas = [[`=COUNTIFS('资产主表'!$C$6:$C$234,A${row},'资产主表'!$K$6:$K$234,"已完成")+COUNTIFS('资产主表'!$C$6:$C$234,A${row},'资产主表'!$K$6:$K$234,"原型已接入")+COUNTIFS('资产主表'!$C$6:$C$234,A${row},'资产主表'!$K$6:$K$234,"正式接入")+COUNTIFS('资产主表'!$C$6:$C$234,A${row},'资产主表'!$K$6:$K$234,"正式美术已接入")`]];
}

const versions = workbook.worksheets.getItem("版本记录");
versions.getRange("A13:G13").copyTo(versions.getRange("A14:G14"), "all");
versions.getRange("A14:G14").values = [["v0.1.10",dateSerial,"Boss/场地/手电筒资产收口","3 Boss / 3场地 / 3音频","登记95/90/85层独立Boss和竞技场GLB、三条手电筒OGG及母版；记录永久结构代理与高模流式边界。","稳定玩法ID不变；楼板、关卡墙和塔楼外墙永久可见；仅正式高模视野外流式。","Codex"]];

await fs.mkdir(outputDir, { recursive: true });
const blob = await SpreadsheetFile.exportXlsx(workbook);
await blob.save(registryPath);
await blob.save(`${outputDir}/ShellStorm2_美术资产台账_v001.xlsx`);
for (const sheetName of ["总览", "资产主表", "版本记录"]) {
  const preview = await workbook.render({ sheetName, autoCrop: "all", scale: 1, format: "png" });
  await fs.writeFile(`${outputDir}/${sheetName}.png`, new Uint8Array(await preview.arrayBuffer()));
}
console.log("REGISTRY_UPDATE_OK rows=9 range=A226:X234 version=v0.1.10");
