import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import { FileBlob, SpreadsheetFile } from '/Users/summercards/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs';

const root = process.cwd();
const version = process.argv[2] || 'v009';
const skipValidation = process.argv.includes('--skip-validation');
const pkg = `assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production/${version}`;
const ledger = JSON.parse(await fs.readFile(`${root}/${pkg}/character_transfer_ledger_${version}.json`, 'utf8'));
const path = `${root}/assets/registry/ShellStorm2_美术资产台账_v001.xlsx`;
const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(path));
const model = `${pkg}/source/model/chr_bunny01_model_${version}.blend`;
const motion = `${pkg}/source/animation/chr_bunny01_animation_${version}.blend`;
const wrapper = `${pkg}/runtime/chr_bunny01_root_${version}.tscn`;
const hash = async p => crypto.createHash('sha256').update(await fs.readFile(`${root}/${p}`)).digest('hex');
const master = wb.worksheets.getItem('资产主表');
const mappings = new Map([[6,wrapper],[156,wrapper],[157,`${pkg}/exports/chr_bunny01_body_${version}.glb`],[158,`${pkg}/exports/chr_bunny01_head_${version}.glb`],[159,`${pkg}/exports/chr_bunny01_ear_l_${version}.glb; ${pkg}/exports/chr_bunny01_ear_r_${version}.glb`],[160,`${pkg}/exports/chr_bunny01_hand_l_${version}.glb; ${pkg}/exports/chr_bunny01_hand_r_${version}.glb`],[161,`${pkg}/exports/chr_bunny01_foot_l_${version}.glb`],[162,`${pkg}/exports/chr_bunny01_foot_r_${version}.glb`],[205,wrapper],[297,`${pkg}/runtime/chr_bunny01_chibi_anime_root_${version}.tscn`]]);
for (const [row,p] of mappings) {
  master.getRange(`M${row}`).values = [[version]];
  master.getRange(`O${row}`).values = [[p]];
  master.getRange(`P${row}`).values = [[`${model}; ${motion}; ${pkg}/character_transfer_ledger_${version}.json`]];
  master.getRange(`T${row}`).values = [[(await Promise.all(p.split('; ').map(hash))).join(' / ')]];
  const old = String(master.getRange(`X${row}`).values[0][0] ?? '');
  const note = version === 'v011' ? '2026-09-10：v011 +Y到Godot -Z统一朝向；原位直链绑定、腰胸归位、四基础动作无骨链拉伸。验收结果见中转JSON。' : version === 'v010' ? '2026-09-09：v010 腰胸/上下臂/指链/大小腿新骨架，模型未改；待机、移动、持枪待机、持枪移动重新制作并接入。用户要求跳过验收，未验证；其他状态沿用v009。' : '2026-09-09：双Blend共享骨架 v009；新导出分件骨局部原点，八态Blender动作库接入；玩法层级/碰撞不变。';
  if (!old.includes(note)) master.getRange(`X${row}`).values = [[`${old}\n${note}`]];
}
const parts = wb.worksheets.getItem('角色组件');
master.getRange('N159').values = [['左右独立 GLB / 已烘焙镜像']];
parts.getRange('F34:F35').values = [['骨局部 GLB / 左耳独立网格'],['骨局部 GLB / 右耳独立网格']];
parts.getRange('E31').values = [[wrapper]];
const names=['body','head','ear_l','ear_r','hand_l','hand_r','foot_l','foot_r'];
for(let i=0;i<names.length;i++) {
  parts.getRange(`E${32+i}`).values = [[`${pkg}/exports/chr_bunny01_${names[i]}_${version}.glb`]];
  parts.getRange(`M${32+i}`).values = [[`${version}：${names[i]} 兼容部件原点导出；共享模型/动作骨架；状态 ${ledger.status}。`]];
}
const three = wb.worksheets.getItem('3D-角色');
if(version === 'v011') {
  master.getRange('N156').values=[['创作高1.5m；运行可见高1.05m；碰撞由Player3D拥有，不随美术骨架修改。']];
  parts.getRange('F31').values=[['刚性分件骨动作适配；创作高1.5m，运行可见高1.05m；玩法碰撞独立。']];
  const states=wb.worksheets.getItem('动画与状态');
  states.getRange('F6').values=[['v011：3.2秒低幅呼吸/重心微移，部件刚性不缩放；持枪待机使用armed_idle（2.8秒）。']];
  states.getRange('F7').values=[['v011：0.8秒交替步态与低幅起伏；持枪移动使用armed_moving；0.18秒过渡，无骨链拉伸。']];
  states.getRange('G6').values=[['刚性头部，不缩放；低幅反向滞后保持重量感。']];
}
three.getRange('C6').values = [[wrapper]];
three.getRange('D6').values = [[`${pkg}/exports/chr_bunny01_model_${version}.glb；运行时分件见角色中转记录`]];
three.getRange('E6').values = [['模型、动作双母版：完整路径见「角色中转记录」']];
three.getRange('O6:O7').values = [[version],[version]];
three.getRange('P6:P7').values = [[`双文件共享骨架；状态 ${ledger.status}；中转 ${pkg}/character_transfer_ledger_${version}.json`],[`Avatar3D引用 ${wrapper}；功能层级未更改`]];
let sheet;
try { sheet=wb.worksheets.getItem('角色中转记录'); } catch { sheet=wb.worksheets.add('角色中转记录'); }
const records = [[`角色 ${version} 模型与动作中转记录`],['状态',ledger.status,'骨架ID',ledger.skeleton_id],['文件类型','相对路径','SHA-256','字节数'],...ledger.files.map(f=>[f.path.endsWith('.blend')?(f.path.includes('/animation/')?'动作母版':'模型母版'):'导出文件',f.path,f.sha256,f.bytes])];
sheet.getRange('A1').write(records);
sheet.getRange('A1:D1').merge();
sheet.getRange('A1:D30').format.font.name='Arial';
sheet.getRange('A1:D30').format.font.size=11;
sheet.getRange('A3:D3').format.fill='#246397';
sheet.getRange('A3:D3').format.font.color='#FFFFFF';
sheet.getRange('A:A').format.columnWidth=16;
sheet.getRange('B:B').format.columnWidth=75;
sheet.getRange('C:C').format.columnWidth=70;
sheet.getRange('D:D').format.columnWidth=12;
sheet.getRange('C2:D2').merge();
sheet.getRange('C2').values = [[`骨架：${ledger.skeleton_id}`]];
sheet.getRange('A4:D30').format.wrapText=true;
sheet.getRange('A4:D30').format.rowHeight=65;
sheet.freezePanes.freezeRows(3);
sheet.showGridLines=false;
wb.recalculate();
await (await SpreadsheetFile.exportXlsx(wb)).save(path);
await fs.mkdir(`${root}/outputs/character_pipeline/registry`,{recursive:true});
for(const [name,range] of [['角色中转记录','A1:D8'],['3D-角色','A4:F8'],['角色组件','A31:F39'],['资产主表','A156:O162'],['动画与状态','A5:G7']]) {
  if (skipValidation) break;
  const blob=await wb.render({sheetName:name,range,scale:1,format:'png'});
  await fs.writeFile(`${root}/outputs/character_pipeline/registry/${name}.png`,new Uint8Array(await blob.arrayBuffer()));
}
console.log('CHARACTER_REGISTRY_SYNC_OK');
