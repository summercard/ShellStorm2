import bpy
o = bpy.data.objects["女儿墙直段_水泥结构_制作"]
print("matrix_world:", [tuple(round(v,6) for v in row) for row in o.matrix_world])
me = o.data
smooth = sum(1 for p in me.polygons if p.use_smooth)
print("polys=%d smooth=%d flat=%d" % (len(me.polygons), smooth, len(me.polygons)-smooth))
print("has_custom_normals:", me.has_custom_normals)
