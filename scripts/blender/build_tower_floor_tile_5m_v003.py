"""5米工业拼接地砖 v003 —— 反共面修复版。Run in Blender background from project root.

v002 的两个几何缺陷（2026-09-22 实测：Blender headless 按连通分量还原零件 + 共面扫描）：

1. 共面抖动（用户报的"闪面"）
   《哑光面板 / 角部紧固座 / 紧固槽 / 检修盖板》四个家族的顶面全部落在同一平面
   z=+0.1500，而它们的 XY 互相重叠 ⇒ 最严重处 0.324 m²（正是检修盖板整片）深度打平，
   像素级 z-fighting，相机一动就闪。用户截图圈的就是这块。
2. 盖框隐形（顺带查出）
   《检修盖框》顶面 z=+0.1480 比面板低 2mm，整件落在面板实体内部 ⇒ 金属盖框在任何
   角度都不可能被看到，资产上只剩"盖板在闪"的鬼影。设计意图（金属包边 + 暖色警示短标
   + 专用检修盖近景相机）说明它本该可见。

v003 修法：只改 z 高度，不改 XY、材质、PaletteUV、三角面拓扑口径与碰撞契约。

  反共面规则：任何两个在 XY 上投影重叠的可见面，平面高度差必须 >= 0.0020 m。
  锚点不动：《哑光面板》顶面 = +0.1500。运行时 TowerFloorStage3D._build_floor() 对
  98F / 远征走 `floor_visual_y = -FLOOR_THICKNESS * 0.5 = -0.15` 的固定偏移，行走面因此
  落在世界 Y=0。锚点一动，整层地砖就会整体抬降。
  阶梯（顶面 z，自下而上）：
    承重底板 0.0800（不变） → 金属压边 0.1480（不变） → 哑光面板 0.1500（锚点，不变）
    → 检修盖框 / 角部紧固座 / 检修警示短标 0.1520（+2.0）
    → 紧固槽 / 检修盖板格栅条 0.1540（再 +2.0）
  检修盖板同时由"一整块盖板 + 5 条凸起细槽"改为"格栅条 + 5 道通透细槽"：
  细槽改负空间后，槽底露出的正是低 2mm 的金属盖框，层级天生分离，不必再往盖板上
  叠第四层凸起。槽的足迹与 v002 完全一致（28x260mm x 5），只是从"凸起"变成"凹槽"。
"""
import bpy, math, json, hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/art/environments/tower_descent_3d'
SRC=OUT/'source/floor_tile_5m'
COMP=OUT/'components/floor_tile_5m'
PRE=ROOT/'outputs/verification/floor_tile_5m'
for p in (SRC,COMP,PRE):p.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
# 本机 Blender 偏好开着「翻译新数据名」，自动生成的节点名会被译成中文
# （原理化 BSDF / 背景），任何按英文名取节点的写法都会拿到 None。这里显式关掉；
# 下面取节点一律按 node.type，不再依赖名字。
bpy.context.preferences.view.use_translate_new_dataname=False
scene=bpy.context.scene
scene.unit_settings.system='METRIC'
source=bpy.data.collections.new('01_制作组件_已统一材质');scene.collection.children.link(source)
game=bpy.data.collections.new('02_游戏输出_独立资产包_v003');scene.collection.children.link(game)
package=bpy.data.collections.new('地面系统_5米工业地砖_资产包');game.children.link(package)
preview=bpy.data.collections.new('90_展示与验收_灯光相机');scene.collection.children.link(preview)
palette_path=ROOT/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
image=bpy.data.images.load(str(palette_path),check_existing=True)
def mat(name,metal,rough):
 m=bpy.data.materials.new(name);m.use_nodes=True
 n=m.node_tree.nodes
 bs=next(x for x in n if x.type=='BSDF_PRINCIPLED')
 bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
 uv=n.new('ShaderNodeUVMap');uv.uv_map='PaletteUV'
 t=n.new('ShaderNodeTexImage');t.image=image;t.interpolation='Closest'
 m.node_tree.links.new(uv.outputs['UV'],t.inputs['Vector']);m.node_tree.links.new(t.outputs['Color'],bs.inputs['Base Color'])
 return m
metal=mat('01_精工金属_紫色骨架',.82,.30)
paint=mat('02_细腻哑光_青绿大面',.03,.72)
parts=[]
faces=[]   # (name, flat_x0, flat_x1, flat_y0, flat_y1, top_z) —— 反共面自检用
def uv_assign(o,cell):
 mesh=o.data
 for uv in list(mesh.uv_layers):mesh.uv_layers.remove(uv)
 layer=mesh.uv_layers.new(name='PaletteUV');mesh.uv_layers.active=layer;layer.active_render=True
 col,row=cell;u=(col+.5)/10;v=1-(row+.5)/10
 for poly in mesh.polygons:
  count=len(poly.loop_indices)
  for i,idx in enumerate(poly.loop_indices):
   ang=2*math.pi*i/count
   layer.data[idx].uv=(u+.026*math.cos(ang),v+.026*math.sin(ang))
