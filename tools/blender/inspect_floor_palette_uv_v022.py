import bpy, json
c=bpy.data.collections.get('116_二楼地板色彩深化_资产包')
def rec(x):
 s=set(x.objects)
 for ch in x.children:s.update(rec(ch))
 return s
out=[]
for o in sorted(rec(c),key=lambda x:x.name):
 if o.type!='MESH':continue
 uv=o.data.uv_layers.get('PaletteUV') or o.data.uv_layers.active
 varying=0; cells=set(); ranges=[]
 if uv:
  for p in o.data.polygons:
   coords=[uv.data[i].uv[:] for i in p.loop_indices]
   cs={(int(x*10),int(y*10)) for x,y in coords}; cells.update(cs)
   if len(cs)>1:varying+=1
   ranges.append((max(x for x,y in coords)-min(x for x,y in coords),max(y for x,y in coords)-min(y for x,y in coords)))
 out.append({'object':o.name,'polygons':len(o.data.polygons),'uv_layer':uv.name if uv else None,'cells':sorted(cells),'faces_crossing_cells':varying,'max_face_uv_span':[max((r[0] for r in ranges),default=0),max((r[1] for r in ranges),default=0)],'materials':[m.name if m else None for m in o.data.materials]})
print('FLOOR_UV_AUDIT='+json.dumps(out,ensure_ascii=False))
