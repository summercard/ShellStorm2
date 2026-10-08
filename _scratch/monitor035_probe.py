import bpy,json
print('FILE',bpy.data.filepath)
r=bpy.data.objects['Boss002_Rig'];r.animation_data.action=bpy.data.actions['activate'];s=bpy.data.scenes['BOSS002_STUDIO'];s.frame_set(1)
for o in bpy.data.collections['BOSS002_MONITOR'].all_objects:
 if o.type!='MESH' or o.name.startswith(('KEY_','Keyboard','Plug')):continue
 groups={o.vertex_groups[g.group].name for v in o.data.vertices for g in v.groups if g.weight>.01}
 if any(x in groups for x in ['monitor_tilt','monitor_spin','support_01','support_02','support_03','rear_axle']) or o.name.startswith(('Texture','Screen','Portrait')):
  e=o.evaluated_get(bpy.context.evaluated_depsgraph_get());m=e.to_mesh();vs=[e.matrix_world@v.co for v in m.vertices];e.to_mesh_clear()
  print(o.name,sorted(groups),'bounds',[[round(min(p[i] for p in vs),3),round(max(p[i] for p in vs),3)] for i in range(3)])
