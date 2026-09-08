import bpy, json
names=['普通地板_主体_金属哑光反光_v008','普通地板_主体_金属哑光反光']
out=[]
for o in bpy.data.objects:
 if any(n in o.name for n in names):
  out.append({'object':o.name,'materials':[m.name if m else None for m in o.data.materials],
   'uv_layers':[{'name':u.name,'active':u==o.data.uv_layers.active,'active_render':u.active_render,'active_clone':u.active_clone} for u in o.data.uv_layers]})
print('FLOOR_LAYER_AUDIT='+json.dumps(out,ensure_ascii=False))
