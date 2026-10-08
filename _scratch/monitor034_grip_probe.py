import bpy,json
from mathutils import Vector
r=bpy.data.objects['Boss002_Rig'];r.animation_data.action=bpy.data.actions['idle'];s=bpy.data.scenes['BOSS002_STUDIO'];s.frame_set(1);d=bpy.context.evaluated_depsgraph_get()
for n in ['Keyboard outer shell','Sculpted glove L','KEY_00_00','KEY_11_04']:
 o=bpy.data.objects.get(n)
 if not o:continue
 e=o.evaluated_get(d);m=e.to_mesh();vs=[e.matrix_world@v.co for v in m.vertices];e.to_mesh_clear()
 print(n,'min',[min(p[i] for p in vs) for i in range(3)],'max',[max(p[i] for p in vs) for i in range(3)],'origin',list(o.matrix_world.translation),'mesh_center',list(sum((v.co for v in o.data.vertices),Vector())/len(o.data.vertices)))
print('handmat',[list(x) for x in r.pose.bones['hand.L'].matrix]);print('propmat',[list(x) for x in r.pose.bones['prop_socket.L'].matrix])
