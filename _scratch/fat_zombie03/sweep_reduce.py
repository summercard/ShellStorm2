import bpy,json
from pathlib import Path
from mathutils.bvhtree import BVHTree
root=Path(__file__).resolve().parents[2];pkg=root/'assets/art/enemies/normal_enemy_3d/fat_zombie03'
bpy.ops.wm.open_mainfile(filepath=str(pkg/'source/model/enm_normal_fat_zombie03_model_v003.blend'))
old=next(o for o in bpy.context.scene.objects if o.type=='MESH')
features={v.index:any(g.weight>.25 and any(x in old.vertex_groups[g.group].name for x in ['Head','Hand','Thumb','Index','Middle','Pinky','Ring']) for g in v.groups) for v in old.data.vertices}
results=[]
for fac in [.001,.005,.01,.03,.1]:
 for invert in [True]:
  m=old.copy();m.data=old.data.copy();bpy.context.scene.collection.objects.link(m);m.shape_key_clear()
  for mod in list(m.modifiers):m.modifiers.remove(mod)
  vg=m.vertex_groups.new(name='protect_features')
  for v in m.data.vertices:vg.add([v.index],.8 if features[v.index] else .05,'REPLACE')
  d=m.modifiers.new('reduce','DECIMATE');d.ratio=.348;d.use_collapse_triangulate=True
  if fac:d.vertex_group=vg.name;d.vertex_group_factor=fac;d.invert_vertex_group=invert
  bpy.context.view_layer.objects.active=m;bpy.ops.object.modifier_apply(modifier=d.name)
  tree=BVHTree.FromPolygons([v.co for v in m.data.vertices],[list(p.vertices) for p in m.data.polygons])
  err={'feature':[],'body':[]}
  for v in old.data.vertices:err['feature' if features[v.index] else 'body'].append(tree.find_nearest(v.co)[3]*.7)
  results.append({'factor':fac,'invert':invert,'tris':len(m.data.polygons),'errors':{k:{'max':max(v),'mean':sum(v)/len(v),'p95':sorted(v)[int(len(v)*.95)]} for k,v in err.items()}})
  bpy.data.objects.remove(m,do_unlink=True)
print('SWEEP',json.dumps(results),flush=True)

