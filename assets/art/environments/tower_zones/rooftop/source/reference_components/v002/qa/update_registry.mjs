import fs from 'node:fs/promises';import crypto from 'node:crypto';import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
const R='/Users/summercards/ShellStorm2',O=R+'/assets/art/environments/tower_zones/rooftop/source/reference_components/v002';
const path=R+'/assets/registry/ShellStorm2_美术资产台账_v001.xlsx';
await fs.copyFile(path,O+'/qa/registry_before.xlsx');
const cat=JSON.parse(await fs.readFile(O+'/component_packages_v002/catalog.json','utf8'));
const source=cat[0].source_blend,sha=crypto.createHash('sha256').update(await fs.readFile(R+'/'+source)).digest('hex');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(path)),s=wb.worksheets.getItem('3D-场景通用'),m=wb.worksheets.getItem('资产主表');
const rows=s.getRange('A1:A160').values;let next=135;
for(const p of cat){
 let row=rows.findIndex(r=>r[0]===p.package_id)+1;
 if(!row){row=next++;s.getRange(`A${row}:P${row}`).copyFrom(s.getRange('A104:P104'),'all');s.getRange(`A${row}:P${row}`).values=[[p.package_id,p.name_zh,null,null,null,'独立挂藤墙体变体',null,'未创建','未来由Godot包装持有','未创建',null,'XY中心/底面0；-Y','天台参考组件库 / '+p.slug,'Blender源已完成','v002',null]];s.getRange(`A${row}:P${row}`).format.rowHeight=84;}
 s.getRange(`E${row}`).values=[[source+'#'+p.blender_collection]];
 s.getRange(`K${row}`).values=[[p.bounds_size.map(v=>v.toFixed(3)).join('×')+' m']];
 s.getRange(`O${row}`).values=[['v002']];
 s.getRange(`P${row}`).values=[[`父库=ENV-ROOFTOP-REFERENCE-COMPONENT-LIBRARY；manifest=${source.substring(0,source.lastIndexOf('/'))}/component_packages_v002/${p.category.slice(0,2)}/${p.slug}/asset_manifest.json；外墙植物包络不进入阻挡；未导入Godot。`]];
 if(p.slug==='door_lamp')s.getRange(`F${row}`).values=[['厚门柱1.10m、门楣1.16m、门槛1.55m；门扇内凹；独立输出。']];
}
s.getRange('E97:F97').values=[[source,'44独立包；新增7个挂藤墙体变体，门口具有真实石材厚度与内凹门扇。']];
s.getRange('O97:P97').values=[['v002',`2026-09-17：36包锁区签名保持；门柱1.10m/门楣1.16m；4材质；126322面UV通过；未接入Godot。SHA256=${sha}`]];
m.getRange('M429:P429').values=[['v002','44包 / 45输出网格 / 4材质',source,'用户参考与加厚门口追加要求；v002/qa/验证报告']];m.getRange('T429').values=[[sha]];
m.getRange('Y429').values=[['v002新增7个挂藤变体；门口加厚并保持门扇尺寸；其余36包源/输出几何及变换签名一致；未导入Godot。']];
wb.recalculate();
console.log((await wb.inspect({kind:'table',range:'3D-场景通用!A135:B141',include:'values',tableMaxRows:7,tableMaxCols:2})).ndjson);
for(const [sheet,range,name] of [['3D-场景通用','A135:B141','registry_new'],['3D-场景通用','E124:F124','registry_door'],['资产主表','M429:P429','registry_master']]){const png=await wb.render({sheetName:sheet,range,scale:1.2});await fs.writeFile(O+'/qa/'+name+'.png',new Uint8Array(await png.arrayBuffer()));}
await (await SpreadsheetFile.exportXlsx(wb)).save(path);
await fs.writeFile(O+'/qa/registry_update.json',JSON.stringify({sha256:sha,scene_rows:[97,141],new_rows:[135,141],master_row:429},null,2));console.log('UPDATED',sha);
