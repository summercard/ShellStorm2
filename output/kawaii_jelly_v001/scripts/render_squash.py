import bpy,sys
import numpy as np
sys.path.insert(0,'/Users/summercards/ShellStorm2/output/kawaii_jelly_v001')
import kawaii_jelly_interaction as j
s=j.new_state(bpy.context.scene);s['q']=np.array((.34,0,-.28));s['r']=.15;j.apply_state(s)
bpy.context.scene.render.filepath='/Users/summercards/ShellStorm2/output/kawaii_jelly_v001/renders/果冻_弹性形变.png'
bpy.context.scene.cycles.samples=48
bpy.ops.render.render(write_still=True)
