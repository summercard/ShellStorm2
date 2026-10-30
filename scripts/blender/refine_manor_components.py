"""Live MCP visual correction after examining manor_initial.png."""
import bpy,json,math,random
from pathlib import Path
from mathutils import Vector
R=Path('I:/工作项目/shellstrom2/ShellStorm2');S=R/'art_source/environments/tower_zones/expedition/source/common_components/v017';W=R.parent/'ShellStorm2-work/manor_v017'
scene=bpy.context.scene
catalog=json.loads((S/'component_catalog.json').read_text(encoding='utf-8'))['components']
doc=json.loads((S/'component_instances.json').read_text(encoding='utf-8'));instances=doc['instances']
# Reuse the authoring geometry helpers without executing scene creation.
code=(R/'scripts/blender/author_manor_components.py').read_text(encoding='utf-8-sig')
helpers=code[code.index('class Geo:'):code.index('catalog=[];COLS={}')]
image=next(i for i in bpy.data.images if i.filepath.endswith('512.png'))
pixels=list(image.pixels)
def color(rgb):
 best=None
 for y in range(10):
  for x in range(10):
   off=(int((y+.5)*51.2)*512+int((x+.5)*51.2))*4;v=pixels[off:off+3];d=sum((v[i]-rgb[i])**2 for i in range(3))
   if best is None or d<best[0]:best=(d,x,y)
 return best[1:]
C={k:color(v) for k,v in dict(wood=(.21,.105,.04),walnut=(.125,.055,.025),edge=(.055,.047,.035),gold=(.48,.32,.105),brightgold=(.66,.48,.19),red=(.29,.035,.055),red2=(.37,.065,.08),red3=(.19,.025,.04),ivory=(.74,.70,.61),white=(.85,.84,.77),black=(.045,.055,.065),stone=(.23,.24,.24),vein=(.37,.34,.25),green=(.035,.13,.055),leaf=(.08,.21,.09),leaflight=(.12,.27,.13),soil=(.07,.04,.02),paper=(.62,.60,.49)).items()}
mats=[bpy.data.materials[n] for n in ['01_精工金属_紫色骨架','02_细腻哑光_青绿大面','03_清漆反光_紫粉点缀','04_柔和自发光_UI灯光']]
exec(helpers,globals())
random.seed(430)
# Darken high contrast parquet by assigning yellow-looking boards to walnut.
c=bpy.data.collections['Component_manor_floor_wood']
for o in c.objects:
 if o.type=='MESH':
  uv=o.data.uv_layers.active
  for p in o.data.polygons:
   co=uv.data[p.loop_indices[0]].uv
   if int(co.x*10)==C['vein'][0] and int(co.y*10)==C['vein'][1]:
    for li in p.loop_indices:uv.data[li].uv.x+=(C['walnut'][0]-C['vein'][0])/10;uv.data[li].uv.y+=(C['walnut'][1]-C['vein'][1])/10
# Refine existing rug geometry: floral filigree within the existing three definitions.
for e in catalog:
 if e['component_family']!='rug':continue
 c=bpy.data.collections[e['collection']];w,d={'manor_rug_lounge':(8,10),'manor_rug_runner':(2.4,5),'manor_rug_bedroom':(3,4)}[e['slug']]
 g=Geo();rug(g,w,d)
 for side in [-1,1]:
  for j in range(int(d/.48)-1):
   x=side*(w/2-.31);y=-d/2+.6+j*.48
   for flip in [-1,1]:
    g.tube([(x+flip*.09*math.sin(t*math.pi*2),y+t*.32,.046) for t in [k/12 for k in range(13)]],.007,'gold',1,4)
 for ix in range(-int(w/.65)+1,int(w/.65)):
  for iy in range(-int(d/.7)+1,int(d/.7)):
   x=ix*.32;y=iy*.34
   if abs(x)<w/2-.65 and abs(y)<d/2-.65:
    g.tube([(x+.055*math.cos(k*math.pi/8),y+.09*math.sin(k*math.pi/8),.041) for k in range(17)],.004,'red3',1,4)
 for o in list(c.objects):bpy.data.objects.remove(o,do_unlink=True)
 e['bounds_size_m']=g.finish(c,e['slug'])
