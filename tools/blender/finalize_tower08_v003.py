"""Final source envelope corrections and visible external pinnacle fins."""
import bpy, json, shutil, math
from pathlib import Path
from mathutils import Vector
R=Path(__file__).resolve().parents[2]
OLD=R/'assets/art/environments/open_world/source/tower_08/v002'
OUT=OLD.parent/'v003'; BLEND=OUT/'塔8_CITYLIVE空中花园地标_50m_v003.blend'
if BLEND.exists(): raise SystemExit('Existing v003 protected')
for d in ('qa','previews','references','component_packages'): (OUT/d).mkdir(parents=True,exist_ok=True)
shutil.copy2(OLD/'references/塔8_用户参考.jpg',OUT/'references/塔8_用户参考.jpg')
bpy.ops.wm.open_mainfile(filepath=str(OLD/'塔8_CITYLIVE空中花园地标_50m_v002.blend'))
sc=bpy.context.scene; sc['version']='v003'
game=bpy.data.collections['02_游戏输出_独立资产包_v002']; game.name='02_游戏输出_独立资产包_v003'
# Expose crown's architectural fins beyond the central upper facade.
for o in [o for o in sc.objects if o.type=='MESH']:
 if o.get('package_id')=='tower_08/spire_fins':
  for v in o.data.vertices: v.co.y-=2.8
 # Point-wise trimming applies only to 55mm ornaments outside the envelope.
 for v in o.data.vertices:
  q=o.matrix_world@v.co
  if q.y < -17: v.co.y+=-17-q.y
  if q.y > 17: v.co.y+=17-q.y
  if q.z<0: v.co.z-=q.z
 o['version']='v003'
# Font outlines are embedded for maintainable editing; palette remains external.
for font in bpy.data.fonts:
 if font.filepath and font.filepath!='<builtin>':
  try: font.pack()
  except Exception: pass
meta=json.loads((OLD/'catalog.json').read_text(encoding='utf8'))
bpy.context.view_layer.update()
for item in meta['packages']:
 c=bpy.data.collections[item['collection']]
 pts=[o.matrix_world@v.co for o in c.objects if o.type=='MESH' for v in o.data.vertices]
 mn=[min(v[j] for v in pts) for j in range(3)]; mx=[max(v[j] for v in pts) for j in range(3)]
 item.update(version='v003',source_blend=str(BLEND.relative_to(R)),bounds_min=mn,bounds_max=mx,dimensions=[mx[j]-mn[j] for j in range(3)])
 d=OUT/'component_packages'/item['category']/item['slug']; d.mkdir(parents=True,exist_ok=True)
 (d/'asset_manifest.json').write_text(json.dumps(item,ensure_ascii=False,indent=2),encoding='utf8')
meta.update(source_version='v003',source_blend=str(BLEND.relative_to(R)),source_status='Blender源已完成',review_notes='最终点级包络修正、冠顶飞扶壁可见性修正；保留v001/v002；公共色盘不打包；字体打包')
(OUT/'catalog.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8')
plan=json.loads((OLD/'component_plan.json').read_text(encoding='utf8')); plan['source_version']='v003'
(OUT/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'component_packages/tree.txt').write_text('\n'.join(c['category']+'/'+c['slug']+' - '+c['display_name'] for c in meta['packages']),encoding='utf8')
sc.camera=bpy.data.objects['CAM_参考图全景']; sc.render.resolution_x=1400; sc.render.resolution_y=1800
sc.render.filepath=str(OUT/'previews/01_塔8_参考全景.png')
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND)); print('SOURCE_SAVED',str(BLEND),flush=True)
try:
 prefs=bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type='OPTIX'; prefs.get_devices()
 for dev in prefs.devices: dev.use=dev.type!='CPU'
 if any(dev.use for dev in prefs.devices): sc.cycles.device='GPU'
except Exception: pass
cams=[('CAM_参考图全景','01_塔8_参考全景.png'),('CAM_正立面','02_塔8_正立面.png'),('CAM_花园入口近景','03_塔8_悬挑花园入口.png'),('CAM_冠顶巨幕近景','04_塔8_冠顶巨幕.png'),('CAM_俯视','05_塔8_俯视结构.png'),('CAM_背面','06_塔8_背面完整性.png')]
for name,file in cams:
 cam=bpy.data.objects[name]; sc.camera=cam; sc.render.resolution_x=cam['resolution_x']; sc.render.resolution_y=cam['resolution_y']; sc.render.filepath=str(OUT/'previews'/file)
 bpy.ops.render.render(write_still=True); print('RENDER_DONE',file,flush=True)
print('FINAL_SOURCE_COMPLETE',flush=True)
