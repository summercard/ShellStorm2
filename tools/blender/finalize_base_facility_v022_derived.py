import bpy, bmesh, json
from pathlib import Path
ROOT=Path('/Users/summercards/ShellStorm2')
collections=['31__02_游戏输出_整合模型','33__02_游戏输出_整合模型','51_圆形全息设备平台_资产包','62_主通道应急灯组_资产包','73_POWER工业配电系统_资产包','74_东墙工业管线系统_资产包','78_02_游戏输出_整合模型_v021','81_WORK_TOGETHER工业海报_资产包','82_东墙小型安全设备_资产包','49_02_游戏输出_整合模型_v020','61_02_游戏输出_整合模型_v020','57_02_游戏输出_整合模型_v020','51_02_游戏输出_整合模型_v020','14_西北贴墙L型楼梯_资产包']
seen=set(); stats={}
for name in collections:
 c=bpy.data.collections[name]; obs=set(c.objects)
 for ch in c.children: obs.update(ch.all_objects)
 before=after=removed=0
 for o in obs:
  if o in seen or o.type!='MESH' or o.name.startswith('COLLISION_'): continue
  seen.add(o); bm=bmesh.new(); bm.from_mesh(o.data); bm.normal_update(); before+=sum(max(1,len(f.verts)-2) for f in bm.faces)
  nm=o.matrix_world.to_3x3().inverted().transposed(); down=[f for f in bm.faces if (nm@f.normal).normalized().z < -0.65]
  removed+=sum(max(1,len(f.verts)-2) for f in down)
  if down:bmesh.ops.delete(bm,geom=down,context='FACES')
  bmesh.ops.triangulate(bm,faces=list(bm.faces)); after+=len(bm.faces); bm.to_mesh(o.data); bm.free()
 stats[name]={'triangles_before':before,'triangles_after':after,'removed':removed}
bpy.context.scene['v022_derived_optimized_collections']=len(collections)
bpy.context.scene['v022_derived_stats']=json.dumps(stats,ensure_ascii=False)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'source/art/blender/base_facility_layout/export/v022/base_facility_runtime_layout_hq-v022-updated_packages.blend'))
print('V022_DERIVED_FINALIZED='+json.dumps({'collections':len(collections),'objects':len(seen),'removed':sum(v['removed'] for v in stats.values())},ensure_ascii=False))
