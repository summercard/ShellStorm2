for o in packs['07_矮沙发'].objects:
 o.location.y+=.20
 o.location.x-=.10
for name in ['08_茶几','17_茶几食物和笔筒']:
 for o in packs[name].objects:o.location.y+=.16
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/粉色电竞卧室_高还原_v001.blend')
