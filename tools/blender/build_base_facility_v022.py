import bpy, bmesh, json, math, os, re
from pathlib import Path
from mathutils import Vector

ROOT=Path('/Users/summercards/ShellStorm2')
SOURCE=ROOT/'source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v022.blend'
EXPORT_DIR=ROOT/'source/art/blender/base_facility_layout/export/v022'
DERIVED=EXPORT_DIR/'base_facility_runtime_layout_hq-v022-updated_packages.blend'

PACKAGES={
 'loft_bed_and_bedding':('31_参考床架床品与床下收纳_资产包','31__02_游戏输出_整合模型','remaining'),
 'loft_bedside_lamp':('33_暖橙床头灯_资产包','33__02_游戏输出_整合模型','remaining'),
 'hologram_terminal_platform':('51_圆形全息设备平台_资产包','51_圆形全息设备平台_资产包','remaining'),
 'corridor_emergency_light_group':('62_主通道应急灯组_资产包','62_主通道应急灯组_资产包','remaining'),
 'east_power_distribution':('73_POWER工业配电系统_资产包','73_POWER工业配电系统_资产包','wall'),
 'east_industrial_pipeline_system':('74_东墙工业管线系统_资产包','74_东墙工业管线系统_资产包','wall'),
 'east_maintenance_workstation':('78_维修工作台与工具墙_资产包','78_02_游戏输出_整合模型_v021','remaining'),
 'east_work_together_poster':('81_WORK_TOGETHER工业海报_资产包','81_WORK_TOGETHER工业海报_资产包','wall'),
 'east_small_safety_devices':('82_东墙小型安全设备_资产包','82_东墙小型安全设备_资产包','wall'),
 'weapon_workshop_station':('49_武器工作台与弹药附件_资产包','49_02_游戏输出_整合模型_v020','remaining'),
 'south_wall_information_boards':('61_南墙资料板组_资产包','61_02_游戏输出_整合模型_v020','wall'),
 'water_purifier':('57_净水器_资产包','57_02_游戏输出_整合模型_v020','remaining'),
 'heavy_supply_shelf':('51_重型货架与补给箱_资产包','51_02_游戏输出_整合模型_v020','remaining'),
 'northwest_l_stair':('14_西北贴墙L型楼梯_资产包','14_西北贴墙L型楼梯_资产包','stair'),
}

def rec(c):
 s=set(c.objects)
 for ch in c.children:s.update(rec(ch))
 return s

def bbox(obs):
 pts=[]
 for o in obs:
  if o.type=='MESH': pts += [o.matrix_world@Vector(p) for p in o.bound_box]
 return ([min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)])

def shift(collection,delta):
 for o in rec(collection): o.location += Vector(delta)

def wall_snap(name,axis,side,target):
 c=bpy.data.collections[name]; obs=rec(c); lo,hi=bbox(obs)
 value=hi[axis] if side=='max' else lo[axis]
 d=[0,0,0]; d[axis]=target-value; shift(c,d); return d[axis]

# Save a new editable source version before derived optimization.
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))

# Bed: uniform 2/3 around footprint center and floor contact; remap bright white
# bed linen palette cell (9,0) to the duvet's muted green cell (2,4).
bed=rec(bpy.data.collections['31__02_游戏输出_整合模型'])
lo,hi=bbox(bed); pivot=Vector(((lo[0]+hi[0])/2,(lo[1]+hi[1])/2,lo[2])); scale=2/3
for o in bed:
 if o.type!='MESH': continue
 inv=o.matrix_world.inverted()
 for v in o.data.vertices:
  w=o.matrix_world@v.co; v.co=inv@(pivot+(w-pivot)*scale)
 uv=o.data.uv_layers.get('PaletteUV') or o.data.uv_layers.active
 if uv:
  for p in o.data.polygons:
   if p.material_index!=1: continue
   for li in p.loop_indices:
    co=uv.data[li].uv
    if int(co.x*10)==9 and int(co.y*10)==0: co=(0.25,0.45)

# Lamp goes onto the north end of the two moved cabinets; bottom sits on top.
lamp=rec(bpy.data.collections['33__02_游戏输出_整合模型']); llo,lhi=bbox(lamp)
shift(bpy.data.collections['33__02_游戏输出_整合模型'],(-3.70-(llo[0]+lhi[0])/2,7.70-(llo[1]+lhi[1])/2,7.47-llo[2]))

# Hologram: asset-local brighter emissive duplicate and a 10-second linear loop.
holo=bpy.data.collections['51_圆形全息设备平台_资产包']; shield=[]
for o in rec(holo):
 if o.type=='MESH' and ('悬浮盾牌' in o.name or '中央发光核心' in o.name):
  shield.append(o)
  for i,m in enumerate(o.data.materials):
   if m and '自发光' in m.name or (m and '柔和' in m.name):
    nm=bpy.data.materials.get('04_柔和自发光_UI灯光_全息增强_v022')
    if not nm:
     nm=m.copy(); nm.name='04_柔和自发光_UI灯光_全息增强_v022'
     if nm.use_nodes:
      for n in nm.node_tree.nodes:
       if n.type=='BSDF_PRINCIPLED' and 'Emission Strength' in n.inputs: n.inputs['Emission Strength'].default_value=2.2
       if n.type=='EMISSION': n.inputs['Strength'].default_value=2.2
    o.data.materials[i]=nm
spinner=bpy.data.objects.new('51_全息悬浮形状_缓慢旋转',None); holo.objects.link(spinner); spinner.location=(5.0,1.68,1.40)
for o in shield:
 world=o.matrix_world.copy(); o.parent=spinner; o.matrix_world=world
