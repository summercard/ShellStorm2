"""Tower 8: 50m Art Deco landmark, editable palette-only Blender source.
No existing assets, runtime scenes or spreadsheets are modified.
"""
import bpy, math, random, json, shutil, ast, sys
from pathlib import Path
from collections import Counter
from mathutils import Vector
from mathutils.geometry import tessellate_polygon
R=Path(__file__).resolve().parents[2]
OUT=R/'assets/art/environments/open_world/source/tower_08/v001'
BLEND=OUT/'塔8_CITYLIVE空中花园地标_50m_v001.blend'
if BLEND.exists(): raise SystemExit('Existing source protected. Increment version before rebuilding.')
for d in ('previews','qa','references','component_packages'): (OUT/d).mkdir(parents=True,exist_ok=True)
(OUT.parent/'.gdignore').write_text('',encoding='utf8')
shutil.copy2('C:/Users/zhuangmenghong/.workbuddy/clipboard-images/clipboard-2026-09-30T10-52-46-545Z-41746afe.jpg',OUT/'references/塔8_用户参考.jpg')
ASSET='ENV-OPENWORLD-TOWER08'
random.seed(80930)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc=bpy.context.scene
sc.unit_settings.system='METRIC'; sc.unit_settings.scale_length=1
sc['asset_id']=ASSET; sc['building_id']='塔8'; sc['relationship']='peer_of_main_tower'
sc['version']='v001'; sc['block_id']='open_world'; sc['front_direction']='-Y'
sc['scope']='参考图阶梯塔楼、悬挑花园、巨幕、尖塔；源制作限定；非战斗房型'
palette_path=R/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
palette=bpy.data.images.load(str(palette_path)); palette.filepath=str(palette_path)
NAMES=['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']
MATS=[]
for i,n in enumerate(NAMES):
 m=bpy.data.materials.new(n); m.use_nodes=True; p=m.node_tree.nodes.get('Principled BSDF')
 p.inputs['Metallic'].default_value=[.82,.02,.16,0][i]
 p.inputs['Roughness'].default_value=[.28,.70,.16,.38][i]
 p.inputs['Coat Weight'].default_value=[.18,0,.65,0][i]
 uv=m.node_tree.nodes.new('ShaderNodeUVMap'); uv.uv_map='PaletteUV'
 tex=m.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=palette; tex.interpolation='Closest'
 m.node_tree.links.new(uv.outputs['UV'],tex.inputs['Vector']); m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
 if i==3:
  m.node_tree.links.new(tex.outputs['Color'],p.inputs['Emission Color']); p.inputs['Emission Strength'].default_value=1.25
 MATS.append(m)
CREAM=(9,7); LIGHT=(9,6); TILE=(9,5); TILE2=(9,4); DARK=(9,1); STEEL=(9,3)
GOLD=(8,3); GOLD2=(8,9); BLUE=(5,5); BLUE2=(3,5); BLUEHI=(6,5)
TEAL=(6,4); GREEN=(6,4); GREEN2=(7,4); BLACK=(9,0); RUST=(7,2)
# Reuse the proven explicit geometry / editable UV-island implementation only.
tree=ast.parse((R/'tools/blender/build_skyline_08_source_v003.py').read_text(encoding='utf8'))
for node in tree.body:
 if isinstance(node,(ast.FunctionDef,ast.ClassDef)) and node.name in ['coll','uv_mesh','Part','rail']:
  code=ast.unparse(node).replace('skyline_08/','tower_08/').replace("'v003'","'v001'").replace('1F–8F＋天台','装饰退台地标；不定义战斗楼层')
  exec(compile(code,'<shared_palette_geometry>','exec'))
def bolts(p,points,axis=(0,-1,0),r=.06,c=None):
 for pos in points: p.rod(pos,tuple(Vector(pos)+Vector(axis)*.06),r,c or GOLD,0,6)
