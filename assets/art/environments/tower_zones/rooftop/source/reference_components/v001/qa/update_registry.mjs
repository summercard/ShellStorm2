import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
const root='/Users/summercards/ShellStorm2';
const dir=root+'/assets/art/environments/tower_zones/rooftop/source/reference_components/v001';
const file=root+'/assets/registry/ShellStorm2_美术资产台账_v001.xlsx';
const id='ENV-ROOFTOP-REFERENCE-COMPONENT-LIBRARY';
const catalog=JSON.parse(await fs.readFile(dir+'/component_packages_v001/catalog.json','utf8'));
const source=catalog[0].source_blend;
const hash=crypto.createHash('sha256').update(await fs.readFile(root+'/'+source)).digest('hex');
try {await fs.access(dir+'/qa/registry_before.xlsx');} catch {await fs.copyFile(file,dir+'/qa/registry_before.xlsx');}
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(file));
const s=wb.worksheets.getItem('3D-场景通用'),m=wb.worksheets.getItem('资产主表');
const ids=s.getRange('A1:A200').values;
if(ids.some(r=>r[0]===id)){
 m.getRange('T429').values=[[hash]];
 const note=s.getRange('P97').values[0][0];s.getRange('P97').values=[[note.replace(/SHA256=[a-f0-9]+/,'SHA256='+hash)]];
 wb.recalculate();await (await SpreadsheetFile.exportXlsx(wb)).save(file);
 const meta=JSON.parse(await fs.readFile(dir+'/qa/registry_update.json','utf8'));meta.source_sha256=hash;
 await fs.writeFile(dir+'/qa/registry_update.json',JSON.stringify(meta,null,2));
 console.log('REGISTRY_HASH_UPDATED',hash);process.exit(0);
}
const first=97;
const rows=[[id,'天台区块 参考组件库',null,null,source,'参考图九类组件+标准外墙；37独立包；可编辑制作源及整合输出。',null,'未创建','未来由Godot包装持有','未创建','外墙5×0.30×11.9m；逻辑12m','XY居中、底面Z=0；正面-Y','Rooftop / 100F；组件库，非正式布局替换','Blender源已完成','v001',`2026-09-17；四共享材质；逐面PaletteUV与尺寸验收；未导出GLB或接入运行时。SHA256=${hash}`]];
for(const p of catalog)rows.push([p.package_id,p.name_zh,null,null,source+'#'+p.blender_collection,'独立资产包；'+p.category,null,'未创建','独立包运行包装','未创建',p.bounds_size.map(v=>v.toFixed(3)).join('×')+' m','XY中心/底面0；-Y','天台参考组件库 / '+p.slug,'Blender源已完成','v001',`父ID=${id}；manifest=${source.substring(0,source.lastIndexOf('/'))}/component_packages_v001/${p.category.slice(0,2)}/${p.slug}/asset_manifest.json；不替换既有运行资产。`]);
for(let i=0;i<rows.length;i++)s.getRange(`A${first+i}:P${first+i}`).copyFrom(s.getRange('A90:P90'),'all');
s.getRange(`A${first}:P${first+rows.length-1}`).values=rows;
s.getRange(`A${first}:P${first+rows.length-1}`).format.rowHeight=84;
s.getRange(`A${first}:P${first+rows.length-1}`).format.wrapText=true;
const r=429;
m.getRange(`A${r}:Y${r}`).copyFrom(m.getRange('A428:Y428'),'all');
m.getRange(`A${r}:Y${r}`).values=[[id,'天台参考组件库','场景','environment_kit_3d','rooftop_reference','component_library','ENV-ROOFTOP-SHELTER-90X80','Blender Z-up / -Y','reference_components','100F独立组件制作；原运行布局保留','Blender源已完成','P1','v001','37包 / 38输出网格 / 4材质',source,'用户参考图；qa/build_rooftop.py；qa/task_validation.json','天台;屋顶;女儿墙;外墙;空调;管道;藤蔓',null,null,hash,'Codex',new Date('2026-09-17T00:00:00Z'),'用户提供参考图；Blender几何制作','项目内部','组件目录是本批替换边界；外墙5×0.3×11.9m，逻辑/未来阻挡12m；未导出或改变正式Godot引用。']];
m.getRange(`R${r}`).formulas=[[`=LOWER(TRIM(C${r})&"|"&TRIM(D${r})&"|"&TRIM(E${r})&"|"&TRIM(F${r})&"|"&TRIM(H${r})&"|"&TRIM(I${r}))`]];
m.getRange(`S${r}`).formulas=[[`=IF(COUNTIF($R$6:$R$${r},R${r})>1,"重复","唯一")`]];
m.getRange(`V${r}`).numberFormat='yyyy-mm-dd';m.getRange(`A${r}:Y${r}`).format.rowHeight=90;m.getRange(`A${r}:Y${r}`).format.wrapText=true;
wb.recalculate();
console.log((await wb.inspect({kind:'table',range:'3D-场景通用!A97:B100',include:'values',tableMaxRows:4,tableMaxCols:2})).ndjson);
console.log((await wb.inspect({kind:'match',range:'资产主表!R429:S429',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!',options:{useRegex:true,maxResults:10}})).ndjson);
for(const [sheet,range,name] of [['3D-场景通用','A97:B108','registry_01'],['3D-场景通用','A109:B120','registry_02'],['3D-场景通用','A121:B134','registry_03'],['资产主表','A429:G429','registry_master']]){
 const png=await wb.render({sheetName:sheet,range,scale:1.4});await fs.writeFile(dir+'/qa/'+name+'.png',new Uint8Array(await png.arrayBuffer()));
}
await (await SpreadsheetFile.exportXlsx(wb)).save(file);
await fs.writeFile(dir+'/qa/registry_update.json',JSON.stringify({source_sha256:hash,master_row:r,scene_rows:[first,first+rows.length-1],asset_id:id,children:catalog.length},null,2));
console.log('REGISTRY_UPDATED',hash);
