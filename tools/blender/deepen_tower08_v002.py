"""Preserve v001, deepen reference correspondence, produce reviewed v002 source."""
import bpy, math, random, json, ast, shutil
from pathlib import Path
from mathutils import Vector
from mathutils.geometry import tessellate_polygon
R=Path(__file__).resolve().parents[2]
OLD=R/'assets/art/environments/open_world/source/tower_08/v001'
OUT=OLD.parent/'v002'; BLEND=OUT/'塔8_CITYLIVE空中花园地标_50m_v002.blend'
if BLEND.exists(): raise SystemExit('v002 exists; preserve source and increment version.')
for d in ('previews','qa','references','component_packages'): (OUT/d).mkdir(parents=True,exist_ok=True)
shutil.copy2(OLD/'references/塔8_用户参考.jpg',OUT/'references/塔8_用户参考.jpg')
bpy.ops.wm.open_mainfile(filepath=str(OLD/'塔8_CITYLIVE空中花园地标_50m_v001.blend'))
sc=bpy.context.scene; sc['version']='v002'
ASSET='ENV-OPENWORLD-TOWER08'; NAMES=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
MATS=[bpy.data.materials[n] for n in NAMES]
CREAM=(9,7); LIGHT=(9,6); TILE=(9,5); TILE2=(9,4); DARK=(9,1); STEEL=(9,3)
GOLD=(6,3); GOLD2=(7,3); BLUE=(3,6); BLUE2=(2,6); BLUEHI=(5,6)
TEAL=(6,5); GREEN=(6,4); GREEN2=(7,4); BLACK=(9,0); RUST=(7,2)
PINK=(5,8); PURPLE=(3,7); ORANGE=(6,2); RED=(5,1)
catalog=json.loads((OLD/'catalog.json').read_text(encoding='utf8'))['packages']
root=bpy.data.collections['塔8_CITYLIVE空中花园地标_中文资产管理']
src=bpy.data.collections['01_制作组件_按独立资产包']; game=bpy.data.collections['02_游戏输出_独立资产包_v001']; game.name='02_游戏输出_独立资产包_v002'
display=bpy.data.collections['90_展示与验收_固定灯光相机']
categories=[('architecture','01_建筑结构'),('facilities','02_入口与固定附属设施'),('signage','03_CITYLIVE巨幕与冠徽'),('garden','04_退台花园与栏杆'),('support','05_尖塔与灯带')]
CATS={k:bpy.data.collections[n] for k,n in categories}; SCATS={k:bpy.data.collections[n+'_制作源'] for k,n in categories}
palette_path=R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
# Remove incidental baseline underhang and keep the authored XY frame centered.
# Only out-of-envelope vertices are clamped, never rescale the whole building.
for o in [o for o in sc.objects if o.type=='MESH']:
 for v in o.data.vertices:
  q=o.matrix_world@v.co
  if q.z<0: v.co.z-=q.z
  if q.y < -17: v.co.y+=-17-q.y
 # Correct reference colors directly by cell, both source and output meshes.
 mapping={(5,5):BLUE,(3,5):BLUE2,(6,5):BLUEHI,(8,3):GOLD,(8,9):GOLD2,(6,7):PINK,(5,6):PURPLE,(7,2):ORANGE,(5,7):RED}
 uv=o.data.uv_layers['PaletteUV']
 for face in o.data.polygons:
  q=uv.data[face.loop_start].uv; key=(int(q.x*10),int((1-q.y)*10))
  if key in mapping:
   new=mapping[key]; dx=(new[0]-key[0])*.1; dy=(key[1]-new[1])*.1
   for li in face.loop_indices: uv.data[li].uv+=Vector((dx,dy))
 o['version']='v002'