def box(name,loc,size,material,cell,bevel=0):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
 o=bpy.context.object;o.name=name;o.dimensions=size
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 for c in list(o.users_collection):c.objects.unlink(o)
 source.objects.link(o)
 if bevel:
  mod=o.modifiers.new('可编辑倒角','BEVEL');mod.width=bevel;mod.segments=1
  bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
 o.data.materials.append(material);uv_assign(o,cell);parts.append(o)
 # 倒角只削边、不改包围盒，但会把**平顶**四周内缩一个倒角宽 —— 自检按平顶算。
 fx=size[0]/2-bevel;fy=size[1]/2-bevel
 faces.append((name,loc[0]-fx,loc[0]+fx,loc[1]-fy,loc[1]+fy,loc[2]+size[2]/2))
 return o
# ---- 反共面阶梯常量 -------------------------------------------------------
PLATE_TOP=.1500   # 行走面锚点：禁止改动（运行时固定 -0.15 偏移）
CLEAR=.0020       # 两个 XY 重叠可见面之间的最小高度差
L_MID=PLATE_TOP+CLEAR            # 0.1520 盖框 / 紧固座 / 警示短标
L_TOP=PLATE_TOP+CLEAR*2          # 0.1540 紧固槽 / 盖板格栅条
def cz(top,thick):return top-thick/2
# Existing centered floor contract: exact 5x5x0.30m; runtime drops by .15m.
base=box('承重底板_接口锁定',(0,0,-.035),(5,5,.23),paint,(9,1))
for x in (-1.20,1.20):
 for y in (-1.20,1.20):
  box('哑光面板_独立压边',(x,y,.105),(2.35,2.35,.09),paint,(9,4),.018)
for x in (-2.43,2.43):box('纵向金属压边',(x,0,.118),(.09,4.86,.06),metal,(9,3),.008)
for y in (-2.43,2.43):box('横向金属压边',(0,y,.118),(4.78,.09,.06),metal,(9,3),.008)
# 角部紧固座：顶面 v002=+0.1500（与面板共面）→ v003=+0.1520（高出面板 2mm）。
for x in (-2.32,2.32):
 for y in (-2.32,2.32):
  box('角部紧固座',(x,y,cz(L_MID,.032)),(.14,.14,.032),metal,(9,6),.012)
  # 紧固槽：座上刻线，贯穿座顶到槽顶 2mm，槽底埋进座体 1mm。
  box('紧固槽',(x,y,cz(L_TOP,.030)),(.082,.022,.030),paint,(9,1))
# 检修口：盖框整体抬高到 +0.1520。v002 的 +0.1480 让它完全埋在面板内部（隐形）。
box('检修盖框',(1.56,-1.56,cz(L_MID,.022)),(.83,.61,.022),metal,(9,2),.018)
# 盖板拆成格栅：中间 5 道 28x260mm 通透细槽（槽底=盖框顶面，低 2mm），
# 槽与槽之间是格栅条，两端各一块满宽端条。槽足迹与 v002 的《检修散热细槽》一致。
GRATE_Y=-1.56
for cx,cw in ((1.2705,.111),(1.395,.082),(1.505,.082),(1.615,.082),(1.725,.082),(1.8495,.111)):
 box('检修盖板格栅条',(cx,GRATE_Y,cz(L_TOP,.006)),(cw,.26,.006),paint,(9,3))
for cy in (-1.7425,-1.3775):
 box('检修盖板端条',(1.56,cy,cz(L_TOP,.006)),(.69,.105,.006),paint,(9,3))
# 暖色识别短标：顶面 v002=+0.1505（凸出 0.5mm）→ v003=+0.1520。
box('检修警示短标',(1.56,-1.94,cz(L_MID,.024)),(.42,.038,.024),paint,(3,5))
# ---- 反共面自检（在 join 之前、用平顶足迹做保守判据） ----------------------
violations=[]
for i in range(len(faces)):
 for j in range(i+1,len(faces)):
  a,b=faces[i],faces[j]
  if min(a[2],b[2])-max(a[1],b[1])<=1e-5:continue     # 平顶 XY 不重叠 → 无共面风险
  if min(a[4],b[4])-max(a[3],b[3])<=1e-5:continue
  if abs(a[5]-b[5])<CLEAR-1e-9:
   violations.append((a[0],b[0],round(a[5],4),round(b[5],4)))
print('COPLANAR_SELFCHECK parts=%d pairs=%d %s'%(len(faces),len(violations),'PASS' if not violations else 'FAIL'))
for v in violations:print('   VIOLATION',v)
assert not violations,'v003 反共面自检未通过：同高度且 XY 重叠'
# Bake source transforms into ONE mesh, shared by batched MultiMesh surfaces.
bpy.ops.object.select_all(action='DESELECT')
clones=[]
for o in parts:
 c=o.copy();c.data=o.data.copy();package.objects.link(c);c.select_set(True);clones.append(c)
