import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import { FileBlob, SpreadsheetFile } from '/Users/summercards/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs';

const root = process.cwd();
const pkg = 'assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v009';
const ledger = JSON.parse(await fs.readFile(`${root}/${pkg}/character_transfer_ledger_v009.json`, 'utf8'));
const path = `${root}/assets/registry/ShellStorm2_美术资产台账_v001.xlsx`;
const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(path));
const model = `${pkg}/source/model/chr_bunny01_model_v009.blend`;
const motion = `${pkg}/source/animation/chr_bunny01_animation_v009.blend`;
const wrapper = `${pkg}/runtime/chr_bunny01_root_v009.tscn`;
const hash = async p => crypto.createHash('sha256').update(await fs.readFile(`${root}/${p}`)).digest('hex');
const master = wb.worksheets.getItem('资产主表');
const mappings = new Map([[6,wrapper],[156,wrapper],[157,`${pkg}/exports/chr_bunny01_body_v009.glb`],[158,`${pkg}/exports/chr_bunny01_head_v009.glb`],[159,`${pkg}/exports/chr_bunny01_ear_l_v009.glb; ${pkg}/exports/chr_bunny01_ear_r_v009.glb`],[160,`${pkg}/exports/chr_bunny01_hand_l_v009.glb; ${pkg}/exports/chr_bunny01_hand_r_v009.glb`],[161,`${pkg}/exports/chr_bunny01_foot_l_v009.glb`],[162,`${pkg}/exports/chr_bunny01_foot_r_v009.glb`],[205,wrapper],[297,`${pkg}/runtime/chr_bunny01_chibi_anime_root_v009.tscn`]]);
for (const [row,p] of mappings) {
  master.getRange(`M${row}`).values = [['v009']];
  master.getRange(`O${row}`).values = [[p]];
  master.getRange(`P${row}`).values = [[`${model}; ${motion}; ${pkg}/character_transfer_ledger_v009.json`]];
  master.getRange(`T${row}`).values = [[(await Promise.all(p.split('; ').map(hash))).join(' / ')]];
  const old = String(master.getRange(`X${row}`).values[0][0] ?? '');
  const note = '2026-09-09：双Blend共享骨架 v009；新导出分件骨局部原点，八态Blender动作库接入；玩法层级/碰撞不变。';
  if (!old.includes(note)) master.getRange(`X${row}`).values = [[`${old}\n${note}`]];
}
const parts = wb.worksheets.getItem('角色组件');
master.getRange('N159').values = [['左右独立 GLB / 已烘焙镜像']];
parts.getRange('F34:F35').values = [['骨局部 GLB / 左耳独立网格'],['骨局部 GLB / 右耳独立网格']];
parts.getRange('E31').values = [[wrapper]];
const names=['body','head','ear_l','ear_r','hand_l','hand_r','foot_l','foot_r'];
for(let i=0;i<names.length;i++) {
  parts.getRange(`E${32+i}`).values = [[`${pkg}/exports/chr_bunny01_${names[i]}_v009.glb`]];
  parts.getRange(`M${32+i}`).values = [[`v009：${names[i]} 骨局部导出；共享模型/动作骨架；见角色中转记录。`]];
}
const three = wb.worksheets.getItem('3D-角色');
three.getRange('C6').values = [[wrapper]];
three.getRange('D6').values = [[`${pkg}/exports/chr_bunny01_model_v009.glb（整骨架审阅）；运行时分件见角色中转记录`]];
three.getRange('E6').values = [['模型、动作双母版：完整路径见「角色中转记录」']];
three.getRange('O6:O7').values = [['v009'],['v009']];
three.getRange('P6:P7').values = [[`双文件共享骨架；中转 ${pkg}/character_transfer_ledger_v009.json`],[`Avatar3D引用 ${wrapper}；功能层级未更改`]];
let sheet;
try { sheet=wb.worksheets.getItem('角色中转记录'); } catch { sheet=wb.worksheets.add('角色中转记录'); }
const records = [['角色 v009 模型与动作中转记录'],['状态',ledger.status,'骨架ID',ledger.skeleton_id],['文件类型','相对路径','SHA-256','字节数'],...ledger.files.map(f=>[f.path.endsWith('.blend')?(f.path.includes('/animation/')?'动作母版':'模型母版'):'导出文件',f.path,f.sha256,f.bytes])];
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
for(const [name,range] of [['角色中转记录','A1:D8'],['3D-角色','A4:F8'],['角色组件','A31:F39'],['资产主表','A156:O162']]) {
  const blob=await wb.render({sheetName:name,range,scale:1,format:'png'});
  await fs.writeFile(`${root}/outputs/character_pipeline/registry/${name}.png`,new Uint8Array(await blob.arrayBuffer()));
}
console.log('CHARACTER_REGISTRY_SYNC_OK');
