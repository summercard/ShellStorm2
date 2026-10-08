import bpy,json
s=bpy.data.scenes['BOSS002_STUDIO'];bpy.context.window_manager.windows[0].scene=s
b=bpy.data.objects['Crescent pedestal'];g=[]
for st in range(97):
 f=1+st/2;s.frame_set(int(f),subframe=f%1);e=b.evaluated_get(bpy.context.evaluated_depsgraph_get());m=e.to_mesh();g.append(min((e.matrix_world@v.co).z for v in m.vertices));e.to_mesh_clear()
print(json.dumps({'min':min(g),'max':max(g),'ints':g[::2],'halfs':g[1::2]}))
