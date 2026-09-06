"""Authored industrial floor replacement. Run in Blender background from project root."""
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
scene=bpy.context.scene
scene.unit_settings.system='METRIC'
source=bpy.data.collections.new('01_制作组件_已统一材质');scene.collection.children.link(source)
game=bpy.data.collections.new('02_游戏输出_独立资产包_v002');scene.collection.children.link(game)
package=bpy.data.collections.new('地面系统_5米工业地砖_资产包');game.children.link(package)
preview=bpy.data.collections.new('90_展示与验收_灯光相机');scene.collection.children.link(preview)
palette_path=ROOT/'assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png'
image=bpy.data.images.load(str(palette_path),check_existing=True)
def mat(name,metal,rough):
 m=bpy.data.materials.new(name);m.use_nodes=True
 n=m.node_tree.nodes;bs=n.get('Principled BSDF');bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
 uv=n.new('ShaderNodeUVMap');uv.uv_map='PaletteUV'
 t=n.new('ShaderNodeTexImage');t.image=image;t.interpolation='Closest'
 m.node_tree.links.new(uv.outputs['UV'],t.inputs['Vector']);m.node_tree.links.new(t.outputs['Color'],bs.inputs['Base Color'])
 return m
metal=mat('01_精工金属_紫色骨架',.82,.30)
paint=mat('02_细腻哑光_青绿大面',.03,.72)
parts=[]
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
 o.data.materials.append(material);uv_assign(o,cell);parts.append(o);return o
# Existing centered floor contract: exact 5×5×0.30m; runtime drops by .15m.
base=box('承重底板_接口锁定',(0,0,-.035),(5,5,.23),paint,(9,1))
for x in (-1.20,1.20):
 for y in (-1.20,1.20):
  box('哑光面板_独立压边',(x,y,.105),(2.35,2.35,.09),paint,(9,4),.018)
for x in (-2.43,2.43):box('纵向金属压边',(x,0,.118),(.09,4.86,.06),metal,(9,3),.008)
for y in (-2.43,2.43):box('横向金属压边',(0,y,.118),(4.78,.09,.06),metal,(9,3),.008)
for x in (-2.32,2.32):
 for y in (-2.32,2.32):
  box('角部紧固座',(x,y,.134),(.14,.14,.032),metal,(9,6),.012)
  box('紧固槽',(x,y,.149),(.082,.022,.002),paint,(9,1))
# Flush maintenance hatch belongs to the floor; no collision or gameplay identity.
box('检修盖框',(1.56,-1.56,.139),(.83,.61,.018),metal,(9,2),.018)
box('检修盖板',(1.56,-1.56,.148),(.69,.47,.004),paint,(9,3))
for x in (1.34,1.45,1.56,1.67,1.78):box('检修散热细槽',(x,-1.56,.15),(.028,.26,.001),paint,(9,1))
# One restrained warm identifying stripe per tile, outside the central action field.
box('检修警示短标',(1.56,-1.94,.15),(.42,.038,.001),paint,(3,5))
# Bake source transforms into ONE mesh, shared by batched MultiMesh surfaces.
bpy.ops.object.select_all(action='DESELECT')
clones=[]
for o in parts:
 c=o.copy();c.data=o.data.copy();package.objects.link(c);c.select_set(True);clones.append(c)
bpy.context.view_layer.objects.active=clones[0];bpy.ops.object.join()
merged=bpy.context.object;merged.name='FloorTile_5m'
bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
# Slot consolidation through bmesh join preserves PaletteUV and material roles.
merged['asset_id']='ENV-TOWER-FLOOR-TILE-5M';merged['version']='v002'
merged['collision_contract']='5x5x0.30m centered, supplied by Godot wrapper'
source.hide_render=True;source.hide_viewport=True
bpy.ops.object.select_all(action='DESELECT');merged.select_set(True);bpy.context.view_layer.objects.active=merged
blend=SRC/'env_tower_floor_tile_5m_source_v002.blend'
glb=COMP/'env_tower_floor_tile_5m_top3d_v002.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_image_format='NONE',export_yup=True,export_extras=True,export_materials='EXPORT')
# Fixed reference camera plus near/top cameras for reproducible visual QA.
def camera(name,loc,target,ortho):
 d=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,d);preview.objects.link(o);o.location=loc;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();d.type='ORTHO';d.ortho_scale=ortho;return o
cam=camera('参考镜头_固定',(6,-7,9),(0,0,0),7.3)
top=camera('俯视结构镜头',(0,0,10),(0,0,0),5.8)
close=camera('检修盖近景',(3.6,-3.6,4),(1.5,-1.5,.1),2.0)
for name,loc,energy,color,size in [('主光',(1,-3,7),1100,(.85,.93,1),5),('暖侧光',(-4,2,4),750,(1,.67,.38),4)]:
 d=bpy.data.lights.new(name,'AREA');d.energy=energy;d.color=color;d.shape='DISK';d.size=size
 o=bpy.data.objects.new(name,d);preview.objects.link(o);o.location=loc;o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
scene.world=bpy.data.worlds.new('低亮环境');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.16,.19,.25,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.5
scene.render.engine='CYCLES';scene.cycles.samples=24
scene.render.resolution_x=900;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';scene.camera=cam
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
# Same camera/lighting for original plain slab and refined tile.
merged.hide_render=True
original=box('验收专用旧白模',(0,0,0),(5,5,.30),paint,(9,4));source.hide_render=False
for p in parts:p.hide_render=p!=original
scene.render.filepath=str(PRE/'before.png');bpy.ops.render.render(write_still=True)
bpy.data.objects.remove(original,do_unlink=True);source.hide_render=True;merged.hide_render=False
for c,name in [(cam,'after'),(top,'top'),(close,'close')]:
 scene.camera=c;scene.render.filepath=str(PRE/(name+'.png'));bpy.ops.render.render(write_still=True)
scene.camera=cam
manifest={'asset_id':'ENV-TOWER-FLOOR-TILE-5M','version':'v002','category':'room_kit','logic_id':'tower_descent','component':'floor_tile_5m','name':'5米工业拼接地砖','collection':package.name,'objects':[merged.name],'source':str(blend.relative_to(ROOT)),'visual':str(glb.relative_to(ROOT)),'shared_palette':str(palette_path.relative_to(ROOT)),'dimensions_m':[5,5,.3005],'origin':'center; visual top +0.1505; runtime offset -0.15','front':'Godot -Z','collision':'existing centered 5x5x0.30 box; stage support unchanged','materials':[metal.name,paint.name],'triangles':sum(len(p.vertices)-2 for p in merged.data.polygons),'sha256':hashlib.sha256(glb.read_bytes()).hexdigest(),'scope':'100F rooftop and 98F floor visuals only; 99F authored floor, wall/stair/door transforms unchanged','replacement':'v001 registry pointed to GLB but actual runtime was BoxMesh; v002 now explicitly imports the authored mesh','locked_contract':{'grid_m':5,'thickness_m':.30,'floor_height_m':9,'unchanged_runtime_support':True},'independent_packages':1,'empty_packages':0,'multi_owned_objects':0}
(COMP/'asset_manifest_v002.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
print('FLOOR_TILE_V002_READY',json.dumps(manifest,ensure_ascii=False))
