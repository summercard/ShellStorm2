import bpy,json
r=bpy.data.objects['Boss002_Rig'];r.animation_data.action=bpy.data.actions['activate'];s=bpy.data.scenes['BOSS002_STUDIO'];out={}
for f in [64,101,121,136,146,151,155,161,179,193]:
 s.frame_set(f);dg=bpy.context.evaluated_depsgraph_get();v={}
 for name in ['Portrait display','Sculpted glove L','Keyboard outer shell']:
  o=bpy.data.objects[name].evaluated_get(dg);me=o.to_mesh();vs=[o.matrix_world@p.co for p in me.vertices];o.to_mesh_clear();v[name]=[min(p.z for p in vs),max(p.z for p in vs)]
 out[f]=v
print(json.dumps(out))
