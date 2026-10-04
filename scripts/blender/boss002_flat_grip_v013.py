"""Curl each finger above the contact plane, keeping surface grip at impact."""
from mathutils.bvhtree import BVHTree
s.frame_set(33);bpy.context.view_layer.update()
hand=bpy.data.objects['Sculpted glove L'];keyob=bpy.data.objects['Keyboard outer shell']
deps=bpy.context.evaluated_depsgraph_get();ev=keyob.evaluated_get(deps);me=ev.to_mesh()
bvh=BVHTree.FromPolygons([ev.matrix_world@v.co for v in me.vertices],[list(p.vertices) for p in me.polygons]);ev.to_mesh_clear()
corrections={}
for digit in range(1,5):
 bones=[rig.pose.bones['digit%d_%02d.L'%(digit,j)] for j in [1,2]]
 base=[p.rotation_quaternion.copy() for p in bones]
 ids=[g.index for g in hand.vertex_groups if g.name.startswith('digit%d_'%digit)]
 verts=[v.index for v in hand.data.vertices if sum(g.weight for g in v.groups if g.group in ids)>.4]
 best=None
 for a in [x*.25 for x in range(-4,17)]:
  for b in [x*.25 for x in range(-4,17)]:
   for pb,q,factor in zip(bones,base,[a,b]):
    axis_,angle=q.to_axis_angle();pb.rotation_quaternion=Quaternion(axis_,angle*factor)
   bpy.context.view_layer.update();ev=hand.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();points=[ev.matrix_world@me.vertices[i].co for i in verts];ev.to_mesh_clear()
   low=min(v.z for v in points);distance=min(bvh.find_nearest(v)[3] for v in points)
   score=max(0,.008-low)*1000+max(0,distance-.04)*100+abs(a-1)+abs(b-1)
   if best is None or score<best[0]:best=(score,[p.rotation_quaternion.copy() for p in bones],low,distance)
 print('FLAT_GRIP',digit,best[0],best[2:])
 for pb,q in zip(bones,best[1]):corrections[pb.name]=q;pb.rotation_quaternion=q
for frame in range(1,56):
 s.frame_set(frame);f=frame-1
 weight=min(1,max(0,(f-12)/10)) if f<=40 else max(0,(54-f)/14)
 weight=weight*weight*(3-2*weight)
 for name,q in corrections.items():
  pb=rig.pose.bones[name];pb.rotation_quaternion=pb.rotation_quaternion.slerp(q,weight);pb.keyframe_insert('rotation_quaternion',frame=frame,group=name)
