"""Bake evaluated chain corrections after driver evaluation, before finger grip."""
for frame in range(27,45):
 s.frame_set(frame);bpy.context.view_layer.update()
 for iteration in range(3):
  ob=bpy.data.objects['Keyboard outer shell'];ev=ob.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();vs=[ev.matrix_world@v.co for v in me.vertices];ev.to_mesh_clear()
  delta=Vector((0,0,0));minimum=min(v.z for v in vs)
  if 33<=frame<=41:
   delta.z=.025-minimum;delta.y=3.2-sum(v.y for v in vs)/len(vs)
  elif frame==32 or frame==42:
   delta.z=max(0,.05-minimum)
  names=['arm_%02d.L'%i for i in range(1,7)]+['hand_ctrl.L']
  matrices={n:rig.pose.bones[n].matrix.copy() for n in names}
  for i,n in enumerate(names):
   pb=rig.pose.bones[n];m=matrices[n];m.translation+=delta*(i/6);pb.matrix=m;bpy.context.view_layer.update()
   for path in ['location','rotation_quaternion','scale']:pb.keyframe_insert(path,frame=frame,group=n)
  s.frame_set(frame);bpy.context.view_layer.update()
