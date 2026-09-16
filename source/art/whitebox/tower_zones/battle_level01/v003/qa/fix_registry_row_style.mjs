import {FileBlob, SpreadsheetFile} from '/Users/summercards/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs';

const ledger='/Users/summercards/ShellStorm2/assets/registry/ShellStorm2_美术资产台账_v001.xlsx';
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(ledger));
const sheet=wb.worksheets.getItem('3D-场景通用');
sheet.getRange('A89:P89').copyTo(sheet.getRange('A91:P91'),'all');
sheet.getRange('A91:P91').values=[[
  'ENV-BATTLE-L01-CORRIDOR-WALL-5M','局内关卡01 走廊通用墙壁 5×0.30×11.9m 白模','未制作','未制作',
  'source/art/whitebox/tower_zones/battle_level01/v003/blender/局内关卡01_白模_走廊墙壁_5x0.3x11.9m_v003.blend',
  '走廊通用实墙白模模块；按5m网格重复拼接。','未接入','无','无','无','5×0.30×11.9m',
  '底面中心；Godot -Z','局内关卡01 / Battle','白模源已完成；QA PASS','v003',
  '2026-09-16：普通墙改为5m标准件；带门墙完整占用5m槽。Scale=1，无超过5m墙件；未导出GLB或接入Godot。'
]];
sheet.getRange('A91:P91').format = {verticalAlignment:'top', wrapText:true};
const out=await SpreadsheetFile.exportXlsx(wb);
await out.save(ledger);
