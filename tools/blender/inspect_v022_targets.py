import bpy, json
from mathutils import Vector

targets = [
"31__02_游戏输出_整合模型","33__02_游戏输出_整合模型","51_圆形全息设备平台_资产包",
"62_主通道应急灯组_资产包","73_POWER工业配电系统_资产包","74_东墙工业管线系统_资产包",
"78_02_游戏输出_整合模型_v021","81_WORK_TOGETHER工业海报_资产包","82_东墙小型安全设备_资产包",
"49_02_游戏输出_整合模型_v020","61_02_游戏输出_整合模型_v020","57_02_游戏输出_整合模型_v020",
"51_02_游戏输出_整合模型_v020","64_光束尘埃动效组_资产包","14_西北贴墙L型楼梯_资产包"]

def recursive_objects(c):
    found=set(c.objects)
    for ch in c.children:
        found.update(recursive_objects(ch))
    return found

out={}
for name in targets:
    c=bpy.data.collections.get(name)
    if not c:
        out[name]={"missing":True}; continue
    obs=recursive_objects(c)
    pts=[]
    for o in obs:
        if o.type=='MESH':
            pts.extend(o.matrix_world @ Vector(p) for p in o.bound_box)
    out[name]={"count":len(obs),"types":{t:sum(o.type==t for o in obs) for t in sorted({o.type for o in obs})},
        "bounds":([min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]) if pts else None,
        "objects":[o.name for o in sorted(obs,key=lambda x:x.name)]}
print("V022_INSPECT="+json.dumps(out,ensure_ascii=False))
