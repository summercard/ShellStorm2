"""High-quality assembly preview; independent masters stay separate and unchanged."""
import bpy,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent));import tower04_court_common as H
R=H.R;T=R/'assets/art/environments/open_world/source/tower_04/v010';C=R/'assets/art/environments/open_world/source/tower_04_2/v002'
a=json.loads((T/'catalog.json').read_text(encoding='utf8'));b=json.loads((C/'near_catalog.json').read_text(encoding='utf8'))
bpy.ops.wm.open_mainfile(filepath=str(R/a['source_blend']));sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc
with bpy.data.libraries.load(str(R/b['source_blend']),link=False) as (x,y):y.collections=['02_游戏输出_分区实例']
sc.collection.children.link(y.collections[0])
for o in list(sc.objects):
 if o.type=='LIGHT':o.hide_render=True
display=H.coll('90_合景效果验收',sc.collection)
world=bpy.data.worlds.new('黄昏合景天空');world.use_nodes=True;world.node_tree.nodes['Background'].inputs['Color'].default_value=(.43,.52,.65,1);world.node_tree.nodes['Background'].inputs['Strength'].default_value=.4;sc.world=world
ld=bpy.data.lights.new('合景斜阳','SUN');ld.energy=3.2;ld.color=(1,.73,.42);ld.angle=.09;sun=bpy.data.objects.new(ld.name,ld);display.objects.link(sun);sun.rotation_euler=(.7,-.75,-.55)
cam=H.camera(sc,'CAM_塔4及下方庭院',(154,-218,144),(-3,-15,11),204,display)
H.render(sc,cam,T/'previews/塔4与塔4-2_高精合景预览.png',(1900,1200),64)
cam=H.camera(sc,'CAM_庭院仰看圆楼',(-29,-63,11),(-50,-3,19),64,display)
H.render(sc,cam,C/'previews/庭院与圆楼空间关系.png',(1600,1100),48)
