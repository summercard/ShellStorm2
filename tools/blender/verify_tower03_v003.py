"""塔3 v003 最终重开态验收：不改 Godot、运行资产或账本。"""
from __future__ import annotations
import bpy, hashlib, json, math, struct
from collections import Counter, defaultdict
from pathlib import Path
from mathutils import Vector

ROOT=Path('I:/工作项目/shellstrom2/ShellStorm2')
BASE=ROOT/'assets/art/environments/open_world'
SOURCE=BASE/'source/tower_03/export/v001/env_tower_03-v001-runtime.blend'
ORIGINAL=BASE/'source/tower_03/v001/塔楼03_设备天台办公楼_v001.blend'
BLEND=BASE/'source/tower_03/export/v003/env_tower_03-v003-runtime_optimized.blend'
V001=BASE/'source/tower_03/export/v001/export_manifest.json'
V003=BASE/'source/tower_03/export/v003/export_manifest.json'
OPT_QA=BASE/'source/tower_03/export/v003/qa/optimization_v003.json'
EXPORT_QA=BASE/'source/tower_03/export/v003/qa/export_v003.json'
PALETTE=ROOT/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
STAGED=BASE/'source/tower_03/export/v003/staged_components'
OUT_QA=BASE/'source/tower_03/export/v003/qa'
EXPECTED={SOURCE:'a5eb1a4429fdb9ccbbf1de3a6ae11a4f2b1edcac3deb02878f455ecf99b3f744',ORIGINAL:'91b2f8f7d7ccfd483e76799e4b0a7573492b1741021eb3f7b34e5bfc24ec631e'}
UV_MARGIN=.01
UV_MIN_AREA=1e-10
BOUND_EPS=1e-6


def sha(path):
 h=hashlib.sha256();
 with Path(path).open('rb') as f:
  for c in iter(lambda:f.read(1024*1024),b''): h.update(c)
 return h.hexdigest()

def tri(obj): obj.data.calc_loop_triangles(); return len(obj.data.loop_triangles)
def bounds(objects):
 p=[obj.matrix_world@Vector(c) for obj in objects for c in obj.bound_box]
 return [[min(x[i] for x in p) for i in range(3)],[max(x[i] for x in p) for i in range(3)]]
def add_anchor(b,a): return [[b[s][i]+a[i] for i in range(3)] for s in range(2)]
def uv_area(c): return abs(sum(a[0]*c[(i+1)%len(c)][1]-c[(i+1)%len(c)][0]*a[1] for i,a in enumerate(c)))*.5
def cell(uv): return (min(9,max(0,int(math.floor(uv[0]*10)))),min(9,max(0,int(math.floor(uv[1]*10)))))
def uv_ok(c):
 if not c or not all(math.isfinite(v) for u in c for v in u): return False,'invalid'
 cells={cell(u) for u in c}
 if len(cells)!=1:return False,'crosses_cells'
 x,y=next(iter(cells))
 if not all(x*.1+UV_MARGIN<=u[0]<=(x+1)*.1-UV_MARGIN and y*.1+UV_MARGIN<=u[1]<=(y+1)*.1-UV_MARGIN for u in c):return False,'unsafe_margin'
 if uv_area(c)<=UV_MIN_AREA:return False,'zero_uv_area'
 return True,'ok'
def glb_json(path):
 raw=Path(path).read_bytes(); magic,ver,length=struct.unpack_from('<4sII',raw,0); assert (magic,ver,length)==(b'glTF',2,len(raw))
 pos=12; out=None
 while pos<len(raw):
  n,t=struct.unpack_from('<II',raw,pos);pos+=8; data=raw[pos:pos+n];pos+=n
  if t==0x4E4F534A:out=json.loads(data.rstrip(b' \0\r\n').decode())
 return out
def glb_tri(data):
 a=data.get('accessors',[]); total=0
 for m in data.get('meshes',[]):
  for p in m.get('primitives',[]):
   total += int(a[p['indices']]['count'])//3 if 'indices' in p else int(a[p['attributes']['POSITION']]['count'])//3
 return total