spinner.rotation_euler=(0,0,0); spinner.keyframe_insert('rotation_euler',frame=1,index=2)
spinner.rotation_euler.z=math.tau; spinner.keyframe_insert('rotation_euler',frame=240,index=2)
if spinner.animation_data and spinner.animation_data.action:
 for fc in spinner.animation_data.action.fcurves:
  for kp in fc.keyframe_points: kp.interpolation='LINEAR'
  fc.modifiers.new('CYCLES')
bpy.context.scene.render.fps=24; bpy.context.scene.frame_start=1; bpy.context.scene.frame_end=240

# Wall contact at the interior surface, leaving 2 cm safety gap.
wall_moves={
 'corridor_east':wall_snap('62_主通道应急灯组_资产包',0,'max',14.71),
}
# The emergency pair needs independent symmetric placement.
for o in rec(bpy.data.collections['62_主通道应急灯组_资产包']):
 if o.location.x<0: o.location.x-=1.62
# Recompute east member after the collection-wide move to exact symmetric centers.
for o in rec(bpy.data.collections['62_主通道应急灯组_资产包']):
 if o.location.x>0: o.location.x += 0.0
for n in ['73_POWER工业配电系统_资产包','74_东墙工业管线系统_资产包','81_WORK_TOGETHER工业海报_资产包','82_东墙小型安全设备_资产包']:
 wall_moves[n]=wall_snap(n,0,'max',14.80)
for n in ['49_02_游戏输出_整合模型_v020','61_02_游戏输出_整合模型_v020','57_02_游戏输出_整合模型_v020']:
 wall_moves[n]=wall_snap(n,0,'min',-14.80)
for n in ['78_02_游戏输出_整合模型_v021','51_02_游戏输出_整合模型_v020']:
 wall_moves[n]=wall_snap(n,1,'min',-14.80)

# Remove only the deprecated mesh-based dust package.
dust=bpy.data.collections.get('64_光束尘埃动效组_资产包')
if dust:
 for o in list(rec(dust)): bpy.data.objects.remove(o,do_unlink=True)
 for p in list(dust.children): bpy.data.collections.remove(p)
 bpy.data.collections.remove(dust)

bpy.context.scene['asset_version']='v022'
bpy.context.scene['v022_scope']='requested packages only'
bpy.context.scene['v022_wall_moves_m']=json.dumps(wall_moves,ensure_ascii=False)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))

# Derived export file: delete downward-facing triangles and triangulate only export copies.
EXPORT_DIR.mkdir(parents=True,exist_ok=True)
stats={}
for slug,(pkg,coll,scope) in PACKAGES.items():
 c=bpy.data.collections[coll]; before=after=removed=0
 for o in rec(c):
  if o.type!='MESH' or o.name.startswith('COLLISION_'): continue
  me=o.data; before += sum(len(p.vertices)-2 for p in me.polygons)
  bm=bmesh.new(); bm.from_mesh(me); bm.normal_update()
  down=[]
  normal_matrix=o.matrix_world.to_3x3().inverted().transposed()
  for f in bm.faces:
   if (normal_matrix@f.normal).normalized().z < -0.65: down.append(f)
  removed += sum(max(1,len(f.verts)-2) for f in down)
  if down:bmesh.ops.delete(bm,geom=down,context='FACES')
  bmesh.ops.triangulate(bm,faces=list(bm.faces),quad_method='BEAUTY',ngon_method='BEAUTY')
  bm.to_mesh(me); bm.free(); me.update(); after += len(me.polygons)
 stats[slug]={'triangles_before':before,'triangles_after':after,'downward_triangles_removed':removed,'bbox_blender':dict(zip(['min','max'],bbox(rec(c))))}
bpy.ops.wm.save_as_mainfile(filepath=str(DERIVED))

def next_glb(slug,scope):
 if scope=='stair': base=ROOT/'assets/art/environments/base_facility_3d/components/env_base99_stair_l_z5'; stem='env_base99_stair_l_z5_visual_top3d_'
 else:
  group='env_base99_wall_contents_v021' if scope=='wall' else 'env_base99_remaining_facilities_v021'
  base=ROOT/f'assets/art/environments/base_facility_3d/components/{group}/{slug}'; stem=f'{slug}_visual_top3d_'
 base.mkdir(parents=True,exist_ok=True); nums=[]
 for p in base.glob(stem+'v*.glb'):
  m=re.search(r'v(\d+)$',p.stem)
  if m: nums.append(int(m.group(1)))
 return base/f'{stem}v{max(nums+[0])+1:03d}.glb'

exports={}
for slug,(pkg,coll,scope) in PACKAGES.items():
 c=bpy.data.collections[coll]; obs=[o for o in rec(c) if not o.name.startswith('COLLISION_')]
 bpy.ops.object.select_all(action='DESELECT')
 for o in obs:o.select_set(True)
 if obs:bpy.context.view_layer.objects.active=obs[0]
 out=next_glb(slug,scope)
 bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_yup=True,
  export_apply=False,export_animations=True,export_materials='EXPORT',export_image_format='NONE',
  export_cameras=False,export_extras=True,export_lights=False)
 exports[slug]={'package':pkg,'collection':coll,'scope':scope,'glb':str(out.relative_to(ROOT)),**stats[slug]}
(EXPORT_DIR/'export_manifest.json').write_text(json.dumps({'version':'v022','source_blend':str(SOURCE.relative_to(ROOT)),'derived_blend':str(DERIVED.relative_to(ROOT)),'packages':exports},ensure_ascii=False,indent=2)+'\n')
print('BASE99_V022_BUILT='+json.dumps({'packages':len(exports),'wall_moves':wall_moves},ensure_ascii=False))