# Rounded edges on furniture; seams, carved panels and shade silhouettes preserved.
for e in catalog:
 for o in bpy.data.collections[e['collection']].objects:
  if o.type=='MESH' and e['component_family'] in ['cabinet','table','reception_desk','door','wall_grille','vanity','luggage_cart','bath_screen']:
   mod=o.modifiers.new('边缘精修_保留轮廓','BEVEL');mod.width=.012;mod.segments=2;mod.limit_method='ANGLE'
   mod.angle_limit=.6
# Stone under the central lounge and front desk, parquet retained as side strips.
for ins in instances:
 if ins['component_id']=='ENV-EXP03-MANOR-FLOOR-WOOD' and ins['position_m'][0] in [-5,0]:
  o=bpy.data.objects[ins['source_object']];o.instance_collection=bpy.data.collections['Component_manor_floor_stone'];ins['component_id']='ENV-EXP03-MANOR-FLOOR-STONE'
# Existing 5m module references add the missing small rest and bedroom furniture.
out=bpy.data.collections['02_游戏输出_组件实例参考']
def add(s,x,y,z=0,a=0):
 slug='manor_'+s;e=next(e for e in catalog if e['slug']==slug);o=bpy.data.objects.new('预览_'+s+'_'+str(len(instances)),None);o.instance_type='COLLECTION';o.instance_collection=bpy.data.collections[e['collection']];out.objects.link(o);o.location=(x,y,z);o.rotation_euler.z=math.radians(a)
 instances.append(dict(component_id=e['component_id'],instance_id=o.name,position_m=[x,y,z],rotation_y_deg=a,scale=[1,1,1],source_object=o.name))
add('console',11.9,-2.6,.05,270);add('plant_compact',11.9,-2.6,.90)
add('painting',10,-.26,1.35,180)
add('side_table',8.8,1.25,.05);add('armchair',9.1,2.1,.05,135)
add('rug_bedroom',10,-2.5,.01)
add('wall_lamp',12.15,5,1.5,270);add('wall_lamp',12.15,-8,1.5,270)
# More visibility of paneling and the curved counter apron than the initial near-top view.
cam=bpy.data.objects['参考顶视相机'];cam.location=(0,-18,38);cam.rotation_euler=(Vector((0,0,0))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=28.8
scene.camera=cam;scene.render.resolution_x=1600;scene.render.resolution_y=1500
scene.world.use_nodes=True;bg=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.07,.065,.055,1);bg.inputs[1].default_value=.45
scene.view_settings.exposure=.6
scene.cycles.samples=48
scene['visual_review']='Initial render reviewed: reduced yellow floor contrast, added stone field, enriched carpet filigree, softened furniture edges, adjusted camera for wall and desk visibility.'
from collections import Counter
counts=Counter(i['component_id'] for i in instances)
for e in catalog:e['instance_count']=counts[e['component_id']]
(S/'component_catalog.json').write_text(json.dumps({'components':catalog},ensure_ascii=False,indent=2),encoding='utf-8')
doc['instances']=instances;doc['validation']['instance_count']=len(instances);doc['validation']['source_object_count']=len(instances)
(S/'component_instances.json').write_text(json.dumps(doc,ensure_ascii=False,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(S/'复古公馆_模块化组件母版_v017.blend'))
scene.render.filepath=str(W/'manor_refined.png');bpy.ops.render.render(write_still=True)
scene.camera=bpy.data.objects['三分之四检查相机'];scene.render.filepath=str(W/'manor_oblique.png');bpy.ops.render.render(write_still=True)
scene.camera=cam;bpy.ops.wm.save_as_mainfile(filepath=str(S/'复古公馆_模块化组件母版_v017.blend'))
print('REFINED',len(instances))