def main():
 assert Path(bpy.data.filepath).resolve()==BLEND.resolve(),bpy.data.filepath
 old=json.loads(V001.read_text(encoding='utf-8')); new=json.loads(V003.read_text(encoding='utf-8')); opt=json.loads(OPT_QA.read_text(encoding='utf-8')); exp=json.loads(EXPORT_QA.read_text(encoding='utf-8'))
 assert len(old['records'])==217 and len(new['records'])==217
 hashes={str(p):{'expected':h,'actual':sha(p),'match':sha(p)==h} for p,h in EXPECTED.items()}; palette_hash=sha(PALETTE)
 objects=[bpy.data.objects[n] for r in new['records'] for n in r['objects']]
 assert len(objects)==228 and len(set(objects))==228
 uv=Counter(); uv_objects=[]; mat_errors=[]; bounds_errors=[]; blend_records=[]
 for r in new['records']:
  os=[bpy.data.objects[n] for n in r['objects']]; t=sum(tri(o) for o in os); b=bounds(os); wb=add_anchor(b,r['anchor_blender']);
  blend_records.append((r['slug'],t));
  for s in range(2):
   for i in range(3):
    if abs(wb[s][i]-r['bounds_blender'][s][i])>BOUND_EPS:bounds_errors.append({'slug':r['slug'],'axis':(s,i),'blend':wb[s][i],'manifest':r['bounds_blender'][s][i]})
  for o in os:
   layer=o.data.uv_layers.get('PaletteUV')
   if layer is None:uv['missing_layer']+=len(o.data.polygons);continue
   if o.data.uv_layers.active!=layer or not layer.active_render:uv['inactive_layer_objects']+=1
   for p in o.data.polygons:
    good,reason=uv_ok([tuple(layer.data[i].uv) for i in p.loop_indices]);uv[reason]+=1
    if not good:uv_objects.append({'object':o.name,'face':p.index,'reason':reason})
   for extra in o.data.uv_layers:
    if extra.name!='PaletteUV':uv['extra_uv_layers']+=1
   for m in o.data.materials:
    if not m:continue
    if m.name not in {'01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光'}:mat_errors.append({'object':o.name,'material':m.name})
  
 glb_errors=[]; glb_total=0; glb_records=[]
 for r in new['records']:
  path=ROOT/r['glb']; data=glb_json(path); gt=glb_tri(data); glb_total+=gt
  errors=[]
  if data.get('images') or data.get('textures'):errors.append('embedded_images_or_textures')
  if data.get('animations') or data.get('cameras') or data.get('extensions',{}).get('KHR_lights_punctual'):errors.append('non_visual_payload')
  if len(data.get('materials',[]))>4:errors.append('material_budget')
  if any('TEXCOORD_0' not in p.get('attributes',{}) for m in data.get('meshes',[]) for p in m.get('primitives',[])):errors.append('missing_texcoord_0')
  if gt!=r['triangle_count_blender']:errors.append('glb_blender_triangle_mismatch')
  if errors:glb_errors.append({'slug':r['slug'],'errors':errors})
  glb_records.append({'slug':r['slug'],'triangles_glb':gt,'sha256':sha(path),'errors':errors})
 categories=defaultdict(lambda:[0,0,0])
 for r in new['records']:
  c=r['category']; categories[c][0]+=1;categories[c][1]+=r['triangle_count_blender'];categories[c][2]+=r['triangle_count_glb']
 old_by={r['slug']:r for r in old['records']}; retention_errors=[]
 for r in new['records']:
  before=old_by[r['slug']]['triangle_count']; after=r['triangle_count_blender']; slug=r['slug'];
  if (r['category']=='floor' or slug in {'main_structure','entrance'}) and after!=before:retention_errors.append({'slug':slug,'rule':'100%','before':before,'after':after})
  if r['category'] in {'support','hvac','telecom'} or slug in {'plant_room','plant_east_louvers'}:
   if after<math.ceil(before*.82):retention_errors.append({'slug':slug,'rule':'.82','before':before,'after':after,'retention':after/before})
 stable_bad=[r['slug'] for r in new['records'] if any(v in r[k].replace('\\','/') for k in ('stable_glb','runtime_glb','stable_prefab') for v in ('/v001/','/v002/','/v003/','_v001','_v002','_v003'))]
 report={'passed': all(x['match'] for x in hashes.values()) and not uv_objects and not mat_errors and not bounds_errors and not glb_errors and not retention_errors and glb_total<100000 and len(stable_bad)==0,'version':'v003','reopened_blend':str(BLEND.relative_to(ROOT)).replace('\\','/'),'reopened_blend_sha256':sha(BLEND),'protected_hashes':hashes,'palette_sha256':palette_hash,'records':217,'triangles_blend_reopened':sum(t for _,t in blend_records),'triangles_manifest_glb':sum(r['triangle_count_glb'] for r in new['records']),'triangles_glb_actual':glb_total,'script_memory_stat_triangles':opt['triangles_after'],'reopen_delta_vs_script':sum(t for _,t in blend_records)-opt['triangles_after'],'categories':dict(categories),'strict_palette_uv':{'counts':dict(uv),'failures':uv_objects,'passed':not uv_objects and not uv.get('missing_layer') and not uv.get('inactive_layer_objects') and not uv.get('extra_uv_layers')},'bounds_errors':bounds_errors,'material_errors':mat_errors,'glb_errors':glb_errors,'retention_errors':retention_errors,'stable_path_errors':stable_bad,'staged_root':new['staged_component_root'],'runtime_integrated':False,'godot_modified':False,'ledger_modified':False,'visual_acceptance':{'v001':'outputs/tower03_v003/v001','v003':'outputs/tower03_v003/v003','views':['全景_front','全景_back','全景_side','全景_rooftop','近景_天台','近景_HVAC'],'read_by_agent':True}}
 (OUT_QA/'tower03_v003_final.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 lines=['塔3 v003 最终 Blender 优化/导出验收','',f"总状态: {'PASS' if report['passed'] else 'BLOCKED'}",f"重开 Blend tri: {report['triangles_blend_reopened']}",f"GLB 实际 tri: {report['triangles_glb_actual']}",f"内存态脚本 tri: {report['script_memory_stat_triangles']}；重开差异: {report['reopen_delta_vs_script']}",'', '分区（组件数 / Blender重开tri / GLB tri）：']
 for c,v in sorted(categories.items()):lines.append(f'- {c}: {v[0]} / {v[1]} / {v[2]}')
 lines += ['',f"严格 PaletteUV: {'PASS' if report['strict_palette_uv']['passed'] else 'FAIL'}",f"GLB无内嵌纹理/索引一致: {'PASS' if not glb_errors else 'FAIL'}",f"保留率与地板/主体入口锁定: {'PASS' if not retention_errors else 'FAIL'}",f"包络核对: {'PASS' if not bounds_errors else 'FAIL'}",f"源哈希: {'PASS' if all(x['match'] for x in hashes.values()) else 'FAIL'}",'', '视觉证据: outputs/tower03_v003/v001 与 v003；固定机位全景正/背/侧、天台、天台近景、HVAC近景。','运行时接入: false；Godot/账本: 未修改。']
 (OUT_QA/'tower03_v003_final.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
 print(json.dumps({'passed':report['passed'],'triangles_blend_reopened':report['triangles_blend_reopened'],'triangles_glb_actual':report['triangles_glb_actual'],'uv':report['strict_palette_uv']['passed'],'glb_errors':len(glb_errors),'retention_errors':len(retention_errors),'bounds_errors':len(bounds_errors)},ensure_ascii=False),flush=True)

if __name__=='__main__':main()