# Explicit geometry helper reuse; do not replay old scene construction.
tree=ast.parse((R/'tools/blender/build_openworld_tower08_v001.py').read_text(encoding='utf8'))
shared=ast.parse((R/'tools/blender/build_skyline_08_source_v003.py').read_text(encoding='utf8'))
for node in shared.body:
 if isinstance(node,(ast.FunctionDef,ast.ClassDef)) and node.name in ['coll','uv_mesh','Part','rail']:
  code=ast.unparse(node).replace('skyline_08/','tower_08/').replace("'v003'","'v002'").replace('1F–8F＋天台','装饰退台地标；不定义战斗楼层')
  exec(compile(code,'<shared_geometry>','exec'))
for node in tree.body:
 if isinstance(node,ast.FunctionDef) and node.name in ['bolts','diamond','crown','trimbox']:
  exec(compile(ast.unparse(node),'<ornament>','exec'))
# Solid stone pilaster relief on wing side walls, recessed blue slots and golden seams.
for side in (-1,1):
 p=Part('side_relief_%s'%side,'侧面_%s_竖向石柱与蓝色凹槽'%('左' if side<0 else '右'),'architecture',(0,0,0),'side_facade_relief')
 for cx,w,d,z0,z1 in [(19,5.2,15,1.1,25),(16.1,5,18,12,49),(12.1,4.8,21,25,70)]:
  xx=side*(cx+w/2+.035)
  for j in range(4):
   yy=-.5-d*.36+j*d*.24
   p.box((xx,yy,(z0+z1)/2),(.12,d*.155,z1-z0-2.0),BLUE,2,.03)
   for sy in (-1,1):
    p.box((xx+side*.075,yy+sy*d*.095,(z0+z1)/2),(.15,.15,z1-z0-1.7),GOLD,0)
   for zz in [z0+2+k*4 for k in range(max(1,int((z1-z0)/4)))]:
    p.box((xx+side*.10,yy,zz),(.13,d*.15,.08),GOLD,0)
  for yy in [-.5-d*.48,-.5-d*.22,-.5+d*.02,-.5+d*.26,-.5+d*.48]:
   p.box((xx+side*.045,yy,(z0+z1)/2),(.25,.32,z1-z0-.6),LIGHT,1,.03)
 p.finish()
# Additional deep vertical ribs beside the central screen and warmer cove lamps.
p=Part('screen_pilaster_detail','巨幕侧柱_密集竖槽与金属冠饰','architecture',(0,0,0),'fluted_pilaster_details')
for side in (-1,1):
 for dx in (9.25,9.75,10.25): p.box((side*dx,-11.22,48.0),(.15,.20,38.8),GOLD,0)
 for zz in (30.0,67.5):
  for dx in (9.3,10.2): diamond(p,side*dx,-11.38,zz,.50,.90)
for x in [-11+i*2 for i in range(12)]:
 p.box((x,-9.5,69.55),(.95,.20,.23),GOLD2,3)
p.finish()
# Reference lower-base vertical slots, hard-edged ribs and genuine hanging braces.
p=Part('podium_refinement','底部悬挑_细柱托架与蓝金石板','architecture',(0,0,0),'hanging_podium_detail')
for side in (-1,1):
 for y,w,d in [(-13.94,8,6),(-3.5,7,5.6),(14.14,6,5.6)]:
  x=side*(25-(w+.12)/2)
  for dx in (-w*.15,w*.15):
   p.box((x+dx,y-d*.29-.035,4.3),(.62,.14,6.2),BLUE,2)
   for sx in (-1,1): p.box((x+dx+sx*.34,y-d*.29-.08,4.3),(.07,.14,6.7),GOLD,0)
  for dx in (-w*.29,w*.29):
   p.rod((x+dx,y+d*.23,5.5),(x+dx,y-d*.38,8.7),.16,GOLD,0)
  for dx in (-w*.33,0,w*.33): diamond(p,x+dx,y-d/2-.08,9.5,1.9,1.15)
