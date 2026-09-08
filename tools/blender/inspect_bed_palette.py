import bpy, collections, json
o=bpy.data.objects.get('31_主体_v019')
uv=o.data.uv_layers.get('PaletteUV') or o.data.uv_layers.active
out=collections.Counter()
for p in o.data.polygons:
    if not p.loop_indices: continue
    co=uv.data[p.loop_indices[0]].uv
    out[(p.material_index, int(co.x*10), int(co.y*10))]+=p.area
print('BED_CELLS='+json.dumps([{"material":k[0],"cell":[k[1],k[2]],"area":round(v,4)} for k,v in out.most_common()],ensure_ascii=False))
for i,m in enumerate(o.data.materials): print('BED_MAT',i,m.name)
