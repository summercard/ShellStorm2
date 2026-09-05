for o in packs['01_房间外壳'].objects:
 if o.name=='左墙':o.location.y=-.03;o.dimensions.y=3.06
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/粉色电竞卧室_高还原_v001.blend')