root=coll('塔8_CITYLIVE空中花园地标_中文资产管理',sc.collection)
src=coll('01_制作组件_按独立资产包',root); src.hide_render=True; src.hide_viewport=True
# The top-level output collection is the stable whole-building export boundary.
game=coll('02_游戏输出_独立资产包_v001',root)
display=coll('90_展示与验收_固定灯光相机',root)
categories=[('architecture','01_建筑结构'),('facilities','02_入口与固定附属设施'),('signage','03_CITYLIVE巨幕与冠徽'),('garden','04_退台花园与栏杆'),('support','05_尖塔与灯带')]
CATS={k:coll(n,game) for k,n in categories}; SCATS={k:coll(n+'_制作源',src) for k,n in categories}
# Column,row from top. No R9/R10 white-gray surfaces, including typography.
CREAM=(9,7); LIGHT=(9,6); TILE=(9,5); TILE2=(9,4); DARK=(9,1); STEEL=(9,3)
GOLD=(8,3); GOLD2=(8,9); BLUE=(5,5); BLUE2=(3,5); BLUEHI=(6,5)
TEAL=(6,4); GREEN=(6,4); GREEN2=(7,4); BLACK=(9,0); RUST=(7,2)
PINK=(6,7); PURPLE=(5,6); ORANGE=(7,2); RED=(5,7)
catalog=[]
plan=dict(asset_id=ASSET,building_id='塔8',category='关卡场景/开放世界建筑塔',relationship='peer_of_main_tower',source_version='v001',dimensions_m=[50,34,96],width_definition='最外侧实体悬挑结构X=-25至25；无整体缩放',front_direction='-Y',local_origin=[0,0,0],scale_basis='用户给定50m宽；深34m和高96m依据单张参考图推定，不是测绘尺寸',visible_facts=['阶梯退台轮廓','底部悬挑花园及三角托架','双侧竖向蓝色立面','金属压边与细线菱形纹','正面CITY LIVE巨幅竖屏','顶部冠徽及收束尖塔','退台绿化'],inferred=['完整背面和右侧使用同族Art Deco构造','底部最低点落地Z=0；不制作参考图云海','无内部楼层、战斗碰撞、导航或运行时接入'],color_policy='公共色盘；墙面R8C10，墙面细节R7C10；禁止R9C10/R10C10及纯白；4共享材质角色',locked='全部已有资产、公共色盘、运行时和资产账本不修改',component_definitions=['stepped_core','fluted_wing','cantilever_garden','terrace_rail','garden_plant_cluster','entry_portal','screen_housing','screen_geometry_graphic','crown_badge','spire'],source_status='planned',runtime_status='not_exported')
(OUT/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf8')
print('CONTRACT_FROZEN',flush=True)
if '--contract-only' in sys.argv: raise SystemExit(0)

# Helpers: all ornaments are explicit editable solids, not baked textures.
def crown(p,x,y,z,w,h,c=GOLD2,m=0):
 p.panel([(x-w*.5,z+h),(x-w*.26,z+h*.48),(x,z+h*1.22),(x+w*.25,z+h*.48),(x+w*.5,z+h),(x+w*.36,z+.22*h),(x-w*.36,z+.22*h)],y,c,m,.075)
 p.box((x,y,z+.07*h),(w*.76,.12,.12*h),c,m)
def diamond(p,x,y,z,w,h):
 p.path([(x,y,z-h/2),(x+w/2,y,z),(x,y,z+h/2),(x-w/2,y,z),(x,y,z-h/2)],.035,GOLD,0,6)
def trimbox(p,x,y,z,w,d,h):
 p.box((x,y,z),(w,d,h),CREAM,1,.16)
 for zz in (z-h/2+.10,z+h/2-.10): p.box((x,y,zz),(w+.12,d+.12,.14),GOLD,0,.04)
def foliage(p,x,y,z,height=2.8,conifer=False):
 p.rod((x,y,z),(x,y,z+height*.64),.075,RUST,1,6)
 if conifer:
  for k in range(3):
   zz=z+height*(.18+.20*k); rr=height*(.19-.045*k)
   n=7; vv=[(x+rr*math.cos(j*math.tau/n),y+rr*math.sin(j*math.tau/n),zz) for j in range(n)]+[(x,y,zz+height*.48)]
   p.poly(vv,[tuple(reversed(range(n)))]+[(j,(j+1)%n,n) for j in range(n)],GREEN if k%2 else GREEN2,1)
 else:
  for dx,dy,dz,r in [(0,0,.66,.25),(-.16,0,.59,.23),(.15,.08,.66,.22),(0,-.10,.88,.18)]:
   cx=x+dx*height; cy=y+dy*height; cz=z+dz*height; rr=r*height
   vv=[(cx,cy,cz+rr),(cx,cy,cz-rr)]+[(cx+rr*math.cos(j*math.tau/7),cy+rr*math.sin(j*math.tau/7),cz) for j in range(7)]
   p.poly(vv,[(0,2+j,2+(j+1)%7) for j in range(7)]+[(1,2+(j+1)%7,2+j) for j in range(7)],GREEN if dx else GREEN2,1)
def garden(slug,x,y,z,w,d,under=False):
 p=Part(slug,'退台花园_'+slug,'garden',(x,y,z),'cantilever_garden')
 trimbox(p,x,y,z-.9,w,d,1.8)
 p.box((x,y,z+.04),(w-.28,d-.28,.12),TILE,1,.12)
 # Front and both sides remain distinct railing edges; back hosts architecture.
 for a,b in [((x-w/2+.24,y-d/2+.24),(x+w/2-.24,y-d/2+.24)),((x-w/2+.24,y-d/2+.24),(x-w/2+.24,y+d/2-.24)),((x+w/2-.24,y-d/2+.24),(x+w/2-.24,y+d/2-.24))]: rail(p,a,b,z+.12)
 for xx in [x-w*.30,x,x+w*.30]:
  p.box((xx,y,z+.30),(min(1.9,w*.23),min(d*.45,1.4),.48),CREAM,1,.10)
  foliage(p,xx,y,z+.55,random.uniform(1.6,2.8),xx==x)
 for xx in [x-w*.34,x+w*.34]:
  if under:
   p.box((xx,y+.2,z-2.25),(.55,d*.82,1),GOLD,0,.06)
   p.rod((xx,y+d*.32,z-4.1),(xx,y-d*.39,z-1.8),.22,GOLD,0,8)
   p.rod((xx,y+d*.32,z-4.1),(xx,y+d*.32,z-1.8),.18,GOLD,0,8)
  diamond(p,xx,y-d/2-.04,z-.84,min(1.6,w*.24),1.0)
 p.finish()

# Central inhabited-looking volume: stepped setbacks, full back and side facades.
for i,(w,d,z0,z1) in enumerate([(36,25,0,12),(30,23,12,28),(27,21,28,69),(23,18,69,77),(18,15,77,83),(11,11,83,89)]):
 p=Part('core_%02d'%i,'中央塔身_退台_%02d'%i,'architecture',(0,0,z0),'stepped_core')
 p.box((0,0,(z0+z1)/2),(w,d,z1-z0),CREAM,1,.22)
 for zz in (z0+.22,z1-.35):
  trimbox(p,0,0,zz,w+.55,d+.55,.55)
 for yy in (-d/2-.06,d/2+.06):
  # Giant screen replaces front central windows, not the other three facades.
  for xx in [(-w/2+1.1)+j*(w-2.2)/max(1,round(w/3.6)) for j in range(round(w/3.6)+1)]:
   p.box((xx,yy,(z0+z1)/2),(.18,.19,z1-z0-.9),GOLD,0)
  if i!=2:
   for xx in [(-w/2+2.5)+j*4.2 for j in range(max(1,int((w-2)/4.2)))]:
    p.box((xx,yy*1.005,(z0+z1)/2),(2.5,.11,z1-z0-1.2),BLUE,2)
  elif yy>0:
   for xx in [-10.3,-6.9,-3.45,0,3.45,6.9,10.3]:
    p.box((xx,yy+.03,48.5),(2.8,.10,39.4),BLUE,2)
    for zz in range(31,69,4): p.box((xx,yy+.10,zz),(2.8,.1,.08),GOLD,0)
 for xx in (-w/2-.06,w/2+.06):
  for yy in [-d/2+2+j*3.4 for j in range(max(1,int(d/3.4)))]:
   p.box((xx,yy,(z0+z1)/2),(.10,2.3,z1-z0-1.2),BLUE,2)
   p.box((xx*1.005,yy-1.3,(z0+z1)/2),(.15,.13,z1-z0-.7),GOLD,0)
  for zz in [z0+2+j*4 for j in range(max(1,int((z1-z0)/4)))]: p.box((xx,0,zz),(.17,d-.7,.10),GOLD,0)
 p.finish()

# Unequal-height paired buttresses form the reference's stepped silhouette.
for level,(cx,w,d,z0,z1) in enumerate([(19.0,5.2,15,1.1,25),(16.1,5.0,18,12,49),(12.1,4.8,21,25,70),(8.8,3.6,16,69,77)]):
 for side in (-1,1):
  x=side*cx; y=-.5
  p=Part('wing_%d_%d'%(level,side),'侧翼_%d_%s_凹槽竖向立面'%(level,'左' if side<0 else '右'),'architecture',(x,y,z0),'fluted_wing')
  p.box((x,y,(z0+z1)/2),(w,d,z1-z0),CREAM,1,.22)
  for yy in (y-d/2-.14,y+d/2+.14):
   p.box((x,yy,(z0+z1)/2),(w*.57,.18,z1-z0-1.6),BLUE,2)
   for dx in [-w*.43,-w*.32,w*.32,w*.43]:
    p.box((x+dx,yy-.05,(z0+z1)/2),(.10,.20,z1-z0-1.2),GOLD,0)
   for zz in (z0+.8,z1-.8): p.box((x,yy-.06,zz),(w*.74,.20,.12),GOLD,0)
   if level<2: crown(p,x,yy-.20,z0+(z1-z0)*.52,w*.40,w*.35)
   # Stone panel joints keep large masonry masses articulated.
   for zz in [z0+2.3+j*3.9 for j in range(int((z1-z0)/3.9))]:
    for dx in [-w*.44,w*.44]: p.box((x+dx,yy+.03,zz),(w*.13,.025,.025),TILE,1)
  trimbox(p,x,y,z1-.25,w+.7,d+.5,.64)
  p.finish()
  garden('wing_%d_%d_roof'%(level,side),x,y-d/2+1.0,z1+.08,w+.75,2.6)

# Massive hanging podium balconies: maximum X width exactly 50m.
for side in (-1,1):
 for j,(y,z,w,d) in enumerate([(-13.94,10.3,8.0,6.0),(-3.5,10.3,7.0,5.6),(14.14,10.3,6.0,5.6)]):
  x=side*(25-(w+.12)/2)
  garden('podium_%d_%d'%(side,j),x,y,z,w,d,True)
  p=Part('podium_foot_%d_%d'%(side,j),'悬挑底部_%d_%d_石墩和支座'%(side,j),'architecture',(x,y,0),'fluted_wing')
  p.box((x,y+1.0,4.25),(w*.52,d*.56,8.5),CREAM,1,.18)
  p.box((x,y+1.0,.24),(w*.40,d*.50,.48),GOLD,0,.12)
  for dx in (-w*.19,w*.19): p.box((x+dx,y-d*.29,4.5),(.20,.28,6.8),GOLD,0)
  p.finish()
for side in (-1,1):
 garden('entry_flank_%d'%side,side*10.5,-13.0,11.8,10.0,6.0,True)
 garden('upper_entry_%d'%side,side*6.3,-11.6,26.5,5.4,4.2)
 garden('upper_crown_%d'%side,side*8.8,-7.0,77.5,5.2,3.4)
# Narrow front cornice and garden gallery under the great screen.
garden('screen_lower_gallery',0,-10.2,28,15.8,2.0)
garden('upper_left_shoulder',-6.2,3,83.4,5,3.6)
garden('upper_right_shoulder',6.2,3,83.4,5,3.6)

# Entry: tall gilded portals, glass panes, pilasters and a separate upper arch-window.
p=Part('entry_portal','主入口_金色门框与蓝玻璃门','facilities',(0,-12.7,0),'entry_portal')
p.box((0,-12.66,4.4),(7.3,.55,8.8),DARK,1,.12)
for x in (-3.3,3.3): trimbox(p,x,-13.02,4.7,.62,.64,9.4)
for z in (.3,8.4,9.2): p.box((0,-13.0,z),(7.8,.64,.35),GOLD,0,.06)
for x in (-1.52,1.52):
 p.box((x,-13.05,4.2),(2.8,.10,7.8),BLUEHI,2)
 for zz in (1.3,4.2,7.3): p.box((x,-13.17,zz),(2.85,.12,.12),GOLD,0)
 for xx in (x-1.4,x+1.4): p.box((xx,-13.17,4.2),(.13,.12,7.9),GOLD,0)
 p.box((x*.11,-13.28,3.9),(.11,.15,.8),GOLD2,0)
p.box((0,-13.05,10.0),(10.1,1.4,.8),CREAM,1,.14)
diamond(p,0,-13.78,10.0,1.6,.5)
# The reference's vertical lit window above the entrance.
p.box((0,-11.9,18.7),(5.6,.65,12.8),BLUE,2,.12)
arch=[(-2.0,13.1),(-2.0,23.3),(0,24.7),(2.0,23.3),(2.0,13.1)]
p.panel(arch,-12.3,GOLD2,2,.10)
p.path([(x,-12.46,z) for x,z in arch+[arch[0]]],.12,GOLD,0)
for x in (-.7,.7): p.box((x,-12.47,18.7),(.1,.10,10.8),GOLD,0)
for z in (14,16,18,20,22): p.box((0,-12.47,z),(3.9,.10,.11),GOLD,0)
p.finish()

# Giant screen housing: inset substrate, layered gold frame, panel bolts, lamps.
SY=-11.70; SZ0=29.1; SZ1=67.8; SW=16.2
p=Part('citylive_housing','CITYLIVE巨幕_金边框及检修灯','signage',(0,SY,SZ0),'screen_housing')
p.box((0,SY+.16,(SZ0+SZ1)/2),(SW+1.0,.62,SZ1-SZ0+1.3),DARK,0,.18)
for x in (-SW/2-.27,SW/2+.27):
 p.box((x,SY-.27,(SZ0+SZ1)/2),(.34,.55,SZ1-SZ0+.75),GOLD,0,.06)
 p.box((x+(-.26 if x<0 else .26),SY-.12,(SZ0+SZ1)/2),(.10,.45,SZ1-SZ0+1.0),GOLD2,0)
 for z in [SZ0+j*1.8 for j in range(22)]: p.rod((x,SY-.56,z),(x,SY-.64,z),.065,GOLD2,0,6)
for z in (SZ0-.35,SZ1+.35):
 p.box((0,SY-.26,z),(SW+1.1,.65,.46),GOLD,0,.06)
 for j in range(10):
  x=-7.55+j*1.68; p.box((x,SY-.57,z+.02),(.62,.18,.19),GOLD2,3)
p.finish()
# Poster recreated as palette-colored vector geometry; no private billboard texture.
p=Part('citylive_graphic','CITYLIVE巨幕_城市落日矢量几何画面','signage',(0,SY,SZ0),'screen_geometry_graphic')
y=SY-.25
p.box((0,y,(SZ0+SZ1)/2),(SW,.035,SZ1-SZ0),BLUE2,3)
# Diagonal bands, graphic poster composition from the reference.
p.panel([(-8.08,47.3),(8.08,56.0),(8.08,60.5),(-8.08,52.2)],y-.04,RED,3,.018)
p.panel([(-8.08,42.7),(8.08,47.3),(8.08,54.5),(-8.08,48.0)],y-.063,ORANGE,3,.018)
p.panel([(-8.08,29.15),(8.08,29.15),(8.08,39.0),(-8.08,33.0)],y-.045,PINK,3,.018)
# Solar disk sits in lower poster half; 96 sided geometric outline.
sunx=-.8; sunz=42.1; rr=6.8
p.panel([(sunx+rr*math.cos(j*math.tau/96),sunz+rr*math.sin(j*math.tau/96)) for j in range(96)],y-.075,GOLD2,3,.012)
for j in range(7):
 zz=38.0+j*1.05; half=math.sqrt(max(0,rr*rr-(zz-sunz)**2))
 p.box((sunx,y-.096,zz),(half*2,.013,.15),ORANGE,3)
# Layered skyline silhouettes, spires and small cyan/magenta window lights.
for layer in range(2):
 for j in range(19):
  x=-7.7+j*.83; base=30.5+layer*.75; h=random.uniform(3.2,9.5)
  if j in (8,14): h=12.5 if j==14 else 11
  w=.55 if j%3 else .80; yy=y-.14-layer*.045
  p.box((x,yy,base+h/2),(w,.026,h),BLUE if layer==0 else PURPLE,3)
  if j in (8,14):
   p.box((x,yy,base+h+.35),(w*.6,.027,.7),BLUEHI,3)
   p.rod((x,yy,base+h+.6),(x,yy,base+h+2),.03,BLUEHI,3,4)
  p.box((x-w*.38,yy-.018,base+h/2),(.07,.016,h),BLUEHI if layer==0 else PINK,3)
  for k in range(int(h/.5)):
   if random.random()<.65: p.box((x+.08,yy-.025,base+.25+k*.5),(.07,.013,.16),BLUEHI,3)
# Bridge sweep across the poster, with distinct rails and piers.
pts=[(-8.0,36.8),(-5.3,36.1),(-2.6,35.1),(0,34.1),(3.0,33.1),(5.8,31.7),(8.0,30.5)]
p.path([(x,y-.30,z) for x,z in pts],.16,BLUE2,3,6)
p.path([(x,y-.32,z+.55) for x,z in pts],.065,BLUEHI,3,6)
for x,z in pts[1:-1]:
 p.rod((x,y-.31,29.2),(x,y-.31,z),.12,BLUE2,3,4)
for j in range(45):
 x=random.uniform(-7.7,7.7); z=random.uniform(29.4,33.8)
 p.box((x,y-.22,z),(.10,.014,.10),PINK if j%2 else BLUEHI,3)
# Crown and sparse stars leave clean readable text.
crown(p,0,y-.20,62.5,4.8,2.6,GOLD2,3)
for x,z in [(-5.7,63.1),(6.3,60.9),(-6.5,56.3),(5.8,65.8)]:
 p.box((x,y-.20,z),(.12,.02,.63),BLUEHI,3); p.box((x,y-.20,z),(.57,.02,.12),BLUEHI,3)
p.finish()

font=bpy.data.fonts.load('C:/Windows/Fonts/ariblk.ttf')
def text_package(slug,body,z,width,height,color):
 cu=bpy.data.curves.new('可编辑字体_'+body,'FONT'); cu.body=body; cu.font=font; cu.size=1; cu.resolution_u=6; cu.extrude=.015
 ob=bpy.data.objects.new('字体制作源_'+body,cu); SCATS['signage'].objects.link(ob)
 # Evaluate dimensions with hidden collection temporarily revealed.
 src.hide_viewport=False; bpy.context.view_layer.update()
 dims=ob.dimensions.copy(); ob.scale=(width/dims.x,height/dims.y,1)
 ob.rotation_euler=(math.pi/2,0,0); ob.location=(-width/2,SY-.67,z)
 bpy.context.view_layer.update()
 ev=ob.evaluated_get(bpy.context.evaluated_depsgraph_get()); mesh=bpy.data.meshes.new_from_object(ev)
 p=Part(slug,'巨幕文字_'+body,'signage',(0,SY,z),'screen_geometry_graphic')
 for face in mesh.polygons:
  p.poly([tuple(ob.matrix_world@mesh.vertices[j].co) for j in face.vertices],[tuple(range(len(face.vertices)))],color,3)
 p.finish(); bpy.data.meshes.remove(mesh); src.hide_viewport=True
 ob['purpose']='可编辑字体曲线源；输出网格采用PaletteUV'
text_package('word_city','CITY',55.1,13.5,5.5,CREAM)
text_package('word_live','LIVE',48.6,13.5,5.7,GOLD2)
# Upper crown emblem, centered on a blue heraldic inset.
p=Part('crown_badge','顶部冠徽_金色王冠和蓝色壁龛','signage',(0,-9.5,69),'crown_badge')
p.box((0,-9.3,73.6),(8.7,.46,6.4),GOLD,0,.12)
p.box((0,-9.57,73.6),(7.9,.07,5.7),BLUE,2,.04)
crown(p,0,-9.68,72.0,4.5,2.2)
for z in (70.5,76.7):
 for x in [-4+j*.8 for j in range(11)]: diamond(p,x,-9.66,z,.36,.25)
p.finish()
# Pinnacle: a genuine shrinking articulated tower, not one stretched primitive.
p=Part('spire','顶部尖塔_退台冠顶与避雷针','support',(0,0,83),'spire')
for k,(w,d,z0,z1) in enumerate([(7,7,87,90),(4.5,4.5,90,92),(2.4,2.4,92,93.5)]):
 p.box((0,0,(z0+z1)/2),(w,d,z1-z0),BLUE,2,.10)
 trimbox(p,0,0,z0+.12,w+.4,d+.4,.28)
 for x in (-w/2,w/2):
  for yy in (-d/2,d/2): p.box((x,yy,(z0+z1)/2),(.23,.23,z1-z0+.15),GOLD,0)
for x in (-4.4,-2.9,2.9,4.4):
 h=2.1 if abs(x)>4 else 4.2
 p.box((x,-4.4,86+h/2),(.25,.36,h),GOLD,0)
 p.rod((x,-4.4,86+h),(x,-4.4,87+h),.10,GOLD2,0,6)
p.rod((0,0,93.3),(0,0,95.85),.09,GOLD,0,12)
p.rod((0,0,95.75),(0,0,96),.06,GOLD2,3,12)
p.finish()
print('GEOMETRY_COMPLETE',len(catalog),flush=True)
meta=dict(plan); meta.update(source_status='Blender源已完成',runtime_status='未导出；未接入',source_blend=str(BLEND.relative_to(R)),packages=catalog,package_count=len(catalog),shared_palette=str(palette_path.relative_to(R)),unit='meter',collision_status='none_visual_only',ledger_status='未写入分账本；源清单登记')
(OUT/'catalog.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'component_packages/tree.txt').write_text('\n'.join(c['category']+'/'+c['slug']+' - '+c['display_name'] for c in catalog),encoding='utf8')
sc.render.engine='CYCLES'; sc.cycles.samples=32; sc.cycles.use_denoising=True
sc.render.image_settings.file_format='PNG'; sc.render.film_transparent=False
sc.view_settings.view_transform='AgX'; sc.view_settings.look='AgX - Medium High Contrast'; sc.view_settings.exposure=.55
world=bpy.data.worlds.new('蓝天展示环境_不导出'); sc.world=world; world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.46,.55,.70,1); world.node_tree.nodes['Background'].inputs[1].default_value=.8
bg=world.node_tree.nodes.new('ShaderNodeBackground'); bg.inputs[0].default_value=(.065,.30,.58,1); bg.inputs[1].default_value=.65
lp=world.node_tree.nodes.new('ShaderNodeLightPath'); mix=world.node_tree.nodes.new('ShaderNodeMixShader')
world.node_tree.links.new(lp.outputs['Is Camera Ray'],mix.inputs[0]); world.node_tree.links.new(world.node_tree.nodes['Background'].outputs[0],mix.inputs[1]); world.node_tree.links.new(bg.outputs[0],mix.inputs[2]); world.node_tree.links.new(mix.outputs[0],world.node_tree.nodes['World Output'].inputs['Surface'])
def light(n,kind,pos,power,color,size=40):
 data=bpy.data.lights.new(n,kind); data.energy=power; data.color=color
 ob=bpy.data.objects.new(n,data); display.objects.link(ob); ob.location=pos; ob.rotation_euler=(Vector((0,0,43))-Vector(pos)).to_track_quat('-Z','Y').to_euler()
 if kind=='AREA': data.shape='DISK'; data.size=size
 if kind=='SUN': data.angle=.12
light('KEY_暖色太阳','SUN',(-65,-100,155),3.0,(1,.87,.68))
light('FILL_正面软光','AREA',(25,-65,80),12000,(.67,.82,1),55)
light('RIM_金属边缘光','AREA',(30,40,120),18000,(1,.85,.62),45)
def camera(n,pos,target,scale,res):
 data=bpy.data.cameras.new(n); data.type='ORTHO'; data.ortho_scale=scale; data.clip_end=1000
 ob=bpy.data.objects.new(n,data); display.objects.link(ob); ob.location=pos; ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
 ob['resolution_x']=res[0]; ob['resolution_y']=res[1]; return ob
cameras=[
(camera('CAM_参考图全景',(-105,-200,96),(0,0,46),108,(1400,1800)),'01_塔8_参考全景.png'),
(camera('CAM_正立面',(0,-200,47),(0,0,47),106,(1200,1700)),'02_塔8_正立面.png'),
(camera('CAM_花园入口近景',(-60,-110,36),(0,-5,17),55,(1500,1100)),'03_塔8_悬挑花园入口.png'),
(camera('CAM_冠顶巨幕近景',(-48,-95,81),(0,-3,70),49,(1300,1500)),'04_塔8_冠顶巨幕.png'),
(camera('CAM_俯视',(0,-.001,190),(0,0,25),59,(1400,1100)),'05_塔8_俯视结构.png'),
(camera('CAM_背面',(95,155,88),(0,0,45),109,(1200,1600)),'06_塔8_背面完整性.png')]
sc.camera=cameras[0][0]; sc.render.resolution_x=1400; sc.render.resolution_y=1800; sc.render.resolution_percentage=100
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':
   area.spaces.active.region_3d.view_perspective='CAMERA'; area.spaces.active.shading.type='MATERIAL'; area.spaces.active.clip_end=1000
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND)); print('SOURCE_SAVED',str(BLEND),flush=True)
try:
 prefs=bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type='OPTIX'; prefs.get_devices()
 gpu=False
 for device in prefs.devices: device.use=device.type!='CPU'; gpu=gpu or device.use
 if gpu: sc.cycles.device='GPU'
 print('GPU',gpu,flush=True)
except Exception as e: print('CPU_FALLBACK',e,flush=True)
for cam,filename in cameras:
 sc.camera=cam; sc.render.resolution_x=cam['resolution_x']; sc.render.resolution_y=cam['resolution_y']; sc.render.filepath=str(OUT/'previews'/filename)
 bpy.ops.render.render(write_still=True); print('RENDER_DONE',filename,flush=True)
print('TOWER08_SOURCE_RENDERED',flush=True)
