import bpy
from collections import Counter
o = bpy.data.objects["女儿墙直段_水泥结构_制作"]
me = o.data
uv = me.uv_layers["PaletteUV"].data
loops = me.loops
mn=[1e9,1e9]; mx=[-1e9,-1e9]
for l in uv:
    u,v = l.uv
    mn[0]=min(mn[0],u); mn[1]=min(mn[1],v)
    mx[0]=max(mx[0],u); mx[1]=max(mx[1],v)
print("UV bounds: min=%s max=%s" % (tuple(round(x,6) for x in mn), tuple(round(x,6) for x in mx)))
# 每个面的 UV 聚合
fb = Counter()
for p in me.polygons:
    us=[]; vs=[]
    for li in p.loop_indices:
        u,v = uv[li].uv; us.append(round(u,4)); vs.append(round(v,4))
    fb[(tuple(sorted(set(us))), tuple(sorted(set(vs))))] += 1
print("distinct per-face UV rects: %d" % len(fb))
for k,c in fb.most_common(12):
    print("   count=%-4d U=%s V=%s" % (c, k[0][:4], k[1][:4]))
# 面法向 -> 平均 UV
print()
print("normal -> mean UV")
agg = {}
for p in me.polygons:
    n=p.normal
    key=(round(n.x,1),round(n.y,1),round(n.z,1))
    us=[uv[li].uv[0] for li in p.loop_indices]; vsv=[uv[li].uv[1] for li in p.loop_indices]
    a=agg.setdefault(key,[0,0.0,0.0])
    a[0]+=1; a[1]+=sum(us)/len(us); a[2]+=sum(vsv)/len(vsv)
for k,(c,su,sv) in sorted(agg.items(), key=lambda x:-x[1][0])[:10]:
    print("   n=%-18s faces=%-4d meanU=%.5f meanV=%.5f" % (str(k), c, su/c, sv/c))