p.finish()
# Tall staggered flutes and needle crown: pronounced tapered Art Deco silhouette.
p=Part('spire_fins','冠顶_高低错落金色飞扶壁尖针','support',(0,0,83),'spire_deco_fins')
for side in (-1,1):
 for yy,xx,z0,z1 in [(-4.0,3.8,81.8,88.4),(-2.2,4.8,80.5,86.8),(1,3.4,84.0,90.1)]:
  x=side*xx
  p.box((x,yy,(z0+z1)/2),(.48,.7,z1-z0),GOLD,0,.06)
  p.panel([(x-.23,z1-.8),(x-.23,z1),(x,z1+1.6),(x+.23,z1),(x+.23,z1-.8)],yy-.39,GOLD,0,.13)
  p.box((x,yy-.45,z0+1),(.10,.10,z1-z0-1),GOLD2,3)
for x in (-1.7,1.7):
 for yy in (-2,2): p.box((x,yy,91.2),(.24,.24,3.2),GOLD,0)
p.finish()
# Update all manifests after independent geometry changes.
bpy.context.view_layer.update()
for item in catalog:
 c=bpy.data.collections[item['collection']]; points=[o.matrix_world@v.co for o in c.objects if o.type=='MESH' for v in o.data.vertices]
 mn=[min(v[j] for v in points) for j in range(3)]; mx=[max(v[j] for v in points) for j in range(3)]
 item.update(version='v002',source_blend=str(BLEND.relative_to(R)),bounds_min=mn,bounds_max=mx,dimensions=[mx[j]-mn[j] for j in range(3)])
 directory=OUT/'component_packages'/item['category']/item['slug']; directory.mkdir(parents=True,exist_ok=True)
 (directory/'asset_manifest.json').write_text(json.dumps(item,ensure_ascii=False,indent=2),encoding='utf8')
plan=json.loads((OLD/'component_plan.json').read_text(encoding='utf8')); plan['source_version']='v002'; plan['source_status']='Blender源已完成'; plan['component_definitions']+=['side_facade_relief','fluted_pilaster_details','hanging_podium_detail','spire_deco_fins']
(OUT/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf8')
meta=json.loads((OLD/'catalog.json').read_text(encoding='utf8')); meta.update(source_version='v002',source_blend=str(BLEND.relative_to(R)),packages=catalog,package_count=len(catalog),source_status='Blender源已完成',review_notes='v002纠正深蓝/金色、底部微小越界、侧面竖向结构、冠顶尖针；保留v001')
(OUT/'catalog.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'component_packages/tree.txt').write_text('\n'.join(c['category']+'/'+c['slug']+' - '+c['display_name'] for c in catalog),encoding='utf8')
sc.view_settings.exposure=.35
sc.camera=bpy.data.objects['CAM_参考图全景']; sc.render.resolution_x=1400; sc.render.resolution_y=1800
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND)); print('SOURCE_SAVED',str(BLEND),flush=True)
try:
 prefs=bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type='OPTIX'; prefs.get_devices()
 for dev in prefs.devices: dev.use=dev.type!='CPU'
 if any(dev.use for dev in prefs.devices): sc.cycles.device='GPU'
except Exception: pass
cams=[('CAM_参考图全景','01_塔8_参考全景.png'),('CAM_正立面','02_塔8_正立面.png'),('CAM_花园入口近景','03_塔8_悬挑花园入口.png'),('CAM_冠顶巨幕近景','04_塔8_冠顶巨幕.png'),('CAM_俯视','05_塔8_俯视结构.png'),('CAM_背面','06_塔8_背面完整性.png')]
for name,filename in cams:
 cam=bpy.data.objects[name]; sc.camera=cam; sc.render.resolution_x=cam['resolution_x']; sc.render.resolution_y=cam['resolution_y']; sc.render.filepath=str(OUT/'previews'/filename)
 bpy.ops.render.render(write_still=True); print('RENDER_DONE',filename,flush=True)
print('TOWER08_V002_COMPLETE',flush=True)