bpy.context.view_layer.objects.active=clones[0];bpy.ops.object.join()
merged=bpy.context.object;merged.name='FloorTile_5m'
bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
# Slot consolidation through bmesh join preserves PaletteUV and material roles.
merged['asset_id']='ENV-TOWER-FLOOR-TILE-5M';merged['version']='v003'
merged['collision_contract']='5x5x0.30m centered, supplied by Godot wrapper'
merged['anti_coplanar_rule']='XY-overlapping visible faces differ in plane height by >= 0.0020 m'
source.hide_render=True;source.hide_viewport=True
bpy.ops.object.select_all(action='DESELECT');merged.select_set(True);bpy.context.view_layer.objects.active=merged
blend=SRC/'env_tower_floor_tile_5m_source_v003.blend'
# 运行资产路径不带版本号（仓库约定）：直接覆盖运行时 GLB。
glb=COMP/'env_tower_floor_tile_5m_top3d.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_image_format='NONE',export_yup=True,export_extras=True,export_materials='EXPORT')
# Fixed reference camera plus near/top cameras for reproducible visual QA.
def camera(name,loc,target,ortho):
 d=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,d);preview.objects.link(o);o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();d.type='ORTHO';d.ortho_scale=ortho;return o
cam=camera('参考镜头_固定',(6,-7,9),(0,0,0),7.3)
top=camera('俯视结构镜头',(0,0,10),(0,0,0),5.8)
close=camera('检修盖近景',(3.6,-3.6,4),(1.5,-1.5,.1),2.0)
hatch=camera('检修盖俯视近景',(1.56,-1.56,6),(1.56,-1.56,.15),1.6)
for name,loc,energy,color,size in [('主光',(1,-3,7),1100,(.85,.93,1),5),('暖侧光',(-4,2,4),750,(1,.67,.38),4)]:
 d=bpy.data.lights.new(name,'AREA');d.energy=energy;d.color=color;d.shape='DISK';d.size=size
 o=bpy.data.objects.new(name,d);preview.objects.link(o);o.location=loc;o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
scene.world=bpy.data.worlds.new('低亮环境');scene.world.use_nodes=True
bg=next(x for x in scene.world.node_tree.nodes if x.type=='BACKGROUND')
bg.inputs[0].default_value=(.16,.19,.25,1);bg.inputs[1].default_value=.5
scene.render.engine='CYCLES';scene.cycles.samples=24
scene.render.resolution_x=900;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';scene.camera=cam
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
manifest={'asset_id':'ENV-TOWER-FLOOR-TILE-5M','version':'v003','category':'room_kit','logic_id':'tower_descent','component':'floor_tile_5m','name':'5米工业拼接地砖','collection':package.name,'objects':[merged.name],'source':str(blend.relative_to(ROOT)),'visual':str(glb.relative_to(ROOT)),'shared_palette':str(palette_path.relative_to(ROOT)),'dimensions_m':[5,5,.304],'origin':'center; walk surface visual top +0.1500 (unchanged); anti-coplanar decoration top +0.1540; runtime offset -0.15','front':'Godot -Z','collision':'existing centered 5x5x0.30 box; stage support unchanged','materials':[metal.name,paint.name],'triangles':sum(len(p.vertices)-2 for p in merged.data.polygons),'sha256':hashlib.sha256(glb.read_bytes()).hexdigest(),'scope':'tower common floor (98F / expedition / polished layers) visuals only; 99F authored floor, wall/stair/door transforms unchanged','replacement':'v002 had 4 part families coplanar at z=+0.1500 over overlapping XY (358 coplanar pairs) => pixel-level z-fighting shimmer; v002 hatch frame top +0.1480 was 2mm below the panel surface so the metal frame was buried and invisible. v003 staggers every visible plane by >= 2.0mm and turns the hatch vents into real 2mm recesses.','anti_coplanar':{'rule':'XY-overlapping visible faces differ in plane height by >= 0.0020 m','anchor':'panel top +0.1500 unchanged (runtime -0.15 offset contract)','ladder_m':{'panel':.1500,'hatch_frame_fastener_seat_warn_stripe':.1520,'fastener_slot_grate':.1540},'selfcheck_pairs':0},'locked_contract':{'grid_m':5,'thickness_m':.3,'floor_height_m':9,'walk_surface_local_z':.15,'unchanged_runtime_support':True},'independent_packages':1,'empty_packages':0,'multi_owned_objects':0}
(COMP/'asset_manifest_v003.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
print('FLOOR_TILE_V003_READY',json.dumps(manifest,ensure_ascii=False))
# Same camera/lighting for original plain slab and refined tile.
merged.hide_render=True
original=box('验收专用旧白模',(0,0,0),(5,5,.30),paint,(9,4));source.hide_render=False
for p in parts:p.hide_render=p!=original
scene.render.filepath=str(PRE/'before.png');bpy.ops.render.render(write_still=True)
bpy.data.objects.remove(original,do_unlink=True);source.hide_render=True;merged.hide_render=False
for c,name in [(cam,'after'),(top,'top'),(close,'close'),(hatch,'hatch_top')]:
 scene.camera=c;scene.render.filepath=str(PRE/(name+'.png'));bpy.ops.render.render(write_still=True)
scene.camera=cam
print('FLOOR_TILE_V003_QA_RENDERS',str(PRE))
