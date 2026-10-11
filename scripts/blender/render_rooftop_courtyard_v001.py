import bpy,json,sys
from pathlib import Path
R=Path('I:/工作项目/shellstrom2/ShellStorm2');O=R/'outputs/rooftop_courtyard_v001'
s=bpy.data.scenes['复古天台庭院_v001'];bpy.context.window.scene=s;s.frame_set(1);bpy.context.view_layer.update()
# Dark neutral display background, no ground/backdrop model.
s.render.film_transparent=False
bg=next(n for n in s.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs['Color'].default_value=(.075,.085,.105,1)
s.cycles.samples=24
prefix='optimized_' if 'optimized' in bpy.data.filepath else ''
for name,file in [('全景第三视角','overview.png'),('俯视结构','top.png'),('沙发收音机近景','closeup.png'),('背面结构','rear.png')]:
    s.camera=bpy.data.objects[name];s.render.filepath=str(O/(prefix+file));bpy.ops.render.render(write_still=True)
print('COURTYARD_RENDER_OK')
